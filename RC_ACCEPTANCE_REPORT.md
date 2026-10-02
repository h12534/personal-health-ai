# RC / Beta Acceptance Report

报告日期：2026-10-02。版本：`0.1.0-beta.1+2`。此报告严格区分本地验证、工具就绪和真实外部验收。

1. **GitHub remote**：NOT CONFIGURED；当前没有 remote，未创建公开仓库。
2. **CI 每个 Job 实际结果**：NOT RUN；workflow 已审计并增加 release/backend/PostgreSQL/iOS/Android 门禁，等待 private remote push。
3. **PostgreSQL 真实结果**：NOT RUN；本机无 PostgreSQL/Docker。SQLite 空库迁移/check/downgrade/re-upgrade PASS，但不替代 PostgreSQL。
4. **Backup Restore 实跑**：NOT RUN；代表性 seed、pg_dump/drop/create/pg_restore、count/UUID/RAG/lab/workout/meal 验证与 artifact 已就绪。
5. **macOS Build**：NOT RUN；CI 已配置 release no-codesign。
6. **Xcode Version**：UNKNOWN；CI 将输出 `xcodebuild -version`。
7. **iPhone 型号 / iOS 版本**：UNKNOWN。
8. **HealthKit 测试**：静态与 Dart test PASS；真机 NOT RUN。
9. **Notification 测试**：规则/Mock/Dart test PASS；真机本地通知和锁屏 NOT RUN。
10. **Face ID 测试**：单元/Widget 逻辑已有；真机 NOT RUN。
11. **Offline Sync 测试**：本地 outbox/idempotency 自动测试 PASS；飞行模式/杀 App/恢复网络真机 NOT RUN。
12. **Staging Server**：配置 READY；部署 NOT RUN。
13. **HTTPS**：配置静态 PASS；真实 DNS/TLS/HSTS/续期 NOT RUN。
14. **Vision Provider**：25 个样本位，0 个已授权 ready；真实结果 NOT RUN。
15. **LLM Provider**：10 个固定问题 harness READY；真实结果 NOT RUN。
16. **Embedding / RAG**：36 个固定 cases，harness READY；真实 pgvector/provider/citation review NOT RUN。
17. **OCR**：5 个样本位，0 个已授权 ready；真实结果 NOT RUN。
18. **APNs**：NOT READY；凭据未提供，transport 仍显式禁用；device environment/rotation 后端边界已完成。
19. **TestFlight**：NOT RUN。
20. **Beta 版本号**：`0.1.0-beta.1`，build `2`。
21. **当前 P0 / P1 Bugs**：本地自动化未发现开放 P0/P1；外部门禁未跑，不能据此断言真实环境为 0。APNs transport、默认 Flutter Icon 和未确认 Bundle ID 是已知发布缺口。
22. **是否 Beta Ready**：**否**。Release Gate 尚有多个真实环境门禁未关闭。
23. **尚需所有者提供**：GitHub private repo URL/权限；可用 macOS 或允许 Actions macOS；Apple Team ID、最终 Bundle ID/显示名、Developer/App Store Connect 权限、APNs Key ID 与 `.p8` 安全路径；iPhone 型号/iOS；staging/production 主机、域名/DNS；Provider endpoint/key/model；授权餐食图片和脱敏体检样本；最终 App Icon/品牌决定。

本地实际证据：Backend 81 passed；Ruff PASS；strict mypy 164 files；Flutter analyze PASS；Flutter 37 passed；SQLite 迁移链与两次 `alembic check` PASS；Release Audit PASS。
