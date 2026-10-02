# CI Audit

审计日期：2026-10-02。工作流文件为 `.github/workflows/ci.yml`。当前没有 Git remote，因此下表是**配置审计**，不是 GitHub Actions 实跑结果。

| Job | Runner | 强制门禁 | 产物/说明 |
|---|---|---|---|
| `release-audit` | Ubuntu | secret/artifact 跟踪检查、生产/iOS 静态防护、Shell syntax | 外部门禁只输出 warning，不伪造 PASS |
| `backend` | Ubuntu | Python 3.12、Ruff、format、strict mypy、完整 pytest | 不允许 skip/lint disable |
| `backend-postgres` | Ubuntu + pgvector/pg16 + Redis 7.4 | 空库 upgrade head、`alembic check`、0008→0006→0007→0008、真实 integration tests | seed 代表性记录，执行 pg_dump/restore，上传 `postgres-restore-report` |
| `mobile-ios-primary` | macOS | Flutter 3.47.5、`flutter doctor -v`、Xcode version、CocoaPods、format/analyze/test、release no-codesign | iOS 是 primary；实际 Xcode 版本来自 Job log |
| `mobile-android-compat` | Ubuntu | Temurin Java 17、Flutter 3.47.5、生成 secondary Android runner、debug APK | 修复本机 Java 8 导致的已知失败条件 |

工作流额外配置：只读 repository 权限、branch/ref concurrency cancel、手动 `workflow_dispatch`。

## 首次 push 后的操作

1. 确认仓库是 Private，添加 `origin` 并推送 RC 分支。
2. 打开 Actions，记录 workflow URL、commit SHA、runner image、每个 Job 的 conclusion 和 duration。
3. 下载 `postgres-restore-report`，核对 10 张核心表数量、marker UUID、Alembic head 和 `result=passed`。
4. 任何失败必须修复并重新运行；不得用 `continue-on-error`、skip test 或删门禁关闭。
5. 只有 actual run 全绿后，才在 `RC_ACCEPTANCE_REPORT.md` 将 CI/PostgreSQL/Restore/macOS 标为 PASS。

## 当前实际结果

`NOT RUN`：没有 GitHub remote 或 Actions run URL，不能读取实际 CI 结果。
