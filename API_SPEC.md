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

## Phase 3：餐食图片分析

| Method | Path | 用途 |
|---|---|---|
| POST | `/meals/analyze-image` | multipart 单图上传，支持 `Idempotency-Key`，返回分析状态/草稿 |
| GET | `/meals/analyses/{analysis_id}` | 轮询 pending/processing 或读取完整草稿 |
| PATCH | `/meals/analyses/{analysis_id}/items/{item_id}` | 修改匹配、名称、中心/范围克重、份量或烹饪方式 |
| POST | `/meals/analyses/{analysis_id}/items` | 从食物库补充遗漏食物 |
| DELETE | `/meals/analyses/{analysis_id}/items/{item_id}` | 从草稿软删除错误条目 |
| POST | `/meals/analyses/{analysis_id}/reanalyze` | 在次数上限内重新分析同一图片 |
| POST | `/meals/analyses/{analysis_id}/confirm` | 原子创建 `vision_confirmed` 正式餐次，支持幂等重放 |
| DELETE | `/meals/analyses/{analysis_id}` | 删除未确认草稿和私有图片 |
| PATCH | `/profile/privacy/meal-vision` | 更新第三方视觉同意和图片长期保留选择 |

上传字段：`image`（JPEG/PNG/WEBP，最大 10 MB），可选 `location_context`、`meal_type`、含时区的 `eaten_at` 与 `note`。同一用户和 `Idempotency-Key` 返回同一分析；无 Key 时以原始上传 SHA-256 生成幂等键。返回状态包括 `pending, processing, completed, failed, confirmed, expired`。

分析响应包含匹配食物、中心/上下限克重、由食物库计算的中心营养和热量范围、识别/份量/匹配置信度、隐藏成分和警告。Provider 原始响应及图片路径不对客户端暴露。`confirm` 前任何分析都不会出现在 `/meals`、每日营养或 Dashboard。

## 后续资源

## Phase 4：饮食教练

| Method | Path | 用途 |
|---|---|---|
| GET | `/diet/targets/daily` | 程序化每日目标与安全说明 |
| GET | `/diet/weight-trend` | 7/14/28 天趋势与平台期资格 |
| GET | `/diet/adherence?days=` | 记录、热量与蛋白依从性 |
| GET | `/diet/energy-model` | 公式/观察/混合 TDEE |
| GET | `/diet/next-meal` | 下一餐热量和蛋白范围 |
| GET | `/diet/weekly-review` | 周回顾、趋势与待审批调整 |
| GET | `/diet/adjustments/current` | 生成/读取当前建议 |
| POST | `/diet/adjustments/{id}/accept` | 接受并建立次日目标版本 |
| POST | `/diet/adjustments/{id}/decline` | 拒绝建议，保持当前目标 |
| GET/POST | `/diet/hunger` | 饥饿记录 |
| GET/POST/DELETE | `/diet/memories` | 可管理的个人饮食记忆 |
| GET/POST/PATCH/DELETE | `/canteens` | 个人食堂；GET 返回活跃档口与可用菜品树 |
| POST/PATCH/DELETE | `/canteens/{id}/stalls`、`/canteens/stalls/{id}` | 档口维护 |
| POST/PATCH/DELETE | `/canteens/stalls/{id}/dishes`、`/canteens/dishes/{id}` | 菜品与收藏维护 |
| POST | `/canteens/stalls/{stall_id}/learn-from-meal/{meal_id}` | 从已确认餐食学习菜品 |
| GET | `/canteens/recommendations` | 对下一餐范围排序菜品 |
| GET/POST/DELETE | `/saved-meals` | 常用餐营养快照 |
| POST | `/saved-meals/{id}/log` | 幂等记录常用餐 |
| POST | `/ai/coach/chat` | 结构化私人饮食教练；只返回建议动作 |

调整的 accept/decline 与常用餐 log 都要求稳定幂等键。跨用户资源返回 404。Coach 不根据模型输出直接修改目标或记录餐食。

## 后续资源

保留 `/training`, `/workouts`, `/activity`, `/sleep`, `/water`, `/labs`, `/reports`, `/knowledge`, `/reminders`。

