# iPhone / TestFlight Beta Readiness

状态定义：“代码就绪”表示仓库中已实现；“外部门禁”表示需要 Apple 凭据、macOS/真机、域名或服务器才能证明，不伪造通过。

| 项目 | 状态 | 验收 |
|---|---|---|
| Bundle ID | 代码就绪 | `IOS_BUNDLE_ID` 生成本地 xcconfig；发布前锁定与 App Store Connect 一致的 ID |
| Team ID / Signing | 外部门禁 | 需 Apple Developer Team、发布证书和 provisioning profile |
| App Name | 代码就绪 | `APP_DISPLAY_NAME` 可配置；上传前确认最终中英文名 |
| App Icon / Launch Screen | 需产品确认 | 资产槽位完整；需在真机确认不是占位视觉且各尺寸无 alpha |
| Privacy strings | 代码就绪 | Camera、Photos、HealthKit、Face ID 用途说明已写入 Info.plist |
| HealthKit capability | 代码就绪/真机待验 | entitlement 与 Xcode capability 已存在，只读分类授权；需真机验证部分授权和撤权 |
| Camera / Photos / Files | 代码就绪/真机待验 | 权限语义与 PDF document picker 已实现 |
| Notifications | 代码就绪/真机待验 | 延迟授权、本地定时、快捷完成、锁屏脱敏；APNs 凭据待提供 |
| Network HTTPS | 代码就绪/域名待配 | staging/prod 拒绝 HTTP，未添加全局 ATS 放行 |
| Keychain / App Lock | 代码就绪/真机待验 | Token 保留 Keychain，可选 Face ID/Touch ID 默认关闭，2 分钟后台宽限 |
| Privacy policy / support URL | 外部门禁 | 需真实 HTTPS URL，内容与 Provider/保留/删除一致 |
| iOS no-codesign build | CI 已配置 | 需 Git remote 启用 Actions 后获得 macOS 实际结果 |
| TestFlight upload | 外部门禁 | 需签名、App Store Connect record、版本/构建号和审核 metadata |

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
