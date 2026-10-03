# Release Candidate Audit

审计日期：2026-10-03（Asia/Shanghai）
分支：`feature/release-candidate-beta`
Beta 版本：`0.1.0-beta.1+2`

## 结论

**Real GitHub CI 已关闭，尚未 Beta Ready。** [全绿 run 37134206768](https://github.com/h12534/personal-health-ai/actions/runs/37134206768) / commit `af22faaab2b6694ff00808d07f7f8ad0edea4b48` 已提供真实 PostgreSQL/pgvector/Redis、Restore、macOS/Xcode iOS no-codesign 与 Android 构建证据。下一门禁为 physical iPhone acceptance；Staging HTTPS、真实 Provider、APNs 和 TestFlight 仍待实证。详情见 `CI_AUDIT.md`。

公开推送前检查 main/RC 可达的 54 个提交与 625 个 blob，未发现匹配的凭据/私有数据/备份；媒体仅为 iOS 图标/启动图，Provider manifest 为未填充样本位。凭据保存在本机 GCM，日志和下载证据位于被忽略的 artifacts；未上传原始备份或健康数据。仓库使用 Public 是所有者最新的明确决定。

## 本地已验证

| 门禁 | 结果 | 证据 |
|---|---|---|
| Backend pytest | PASS | 修复后本地 83 passed，163.98s；CI 83 passed，27.66s |
| Ruff | PASS | 201 files checked/formatted |
| strict mypy | PASS | 165 source files |
| Flutter analyze | PASS | No issues found |
| Flutter test | PASS | 37 tests passed |
| SQLite 迁移链 | PASS | 空库 0001→0008；`alembic check`；0008→0006→0007→0008；再次 check |
| Release static audit | PASS | 0 errors，3 个预期外部门禁 warning |
| Provider inventory | PASS（仅工具） | Vision 25 slots/0 ready；OCR 5/0 ready；RAG 36 cases；Coach 10 cases |

SQLite 的 PASS 证明便携性；真实 PostgreSQL 16 + pgvector 也已在上述 workflow 验收通过。

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

## 发布门禁状态

| 门禁 | 当前状态 | 关闭条件 |
|---|---|---|
| GitHub remote / actual CI | PASS / CLOSED | 所有者授权 Public；指定 main/RC 已推送，五 Job 全绿 |
| PostgreSQL 16 + pgvector | PASS | 真实 PostgreSQL 16.15、7 integration tests、两次 Alembic check |
| Restore Drill 实跑 | PASS | 10 表 count/UUID 一致、artifact 已下载验证 |
| macOS/Xcode no-codesign | PASS | Xcode 26.6 / macOS 26.6.2，真实 release build |
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
