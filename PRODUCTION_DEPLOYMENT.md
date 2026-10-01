# 生产部署

`docker-compose.production.yml` 包含 PostgreSQL/pgvector、Redis、私有文件存储初始化、FastAPI、Celery Worker、Celery Beat、TLS Nginx 和可选 Backup 任务。数据库和 Redis 不映射公网端口。

## 首次部署

1. 在 Linux 主机安装 Docker Engine 和 Compose v2，创建专用非 root 运维账号。
2. 复制 `.env.production.example` 为 `.env.production`，生成长随机 `APP_SECRET_KEY` 和数据库密码。`DATABASE_URL` 中的密码必须做 URL encoding。禁止提交该文件。
3. 将 `STORAGE_HOST_PATH` 和 `BACKUP_HOST_PATH` 指向受限制的持久目录；备份目录应再加密复制到另一故障域。
4. 为 API 域名申请 Let's Encrypt 或其他可信证书，`TLS_CERT_HOST_PATH` 目录必须包含 `fullchain.pem` 和 `privkey.pem`。也可在 Cloudflare Tunnel/托管反向代理终止 TLS，但到 iPhone 的外部端点仍必须是 HTTPS。
5. 验证并启动：

```bash
docker compose --env-file .env.production -f docker-compose.production.yml config
docker compose --env-file .env.production -f docker-compose.production.yml up --build -d
curl --fail https://api.example.com/health/live
curl --fail https://api.example.com/health/ready
```

`/health/live` 只证明进程存活。`/health/ready` 检查数据库、Redis 和私有存储；外部 AI 失败不会使应用整体不就绪。

## 发布顺序

1. 备份数据库和私有文件。
2. 在预发环境运行 `alembic upgrade head` 和冒烟测试。
3. 更新 backend/worker/beat；单一 backend 容器启动时执行迁移，不并发运行多个迁移者。
4. 确认 readiness 与 Celery `supervision_sweep_completed` 结构化日志。
5. 再发布指向该 HTTPS 端点的 iOS 构建。

## APNs

默认保持 `PUSH_PROVIDER=mock`。拿到 Apple 凭据后，把 `.p8` 作为 Docker Secret 只挂载给 backend 和 `celery_worker`，将容器内路径设为 `APNS_AUTH_KEY_PATH`，再配置 Team ID、Key ID、Bundle ID 与 sandbox/production 开关。不把 `.p8` 放入镜像、Compose 文件或 Git。当前 `ApplePushProvider` 是已校验配置的业务边界，真实 HTTP/2 APNs 传输仍是拿到凭据后的发布门禁。

## 可观测性

HTTP 日志包含 request ID、method、path、status 和 duration。AI 使用表保留 Provider/Model/latency/token 统计，通知表保留状态/原因/Provider 而不保留敏感全文，Celery sweep 输出聚合数量。`SENTRY_DSN` 是预留配置；未设置时不阻塞服务。启用错误上报前必须配置健康正文、Token、文件路径和 Provider payload 脱敏。
