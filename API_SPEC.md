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

## Phase 2：食物

| Method | Path | 用途 |
|---|---|---|
| GET | `/foods?q=&category=&limit=` | 搜索/列出可见食物 |
| GET | `/foods/search?q=&category=&limit=` | 同上，兼容显式搜索路径 |
| GET | `/foods/{id}` | 食物详情 |
| POST | `/foods` | 创建当前用户的自定义食物 |
| PATCH | `/foods/{id}` | 更新本人自定义食物 |
| DELETE | `/foods/{id}` | 软删除本人自定义食物 |
| POST | `/foods/{id}/favorite` | 收藏食物 |
| DELETE | `/foods/{id}/favorite` | 取消收藏 |
| GET | `/foods/favorites` | 收藏列表 |
| GET | `/foods/recent?limit=20` | 最近使用食物 |

系统食物所有已认证用户可读；自定义食物仅所有者可见、可写。搜索覆盖规范化名称、别名、品牌与分类，并综合收藏、最近使用和匹配质量排序。

## Phase 2：餐次与营养

| Method | Path | 用途 |
|---|---|---|
| POST | `/meals` | 创建餐次；支持 `Idempotency-Key` |
| GET | `/meals?from=&to=` | 按用户本地日期列出餐次 |
| GET | `/meals/{id}` | 餐次详情与条目快照 |
| PATCH | `/meals/{id}` | 更新餐次 |
| DELETE | `/meals/{id}` | 软删除餐次及有效条目 |
| POST | `/meals/{id}/items` | 添加条目；支持 `Idempotency-Key` |
| PATCH | `/meals/{id}/items/{item_id}` | 修改食物/份量并重算缓存 |
| DELETE | `/meals/{id}/items/{item_id}` | 软删除条目并重算缓存 |
| GET | `/nutrition/daily?date=` | 当日总量、餐次拆分与餐次数 |
| GET | `/nutrition/range?from=&to=` | 最长 366 天的逐日汇总，包含零记录日 |
| GET | `/nutrition/goals/current?date=` | 查询指定日期生效的目标 |
| GET | `/nutrition/goals/suggested?date=` | 程序化、安全边界内的初始建议 |
| POST | `/nutrition/goals` | 新建目标版本并结束上一版本 |
| PATCH | `/nutrition/goals/{id}` | 修改本人目标版本 |

`meal.eaten_at` 必须包含时区。服务端转为 UTC 保存，并按健康档案的时区（缺省 `Asia/Shanghai`）解释日期范围。目标热量接受范围为 1200–10000 kcal；1000 kcal 等低值直接返回 422。

## 后续资源

保留 `/meals/analyze`, `/diet-plan`, `/training`, `/workouts`, `/activity`, `/sleep`, `/water`, `/labs`, `/reports`, `/ai/chat`, `/knowledge`, `/reminders`。图像识别属于 Phase 3：先返回候选与范围，只有用户确认后才写入正式餐次。

