# Release Candidate Audit

审计日期：2026-10-02
分支：`feature/release-candidate-beta`
Beta 版本：`0.1.0-beta.1+2`

## 结论

当前仓库已完成可在 Windows、本地、无外部凭据条件下完成的 RC 加固，但**尚未 Beta Ready**。本地代码门禁通过；真实 PostgreSQL、GitHub CI、macOS/Xcode、iPhone、Staging HTTPS、真实 Provider、APNs 和 TestFlight 仍必须以外部环境的实际证据关闭，不能用 Mock、SQLite 或文档代替。

## 本地已验证

| 门禁 | 结果 | 证据 |
|---|---|---|
| Backend pytest | PASS | 81 passed，137.97s |
| Ruff | PASS | 199 files checked/formatted |
| strict mypy | PASS | 164 source files |
| Flutter analyze | PASS | No issues found |
| Flutter test | PASS | 37 tests passed |
| SQLite 迁移链 | PASS | 空库 0001→0008；`alembic check`；0008→0006→0007→0008；再次 check |
| Release static audit | PASS | 0 errors，3 个预期外部门禁 warning |
| Provider inventory | PASS（仅工具） | Vision 25 slots/0 ready；OCR 5/0 ready；RAG 36 cases；Coach 10 cases |

SQLite 的 PASS 只证明迁移脚本的便携性，不替代 PostgreSQL 16 + pgvector 验收。

## 本轮修复

- 新增 0008 RC 迁移，记录 push device 的 `environment`，并修复 `exercise_library.normalized_name` 的索引元数据漂移。
- meal、workout、timeline、lab report、knowledge document 和 health report 大列表增加 `limit/offset` 上限。
- 增加 UTC、Asia/Tokyo、Asia/Shanghai、DST、23:59/00:00 和跨夜 DND 回归测试。
- 移动端增加单次 401 自动刷新、Refresh Token Rotation、失败后清除会话及无无限重试测试。
- 增加 Beta Debug Screen、脱敏本地错误日志和 Report Issue。
- Staging 与 Production 共用同一受审计拓扑；staging/production 配置均强制强 secret、PostgreSQL 和 HTTPS。
- Celery supervision sweep 增加 Redis 分布式锁，防止多个 Beat/重复投递造成重叠执行。
- CI 固定 Android Java 17，并加入 migration check、降级/升级和 Restore Drill artifact。
- Restore Drill 写入用户、体重、饮食、训练、知识/RAG、体检、任务和报告的固定测试 UUID。

## 尚未关闭的发布门禁

| 门禁 | 当前状态 | 关闭条件 |
|---|---|---|
| GitHub private remote / actual CI | BLOCKED | 私有仓库 URL 与权限 |
| PostgreSQL 16 + pgvector | BLOCKED | Docker/Linux 或 CI 实跑记录 |
| Restore Drill 实跑 | BLOCKED | PostgreSQL 环境执行并保存 artifact |
| macOS/Xcode no-codesign | BLOCKED | macOS runner 实际绿色 Job |
| iPhone/HealthKit/Camera/PDF/通知/Face ID | BLOCKED | 真机与测试记录 |
| Staging HTTPS/resource measurement | BLOCKED | 主机、域名、DNS、证书 |
| Vision/LLM/Embedding/OCR | BLOCKED | Provider 配置、授权样本和费用数据 |
| APNs | BLOCKED | Apple Team/Key/.p8/Bundle ID；真实 transport 与真机 token |
| TestFlight | BLOCKED | Apple Developer/App Store Connect 和签名 |

## 已知产品发布缺口

- 当前 App Icon 仍是 Flutter 默认图标，Beta 上传前必须替换；这不是代码测试通过项。
- `ApplePushProvider` 仍明确返回 `apns_transport_requires_release_configuration`；未伪装为完成。
- App 尚未从 iOS 原生 APNs 回调取得 token；仓库只完成了后端 token 环境隔离和移动端注册 API 边界。
- 当前 Bundle ID `com.personal.healthcoach` 和显示名“私人健康”是可配置默认值，需所有者最终确认。
