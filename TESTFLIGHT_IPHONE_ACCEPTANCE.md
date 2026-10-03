# TestFlight Physical iPhone Acceptance

唯一默认验收路径：Cloud macOS signed IPA → App Store Connect processing → 所有者 Internal TestFlight → iPhone。**本地 Mac 不要求；USB flutter run 非必需。**

当前状态：NOT RUN。所有者有 iPhone，Apple Developer Program 尚未办理。以下每一项需要实测后记录，不预填 PASS。

| 发布证据 | 实际值 |
|---|---|
| Signing workflow run / commit | 待实际执行 |
| IPA artifact / SHA256 | 待实际构建 |
| Xcode / Flutter / macOS | 待签名 Job 日志 |
| App Store Connect App ID / processed build | 待实际上传处理 |
| Owner Only 内部组成员数 | 待确认 = 1（仅所有者） |
| iPhone 型号 / iOS / App version / build | 待提供/安装 |
| API host / 日期 / 时区 | 待实际验收 |

| 项目 | 通过条件 | 结果 / request_id / 备注 |
|---|---|---|
| Install / login | TestFlight 安装、注册/登录、Refresh 轮换、logout | NOT RUN |
| Keychain | 重开/重启/升级后预期持久化，logout 与失效清理 | NOT RUN |
| Face ID | 默认关闭、开启/成功/取消/失败、后台超时重新锁定 | NOT RUN |
| Camera | 授权/拒绝、旋转 JPEG/HEIC、Draft、不越权远程 Vision | NOT RUN |
| Photo Library | full/limited/denied、设置恢复、取消 | NOT RUN |
| PDF Picker | 文本/扫描 PDF、取消、坏文件、draft 确认 | NOT RUN |
| HealthKit | 分类请求、拒绝/撤权/恢复、无数据不写 0、去重 | NOT RUN |
| Local Notifications | 延迟授权、拒绝/恢复、锁屏脱敏、点击/时区 | NOT RUN |
| Offline Meal | 飞行模式创建、杀 App/重启、恢复网络幂等同步 | NOT RUN |
| Offline Workout | 断网组次与 session 恢复，不重复上传 | NOT RUN |
| App lifecycle | 冷启动、前后台、强退、重启、日志无 secrets | NOT RUN |
| HTTPS API | 真实 TLS、health ready、弱网/超时/401/5xx | NOT RUN |
| Beta diagnostics | 所有要求字段可读；导出仅状态/UUID，无健康正文/token | NOT RUN |

失败记录：build / 最短复现步骤 / 期望与实际 / request_id / 脱敏诊断 / server logs / 修复 commit / 新 TestFlight build / 复测结果。不得将含私人健康内容的截图/诊断提交到 Public Issues。

Debug Limitation：没有实时 Xcode/LLDB/Instruments/USB 调试；原生崩溃参考 TestFlight crash/feedback 和云构建符号，不把 Dart 本地日志当完整 native crash reporter。Sentry 等外部服务只有获得配置和隐私确认后接入，没有 key 不阻塞。
