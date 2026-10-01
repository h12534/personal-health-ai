# PostgreSQL 恢复演练

## 自动演练

`scripts/restore_test.sh` 只允许将源库恢复到名称以 `_restore_drill` 结尾的独立数据库，并拒绝源/目标同名。它会：

1. 对源测试库执行 custom-format `pg_dump`。
2. 删除并重建隔离的 restore-drill 库。
3. 使用 `pg_restore --exit-on-error` 恢复。
4. 对比 `users` 、`daily_tasks`、`notification_logs`、`health_reports` 和 `health_followups` 行数。
5. 确认 `alembic_version` 可读。

GitHub Actions 的 `backend-postgres` job 在 PostgreSQL/pgvector 集成测试后运行该演练。手工命令：

```bash
export POSTGRES_HOST=localhost POSTGRES_PORT=5432 POSTGRES_USER=health
export PGPASSWORD='test-only-password'
export SOURCE_DATABASE=health_os_test
export RESTORE_DATABASE=health_os_restore_drill
sh scripts/restore_test.sh
```

## 私有文件演练

1. 运行 `docker compose --env-file .env.production -f docker-compose.production.yml --profile backup run --rm backup`。
2. 在隔离目录执行 `sha256sum -c SHA256SUMS`。
3. 恢复 `private-files.tar.gz`，保留 0700 目录权限，不覆盖唯一生产副本。
4. 抽样验证餐食图片、体检原文件和知识源 object key 与数据库一致。
5. 在隔离 API 上登录，验证 Timeline、报告、已确认体检趋势和知识检索。

## 2026-10-01 执行记录

- SQLite/Alembic 本地迁移演练：空库 `upgrade head` → `downgrade 0006` → `upgrade head`，最终 revision `0007_phase7_supervision`，通过。
- PostgreSQL 脚本与 CI 门禁：已实现。
- 本机 PostgreSQL 实跑：未执行。当前 Windows 环境没有 Docker、`psql` 或 `pg_dump`，因此不伪造通过记录。添加 Git remote 后的首次 `backend-postgres` CI 或提供隔离测试 PostgreSQL 即可完成这一外部门禁。
