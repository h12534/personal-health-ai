# iOS Build Checklist

本清单用于 macOS CI、开发 Mac、真机和 TestFlight。Windows 本地结果不能关闭任一原生门禁。

## A. macOS no-codesign

- [x] 记录 macOS 版本和 CPU 架构：26.6.2 / arm64。
- [x] `xcodebuild -version`：26.6 / 17F113。
- [x] `flutter doctor -v` 已记录；iOS 构建无阻断项。
- [x] Flutter 3.47.5；`flutter pub get` 成功。
- [x] `dart run tool/configure_ios.dart` 使用 CI 默认 Bundle ID/display name。
- [x] `dart format --output=none --set-exit-if-changed lib test tool`。
- [x] `flutter analyze`。
- [x] `flutter test`：37 tests PASS。
- [x] `flutter build ios --release --no-codesign --dart-define=APP_ENV=staging --dart-define=API_BASE_URL=https://.../api/v1`。
- [x] commit SHA、完整命令、退出码、Xcode/Flutter 版本与 Runner.app 24.4MB 已记录于 `CI_AUDIT.md`。

## B. 签名与真机开发构建

- [ ] 最终确认 `IOS_BUNDLE_ID`、Development Team 和显示名。
- [ ] Runner target 启用 HealthKit；APNs 验收时再启用 Push Notifications/Background Modes。
- [ ] Xcode 自动签名或受控 provisioning profile 成功。
- [ ] 记录 iPhone 型号、iOS 版本、设备 ID 的脱敏后缀和安装时间。
- [ ] `flutter run -d <device>` 或 Xcode Run 可冷启动、前后台切换和重启。

## C. Archive/TestFlight

- [ ] App Icon 已替换 Flutter 默认图标；Launch Screen 无占位品牌。
- [ ] `0.1.0-beta.1` 与递增 build number 一致。
- [ ] Production HTTPS endpoint、privacy policy、support URL 和 App Privacy 已确认。
- [ ] Xcode Archive → Validate App → Upload 成功。
- [ ] App Store Connect processing 成功，无 ITMS 阻断警告。
- [ ] 只创建 Internal Testing，测试者仅所有者本人。
- [ ] 从 TestFlight 安装并重复核心真机矩阵。

## Evidence 记录

| 项目 | 实际值 |
|---|---|
| Commit SHA | `af22faaab2b6694ff00808d07f7f8ad0edea4b48` |
| macOS | 26.6.2 (25G83) / arm64 |
| Xcode | 26.6 (17F113)；CocoaPods 1.17.0 |
| Flutter/Dart | 3.47.5 / 3.13.4 |
| iPhone / iOS | 待填写 |
| Bundle ID | 待确认（默认 `com.personal.healthcoach`） |
| Build | `0.1.0-beta.1+2`（上传前确认递增） |
| CI run / Archive / TestFlight URL | [CI 37134206768](https://github.com/h12534/personal-health-ai/actions/runs/37134206768)；Archive/TestFlight 尚未执行 |
