import Foundation
import Combine
import AirliftFFI

/// Drives the RPPairing host: requests Local Network, keeps the app alive while
/// the user approves the PIN in Settings, advertises the service over Bonjour,
/// and runs `al_pairing_run_host` off the main thread.
@MainActor
final class PairingController: ObservableObject {

    static let shared = PairingController()

    private let hostName = "AirBeep"
    private let hostModel = "Mac17,7"   // device sees a Mac-like pairing host
    private let bindAddress = "0.0.0.0"

    private var netService: NetService?
    private let localNetwork = LocalNetworkAuthorization()
    private let keepAlive = KeepAlive()

    @Published private(set) var running = false
    @Published var pairingStatus: String = "idle"
    @Published var pairingPIN: String? = nil

    /// Path to the pairing file that was actively found or created.
    static var customPairingFilePath: String? = nil

    /// Persisted altIRK keeps the host identity stable across pairings so a
    /// device that has already paired recognises this host.
    nonisolated private static let altIRKKey = "aircardPairingHostAltIRK"
    nonisolated private static var storedAltIRK: String {
        get { UserDefaults.standard.string(forKey: altIRKKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: altIRKKey) }
    }

    private var pairContinuation: CheckedContinuation<String, Error>?

    // MARK: - Public API

    enum PairingError: LocalizedError {
        case busy
        case localNetworkDenied
        case zeroBytes
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .busy: return "Pairing is already in progress."
            case .localNetworkDenied: return "Local Network permission is off. Enable it in Settings › AirBeep › Local Network."
            case .zeroBytes: return "Pairing produced an empty file. Approve the pairing request, then try again."
            case let .failed(msg): return msg
            }
        }
    }

    /// Canonical pairing storage. Kept in Application Support so the credential
    /// is not exposed via File Sharing (pre-2.5 builds stored it in Documents).
    private static var secureDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Legacy location from pre-2.5 builds. Migrated once, then cleaned up.
    private static var legacyDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static let legacyPairingNames = ["aircard_pairing.plist", "airlift_pairing.plist"]

    private static func isValidPairingFile(at path: String) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        return size > 0
    }

    /// Ensures the given pairing file is stored at the canonical secure
    /// location. Legacy Documents copies are removed so the credential is no
    /// longer exposed via File Sharing.
    @discardableResult
    static func syncCanonicalPairingFile(from sourcePath: String) -> String {
        let dir = secureDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let canonicalURL = dir.appendingPathComponent("aircard_pairing.plist")

        if let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)), !data.isEmpty {
            if sourcePath != canonicalURL.path {
                try? data.write(to: canonicalURL, options: .atomic)
            }
            for legacyName in legacyPairingNames {
                let legacyURL = legacyDirectory.appendingPathComponent(legacyName)
                if legacyURL.path != sourcePath, legacyURL.path != canonicalURL.path {
                    try? FileManager.default.removeItem(at: legacyURL)
                }
            }
            customPairingFilePath = canonicalURL.path
            return canonicalURL.path
        }
        return sourcePath
    }

    /// Path where the pairing file is written or read from.
    /// Checks the canonical secure location first, then migrates legacy
    /// Documents copies (pre-2.5) once. Pairing files are imported explicitly
    /// through the document picker; Documents is no longer scanned.
    static func pairingFilePath() -> String {
        // Application Support is not created by the system; the pairing host
        // writes directly to this path via FFI, so the directory must exist.
        try? FileManager.default.createDirectory(
            at: secureDirectory, withIntermediateDirectories: true)
        let canonicalPath = secureDirectory
            .appendingPathComponent("aircard_pairing.plist").path
        if isValidPairingFile(at: canonicalPath) { return canonicalPath }

        for legacyName in legacyPairingNames {
            let legacyPath = legacyDirectory.appendingPathComponent(legacyName).path
            if isValidPairingFile(at: legacyPath) {
                _ = syncCanonicalPairingFile(from: legacyPath)
                if isValidPairingFile(at: canonicalPath) { return canonicalPath }
            }
        }

        if let custom = customPairingFilePath, isValidPairingFile(at: custom) {
            _ = syncCanonicalPairingFile(from: custom)
            if isValidPairingFile(at: canonicalPath) { return canonicalPath }
        }

        return canonicalPath
    }

    /// Start the host and resolve with the pairing-file path, or throw.
    func startAndWait() async throws -> String {
        // If already running, cancel previous to allow clean restart
        if running {
            softCancel()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return try await withCheckedThrowingContinuation { cont in
            pairContinuation = cont
            start()
        }
    }

    func softCancel() {
        stopAdvertising()
        keepAlive.stopAll()
        running = false
        pairingPIN = nil
        pairingStatus = "Cancelled"
        resolve(.failure(CancellationError()))
    }

    private func resolve(_ result: Result<String, Error>) {
        guard let cont = pairContinuation else { return }
        pairContinuation = nil
        cont.resume(with: result)
    }

    func start() {
        stopAdvertising()
        keepAlive.stopAll()
        running = true
        pairingPIN = nil
        pairingStatus = "Starting local host…"

        Task {
            _ = await localNetwork.request()
            guard running else { return }

            keepAlive.startAudio()
            pairingStatus = "Broadcasting… open Settings to pair"
            runHost()
        }
    }

    // MARK: - Private

    private func runHost() {
        let bind = bindAddress
        let name = hostName
        let model = hostModel
        let outPath = Self.pairingFilePath()
        let altIRK = Self.storedAltIRK
        nonisolated(unsafe) let ctx = UnsafeMutableRawPointer(
            Unmanaged.passRetained(self).toOpaque()
        )

        DispatchQueue.global(qos: .userInitiated).async {
            var result = ALPairResult()
            let rc = bind.withCString { bindC in
                name.withCString { nameC in
                    model.withCString { modelC in
                        outPath.withCString { outC in
                            altIRK.withCString { irkC in
                                al_pairing_run_host(
                                    bindC, 0, nameC, modelC, outC, irkC,
                                    pairReadyCallback, pairPinCallback, ctx, &result)
                            }
                        }
                    }
                }
            }

            let outcome: Outcome
            if rc == 0 {
                let issued = cStr(result.host_alt_irk_hex)
                if !issued.isEmpty { Self.storedAltIRK = issued }
                let devName = cStr(result.device_name)
                let filePath = cStr(result.pairing_file_path)
                outcome = .success(
                    name: devName.isEmpty ? "iPhone" : devName,
                    path: filePath.isEmpty ? outPath : filePath
                )
            } else {
                let msg = cStr(result.error)
                outcome = .failure(msg.isEmpty ? "pairing failed (rc=\(rc))" : msg)
            }
            al_pairing_result_free(&result)

            DispatchQueue.main.async {
                Unmanaged<PairingController>.fromOpaque(ctx).release()
                self.finish(outcome)
            }
        }
    }

    private enum Outcome {
        case success(name: String, path: String)
        case failure(String)
    }

    private func finish(_ outcome: Outcome) {
        stopAdvertising()
        // Keep background alive for 5s so iOS doesn't kill the app before user returns from Settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.keepAlive.stopAll()
        }
        running = false
        pairingPIN = nil

        switch outcome {
        case let .success(name, path):
            let canonical = Self.syncCanonicalPairingFile(from: path)
            let size = (try? FileManager.default.attributesOfItem(atPath: canonical)[.size] as? Int) ?? 0
            if size == 0 {
                pairingStatus = "Failed: empty pairing file"
                resolve(.failure(PairingError.zeroBytes))
            } else {
                pairingStatus = "Paired: \(name) (\(size)B)"
                resolve(.success(canonical))
            }
        case let .failure(message):
            pairingStatus = "Failed: \(message)"
            resolve(.failure(PairingError.failed(message)))
        }
    }


    // MARK: Bonjour advertising

    fileprivate func startAdvertising(serviceID: String, port: Int32, txt: [String: Data]) {
        stopAdvertising()
        let service = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: port
        )
        service.setTXTRecord(NetService.data(fromTXTRecord: txt))
        service.publish()
        netService = service
        pairingStatus = "Advertising — open Settings › Privacy & Security › Developer Mode"
    }

    fileprivate func presentPin(_ pin: String) {
        pairingPIN = pin
        pairingStatus = "Enter PIN \(pin) in Settings › Privacy & Security › Developer Mode › Pair with AirBeep"
    }

    private func stopAdvertising() {
        netService?.stop()
        netService = nil
    }
}

// MARK: - C callbacks

private let pairReadyCallback: ALPairReadyCb = { ctx, serviceID, port, keys, vals, count in
    guard let ctx = ctx, let serviceID = serviceID else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
    let id = String(cString: serviceID)

    var txt: [String: Data] = [:]
    if let keys = keys, let vals = vals {
        for i in 0..<Int(count) {
            guard let k = keys[i], let v = vals[i] else { continue }
            txt[String(cString: k)] = Data(String(cString: v).utf8)
        }
    }
    DispatchQueue.main.async {
        controller.startAdvertising(serviceID: id, port: Int32(port), txt: txt)
    }
}

private let pairPinCallback: ALPairPinCb = { pin, ctx in
    guard let ctx = ctx, let pin = pin else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
    let pinString = String(cString: pin)
    DispatchQueue.main.async {
        controller.presentPin(pinString)
    }
}

private func cStr(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr = ptr else { return "" }
    return String(cString: ptr)
}
