# Free Signing Entitlement Audit

审计：2026-10-04。当前分发为 **Private Personal Sideload**。代码/未签名编译/ZIP 检查不代表 Windows 免费重签名或真机 PASS；目前后二者 **NOT RUN**。

## 来源与关键结论

Apple [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)按 ADP / Enterprise / 免费 Apple Developer 三列列出能力。HTML 原始表格的 HealthKit 与 Keychain sharing 三列均为 `icon-checksolid` / `alt="yes"`；Push notifications 的免费列为空。**基础 HealthKit 不能被笼统写成必需付费**，但个人签名工具仍可能不申请/丢弃 entitlement。最终以这个账户、工具版本、实际 profile/签名及设备表现为准。

Apple [entitlements 文档](https://developer.apple.com/documentation/bundleresources/entitlements)区分源配置与 code signing 后的权限：unsigned Runner 没有已签名 entitlement。本项目保留 HealthKit 原配置并附请求 plist；请求文件不会授予权限。Sideloadly [当前更新日志](https://sideloadly.io/changelog)将 custom entitlements 标为付费账号/Patreon 功能，本阶段不依赖它、不破解限制。若免费工具没有产生所需权限，记录工具限制，而非假造 Apple 能力规则。

## A：普通免费个人签名预计可用（仍需真机复核）

| 能力 | 当前配置/处理 | 预期与实际边界 |
|---|---|---|
| 基础 App 启动、HTTPS、Flutter/SQLite/Drift | iOS 16 target、无全局 ATS 放行 | 不依赖付费 entitlement；设备启动/真实 API 未验 |
| 普通单 App Keychain | `flutter_secure_storage` 9.2.4；`first_unlock_this_device`，无自定义共享 access group | Token 仍只存 Keychain；重签名需有效 application-identifier/个人 team 默认 group。不回退明文；升级/续签/账户变化需测 |
| Face ID / Touch ID | `local_auth`，`NSFaceIDUsageDescription` | 用户许可/设备能力决定，不是 APNs 或会员门禁；失败允许取消，默认不锁死 |
| Camera / Photo Library / PDF | Image Picker、用途说明、原生 UIDocumentPicker | 用户许可/limited Photos/文件访问需测，保留现有实现 |
| Local Notifications | `flutter_local_notifications` | 用户授权与 iOS 调度；不需要 `aps-environment` 或 APNs key，晨重/训练/睡眠规则保留 |
| 手动健康、饮食、训练、离线 | 原有手工晨重/训练和 Outbox | 不依赖 HealthKit；不能伪造步数/心率，null 不冒充 0 |

## B：当前暂停的付费发布服务

| 服务 | 当前行为 |
|---|---|
| APNs Remote Push | 原始 Runner.entitlements 本就没有 `aps-environment`；personal 模式在 ApiClient 阻止 push-device 注册。后台 APNs Provider 保留，但不是本次门禁；App 打开时用现有服务端任务/通知同步 |
| Apple Distribution / App Store Connect / TestFlight | 现有 signing Job/脚本/Secrets 架构保留，必须未来明确设置 `APP_DISTRIBUTION=app_store` 并重新 opt-in 才运行。本次不读取 Apple Secrets、生成证书、上传或索取会员信息 |

没有额外 App Groups/iCloud/Siri/Associated Domains/Network Extension entitlement；不为个人安装新增这些能力。

## C：必须实测，不能现在确认

| 项目 | 验证方法/记账 |
|---|---|
| HealthKit 免费重签名 | 先安装 HealthKit-attempt IPA，查看签名/安装日志及 App 诊断，按数据分类主动授权、拒绝/恢复、读取本人数据。只有实际成功才 PASS |
| HealthKit 工具不支持 | 日志/profile/设备证明缺少 capability，记 `UNSUPPORTED_BY_FREE_SIGNING` 并注明具体工具/账户/版本，不泛化为所有免费 Apple Account 都不支持 |
| HealthKit 真正代码/runtime 错误 | 可用 profile/签名仍失败，记 FAIL 并收集 request_id/脱敏诊断，不用 fallback 掩盖错误 |
| Keychain 续签持久化与隔离 | 同账号/同实际 Bundle ID 覆盖后重开/重启，再验证 logout；换工具/ID 后可能不能访问原 item，不保证迁移 |
| Face ID、相机、文件、本地通知 | 真机各权限状态与生命周期/锁屏；单元测试不能代替 |

## Capability fallback 与双产物

- `APP_DISTRIBUTION=personal_sideload` / `PERSONAL_SIDELOAD_HEALTHKIT`：保留 `Runner.entitlements` 的 `com.apple.developer.healthkit=true`。新增只读原生 probe 检查 HealthKit device availability、installed embedded profile eligibility，以及本人 App Mach-O 签名中实际 XML entitlement；缺失/格式无法解析/MethodChannel 错误则 fail closed，选择手动数据，不自动申请读权限。不会调用私有 Security API 或生成/修改签名。
- probe 只检查权限字段，**不是自行验证密码学签名，也不表示用户授予了读取权限**（有效签名由 iOS 安装/启动检查）。DER-only/未知签名格式保守 fallback，即使可能支持也不能记为 UNSUPPORTED，先留待诊断。Apple 不透露准确读授权，仍通过真实数据/设置/安装日志验收；正式 App Store 默认配置不改变。
- `PERSONAL_SIDELOAD_FREE=true`：native/Dart 配置同步；单独空 entitlement 文件，完全不调用 Apple HealthProvider，只用既有 ManualHealthProvider/原手工页面。界面显示“当前私人免费签名版本未启用 Apple Health 自动同步，可以手动记录数据。”
- 两版 Remote Push off，Local Notifications on；Keychain/Face ID/Camera/API/AI/Offline 保留。原正式 HealthKit plist、APNs 后端、付费发布脚本不删除。
- 无健康源/离线时不虚构指标；原生 capability 异常可恢复。iOS 拒绝安装无法在 Dart 层处理，此时改安装 free IPA，不能声称 runtime fallback 修复了操作系统签名失败。

免费 profile 期限/设备/App 数量按 [Apple Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)；刷新是重签名，不是突破限制。最终记账在 `IPHONE_PERSONAL_ACCEPTANCE.md`。
