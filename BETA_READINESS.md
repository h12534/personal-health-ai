# Private Personal Sideload Readiness

> 2026-10-05 UI RC follow-up: the historical CI PASS below is not acceptance of the newer UI redesign. The feature-branch UI gate is currently **OPEN**, pending fail-closed macOS screenshot export, individual review and strict reviewed-pixel baselines; current retry [37282718158](https://github.com/h12534/personal-health-ai/actions/runs/37282718158). Latest local full suites: standard / HealthKit-attempt / free each 268 tests pass; safety script suite 36 pass. No new screenshots are committed. Cloud code compilation, unsigned IPA generation and physical iPhone installation remain separate gates; no local Mac is required. Current evidence: `UI_RC_ACCEPTANCE_REPORT.md` and `CI_AUDIT.md`.

> 2026-10-04 发布目标调整：**Private Personal Sideload**。不要求付费 Apple Developer、本地 Mac、App Store Connect 或 TestFlight；下一门禁是 **Windows 免费重签名 → 本人 iPhone 安装/启动**。云端双 unsigned IPA 已真实生成、下载并核验；安装与首次启动仍 NOT RUN。

本轮代码实际 CI 全绿：[workflow 37183670494](https://github.com/h12534/personal-health-ai/actions/runs/37183670494)，commit `d029f4956cf854015d52b751a92abf2a268b146e`。五个原有 Job 与 personal sideload Job SUCCESS，付费签名 Job SKIPPED / SUSPENDED。Ruff、strict mypy 165 files、89 backend tests、7 PostgreSQL integration tests、Redis、迁移/恢复、Flutter analyze、三种模式各 47 tests、24 guardrail tests、iOS no-codesign / Android 均有真实证据。运行产出 `0.1.0` / build `8.1` 双 IPA，已下载核对完整 SHA256/版本/commit/arm64 unsigned/Payload；详细 Job/hash 在 `CI_AUDIT.md`，未降低门禁。

状态定义：“代码就绪”表示仓库实现，不伪造设备通过。所有者已确认有 iPhone；现在不要求 Apple paid membership、Team ID、App record 或 API Key。免费 Apple Account 只在 Windows 侧载工具内自行认证，不向助手/CI 提供密码或 2FA；真实 HTTPS API 仍未提供。原付费发布路径保留但暂停。安装说明见 `PERSONAL_SIDELOAD_WINDOWS.md`，能力审计见 `FREE_SIGNING_ENTITLEMENT_AUDIT.md`。

| 项目 | 状态 | 验收 |
|---|---|---|
| Bundle ID | 代码就绪 | `IOS_BUNDLE_ID` 生成本地 xcconfig；发布前锁定与 App Store Connect 一致的 ID |
| Personal Signing | Windows / NOT RUN | CI 不签名、不要求 Team ID；所有者免费 Account 在 Sideloadly/AltStore 完成，每约 7 天刷新 |
| App Name | 代码就绪 | `APP_DISPLAY_NAME` 可配置；上传前确认最终中英文名 |
| App Icon / Launch Screen | 需产品确认 | 资产槽位完整；需在真机确认不是占位视觉且各尺寸无 alpha |
| Privacy strings | 代码就绪 | Camera、Photos、HealthKit、Face ID 用途说明已写入 Info.plist |
| HealthKit capability | 正式配置保留/私人实测待验 | 先试保留 HealthKit 的版本；profile capability 检测失败自动手动 fallback；备用 free 版禁用 AppleHealthProvider，不虚构指标 |
| Camera / Photos / Files | 代码就绪/真机待验 | 权限语义与 PDF document picker 已实现 |
| Notifications | 代码就绪/真机待验 | 延迟授权、本地定时、快捷完成、锁屏脱敏；Local Notifications 不依赖 APNs，remote push 另验 |
| Network HTTPS | 代码就绪/域名待配 | staging/prod 拒绝 HTTP，未添加全局 ATS 放行 |
| Keychain / App Lock | 代码就绪/真机待验 | Token 保留 Keychain，可选 Face ID/Touch ID 默认关闭，2 分钟后台宽限 |
| Privacy policy / support URL | 正式发布未来门禁 | 私人安装不要求 App Store record；数据/Provider/删除隐私约束仍保留 |
| Real GitHub CI | PASS / CLOSED | 上述 workflow 五个 Job 全绿；公开开源仓库由所有者明确授权，main/RC 已推送 |
| PostgreSQL / Redis / Restore | PASS（CI） | 真实 PostgreSQL 16.15/pgvector，7 integration tests，10 表恢复 count/UUID 核验与 artifact |
| iOS no-codesign build | PASS（真实 macOS CI） | macOS 26.6.2 arm64、Xcode 26.6 (17F113)、CocoaPods 1.17.0；Runner.app 24.4MB；尚未签名/安装真机 |
| Android secondary | PASS（真实 CI） | Java 17、desugaring、Gradle debug APK 成功；不改变 iOS 主平台定位 |
| Personal unsigned IPA | PASS（CI + 下载独立核验） | [run 37183670494](https://github.com/h12534/personal-health-ai/actions/runs/37183670494) 的 HealthKit-attempt / PERSONAL_SIDELOAD_FREE 双 IPA、0.1.0 / 8.1 / hash/commit；无 CI Apple credentials，无 Runner 签名/profile |
| Apple Distribution / TestFlight / APNs | 当前暂停 | 不属于个人侧载门禁；原正式发布代码保留，需未来明确 opt-in |
| Physical iPhone acceptance | NOT RUN | Windows 免费重签名安装；记录 `IPHONE_PERSONAL_ACCEPTANCE.md`，不使用 TestFlight |

## 本人 iPhone 清单

每项记录 iPhone 型号、iOS 版本、App build、API 环境、时区、测试者和日期。

- [ ] 注册、登录、Refresh Token 轮换、退出后本地私有数据清理。
- [ ] 晨重手工记录，当日任务自动完成。
- [ ] 饮食手工记录和营养聚合。
- [ ] 拍照/相册饮食，EXIF 去除，Draft 编辑/确认/删除。
- [ ] 断网创建饮食，强制关闭/崩溃后重开，联网后 Outbox 幂等同步且不丢失。
- [ ] 训练开始、组次、休息计时、完成、PR 和进度。
- [ ] 断网训练，崩溃/强退后恢复进行中 Session，重试不重复组次。
- [ ] HealthKit 步数：允许、拒绝、无数据、部分授权、撤权、增量同步和状态页。
- [ ] HealthKit 睡眠去重、跨夜区间、无数据不显示为 0。
- [ ] AI Coach：Mock 与真实 Provider 分别验收，高风险问题被安全层短路。
- [ ] 知识问答：引用可打开、证据不足不确定、危急症状提示紧急就医。
- [ ] 体检 PDF：Files picker、远程 OCR 单次同意、Draft 修改、确认、趋势、原文件删除。
- [ ] 通知：启动不弹窗，解释后申请，允许/拒绝/撤权，晨重/训练/睡眠，勿扰，快捷完成，锁屏无敏感文本。
- [ ] 日报在数据不足时仍可生成，结构指标与源记录一致。
- [ ] 周报与月报缓存、手动重生成限制、无伪精确总分。
- [ ] Health Timeline 筛选和跨域对照；VoiceOver 读出指标名、值、单位和“非因果”声明。
- [ ] Face ID/Touch ID 默认关闭，开启失败不锁死，后台 2 分钟内不重复刷脸，超时后重新验证。
- [ ] JSON/CSV 导出可读且只包含当前用户；`DELETE MY DATA` 二次确认及删除后重登录行为。
- [ ] Dynamic Type 大字体、Dark Mode、键盘遮挡、SafeArea、大点击区和非单色状态。
