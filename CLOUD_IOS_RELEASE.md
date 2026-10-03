# Cloud macOS + Apple Developer + Physical iPhone

更新：2026-10-04。**不要求购买或拥有 Mac**；云端 macOS/Xcode 负责签名、Archive/Export 和上传，所有者用自己的 iPhone 从 TestFlight 安装并验收。

## 路线决定

选择 **A：GitHub Actions**，延续 `.github/workflows/ci.yml` 的 Flutter 3.47.5 与 SwiftPM/CocoaPods fallback。复用 Codemagic 的开源 CLI（固定 `0.69.0`）做签名管理，不需要 Codemagic 托管账号。路线 B 作为备选，不同时维护两套发布流水线。

| 比较 | A：GitHub Actions | B：Codemagic 托管 |
|---|---|---|
| 配置复杂度 | 本项目已有真实 macOS CI；增加受保护签名 Job | 新建账号、连接 GitHub、创建 Apple integration 与 workflow |
| Apple signing | CLI 自动复用同一私钥对应证书，创建/拉取 App Store profile；手动导入 fallback | UI 能生成证书、拉取 profile；移动发布设置较集中 |
| TestFlight 上传 | API Key + CLI publish；所有者手工分配内部组 | 内建 App Store Connect 发布集成 |
| Secrets | GitHub `ios-beta` Environment Secrets；限制 release 分支 | encrypted environment groups / Apple integration；限制 workflow |
| Flutter | 沿用已通过的固定版本、analyze/test/native build | 原生支持 Flutter，仍需固定 Flutter/Xcode |
| 成本 | 当前仓库为所有者授权 Public；标准 GitHub-hosted runners 免费，存储/非标准 runner 另看限额 | 个人账号 M2 每月 500 分钟；超额当前 $0.095/min；Team 不享个人免费分钟 |
| 长期维护 | 同一 GitHub 审计和 CI；维护固定 CLI、Flutter 与 runner 标签 | 多一个服务、权限与账单；平台简化签名管理 |

费用以 [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) 和 [Codemagic pricing](https://docs.codemagic.io/billing/pricing/) 为准（2026-10-04 核对）。签名机制见 [CLI fetch-signing-files](https://github.com/codemagic-ci-cd/cli-tools/blob/v0.69.0/docs/app-store-connect/fetch-signing-files.md)、[Codemagic signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/) 与 [GitHub signing security](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。

仓库仍是已授权的 **Public 开源仓库**，本次不改变可见性。若未来选择 Codemagic，连接这个现有仓库，不另建 Public/Private 仓库。

## 当前真实状态

- Real GitHub CI / iOS no-codesign 编译：**PASS / CLOSED**，[run 37135036631](https://github.com/h12534/personal-health-ai/actions/runs/37135036631)，commit `42bbd93baf73312167a32529fe7cb711018effb5`，五个 Job SUCCESS。
- 所有者：已确认有 iPhone；**尚未办理 Apple Developer Program**，iPhone 型号/iOS 版本未提供。
- Cloud signed Job：仓库实现；**尚未签名执行**，默认不启用。
- Distribution signing / signed IPA / App Store Connect upload / processing / TestFlight 安装 / physical acceptance：**NOT RUN**。
- 真实 Staging HTTPS API：**未提供/未验**；`.invalid` 仅用于编译，不能用于 Beta 登录。
- 不将“已配置”、Mock、单元测试、未签名 Runner.app 或上传命令成功记成 TestFlight 可安装。

## 所有者最少准备（按顺序）

1. 自行办理并等待 [Apple Developer Program](https://developer.apple.com/programs/enroll/) 生效；官方年费 $99 或当地币种。苹果账号密码和 2FA 只在 Apple 网站/App 输入，**不要发给助手**。
2. 提供非敏感 Team ID、最终 explicit Bundle Identifier、App Display Name。先在 Apple Developer 网页注册对应 App ID 并启用 **HealthKit**。Bundle ID 不要继续盲用占位默认值。
3. 在 App Store Connect 创建 iOS App record：名称、语言、匹配 Bundle ID、自定 SKU；记下数字 Apple App ID（`ASC_APP_ID`）。App ID 注册和 App record 不能由助手猜测。
4. 创建专用 **Team API Key**，记录 Key ID、Issuer ID；`.p8` 只能下载一次，安全备份后直接录入 GitHub Environment Secret。自动创建 Distribution certificate 所需权限优先专用 Admin key；若组织不允许该权限，用手动签名材料并把上传 key 限为 App Manager。不要混淆 API `.p8` 与 Distribution certificate 私钥。
5. 提供 iPhone 可达、可信 TLS 的 HTTPS API `/api/v1` 地址；后端 `/health/ready` 必须通过数据库、Redis、storage 检查。它是非敏感编译配置，不得嵌入 key、账号密码或 token。

说明：不要求 UDID、开发设备登记、本地 USB/Xcode 或 Developer Mode 来安装 TestFlight Beta。仅需要所有者自己的 Apple Account 能访问内部组。

## GitHub 一次性安全设置

在 Settings → Environments 创建 **`ios-beta`**：限制 deployment branches 为 `main` 与 `feature/release-candidate-beta`，配置所有者审批（若计划支持；必须保留所有者能实际审批的设置），禁用不需要的自动发布。Public 仓库禁止给 PR、fork、任意分支发签名 Secrets。

**已实际完成（2026-10-04）**：当前授权仓库的 `ios-beta` 空环境已创建，required reviewer 为所有者 `h12534`、允许所有者审批自己的运行，部署分支仅 main/RC；Secrets/Variables 仍为空，发布开关未启用。所有者之后只需在这个既有环境录入 Apple Secrets 与上述非敏感变量，不要重复创建环境。

Environment Variables（不是私钥）：

| 名称 | 内容 |
|---|---|
| `IOS_TEAM_ID` | 10 位 Team ID |
| `IOS_BUNDLE_ID` | 最终 explicit Bundle ID |
| `APP_DISPLAY_NAME` | 最终手机显示名 |
| `ASC_APP_ID` | App record 数字 ID |
| `IOS_BETA_API_BASE_URL` | 实际 `https://host/api/v1` |
| `IOS_SIGNING_MODE` | `automatic`（默认）或 `manual` |

Environment Secrets：

| 名称 | 内容 |
|---|---|
| `APP_STORE_CONNECT_ISSUER_ID` | Team API Key Issuer ID |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | 完整 `.p8` 内容，只在 Secrets UI 或安全 stdin 输入 |
| `IOS_CERTIFICATE_PRIVATE_KEY` | 自动模式：持久化 RSA 私钥 PEM，匹配 Distribution certificate；不是 API `.p8` |
| `IOS_DISTRIBUTION_P12_BASE64` | 手动模式：含私钥的 Apple Distribution `.p12` 的 base64 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | 手动模式：`.p12` 密码，可为空 |
| `IOS_PROFILE_BASE64` | 手动模式：App Store HealthKit profile 的 base64 |

证书、profile、APNs key 同样必须仅存 Secrets/加密环境变量，**不得 commit 或粘贴到聊天**。现有 Local Notifications 不依赖 APNs；APNs key 不是本次签名或内部安装的前置项。真实 remote push 是独立后续门禁。

### 自动签名（优先）

先创建 HealthKit App ID，再配置 API Key 和可复用的 Distribution RSA 私钥。GitHub Runner 使用 `fetch-signing-files --type IOS_APP_STORE --strict-match-identifier --create` 复用/创建匹配证书与 profile，将证书导入临时 keychain。

Windows PowerShell 7 / GitHub CLI 可一次性将新 RSA 私钥直接通过 stdin 存 Secret，无需 Mac、无明文落盘，也不打印到终端（仅在所有者准备好后自行执行）：

```powershell
$iosSigningRsa = [System.Security.Cryptography.RSA]::Create(2048)
try {
    $iosSigningRsa.ExportPkcs8PrivateKeyPem() | gh secret set IOS_CERTIFICATE_PRIVATE_KEY --env ios-beta --repo h12534/personal-health-ai
    if ($LASTEXITCODE -ne 0) { throw 'Failed to save signing secret' }
} finally {
    $iosSigningRsa.Dispose()
}
```

必须保存并复用这把 key，**不要每次构建生成新 key/certificate**。Apple 不能回传已丢失的 Distribution 私钥。达到证书数量限制时停止并让所有者选择复用/撤销，不自动撤销其他证书。API 权限或 profile capability 不足时明确失败，不关闭 HealthKit、不绕过签名。

### 一次性人工 fallback（无需 Mac）

若自动 API 受账户权限限制：在受控 Windows 环境用 OpenSSL 生成 RSA 私钥和 CSR；在 Apple Developer 网站选择 Apple Distribution、上传 CSR、下载 `.cer`；用同一私钥与 `.cer` 导出带密码 `.p12`。网页生成匹配 App ID/证书的 App Store provisioning profile（包含 HealthKit），把 `.p12` 和 profile 的 base64 分别录入上述 Secrets，设置 `IOS_SIGNING_MODE=manual`。只在受控、仓库外的临时目录操作，完成后安全删除临时私钥；不要从 Git repo 里导出/保存。

## 执行与产物

在仓库 **Variables** 设置 `IOS_RELEASE_ENABLED=true` 后推送已验证 RC 分支；如需同时上传，再明确设置 `IOS_TESTFLIGHT_UPLOAD=true`。未配置时签名 Job **NOT RUN**，不是门禁 PASS。配置只负责 opt-in，不减少现有五个 Job 的检查。

如果 workflow 已进入 default branch，可在 Actions → CI → Run workflow 选择 RC ref，勾选 `signed_ios`；只有明确勾选 `upload_testflight` 才上传。新 workflow 尚不在 default branch 时，UI/dispatch 可能不可用：用上述 RC push opt-in，不为显示按钮擅自合并 main。

签名 Job 依赖 Backend、Postgres、Release Audit、iOS 编译检查通过，并再次执行 `flutter pub get`、配置身份、format、`flutter analyze`、`flutter test`。使用 `macos-26`；记录 `xcodebuild -version` / CocoaPods / Flutter，而不假定 runner 标签等于固定 Xcode patch。

真正构建命令：

```bash
flutter build ipa --release \
  --export-options-plist="$SIGNING_DIR/ExportOptions.plist" \
  --build-name=0.1.0 --build-number="$BUILD_NUMBER" \
  --dart-define=APP_VERSION=0.1.0 --dart-define=BUILD_NUMBER="$BUILD_NUMBER" \
  --dart-define=APP_ENV=staging --dart-define=API_BASE_URL="$API_BASE_URL"
```

发布版本为 Apple 接受的数字 `0.1.0`；TestFlight 本身表达 Beta。仓库 `0.1.0-beta.1+2` 不直接作为 Apple marketing version。Build 为 workflow run number + attempt（例如 `21.1`），递增且与 Beta Debug 显示完全一致；已有更高 Apple build 时需调整版本或递增策略，不能重用旧号。

输出：`mobile/build/ios/ipa/*.ipa` 与 `release-evidence.json`；校验 codesign、Team/Bundle/显示名/native build、iOS 16、App Store profile、HealthKit entitlement。`testFlightInternalTestingOnly=true`；上传调用不带 external beta review/App Store review 参数。

GitHub artifact 只保留 IPA + 不含 secrets 的证据，7 天自动过期；**不上传** `.p8`、独立 profile、证书/keychain 或完整 archive。IPA 内按 Apple 格式必须嵌入公开签名证书/profile；它不含签名私钥，但包含可提取的客户端代码/API host。Public repo artifact 对有下载权限的人可见；严禁把 backend Provider keys 编译进 App。临时签名目录/keychain/profile 在 `always()` 清理，GitHub-hosted VM 随 Job 销毁。

## TestFlight 只添加所有者本人

1. 上传后在 App Store Connect 等 Apple processing 完成；处理失败不能记为成功。
2. 按实际加密使用填写 export compliance；不自动虚报无加密。完善本次要求的 Beta 信息。
3. TestFlight → Internal Testing → 新建 `Owner Only` 内部组，只选择所有者本人；将 processed build 加入该组。不建外部组、公开邀请链接、不新增其他账户。
4. 在 iPhone 安装 Apple TestFlight，接受本人邀请并安装。记录 build、安装时间和型号/iOS，不需要 Mac。

具体内部组流程见 [Apple internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)；上传与 processing 见 [Apple upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)。

## Physical iPhone 验收与 Debug Limitation

通过 TestFlight 对登录/Refresh、Keychain、Face ID、Camera、Photo Library（拒绝/limited）、PDF Picker、HealthKit（按类型开关/拒绝/恢复/null≠0）、Local Notifications、Offline Meal、Offline Workout、杀 App/重启/前后台、HTTPS API 全部实测。完整记录模板为 `TESTFLIGHT_IPHONE_ACCEPTANCE.md`，不以 Mock 或 Simulator 代替。

Beta Debug Screen 显示版本/build、环境、**API host（无路径/query/credentials）**、HealthKit availability/同步开关状态（Apple 不公开读权限）、通知权限、最近同步、Pending Outbox、最近 server health check、Provider 配置状态及 request_id。配置 Provider 不等于真实 Provider 已验收。

结构化客户端日志只记录事件、错误类别、时间、状态码、耗时、UUID request_id；生命周期事件有日志。服务端同一 `X-Request-ID` 可关联日志；diagnostic export 支持复制，分享前检查。已有 CrashReporter 抽象保留本地兜底，无 Sentry key 不阻塞，不自动把健康数据发送给第三方。

没有本地 Xcode 时，无法实时 LLDB、Instruments 或 USB 调试；记录为 **Debug Limitation**，不是安装/验收必需门禁。优先诊断导出、TestFlight crash/feedback、server logs，保留云构建版本/符号用于后续排障；云重建验证修复。原生 hard crash 可能来不及写 Dart 日志，不能宣称本地 CrashReporter 已覆盖全部 native crash。
