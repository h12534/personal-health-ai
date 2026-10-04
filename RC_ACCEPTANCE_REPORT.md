# RC / Beta Acceptance Report

报告更新：2026-10-04（Asia/Shanghai）。本地候选版本：`0.1.0-beta.1+2`，不是已发布 TestFlight build。Real GitHub CI 门禁已关闭。最新代码证据：[run 37139080992](https://github.com/h12534/personal-health-ai/actions/runs/37139080992)，commit `df4a1e161dfe565787e3a59beed19c7d84bcff97`，五个原有 Job 全部 SUCCESS；新增签名 Job SKIPPED / NOT RUN。逐 Job 记录、耗时和两次失败修复见 `CI_AUDIT.md`。

1. **GitHub remote**：CONFIGURED / PUSHED，`origin=https://github.com/h12534/personal-health-ai.git`；按所有者明确决定使用 Public 开源。仅 main 与 RC 两个远端分支。
2. **CI 每个 Job 实际结果**：PASS；release-audit / backend / backend-postgres / mobile-ios-primary / mobile-android-compat 均 SUCCESS。
3. **PostgreSQL 真实结果**：PASS；PostgreSQL 16.15 + pgvector + Redis 7.4，7 integration tests。vector/cosine/JSONB/全文检索/Hybrid RAG/UUID/时区/unique/幂等/cascade，以及 0001→0007→0008 和降级再升级均通过；两次 `alembic check` 无漂移。
4. **Backup Restore 实跑**：PASS；10 张表 count/UUID 一致，RAG/lab/workout/meal marker 完整，head `0008_release_candidate`。[恢复 artifact](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/artifacts/11277761723) 已下载核对，`result=passed`。
5. **macOS Build**：PASS；真实 macOS 26.6.2 arm64 上 release no-codesign，Runner.app 24.4MB；签名与真机仍待验。
6. **Xcode Version**：26.6，build 17F113；CocoaPods 1.17.0，Flutter 3.47.5 / Dart 3.13.4。
7. **iPhone 型号 / iOS 版本**：所有者已确认有 iPhone；型号 / iOS UNKNOWN。
8. **HealthKit 测试**：静态、Dart test 和 CI 原生编译 PASS（SwiftPM + CocoaPods fallback）；真机授权/数据 NOT RUN。
9. **Notification 测试**：规则/Mock/Dart test PASS；真机本地通知和锁屏 NOT RUN。
10. **Face ID 测试**：单元/Widget 逻辑已有；真机 NOT RUN。
11. **Offline Sync 测试**：本地 outbox/idempotency 自动测试 PASS；飞行模式/杀 App/恢复网络真机 NOT RUN。
12. **Staging Server**：配置 READY；部署 NOT RUN。
13. **HTTPS**：配置静态 PASS；真实 DNS/TLS/HSTS/续期 NOT RUN。
14. **Vision Provider**：25 个样本位，0 个已授权 ready；真实结果 NOT RUN。
15. **LLM Provider**：10 个固定问题 harness READY；真实结果 NOT RUN。
16. **Embedding / RAG**：真实 pgvector 与 Hybrid RAG integration PASS；Embedding 使用明确 Mock。36 个 Provider cases 的真实外部 Embedding/LLM 与 citation review 仍 NOT RUN。
17. **OCR**：5 个样本位，0 个已授权 ready；真实结果 NOT RUN。
18. **APNs**：NOT READY；凭据未提供，transport 仍显式禁用；device environment/rotation 后端边界已完成。
19. **TestFlight**：NOT RUN。
20. **Beta 版本号**：本地候选 `0.1.0-beta.1` / build `2`；云签名使用 Apple numeric marketing version `0.1.0` 与 run number / attempt 组成的递增 build，实际发行 build **NOT RUN**。
21. **当前 P0 / P1 Bugs**：CI 发现的 PostgreSQL schema drift、Android desugaring、Job env 的 runner context 与跨日时区失败均已修复并真实复测通过。当前自动化无开放阻断错误；真机与真实 Provider 未验，不能断言所有环境为 0。APNs transport、默认 Flutter Icon 和未确认 Bundle ID 仍是已知发布缺口。
22. **是否 Beta Ready**：**否**。最新 [run 37139080992](https://github.com/h12534/personal-health-ai/actions/runs/37139080992) / commit `df4a1e161dfe565787e3a59beed19c7d84bcff97` 的五个常规 Job SUCCESS，签名 Job SKIPPED，不视为发行门禁关闭；当前路线为 **Cloud macOS signing → signed IPA → TestFlight Internal → physical iPhone acceptance**。**拥有本地 Mac 不是门禁**。Staging/真实 Provider/remote APNs 仍需分别实证，不把 Local Notifications 验收绑到 APNs。
23. **当前最小缺失项（2026-10-04）**：所有者已确认有 iPhone、尚未办理 Apple Developer Program。先办理 membership，再提供 Team ID、最终 Bundle ID/显示名、App Store Connect App record，API Key/Key ID/Issuer ID/`.p8` 直接存 `ios-beta` Secrets（不发聊天、不 commit）；另需真实 HTTPS API 和 iPhone 型号/iOS。签名/IPA/upload/processing/真机仍 **NOT RUN**。不要求 Mac 或 Apple ID 密码/2FA。自动证书/profile 与手动 fallback 见 `CLOUD_IOS_RELEASE.md`，真机矩阵见 `TESTFLIGHT_IPHONE_ACCEPTANCE.md`。GitHub URL、权限与编译 CI 已不再缺失。

本轮本地修复复测：Backend 89 passed；Ruff PASS；strict mypy 165 files；Flutter analyze PASS；Flutter 40 passed；signing guardrails 14 passed；Release Audit PASS。最新真实 CI 再次验证这些检查，以及真实 PostgreSQL、Redis、迁移/Restore 与原生构建。`ios-beta` 受保护空环境已创建，只有所有者 reviewer、main/RC deployment policy；没有 Apple Secrets，没有开启自动发行或上传。
