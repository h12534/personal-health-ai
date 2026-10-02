# iOS Native Acceptance

静态审计日期：2026-10-02。iOS deployment target 为 16.0，Swift 5，HealthKit entitlement 已提交；Bundle ID 与显示名通过 xcconfig 可覆盖。Windows 上完成了 Dart analyze/test，但所有 native runtime 项仍需 macOS 和 iPhone 实证。

| 能力 | 锁定依赖 | 静态状态 | macOS/真机验收 |
|---|---:|---|---|
| HealthKit | `health 13.3.1` | entitlement、用途说明、按类型授权、去重和 null≠0 代码已审计 | 授权/拒绝/恢复；Steps/Distance/Energy/RHR/Sleep/Workout；iPhone/Watch 多来源 |
| UIDocumentPicker | iOS 原生桥接 | 文件选择器实现存在，体检只生成 Draft | 文本 PDF、扫描 PDF、取消、权限/损坏文件 |
| Image Picker/Camera | `image_picker 1.2.3` | Camera/Photo usage strings 存在，无 microphone 权限 | Camera、照片、limited library、HEIC/JPEG/旋转/后台恢复 |
| Keychain | `flutter_secure_storage 9.2.4` | `first_unlock_this_device`；Token 不入 SQLite | 安装升级、锁屏、rotation、logout、远端失效 |
| Local Notifications | `flutter_local_notifications 22.3.1` | 延迟请求权限、DND、固定提醒、隐私文案、权限诊断 | 允许/拒绝/Settings 恢复、锁屏、Action、时区/跨夜 |
| Timezone | `flutter_timezone 5.1.0` | 本地时区用于 schedule，失败 fallback | 上海/东京/UTC/DST 设备或模拟配置 |
| Face ID/Touch ID | `local_auth 3.0.2` | 用途说明、biometric-only、后台 2 分钟锁 | 开/关、成功、取消、失败、锁定/无 biometrics |
| Drift/SQLite | `drift 2.35.0` | meal/workout/outbox/lab cache；删除覆盖；pending count | 杀 App、重启、飞行模式、恢复同步、无重复 |
| Networking | `dio 5.x` + `connectivity_plus 6.1.5` | staging/prod HTTPS；401 单次 retry；refresh rotation | token expiry、DNS/TLS/飞行模式/弱网/服务器 5xx |
| File directories | `path_provider 2.1.6` | sandbox 路径，无硬编码用户路径 | 升级、存储压力、删除和 orphan 检查 |

## 静态隐私结论

- Camera/照片权限不等于第三方 AI 授权；远程 Vision 必须单独 opt-in。
- OCR 远程处理由 `allow_remote_ocr` 显式控制，结果保持 Draft，用户确认后才进入正式数据。
- Beta diagnostics 不写 Token、API Key、健康数值、聊天正文、Provider 原始 payload 或私有文件路径。
- iOS `Info.plist` 不含 `NSAllowsArbitraryLoads`。

## 当前结果

- Static/Dart：PASS（Flutter analyze 0 issues；37 tests）。
- macOS native build：NOT RUN。
- iPhone runtime：NOT RUN。
- 本文不把 Simulator 或 Mock Provider 结果计作真机 PASS。
