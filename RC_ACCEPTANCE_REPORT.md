# RC / Beta Acceptance Report

报告日期：2026-10-03（Asia/Shanghai）。版本：`0.1.0-beta.1+2`。Real GitHub CI 门禁已关闭。真实证据：[run 37134206768](https://github.com/h12534/personal-health-ai/actions/runs/37134206768)，commit `af22faaab2b6694ff00808d07f7f8ad0edea4b48`，五个 Job 全部 SUCCESS。逐 Job 记录、耗时和失败修复见 `CI_AUDIT.md`。

1. **GitHub remote**：CONFIGURED / PUSHED，`origin=https://github.com/h12534/personal-health-ai.git`；按所有者明确决定使用 Public 开源。仅 main 与 RC 两个远端分支。
2. **CI 每个 Job 实际结果**：PASS；release-audit / backend / backend-postgres / mobile-ios-primary / mobile-android-compat 均 SUCCESS。
3. **PostgreSQL 真实结果**：PASS；PostgreSQL 16.15 + pgvector + Redis 7.4，7 integration tests。vector/cosine/JSONB/全文检索/Hybrid RAG/UUID/时区/unique/幂等/cascade，以及 0001→0007→0008 和降级再升级均通过；两次 `alembic check` 无漂移。
4. **Backup Restore 实跑**：PASS；10 张表 count/UUID 一致，RAG/lab/workout/meal marker 完整，head `0008_release_candidate`。[恢复 artifact](https://github.com/h12534/personal-health-ai/actions/runs/37134206768/artifacts/11277761723) 已下载核对，`result=passed`。
5. **macOS Build**：PASS；真实 macOS 26.6.2 arm64 上 release no-codesign，Runner.app 24.4MB；签名与真机仍待验。
6. **Xcode Version**：26.6，build 17F113；CocoaPods 1.17.0，Flutter 3.47.5 / Dart 3.13.4。
7. **iPhone 型号 / iOS 版本**：UNKNOWN。
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
20. **Beta 版本号**：`0.1.0-beta.1`，build `2`。
21. **当前 P0 / P1 Bugs**：CI 发现的 PostgreSQL schema drift 和 Android desugaring 失败均已修复并真实复测通过。当前自动化无开放阻断错误；真机与真实 Provider 未验，不能断言所有环境为 0。APNs transport、默认 Flutter Icon 和未确认 Bundle ID 仍是已知发布缺口。
22. **是否 Beta Ready**：**否**。Real GitHub CI 已关闭；下一门禁为 **macOS + Xcode + physical iPhone acceptance**，之后仍需 Staging/Provider/APNs/TestFlight 实证。
23. **尚需所有者提供**：可安装真机开发构建的 Mac/Xcode；Apple Team ID、最终 Bundle ID/显示名、Developer/App Store Connect 权限、APNs Key ID 与 `.p8` 安全路径；iPhone 型号/iOS；staging/production 主机、域名/DNS；Provider endpoint/key/model；授权餐食图片和脱敏体检样本；最终 App Icon/品牌决定。GitHub URL、权限与 CI 已不再缺失。

本地修复复测：Backend 83 passed；Ruff PASS；strict mypy 165 files；Flutter analyze PASS；Flutter 37 passed；SQLite 迁移链与两次 `alembic check` PASS；Release Audit/Shell syntax PASS。真实 CI 也已验证以上项目及 PostgreSQL、Restore 与原生构建。
