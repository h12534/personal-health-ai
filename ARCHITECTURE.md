# 系统架构

## 总览

```text
Flutter App (Drift 离线队列，后续接 HealthKit/Health Connect)
        │ HTTPS / JSON
        ▼
Nginx ──► FastAPI 模块化单体 ──► PostgreSQL + pgvector
                  │                       │
                  ├──► Redis ──► Celery Worker/Beat
                  ├──► StorageProvider (Local → S3/R2/MinIO)
                  └──► AI Gateway (OpenAI/Gemini/Claude/Local)
```

## 为什么先用模块化单体

该项目当前只服务一人。独立微服务会引入部署、网络、追踪和一致性成本，却没有对应规模收益。后端按领域拆分 `api / models / schemas / repositories / services / providers / jobs`，保持模块边界；日后图像识别或 RAG 负载确有需要时再独立部署。

## 领域边界

- Identity：用户、密码、会话、Token 轮换。
- Health Profile：人口统计、目标、生活环境、风险提示。
- Tracking：体重、围度、活动、饮水、睡眠。
- Nutrition：食物、餐次、识别结果、食堂与个人校准。
- Training：动作、计划、训练会话与训练组。
- Intelligence：规则引擎、报告、RAG、AI Coach、结构化记忆。
- Platform：设置、通知、文件、审计、任务、AI 成本。

## 关键模式

- API 仅做协议转换和权限校验；业务规则位于 Service。
- Repository 隔离持久化查询；复杂趋势在数据库聚合或纯函数中完成。
- Provider 通过协议接口隔离 AI、Embedding、Vision 和文件存储。
- 后台任务必须幂等；使用业务唯一键避免重复报告/通知。
- 时间统一保存 UTC，用户时区单独存储；用户展示时再转换。
- 删除健康记录默认软删除，审计事件不保存敏感正文。

## 离线同步

移动端记录包含 `local_id`、`server_id`、`sync_status`、`updated_at`。客户端使用 UUID 作为幂等键；服务端写接口后续接收 `Idempotency-Key`。冲突默认 last-write-wins，但体重/训练等事实记录保留冲突副本供用户确认。

## 可观测性

日志使用请求 ID 和结构化字段；禁止密码、完整 Token、API Key、体检全文与身体照片路径。后续接入指标：HTTP 延迟、任务失败率、通知命中率、AI Token/成本、检索质量。

