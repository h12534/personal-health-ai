# iPhone / TestFlight Beta Readiness

> 2026-10-04：Real GitHub CI 已关闭，[最终 run 37135036631](https://github.com/h12534/personal-health-ai/actions/runs/37135036631) 五个 Job 全部 SUCCESS。整体仍未 Beta Ready；下一门禁是 **Cloud macOS signing → IPA → TestFlight → physical iPhone acceptance**。**不要求拥有本地 Mac**。具体配置见 `CLOUD_IOS_RELEASE.md`。

实际全绿：[workflow 37134206768](https://github.com/h12534/personal-health-ai/actions/runs/37134206768)，commit `af22faaab2b6694ff00808d07f7f8ad0edea4b48`。Ruff、strict mypy、83 backend tests、7 PostgreSQL integration tests、Redis、迁移/恢复演练、Flutter analyze、37 Flutter tests、iOS no-codesign 和 Android secondary 均有 SUCCESS 证据。首轮 PostgreSQL 元数据漂移与 Android desugaring 失败已在该提交修复，未降低任何门禁。

状态定义：“代码就绪”表示仓库中已实现；“外部门禁”表示需要 Apple 凭据、云 macOS/真机、域名或服务器才能证明，不伪造通过。所有者已确认有 iPhone，但尚未办理 Apple Developer Program；Team/Bundle/App record/API Key/真实 HTTPS API 尚未提供。

| 项目 | 状态 | 验收 |
|---|---|---|
| Bundle ID | 代码就绪 | `IOS_BUNDLE_ID` 生成本地 xcconfig；发布前锁定与 App Store Connect 一致的 ID |
| Team ID / Signing | 外部门禁 / NOT RUN | 云 CI 自动管理证书/profile 优先，手动 Secrets 导入 fallback；不要求本地 Mac |
| App Name | 代码就绪 | `APP_DISPLAY_NAME` 可配置；上传前确认最终中英文名 |
| App Icon / Launch Screen | 需产品确认 | 资产槽位完整；需在真机确认不是占位视觉且各尺寸无 alpha |
| Privacy strings | 代码就绪 | Camera、Photos、HealthKit、Face ID 用途说明已写入 Info.plist |
| HealthKit capability | 代码就绪/真机待验 | entitlement 与 Xcode capability 已存在，只读分类授权；需真机验证部分授权和撤权 |
| Camera / Photos / Files | 代码就绪/真机待验 | 权限语义与 PDF document picker 已实现 |
| Notifications | 代码就绪/真机待验 | 延迟授权、本地定时、快捷完成、锁屏脱敏；Local Notifications 不依赖 APNs，remote push 另验 |
| Network HTTPS | 代码就绪/域名待配 | staging/prod 拒绝 HTTP，未添加全局 ATS 放行 |
| Keychain / App Lock | 代码就绪/真机待验 | Token 保留 Keychain，可选 Face ID/Touch ID 默认关闭，2 分钟后台宽限 |
| Privacy policy / support URL | 外部门禁 | 需真实 HTTPS URL，内容与 Provider/保留/删除一致 |
| Real GitHub CI | PASS / CLOSED | 上述 workflow 五个 Job 全绿；公开开源仓库由所有者明确授权，main/RC 已推送 |
| PostgreSQL / Redis / Restore | PASS（CI） | 真实 PostgreSQL 16.15/pgvector，7 integration tests，10 表恢复 count/UUID 核验与 artifact |
| iOS no-codesign build | PASS（真实 macOS CI） | macOS 26.6.2 arm64、Xcode 26.6 (17F113)、CocoaPods 1.17.0；Runner.app 24.4MB；尚未签名/安装真机 |
| Android secondary | PASS（真实 CI） | Java 17、desugaring、Gradle debug APK 成功；不改变 iOS 主平台定位 |
| Cloud signed IPA | 流程实现 / NOT RUN | `mobile-ios-signed` 默认关闭，真实运行前需 Apple membership 与受保护 Secrets |
| TestFlight upload / processing | 外部门禁 / NOT RUN | API Key 上传；processed build 只分配所有者一人的内部组 |
| Physical iPhone acceptance | NOT RUN | 用 TestFlight Beta 验收；记录模板 `TESTFLIGHT_IPHONE_ACCEPTANCE.md` |

## 真机 Beta 清单

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
