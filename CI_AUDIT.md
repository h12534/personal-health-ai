# CI Audit

当前发布目标（2026-10-04）为 **Private Personal Sideload**。保留五个原有 Job；新增无 Apple Secrets 的 `mobile-ios-personal-sideload`，HealthKit-attempt / PERSONAL_SIDELOAD_FREE 双 unsigned IPA，Payload 布局、arm64 device Mach-O、无 Runner 签名/profile、原生版本与 Dart flavor 一致性、SHA-256/commit metadata 核验。Windows 个人签名与 iPhone 安装/启动仍 NOT RUN；付费签名/TestFlight 门禁暂停而非通过，未来代码保留。实际新 Job 结果须独立核验，操作见 `PERSONAL_SIDELOAD_WINDOWS.md`。

验收更新：2026-10-04（Asia/Shanghai）。工作流文件为 `.github/workflows/ci.yml`。

**Real GitHub CI：PASS / CLOSED。** 最新代码证据为 [run 37139080992](https://github.com/h12534/personal-health-ai/actions/runs/37139080992)，event `push`，attempt `1`，commit `df4a1e161dfe565787e3a59beed19c7d84bcff97`，workflow conclusion `success`。五个原有 Job 全部 SUCCESS；新增签名 Job **SKIPPED / NOT RUN**，不计作签名门禁通过。下方保留首次关闭门禁的历史证据。

仓库 [h12534/personal-health-ai](https://github.com/h12534/personal-health-ai) 按所有者 2026-10-03 的明确决定使用 Public 开源。仅推送 `main`（Phase 1 基线 `25b026d`）和 `feature/release-candidate-beta`；未推送其他历史 feature refs。验收针对 RC 分支，未合并或替换 main 的基线。

## 首次关闭门禁：每个 Job 的实际结果（2026-10-03）

| Job | 实际结果 | 耗时 | 可核验记录 |
|---|---|---:|---|
| `release-audit` | SUCCESS | 7s | [Job 111235272963](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/job/111235272963)：发布静态审计、三个 Shell 脚本语法检查 |
| `backend` | SUCCESS | 57s | [Job 111235272881](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/job/111235272881)：Ruff、201 files format、strict mypy 165 files、83 pytest passed |
| `backend-postgres` | SUCCESS | 77s | [Job 111235272979](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/job/111235272979)：真实 PG/Redis、7 integration tests、迁移与恢复演练 |
| `mobile-ios-primary` | SUCCESS | 250s | [Job 111235272898](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/job/111235272898)：format/analyze、37 tests、release no-codesign |
| `mobile-android-compat` | SUCCESS | 418s | [Job 111235272789](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/job/111235272789)：真实 Gradle debug APK 构建 |

耗时由 Actions API `completed_at - started_at` 计算，包含准备和清理。构建命令成功不代表签名、安装或真机 runtime 验收。

## PostgreSQL / Redis / Restore 证据

- PostgreSQL **16.15**，服务镜像 `pgvector/pgvector:pg16`；Redis `7.4-alpine`，实际 `PING` PASS。
- `vector` extension、`vector(64)`、cosine distance `<=>`、JSONB round-trip/containment、生成的 `tsvector` 全文匹配、GIN/HNSW 索引和 Hybrid RAG 均有实际测试证据。Embedding 使用明确标记的 Mock，不计作真实外部 Embedding Provider 验收。
- UUID、带时区 timestamp、unique/dedup、ON CONFLICT 幂等与 cascade delete 实测 PASS。
- 空库 **0001→0007→0008**；`alembic check` PASS；**0008→0006→0007→0008** 后第二次 check PASS。新增真实 PostgreSQL metadata drift regression PASS；类型比较和全部检查保留。
- `health_os_test → health_os_restore_drill` 完整 pg_dump/pg_restore PASS。报告时间 `2026-10-03T15:43:55Z` 至 `15:43:58Z`（UTC）。10 张表计数和 10 个固定 marker UUID 一致，`alembic_version=0008_release_candidate`，`result=passed`。
- [Restore artifact 11277761723](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/artifacts/11277761723) 已下载并验证 ZIP SHA256：`54fcfb09ff8d612c5d0bed18c5cb77bb5b1bb22b243ca5622d317a69e4026b49`。dump SHA256：`55e4b3d55f56dd010e2b78aa1edcac0f7315b4c4f4b7b43c18cb43b279b1a616`。仅含合成测试记录。
- 恢复计数：users/weight_logs/meal_logs/workout_sessions/lab_reports/lab_results/daily_tasks/health_reports 各 1；knowledge_documents/knowledge_chunks 各 3。

## Apple 原生构建证据

macOS **26.6.2 (25G83), arm64**；Xcode **26.6 (17F113)**；CocoaPods **1.17.0**；Flutter **3.47.5**；Dart **3.13.4**。iOS deployment target **16.0**，Swift language mode **5.0**。

SwiftPM 启用，日志确认 `health` 和 `flutter_secure_storage` 自动通过 CocoaPods fallback 集成；`pod install` 成功。HealthKit、UIDocumentPicker 原生桥接、Image Picker/Camera、Keychain、Local Notifications、local_auth、Drift/SQLite 对应原生依赖均进入成功的 release 构建。命令：

```sh
flutter build ios --release --no-codesign \
  --dart-define=APP_ENV=staging \
  --dart-define=API_BASE_URL=https://staging-api.personal-health.invalid/api/v1
```

退出码 0，`build/ios/iphoneos/Runner.app` **24.4MB**。该 `.invalid` URL 仅用于编译参数防护，不是已部署的 Staging 服务。HealthKit、Camera、通知、Face ID、Keychain 和离线恢复的真实运行仍待 iPhone 验收。

## 失败及修复记录

首次运行：[37133368111](https://github.com/h12534/personal-health-ai/actions/runs/37133368111)，commit `379d50f88cb14b3b63a1cbee6ef2088ebb582992`，conclusion `failure`。Release Audit、Backend 和 iOS SUCCESS；PostgreSQL 与 Android FAILURE。

| 失败/发现 | 真正原因 | 修复与验证 |
|---|---|---|
| PostgreSQL `alembic check` | Phase 4/5/7 ORM 使用 JSON，但迁移为 JSONB；PG 全文列/GIN/HNSW 元数据缺失；Exercise 表唯一约束未在模型中声明 | 补 JSONB 方言变体、完整 PG migration metadata 与唯一约束；保持 `compare_type=True`，没有过滤反射对象。SQLite cycle/check 与方言测试 PASS；第二轮 PG 全绿 |
| Android `checkDebugAarMetadata` | [通知插件 22.3.1 的 Gradle 要求](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1#gradle-setup)包括 desugaring，生成的 Android 模板未启用 | Kotlin/Groovy 都配置 desugaring、`desugar_jdk_libs:2.1.4` 和 Java 17；本地双模板及幂等检查 PASS；第二轮 APK 成功 |
| Restore harness 审阅发现 | [psql 16 的 command 模式](https://www.postgresql.org/docs/16/app-psql.html)不展开 `:'marker'` 变量 | 改为标准输入 `--file=-`，开启 `ON_ERROR_STOP`；Shell syntax PASS；第二轮真实 restore PASS |

统一修复提交：`af22faaab2b6694ff00808d07f7f8ad0edea4b48`。本地重新验证：Backend 83 passed、Flutter 37 passed、Ruff/strict mypy/analyze、SQLite 两次 migration check、Shell syntax。未 skip/disable test，未降 lint，未删数据库检查。

## Workflow 门禁配置

| Job | Runner | 强制门禁 | 产物/说明 |
|---|---|---|---|
| `release-audit` | Ubuntu | secret/artifact 跟踪检查、生产/iOS 静态防护、Shell syntax | 外部门禁只输出 warning，不伪造 PASS |
| `backend` | Ubuntu | Python 3.12、Ruff、format、strict mypy、完整 pytest | 不允许 skip/lint disable |
| `backend-postgres` | Ubuntu + pgvector/pg16 + Redis 7.4 | 空库 upgrade head、`alembic check`、0008→0006→0007→0008、真实 integration tests | seed 代表性记录，执行 pg_dump/restore，上传 `postgres-restore-report` |
| `mobile-ios-primary` | macOS | Flutter 3.47.5、`flutter doctor -v`、Xcode version、CocoaPods、format/analyze/test、release no-codesign | iOS 是 primary；实际 Xcode 版本来自 Job log |
| `mobile-android-compat` | Ubuntu | Temurin Java 17、Flutter 3.47.5、生成 secondary Android runner、debug APK | 修复本机 Java 8 导致的已知失败条件 |

工作流额外配置：只读 repository 权限、branch/ref concurrency cancel、手动 `workflow_dispatch`。

## 下一门禁

停止业务功能扩展，进入 **Cloud macOS signing → IPA → TestFlight Internal → physical iPhone acceptance**。**拥有本地 Mac 不是门禁**；CI no-codesign 不覆盖签名、安装、真实授权与设备数据。按 `CLOUD_IOS_RELEASE.md` 和 `TESTFLIGHT_IPHONE_ACCEPTANCE.md` 执行，不强制 USB/Xcode Run。

## Cloud signing preparation（2026-10-04）

- 本轮开始前 no-codesign 编译门禁证据为 [run 37135036631](https://github.com/h12534/personal-health-ai/actions/runs/37135036631)，commit `42bbd93baf73312167a32529fe7cb711018effb5`；五个既有 Job 全绿。最新代码复验见下表。
- 新增 `mobile-ios-signed` 独立 opt-in Job：限制授权仓库 main/RC，不在 PR/fork 注入 Secrets；自动签名优先/手动 fallback，真实 IPA 命令、内部限定导出、API Key 上传、签名材料 always cleanup。
- 代码回归本地：Backend 87 tests、Ruff、strict mypy 165 files；Flutter analyze、40 tests；签名基础设施 12 unittest guardrails，Release Audit PASS。Windows 中文路径 LSP 缺陷通过同一源码临时 ASCII 映射核验，无检查降级。
- **没有执行 signed build / IPA / TestFlight**。所有者已确认 membership 未办理；2026-10-04 API 只读检查显示 repository secrets/variables 为空、`ios-beta` 未创建（404）。不读取/打印 Secret 值，不声称配置等于 PASS。环境配置后依然不启用发布开关。
- 随后实际创建并 GET 复核 `ios-beta`：required reviewer 仅 `h12534`（允许 self-review，避免单人开发无法审批），custom branch policy 仅 main 与 RC；Secrets/Variables 为空、发布 opt-in 未启用。只改授权 GitHub 仓库，无 Apple 注册/付款/证书生成。
- 本轮首推 [run 37138093960](https://github.com/h12534/personal-health-ai/actions/runs/37138093960) / commit `6f640620713dbc26bb8d33c99b29f1beb2c8859a` **FAIL** 于 workflow validation，没有 Job 启动。页面 annotation 明确 `(Line: 202, Col: 20): Unrecognized named-value: 'runner'`，对应 Job 级 env 引用 `runner.temp`。修复为脚本运行时解析 `RUNNER_TEMP/health-ios-signing`，新增目录解析与 workflow context 回归测试；没有删检查/测试或降低任何门禁。修复后的真实结果必须独立核验。
- 修复后 [run 37138303764](https://github.com/h12534/personal-health-ai/actions/runs/37138303764) / commit `b51363cd104f6c025fb8a14048dcf6b960f2142f` 正常启动；Release Audit 和 PostgreSQL PASS，但 Backend 84 passed / 3 failed。实际日志 UTC `2026-10-03 16:51`、默认上海用户日期已是 `10-04`；三个旧测试使用 host `date.today()` 造数，却向按用户日期聚合的 Dashboard 断言。同步发现 Weight trends endpoint 使用 host date 而非用户时区。修复为复用既有用户 timezone 服务；相关测试按默认用户日期造数，新增上海/洛杉矶固定 UTC 跨日边界接口回归。所有原断言保留，未设置全局 TZ 或绕过时区检查，未重建/更改 Phase 架构。

## Cloud preparation 后的真实复验（2026-10-04）

[Run 37139080992](https://github.com/h12534/personal-health-ai/actions/runs/37139080992)，commit `df4a1e161dfe565787e3a59beed19c7d84bcff97`，attempt `1`；API 与逐 Job 日志均已读取。运行 UTC `2026-10-03 17:02–17:11`，对应上海 `2026-10-04 01:02–01:11`。

| Job | 实际结果 | 耗时 | 可核验记录 |
|---|---|---:|---|
| `release-audit` | SUCCESS | 7s | [111249575171](https://github.com/h12534/personal-health-ai/actions/runs/37139080992/job/111249575171)：静态发布审计、14 signing guardrail tests、Shell syntax |
| `backend` | SUCCESS | 76s | [111249575376](https://github.com/h12534/personal-health-ai/actions/runs/37139080992/job/111249575376)：Ruff、203 files format、strict mypy 165 files、89 tests passed |
| `backend-postgres` | SUCCESS | 68s | [111249575372](https://github.com/h12534/personal-health-ai/actions/runs/37139080992/job/111249575372)：PG 16.15 / Redis 7.4.11、7 integration tests、两次 Alembic check、完整升降级与 restore |
| `mobile-ios-primary` | SUCCESS | 495s | [111249575335](https://github.com/h12534/personal-health-ai/actions/runs/37139080992/job/111249575335)：format/analyze、40 tests、release no-codesign，Runner.app 24.4MB |
| `mobile-android-compat` | SUCCESS | 345s | [111249575485](https://github.com/h12534/personal-health-ai/actions/runs/37139080992/job/111249575485)：真实 Gradle debug APK |
| `mobile-ios-signed` | **SKIPPED / NOT RUN** | — | [111251056298](https://github.com/h12534/personal-health-ai/actions/runs/37139080992/job/111251056298)：发布 opt-in 关闭；未运行 signing/IPA/upload，不是 PASS |

PG 仍使用真实 `pgvector/pgvector:pg16`；0001→0007→0008 与 0008→0006→0007→0008 全部运行，未改为 SQLite。Restore 日志 `result=passed`、10 表 count/marker UUID、head `0008_release_candidate`；[本轮 restore artifact 11279688010](https://github.com/h12534/personal-health-ai/actions/runs/37139080992/artifacts/11279688010) 已上传，未把它混用为前述历史 artifact 的 SHA256。

iOS 日志再次确认 macOS 26.6.2 arm64、Xcode 26.6 (17F113)、CocoaPods 1.17.0、Flutter 3.47.5 / Dart 3.13.4，SwiftPM 与 `pod install`、iOS 16 no-codesign 构建完成。编译仍使用 `.invalid` 占位 API，不能证明真机联网。

本地复测：Backend **89 passed**（含两个固定 UTC 跨日边界接口用例）、Ruff、strict mypy 165 files、Flutter analyze / **40 passed**、signing guardrails **14 passed**、Release Audit。修复提交为 `df4a1e1`，签名目录修复为 `b51363c`；没有 skip/disable test、降 lint、删除失败检查或绕过数据库。实际 Apple membership/Secrets/API 尚缺，signed IPA、TestFlight processing 和 physical acceptance 仍 **NOT RUN**。
