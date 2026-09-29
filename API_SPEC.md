# API 规范

Base URL：`/api/v1`。所有时间为 ISO 8601，日期为 `YYYY-MM-DD`，数值使用公制。

## 响应

成功：`{"data": ..., "meta": {...}}`

失败：`{"error": {"code": "...", "message": "...", "details": ...}, "request_id": "..."}`

## Phase 1

| Method | Path | 用途 |
|---|---|---|
| POST | `/auth/register` | 初始化唯一用户 |
| POST | `/auth/login` | 密码登录 |
| POST | `/auth/refresh` | 轮换 Refresh Token |
| POST | `/auth/logout` | 撤销当前 Refresh Token |
| GET | `/auth/me` | 当前账户 |
| GET | `/profile` | 读取健康档案 |
| PUT | `/profile` | 创建或完整更新档案 |
| GET | `/weight?from=&to=` | 体重历史 |
| POST | `/weight` | 新增当日体重 |
| PATCH | `/weight/{id}` | 更新体重 |
| DELETE | `/weight/{id}` | 软删除体重 |
| GET | `/weight/trends?days=30` | 7 日均值与趋势 |
| GET | `/dashboard/today` | 今日聚合与下一步建议 |
| GET | `/health` | 存活检查 |
| GET | `/ready` | 数据库/Redis 就绪检查 |

认证头：`Authorization: Bearer <access_token>`。Token 不放查询字符串。写入接口均做 Pydantic 范围校验；OpenAPI 位于 `/docs`。

## 后续资源

保留 `/meals`, `/meals/analyze`, `/nutrition`, `/diet-plan`, `/training`, `/workouts`, `/activity`, `/sleep`, `/water`, `/labs`, `/reports`, `/ai/chat`, `/knowledge`, `/reminders`。图像识别先返回候选与范围，只有用户确认后才写入正式餐次。

