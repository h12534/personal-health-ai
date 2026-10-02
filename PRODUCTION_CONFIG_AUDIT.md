# Production and Staging Configuration Audit

## 静态审计结论

本地 `python scripts/release_audit.py` 已通过。生产与预发拓扑包括 Nginx、FastAPI、PostgreSQL 16 + pgvector、Redis、Celery worker、单一 Celery beat、私有 storage 和按 profile 运行的 backup。PostgreSQL/Redis 未映射公网端口；Nginx 只允许 TLS 1.2/1.3、隐藏版本并配置 HSTS。

真实部署、TLS 和资源数值尚未验证。

## 环境隔离

- Production：`.env.production` + `docker-compose.production.yml`。
- Staging：`.env.staging` + production compose + `docker-compose.staging.yml` override。
- 两类真实 `.env` 均被 Git 忽略；example 只含占位符。
- Backend 对 staging/production 均强制：32+ 字符非占位 secret、PostgreSQL asyncpg URL、HTTPS public URL、非 localhost/example/invalid 域名。
- Flutter staging/production 拒绝 HTTP 和 localhost；没有 broad ATS exception。

Staging 配置检查：

```bash
cp .env.staging.example .env.staging
# 替换全部 secret、路径和域名后
docker compose --env-file .env.staging \
  -f docker-compose.production.yml -f docker-compose.staging.yml config
```

## Scheduler 与幂等

- Compose 只声明一个 `celery_beat`；运维层禁止扩为多副本。
- `supervision.sweep` 使用 Redis NX 锁，30 分钟自动过期，并用 token-compare Lua 安全释放。
- daily task、report、notification 和离线 meal/workout 使用数据库唯一键或 idempotency key。
- retention cleanup 与 supervision sweep 由 UTC Celery Beat 调度；业务日期通过 profile timezone 计算。
- Backup 仍由主机 timer/cron 或显式 backup profile 触发，生产必须保证只有一个调度者。

## Secret、文件与备份

- `.p8/.p12/.mobileprovision/.key/.pem`、数据库 dump、真实 `.env`、Provider 私有样本和结果目录均被忽略。
- storage 与 backup 使用宿主机受限目录；容器内上传目录为 `/data/private/uploads`。
- `scripts/backup.sh` 使用 `umask 077`、custom-format pg_dump、私有文件 tar、SHA256 和 daily/weekly/monthly retention。
- `scripts/restore_test.sh` 只允许 `_restore_drill` 目标名，避免误删任意数据库。

## 部署后必须执行

```bash
docker compose --env-file .env.staging \
  -f docker-compose.production.yml -f docker-compose.staging.yml up --build -d
curl --fail https://staging-api.<domain>/health/live
curl --fail https://staging-api.<domain>/health/ready
RESOURCE_SAMPLES=6 RESOURCE_INTERVAL_SECONDS=10 sh scripts/measure_resources.sh
```

资源报告必须记录 backend/Postgres/Redis/worker/beat 的 CPU、RAM、网络、磁盘 IO 和 PIDs，并补充磁盘容量、AI 并发与 24 小时稳定性。当前无 Docker/服务器，数值状态为 `NOT RUN`。
