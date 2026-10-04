# Personal iPhone Acceptance

当前路径：Cloud macOS unsigned IPA → Windows Sideloadly / AltStore Classic 免费个人签名 → 所有者 iPhone。**不要求本地 Mac、付费会员、App Store Connect 或 TestFlight。** 整体设备安装/启动验收 **NOT RUN**，由所有者真实操作后填写；不预填 PASS。

| 证据 | 实际值 |
|---|---|
| CI run / source commit / artifact | 待实际构建；文件内 evidence 给出 commit/run |
| IPA SHA-256 / version / build / flavor | 待实际产物；使用 SHA256SUMS 核验 |
| Windows / 签名工具与版本 | 待所有者填写；不得写密码/2FA |
| 手机型号 / iOS | 所有者已有 iPhone，具体待填 |
| 实际重签名 Bundle ID / 到期时间 | 待安装工具显示；与源 IPA ID 可能不同 |
| 安装 / 首次启动 | NOT RUN |
| 实际 HTTPS API host / server ready | 未提供/未验；`.invalid` 不算部署 |
| 续签 / 更新 / 数据保留 | NOT RUN |

| 项目 | 实测条件 | 结果/脱敏诊断/request_id |
|---|---|---|
| 安装与启动 | 免费签名、trust/developer mode、冷启动无崩溃 | NOT RUN |
| 登录 / Token / Keychain | 真实 API 登录/refresh/logout，杀 App/重启/续签后预期安全存储 | NOT RUN |
| Face ID | 默认 off、启用/取消/失败、后台 2 分钟后重新锁定 | NOT RUN |
| Camera | 允许/拒绝、JPEG/HEIC、旋转、草稿取消 | NOT RUN |
| Photos | full/limited/denied、设置恢复 | NOT RUN |
| PDF | UIDocumentPicker、本机/iCloud Files、取消/坏文件 | NOT RUN |
| 本地通知 | 授权/拒绝/恢复、晨重/训练/睡眠、锁屏脱敏、点击 | NOT RUN |
| 饮食与 AI | 手工与照片草稿；真实 Provider 或明确 Mock，不冒充真实 AI | NOT RUN |
| 训练 | session/组次/计时/完成 | NOT RUN |
| 离线饮食 / 训练 | 飞行模式、强退重开、恢复网络幂等同步；续签前无丢失 Outbox | NOT RUN |
| 健康页面 | 报告/手动记录可用；free 模式有明确提示，缺测不显示为 0 | NOT RUN |
| HealthKit | 分类授权/拒绝/撤权/有数据读取/去重；记录 below 状态 | NOT RUN |
| API / lifecycle | HTTPS、超时/401/5xx、前后台/冷启动、无 secrets 的诊断 | NOT RUN |
| 7 天刷新 | 同账号/同实际 ID 覆盖续签、Daemon/AltServer；检查新 expiry 和本地数据 | NOT RUN |

HealthKit 最终仅允许实测后填写：**PASS / UNSUPPORTED_BY_FREE_SIGNING / FAIL**。未测试阶段为 NOT RUN；手动版禁用不能直接当证据证明所有免费账号不支持。工具丢失 entitlement 与 App 错误分别记录。先尝试 HealthKit IPA，失败可换 free 版本，安装整个 App 不因 HealthKit/APNs 卡死。

失败记录：版本/build/flavor、最短复现、预期/实际、tool error code、脱敏诊断、request_id、server logs、修复 commit/新 IPA/复测。续签/换工具/删除前先同步和导出，不把本人健康内容、账号标识或完整签名日志提交 Public Issues。

Debug Limitation：没有实时 LLDB/Instruments；优先 App 诊断导出、server request_id、云构建日志。原生 crash 可能来不及写 Dart 日志，不能声称已有完整 native crash telemetry。Sentry 未配置不阻塞、不自动向第三方传健康数据。
