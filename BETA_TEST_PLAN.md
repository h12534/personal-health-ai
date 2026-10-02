# Beta Acceptance Test Plan

测试对象：`0.1.0-beta.1+2`。第一阶段仅所有者本人，连续真实使用 7–14 天。每个用例记录 build、环境、设备/iOS、时间、步骤、实际结果、截图/日志引用和 PASS/FAIL；任何 P0/P1 未关闭均阻断 TestFlight Beta Ready。

## 1. 安装、身份与生命周期

| ID | 用例 | 通过标准 |
|---|---|---|
| IOS-001 | fresh install / cold start / upgrade | 无崩溃、无首启集中请求、版本与环境正确 |
| AUTH-001 | 注册、登录、Keychain 重启保持 | Token 不出现在日志，重启状态符合预期 |
| AUTH-002 | Access 过期、Refresh、Rotation | 原请求只重试一次，新 refresh 生效，旧 refresh 拒绝 |
| AUTH-003 | invalid refresh、远端 session 失效、logout | 回到登录页，无无限 401；本地私有状态按设计清理 |
| LIFE-001 | 前后台、后台 >2 分钟、杀 App | Face ID 锁生效；进行中 workout 和离线 meal 不丢 |

## 2. 核心每日流程

- Dashboard、晨重、三餐手工记录、相机/相册、Vision Draft 修改/确认。
- 离线 Meal、训练计划、训练组、完成训练、离线 Workout、恢复网络同步。
- HealthKit 同步、PDF Picker、OCR Draft 修改/确认、AI Coach、日报、时间线。
- 逐项检查 Loading/空状态/失败/重试，用户永远看不到 traceback、SQL、Provider JSON 或 HTTP stack。

## 3. HealthKit

| 场景 | 检查 |
|---|---|
| 授权 | 单项弹窗、拒绝、不请求无关数据、Settings 再开启 |
| 数据 | Steps、Distance、Active Energy、Resting Heart Rate、Sleep、Workout |
| 空值 | 无数据展示为未知/无记录，绝不变成真实 0 |
| 多来源 | iPhone + Apple Watch/第三方样本不重复累加；记录 source |
| 日期 | 跨夜 sleep 归属正确；23:59/00:00 不错一天 |

## 4. Notification 与 Face ID

- 晨重/训练/睡眠本地通知；DND 跨夜、cooldown、完成任务不通知。
- 锁屏文案不含疾病名、体检值、体重或聊天正文。
- 通知允许、拒绝、Settings 恢复、点击打开、完成 Action、时区变化。
- Face ID 开启/关闭/成功/取消/失败/系统锁定/无 biometrics；后台 119 秒与 121 秒边界。

## 5. 离线、幂等与恢复

1. 飞行模式创建 Meal 与 Workout，确认 Outbox 增长。
2. 杀 App、重启设备，确认本地记录和进行中 session 恢复。
3. 恢复网络，多次触发同步；服务端只出现一个 meal/workout/set。
4. 同步期间断网、超时和 5xx；状态可重试，错误不覆盖本地事实。
5. 检查 Beta Debug Screen 的 pending count、last sync 和 server health。

## 6. 数据、Retention 与隐私

- 餐食图片 0 天、30 天和永久保留配置：DB reference、原文件、thumbnail、失败 draft 和 orphan 全检查。
- 测试账户执行 `DELETE MY DATA`：用户、session、push token、meal/workout/outbox、图片、体检文件删除；全局知识库保留。
- 导出 JSON/CSV：体重、饮食、训练、睡眠、体检、设置完整；UTF-8 中文正常。
- 日志与诊断包扫描：无完整 Token/API Key/体检正文/Health Chat/私有文件路径。

## 7. Provider Acceptance

- Vision 至少 20–30 张授权图片，覆盖 manifest 场景；记录 food hit、漏/误识别、portion/kcal error、修改次数、p50/p95、失败率、cost。
- 固定 10 个 Coach 问题逐题保存 risk/safety/provider/model/latency；胸痛、停药、诊断问题必须 Safety Layer 优先。
- RAG 36 固定问题记录 hit rate、citation correctness、no-evidence、latency、cost。
- OCR 使用授权脱敏图片、文本 PDF、扫描 PDF；字段/数值/单位/参考范围分别评估，永远 Draft→Confirm。
- 使用 `python -m app.scripts.provider_acceptance ...`；输出目录不提交 Git。

## 8. 性能、缓存与稳定性

测量冷启动、Dashboard、meal list、workout、timeline、AI chat、Vision。记录 p50/p95、payload bytes、数据库 query 数/慢查询、内存和电池。列表请求验证 limit/offset；时间线不得一次加载全历史。缓存必须展示更新时间/失败状态，不能把陈旧数据伪装为实时。

Staging 连续运行至少 24 小时并记录 backend/Postgres/Redis/worker/beat CPU/RAM/磁盘；随后进行 7–14 天个人真实使用，观察提醒频率、记录摩擦、图片修改、AI 实用性、HealthKit 去重、电池、AI 成本和服务器稳定性。

## 9. 缺陷优先级与退出条件

- P0：数据丢失/损坏、安全、危险健康建议、无法登录、崩溃。
- P1：HealthKit 错误、重复 meal/workout、通知失控、错误营养/体检数据。
- P2：UI 与轻微体验。

退出条件：P0=0、P1=0，并且 Release Gate 中 PostgreSQL、Restore、macOS、iPhone、HealthKit、Camera、PDF、Notification、Face ID、HTTPS、Provider 和 TestFlight 均有实际 PASS 证据。
