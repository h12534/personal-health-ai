# Windows → Personal iPhone Sideload

当前目标：**Private Personal Sideload**（2026-10-04）。不买 Mac、不办理付费 Apple Developer、不使用 App Store/TestFlight。GitHub 只编译并打包；免费个人签名只在所有者 Windows 工具内完成。仓库仍是所有者已授权的 Public 开源，"Private" 指仅本人使用，不代表仓库或 artifact 是私密的。

## 下载本项目 IPA

1. 登录 GitHub，打开 [本仓库 Actions](https://github.com/h12534/personal-health-ai/actions)，选择 `feature/release-candidate-beta` 的成功 CI；先核对 commit。
2. 确认五个原有 Job 和 `mobile-ios-personal-sideload` 都 SUCCESS。`mobile-ios-primary` 本身只编译，不上传 IPA。
3. 在运行页面底部 Artifacts 下载 `personal-health-ios-unsigned`。解压 **GitHub 的外层 ZIP**，得到 `personal-health-ios-unsigned.ipa`、`SHA256SUMS`、`personal-sideload-evidence.json`、`requested-entitlements.plist`。不要把外层 ZIP 导入安装器，也不要解开/重新压缩 IPA。
4. 先尝试这个保留正式 HealthKit 源配置的版本。若签名/安装失败，或已安装但 HealthKit 不可用，改下载 `personal-health-ios-free-unsigned`，使用 `personal-health-ios-free-unsigned.ipa`（`PERSONAL_SIDELOAD_FREE`，明确禁用 Apple Health、保留手动记录）。两版不要同时安装；尽量保持同一 Apple Account 与实际 Bundle ID 覆盖更新，避免占用额外免费槽位或丢失本地数据。
5. PowerShell 核对哈希：`Get-FileHash -Algorithm SHA256 -LiteralPath '.\personal-health-ios-unsigned.ipa'`，与 SHA256SUMS/evidence 比较；free 文件同理。evidence 同时给出 version/build/commit/环境/API host 与未验收状态。

首个真实成功构建（已下载独立核验）：[run 37183670494](https://github.com/h12534/personal-health-ai/actions/runs/37183670494)，source `d029f4956cf854015d52b751a92abf2a268b146e`，`0.1.0` / build `8.1`。直接 artifact：[HealthKit-attempt](https://github.com/h12534/personal-health-ai/actions/runs/37183670494/artifacts/11296048839)、[free fallback](https://github.com/h12534/personal-health-ai/actions/runs/37183670494/artifacts/11296416798)。本地忽略目录 `artifacts/personal-sideload/37183670494/` 已有这两份 IPA；完整 hash 见 `CI_AUDIT.md`。Windows 签名和设备启动仍需你执行。

unsigned IPA 不含个人签名，因此无法直接点击安装。Artifact 保留 7 天（不是设备签名期限）；过期后重新构建。Public repo 的产物可能被他人下载：不含健康样本/签名材料/Provider keys，不等于防复制分发。

重新构建可由所有者在上述已有运行页面选择 **Re-run all jobs**；重新读取新 run attempt 的 evidence / hash / build，不重用旧哈希或旧到期时间。不为显示 Run workflow 按钮擅自合并 main。

## 路线 A：Sideloadly（当前首选）

本项目仅安装一个自有 IPA，优先 Sideloadly：无需额外安装 AltStore App，占用一个 App 槽位，Daemon 可在 Windows 自动刷新。使用 [Sideloadly 官方下载](https://sideloadly.io/)，不要使用第三方打包版、破解签名或他人共享证书。官方 [FAQ](https://sideloadly.io/faq) 与 [更新日志](https://sideloadly.io/changelog) 是安装/兼容性的依据。

1. 在受控 Windows 10/11 安装官方 Apple iTunes 与所需 iCloud/Apple Mobile Device 组件；按工具官网选择 Apple 直接下载版，不混用冲突的 Microsoft Store 驱动。下载入口只用 [Apple iTunes](https://www.apple.com/itunes/download/win64) 和工具官网链接；已有驱动时先检查，不擅自卸载软件。
2. 安装官方 Sideloadly。USB 连接已解锁 iPhone，在手机确认“信任此电脑”，确认 iTunes/Sideloadly 能看到设备。
3. 选择本人设备，导入 `.ipa`，使用你自己的免费 Apple Account，在本机工具内自行登录/确认 2FA。**密码/2FA 不发 Codex、不存 GitHub、不写日志**；使用第三方签名工具需由你自行判断账户风险，不保证工具是 Apple 官方产品。
4. 保持普通 sideload 模式，不启用 dylib 注入、越狱、绕过限制或付费 entitlement 功能。点击 Start，等待工具实际签名并安装；失败日志先脱敏，不含邮箱/设备标识/认证信息。
5. 按 iOS 提示在“设置 → 通用 → VPN 与设备管理”信任本人开发者；iOS 16+ 如要求，在“设置 → 隐私与安全性 → 开发者模式”启用、重启并确认。不要求 Mac/Xcode。
6. 打开 App；先核对诊断页 version/build/flavor。HealthKit 按 `FREE_SIGNING_ENTITLEMENT_AUDIT.md` 单独记录，不因缺少该能力将整个 App 判为无法使用。

Sideloadly 官方更新日志把“自定义 entitlements”标为 Apple Developer Program/Patreon 功能，**不把它当本次免费安装前置条件**。unsigned 包的请求 plist 只是审计说明，不会自动成为签名权限；不能承诺重签名工具自动保留 HealthKit。缺失时改用 free 版本/手动 fallback，不伪造 profile。

### 7 天和自动刷新

Apple [免费 Personal Team 规则](https://developer.apple.com/help/account/basics/about-your-developer-account)规定 profile 从签发起约 7 天、每设备最多 3 个 App、7 天内最多 10 个 App ID。不是“装一次永远不用管”。尽量第 5–6 天检查/刷新，过期后 App 可能无法启动。

启用 Sideloadly 自动刷新并检查 Daemon 正在运行；首次 USB 配对后可在 iTunes 开启 Wi-Fi 同步。电脑开机、Daemon 活跃、同一局域网且设备可被发现，或连接 USB 时，Daemon 才能续签。电脑长期关机、睡眠、网络隔离或 iPhone 无法发现都会影响刷新；旅行前 USB 手动刷新并确认新到期时间。自动化是重新签名，**不突破 Apple 7 天限制**。

更新和续签使用同一个 Apple Account、同一个工具实际生成的 Bundle ID，优先覆盖安装。切换签名工具、换账户、改 Bundle ID 或卸载会改变 Keychain access group/数据容器；不能承诺 Token/本地离线记录自动迁移。先同步 Outbox、导出必要数据，再操作；健康导出不提交 Public Issues。参见 [Sideloadly 刷新/覆盖说明](https://sideloadly.io/faq)。

## 路线 B：AltStore Classic / AltServer

仅作为替代，不使用 AltStore PAL、App Store 或 TestFlight 路线。按 [AltStore Windows 官方教程](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)安装 Apple 官网版本 iTunes/iCloud、下载 AltServer；USB 配对/信任、在 iTunes 开启 Wi-Fi 同步，运行 AltServer，仅开放需要的私有网络通信。通过托盘 Install AltStore 选择本人设备，在本机自行认证，按提示信任开发者/启用 Developer Mode。

把 IPA 保存到 iPhone Files（例如本人 iCloud Drive，或其他受控文件传输）；AltStore Classic → My Apps → `+` → 选择 IPA。只导入本仓库产物，不创建 public source 或邀请其他用户。AltStore 本身占用一个免费 App 槽位；本项目通常再占一个。

[AltStore 官方刷新说明](https://faq.altstore.io/altstore-classic/your-altstore)：开启 Background Refresh，电脑 AltServer 需可达；My Apps 的 Refresh All 可手动刷新。手机后台调度不是保证，每隔几天主动打开检查；电脑/网络条件不满足时不会永久续签。两条路线都保留 USB 手动刷新作为兜底。维护一个 App 时首选 Sideloadly；已有稳定 AltServer 环境则可沿用 AltStore，不强制切换。

## API 与诊断

CI 可选使用仓库非敏感变量 `PERSONAL_IOS_API_BASE_URL=https://实际域名/api/v1`、`PERSONAL_IOS_BUNDLE_ID`。未提供 API 时仍产出用于安装/启动验收的 IPA，但 evidence 标记 `api_configured=false` 并 warning；`.invalid` 不能登录或同步，**不是后端部署完成**。有真实 HTTPS 地址后重新构建，不嵌入 Provider key/Token，不开放全局 ATS HTTP。

App 保留安全 Token 存储、Face ID、Camera/Photos/PDF、AI/API、本地通知、饮食/训练离线；Remote Push 关闭，服务端提醒在打开 App 时走现有任务/通知同步。验收与排障记录见 `IPHONE_PERSONAL_ACCEPTANCE.md`；优先诊断导出/request_id/server logs。没有 LLDB/Instruments 记录为 Debug Limitation，不要求购买 Mac。
