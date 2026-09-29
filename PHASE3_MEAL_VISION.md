# Phase 3：AI 餐食拍照识别

Phase 3 在 Phase 2 食物库、`NutritionCalculator`、餐次和每日汇总之上增加单张餐食照片识别。AI 结果永远是可编辑草稿；只有用户确认后，系统才在一个事务中创建正式 `meal_logs` / `meal_items`，并立即进入 Dashboard 和每日营养统计。

## 数据流

```text
Flutter camera/gallery
  └─ max edge 2048, JPEG quality 86, no EXIF
       └─ multipart + Idempotency-Key
            └─ MIME + magic + Pillow decode + size/pixel/dimension checks
                 └─ sanitized JPEG → private meal-analysis/YYYY/MM/UUID.jpg
                      └─ pending session → Celery or inline processor
                           └─ VisionProvider strict JSON
                                └─ personal/custom/exact/alias/fuzzy matching
                                     └─ Phase 2 NutritionCalculator
                                          └─ editable draft + ranges
                                               └─ user confirm transaction
                                                    ├─ MealLog(source=vision_confirmed)
                                                    ├─ MealItem nutrition snapshots
                                                    ├─ PersonalFoodMemory
                                                    └─ daily/dashboard aggregation
```

`VISION_ASYNC_ENABLED=false` 适合本地 Mock 开发；生产建议设为 `true`，由 Redis/Celery Worker 处理，客户端轮询分析状态。Beat 每日清理过期草稿、原始响应、图片和过期 AI 用量日志。

## Prompt 与结构化结果

版本化 Prompt 位于 `backend/app/ai/prompts/meal_v1.py`，版本写入每个分析会话。Provider 必须返回严格 JSON Schema：

- `no_food_detected`
- `foods[]`
  - `detected_name`, `aliases`
  - `estimated_weight_g`
  - `weight_range.min_g/max_g`
  - `portion_description`, `cooking_method`
  - `recognition_confidence`, `portion_confidence`
  - `visible_components`, `possible_hidden_ingredients`
  - `possible_oil_weight.min_g/max_g`
- `overall_confidence`, `warnings`

额外字段被拒绝；中心克重必须落在区间内；最多 30 个条目。Prompt 明确禁止模型输出最终热量或饮食建议。模型只负责视觉识别、份量范围和隐藏成分线索。

## Provider

- `MockVisionProvider`：默认，无 API Key 也能运行完整闭环；固定 fixtures 覆盖多食物、低置信度、非食物和非法响应。
- `OpenAICompatibleVisionProvider`：调用兼容 `/chat/completions` 的视觉端点，使用 data URL 和 JSON Schema，超时与尝试次数均有上限。
- `DisabledAIProvider`：显式关闭时返回可识别的服务错误。

环境变量：

```dotenv
VISION_PROVIDER=mock
VISION_BASE_URL=
VISION_API_KEY=
VISION_MODEL=mock-meal-v1
VISION_PROMPT_VERSION=meal_v1
VISION_TIMEOUT_SECONDS=45
VISION_MAX_ATTEMPTS=2
VISION_ASYNC_ENABLED=false
```

远程 Provider 只有在健康档案的 `allow_third_party_vision=true` 时才会接收图片。密钥不写数据库、响应或日志。

## 食物匹配与营养范围

匹配顺序固定为：

1. 当前用户相同场景的 `personal_food_memories`
2. 用户自定义食物精确名称
3. 系统食物精确名称
4. 食物别名
5. 有阈值的模糊匹配
6. `unmatched`，要求用户手动选择

常见烹饪前缀只用于生成额外匹配候选，不创建硬编码营养数据。复合餐由 Vision 拆成可独立编辑的成分；无法可靠拆分时保留未匹配草稿。

营养中心值和区间不来自 LLM：

```text
center = NutritionCalculator(food, estimated_weight_g)
minimum = NutritionCalculator(food, min_weight_g)
maximum = NutritionCalculator(food, max_weight_g)
```

可能的烹饪油被创建为独立隐藏条目，使用食物库中的“食用油”以及独立重量区间。条目置信度取识别、份量、匹配三者的最低值，映射为 `high / medium / low`。

## 状态与失败处理

状态为 `pending → processing → completed → confirmed`。失败为 `failed`，未确认草稿到期为 `expired`。

- `no_food_detected`：不创建食物，不猜测。
- `invalid_vision_response`：Schema 不合格，可重新分析。
- `vision_timeout` / `vision_provider_error`：保留图片和草稿任务，可重试。
- `unmatched`：草稿仍可编辑，但确认前必须匹配食物。
- 重分析默认最多 3 次；视觉请求默认每天 50 次。
- 重复上传以用户 + `Idempotency-Key` 唯一；未提供时使用原上传字节 SHA-256。
- 同一分析重复确认返回同一餐次；并发确认在 PostgreSQL 中锁定分析行。

## 图片隐私与 Retention

接受 JPEG、PNG、WEBP，最大 10 MB；同时检查声明 MIME、魔数、实际解码格式、宽高和总像素。Pillow 完整解码后执行方向校正、RGB 转换和重新编码，因此 GPS EXIF 与其他元数据不会进入私有存储。客户端原始文件名不会被保存。

默认对象键为 `meal-analysis/YYYY/MM/UUID.jpg`。`retain_meal_images=false` 时图片按 `MEAL_IMAGE_RETENTION_DAYS`（默认 30 天）删除；配置为 `0` 时草稿期仍保留图片，确认后立即删除，未完成草稿最迟在草稿过期时删除。开启长期保留时不设过期时间。删除分析草稿会立即删除图片。营养记录与图片生命周期独立。

Provider 原始响应仅用于限时调试，长度上限为 100,000 字符，默认保留 7 天；API 不向客户端返回原始响应。普通日志只记录 ID、Provider、模型、状态和延迟，不记录图片内容、对象键、API Key 或 Provider 原文。

## AI 用量和成本

`ai_usage_logs` 保存用户、分析会话、Provider、模型、任务、输入/输出 Token、图片数、延迟、Provider 可用时的估算成本、状态和错误码。Mock 成本为 0。每天限额在上传前检查；日志默认保留 365 天。当前通用兼容 Provider 不臆测价格，若 Provider 未返回成本则保存 `NULL`。

## Flutter

饮食页提供醒目的“拍照识别一餐”入口，支持相机和相册。图片最长边限制 2048，JPEG 质量 86，并关闭 EXIF。上传显示进度；异步状态按递增间隔轮询。

草稿页显示：

- 本餐中心热量和区间、宏量营养
- 食物匹配、份量范围、热量范围、置信度
- 可能隐藏的油和酱汁
- `±25g / ±50g` 快捷调整与直接输入克重
- 更换匹配、删除、补充遗漏食物
- 餐次和备注
- 明确的“AI 只是草稿”提示

离线时压缩图片和 `local_vision_tasks` 写入 Drift，不丢失本地照片；饮食页列出待完成任务，可联网后继续，或改用 Phase 2 手工记录。确认成功后删除本地任务和图片，并刷新饮食页与 Dashboard。

平台工程由 `flutter create` 生成后运行 `dart run tool/configure_platforms.dart`，写入 iOS 相机/相册用途描述并将 Android `minSdk` 调整为 24。

## 数据表

- `meal_images`
- `meal_analysis_sessions`
- `meal_analysis_items`
- `personal_food_memories`
- `ai_usage_logs`

迁移：`0003_phase3_meal_vision`。PostgreSQL 使用 JSONB，SQLite 测试使用 JSON 变体。

## API

| Method | Path | 说明 |
|---|---|---|
| POST | `/api/v1/meals/analyze-image` | multipart 上传，创建分析 |
| GET | `/api/v1/meals/analyses/{id}` | 轮询/读取草稿 |
| PATCH | `/api/v1/meals/analyses/{id}/items/{item_id}` | 修改重量或匹配 |
| POST | `/api/v1/meals/analyses/{id}/items` | 补充遗漏食物 |
| DELETE | `/api/v1/meals/analyses/{id}/items/{item_id}` | 删除错误条目 |
| POST | `/api/v1/meals/analyses/{id}/reanalyze` | 有限次数重新分析 |
| POST | `/api/v1/meals/analyses/{id}/confirm` | 原子确认并创建正式餐食 |
| DELETE | `/api/v1/meals/analyses/{id}` | 删除未确认草稿和图片 |
| PATCH | `/api/v1/profile/privacy/meal-vision` | 更新远程视觉同意和图片保留 |

## 测试

测试图片由 Pillow 在内存生成；提交的 JSON fixtures 为合成数据，不含用户私人照片。SQLite 测试覆盖上传安全、结构化结果、多食物、匹配、范围、隐藏油、置信度、草稿 CRUD、失败态、事务确认、幂等、权限、每日限额与 Retention。GitHub Actions 使用真实 PostgreSQL 16 和 Redis，执行迁移，并验证 JSONB 列、UUID/时区/嵌套 JSONB 往返、幂等约束和 Redis 连通性。

真实 Provider 和授权图片测试见 [REAL_VISION_TEST.md](REAL_VISION_TEST.md)。
