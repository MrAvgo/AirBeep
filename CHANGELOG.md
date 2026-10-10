# Changelog

All notable changes to **AirBeep** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.5.0] - 2026-10-10

> **English** — Release notes. | **中文** — 发行说明见下方中文版。

### English / Added
- **Recheck tones button.** The app no longer probes the system files at launch (2.4.0), so the displayed state could go stale after a system language change or iOS update. The new button forces a real read and re-syncs the cached state on demand.
- **Preview current tone button.** Reads the live system tone files and plays the start disclosure tone back, so you can hear what the other party would hear without placing a test call.

### English / Changed
- **Backups moved to Library/Application Support.** They were stored in `Documents/AirBeepBackups`, which is exposed via File Sharing — one accidental delete in the Files app and the restore path was gone. Existing backups are migrated automatically on first launch.
- **Release assets now include a SHA256 checksum** (`airbeep-v<version>-unsigned.ipa.sha256`) so the unsigned IPA can be verified before sideloading.

### English / Security
- **Pairing file moved out of Documents.** The pairing credential (`aircard_pairing.plist`) was stored in Documents and therefore visible through File Sharing. It now lives in Library/Application Support; legacy copies are migrated once and the Documents copies are deleted. Pairing files are still imported explicitly through the document picker — Documents is no longer auto-scanned.

---

### 中文 / 新增
- **“重新检测提示音”按钮。** 2.4.0 起 App 启动时不再探测系统文件，改语言或升级系统后界面状态可能过期。新按钮按需真实读取一次并同步缓存状态。
- **“试听当前提示音”按钮。** 读回系统当前提示音文件并播放开始提示音，不用真打电话也能确认对方会听到什么。

### 中文 / 变更
- **备份目录搬到 Library/Application Support。** 原来在 `Documents/AirBeepBackups`，文件共享可见，在“文件”App 里误删就没了恢复路径。老备份首次启动自动迁移。
- **Release 附件新增 SHA256 校验文件**（`airbeep-v<version>-unsigned.ipa.sha256`），侧载前可验包。

### 中文 / 安全
- **配对文件搬出 Documents。** 配对凭证（`aircard_pairing.plist`）原来放在 Documents，经文件共享可见；现已迁入 Library/Application Support，旧文件迁移一次后删除 Documents 中的副本。配对文件仍通过文档选择器显式导入，不再自动扫描 Documents。

---

## [2.4.0] - 2026-10-10

> **English** — Release notes. | **中文** — 发行说明见下方中文版。

### English / Changed
- Removed the automatic tone-state check that ran at app launch. Some users saw
  a startup check get stuck and the switch stay disabled because the underlying
  airlift read could not finish on their iOS release. The app now restores the
  last known state from cache and performs no file access until the user flips
  the switch.
- If anything goes wrong with the tones, you can force the original system
  tones back by changing the system language on the device.

---

### 中文 / 变更
- 移除 app 启动时自动执行的提示音文件状态校验。此前部分用户会因启动校验
  卡住、开关一直处于灰色不可用状态——其根本原因是底层 airlift 读取在部分
  iOS 版本上无法完成。现在打开 app 不再做任何文件读取，改为从本地缓存恢复
  上次的状态，仅在用户拨动开关时才进行实际操作。
- 若提示音出现异常，可通过**更改系统语言**强制恢复为系统默认提示音。

---

**Full Changelog**: [v2.3.0...v2.4.0](https://github.com/LinkPass888/AirBeep/compare/v2.3.0...v2.4.0)

## [2.3.0] - 2026-10-09

> **English** — Release notes. | **中文** — 发行说明见下方中文版。

### English / Fixed
- **Xcode 27 build failure.** With `-default-isolation=MainActor`, `@escaping`
  closures can no longer implicitly reference `self`. The silence and restore
  operations now capture `self` explicitly, so the unsigned IPA builds again.
- **iOS 27.0.1 "AirTraffic did not recover"** on read: the airlift read probe
  now targets a non-empty payload and emits more diagnostic logging.

### English / Added
- Runtime log collection (`AirBeepLog`) with on-device export in the About page
  for easier troubleshooting.
- Manual pairing-file import via `UIDocumentPickerViewController` (`asCopy`),
  avoiding the sandbox security-scope read failure.
- Screen keeps awake and shows a prominent "do not exit the app" warning banner
  while a silence / restore operation is running.

### English / Security
- Removed the unused `BadQuery` vulnerability; only `airlift` is retained.

### English / Infrastructure
- Renamed the product from `placard` to `airbeep` across the project, scheme,
  bridging header, workflow, and scripts.
- Updated supported range to iOS/iPadOS 18.0 – 27.2 B2 (aligned with AirCard /
  AirliftSilence).

---

### 中文 / 已修复
- **修复 Xcode 27 构建失败**：由于 `-default-isolation=MainActor`，`@escaping`
  闭包不能再隐式引用 `self`。静音与恢复操作改为显式捕获 `self`，unsigned
  IPA 重新可以构建。
- **修复 iOS 27.0.1 "AirTraffic did not recover"**（读取时）：airlift 读取
  探针改为非空 payload，并增加诊断日志。

### 中文 / 新增
- **运行时日志采集**（`AirBeepLog`）+ 关于页一键导出，便于排查问题。
- **手动导入配对文件**：改用 `UIDocumentPickerViewController`（`asCopy`），
  规避沙盒安全作用域读取失败。
- **操作中屏幕常亮**，并显示醒目的"操作中请不要退出软件"提示横幅。

### 中文 / 安全
- 移除未使用的 `BadQuery` 漏洞，仅保留 `airlift`。

### 中文 / 基础设施
- 产品由 `placard` 更名为 `airbeep`（项目、scheme、bridging header、
  workflow、脚本全部同步）。
- 支持范围更新为 **iOS/iPadOS 18.0 – 27.2 B2**（与 AirCard / AirliftSilence
  对齐）。

---

**Full Changelog**: [v2.2.0...v2.3.0](https://github.com/LinkPass888/AirBeep/compare/v2.2.0...v2.3.0)