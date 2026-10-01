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
| GET/POST/PATCH/DELETE | `/diet/memories` | 可查看、确认修改和删除的结构化个人饮食记忆 |
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

## Phase 5 endpoints

- GET /api/v1/exercises and GET /api/v1/exercises/search
- POST/GET/PATCH /api/v1/training/plans and POST /api/v1/training/plans/generate
- GET /api/v1/training/progress/{exercise_id}, /training/prs, /training/weekly-review
- POST /api/v1/training/adjustments/apply (user-confirmed, idempotent progression update)
- POST/GET /api/v1/workouts, GET /workouts/{id}
- POST /workouts/{id}/sets, PATCH /workouts/{id}/sets/{set_id}, POST /workouts/{id}/complete
- GET /api/v1/activity/daily, GET /api/v1/sleep, GET/POST /api/v1/recovery/today
- POST /api/v1/health/sync/summary, GET/PUT /api/v1/health/permissions
- DELETE /api/v1/health/sync/{provider}
- POST /api/v1/ai/training/chat

Workout and set writes accept Idempotency-Key and stable client UUIDs. Training adjustments are suggestions until the user confirms them; applying one stores the audit record and updates the active plan target weight. Health summary writes require a provider source_record_id.

## Phase 6 endpoints

| Method | Path | 用途 |
|---|---|---|
| POST | `/api/v1/knowledge/documents/import` | multipart 导入 vetted 文档与明确 metadata |
| GET | `/api/v1/knowledge/documents` | 列出版本、active/archive 状态 |
| GET | `/api/v1/knowledge/documents/{id}/chunks` | 管理用途查看 chunks |
| PATCH | `/api/v1/knowledge/documents/{id}` | 启用/停用/归档 |
| POST | `/api/v1/knowledge/documents/{id}/reembed` | 用当前 Provider 重新 embedding |
| DELETE | `/api/v1/knowledge/documents/{id}` | 软删除文档 |
| POST | `/api/v1/knowledge/search` | Hybrid Search + Rerank + evidence threshold |
| POST | `/api/v1/labs/reports` | 上传图片/PDF；远程 OCR 需 `allow_remote_ocr=true` |
| GET | `/api/v1/labs/reports[/{id}]` | 当前用户报告与 Draft/正式结果 |
| PATCH | `/api/v1/labs/reports/{id}/draft-items/{item_id}` | 修改 OCR 草稿 |
| POST | `/api/v1/labs/reports/{id}/confirm` | 确认全部或指定条目 |
| DELETE | `/api/v1/labs/reports/{id}` | 软删除报告/结果并删除原文件 |
| DELETE | `/api/v1/labs/results/{id}` | 删除单项正式指标 |
| GET | `/api/v1/labs/trends/{normalized_name}` | 规范单位后的历史趋势 |
| POST | `/api/v1/labs/reports/{id}/follow-up-suggestions` | 用户触发生成复查建议 |
| POST | `/api/v1/labs/follow-up-suggestions/{id}/accept` | 用户接受建议 |
| POST | `/api/v1/ai/health/chat` | 安全筛查、个人上下文、RAG、引用式回答 |

Lab 文件最大 30 MB，只接受 JPEG/PNG/WebP/PDF。上传响应永远先是 Draft；只有 confirm 后的值进入趋势和 Health AI context。所有 Lab/Health AI 资源按当前用户过滤，越权统一表现为 404。

## Phase 7 endpoints

Phase 7 路由前缀为 `/api/v1/supervision`：

| Method | Path | 用途 |
|---|---|---|
| GET/POST | `/tasks`, `/tasks/generate` | 幂等生成当日任务并执行自动完成检测 |
| PATCH | `/tasks/{id}` | 手动 `completed/skipped/cancelled` |
| GET/PUT | `/preferences` | 提醒总开关、强度、时间、勿扰与报告日 |
| POST | `/reminders/evaluate?send=false` | 返回提醒决策；`send=true` 仅用于鉴权调试/运维 |
| GET | `/notifications` | 最近 100 条非敏感投递元数据 |
| PUT | `/push-device` | 幂等注册/更新当前用户推送设备 |
| GET/POST | `/reports`, `/reports/generate` | 查询或生成 daily/weekly/monthly 缓存报告 |
| GET | `/timeline?from=&to=&category=` | 时间线 Query Projection，类别为 all/body/nutrition/training/lab/report |
| GET | `/cross-domain?from=&to=&metrics=` | 体重/步数/睡眠/HbA1c 同期数列与非因果声明 |
| POST | `/correlation-guard` | 对因果问题返回限制说明 |
| GET/POST | `/followups` | 查询/建立复查建议 |
| POST/PATCH | `/followups/{id}/confirm`, `/followups/{id}` | 用户确认或改期 |
| POST | `/followups/{id}/cancel` | 取消复查 |
| GET | `/export/json`, `/export/csv` | 导出当前用户数据 |
| DELETE | `/data` | 精确确认字符串后删除当前账号和私有数据 |

HealthKit 同步状态使用 `GET /api/v1/health/sync/status`。系统健康检查为 `GET /health/live` 和 `GET /health/ready`。
