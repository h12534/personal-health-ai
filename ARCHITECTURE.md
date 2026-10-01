# 系统架构

## 总览

```text
iPhone Flutter App (iOS 主目标；Drift/SQLite + Outbox，后续接 HealthKit)
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

Phase 2 的移动端餐次与条目先写入 Drift/SQLite：本地事务同时创建业务记录与 `sync_outbox`。记录包含 `local_id`、`server_id`、`sync_status`、`updated_at`、`deleted_at`；Outbox 保存操作、最小必要 payload、稳定幂等键、尝试次数与错误摘要。

应用启动或网络恢复时按创建时间顺序补传。服务端的餐次创建与条目添加接受 `Idempotency-Key`，即使响应丢失后重试也不会重复写入。成功后回填 `server_id` 并标记 `synced`；失败标记 `failed`，稍后重试。当前不引入 CRDT；服务端条目更新/删除在线执行，离线创建条目在同步前可本地修改或取消。

食物搜索结果写入本地 `food_cache`。无网络时可使用已缓存食物继续创建餐食；退出登录会清除本地健康记录、Outbox 和食物缓存，避免跨账户残留。

## Phase 2 营养数据流

```text
FoodItem + amount/unit
        │ PortionConversionService
        ▼
NutritionCalculator (Decimal, 0.001)
        │ snapshot
        ▼
MealItem ──recalculate──► MealLog cached totals
        │
        ├──► DailyNutritionService ──► /nutrition/daily + /range
        └──► DashboardRuleEngine ────► real metrics + deterministic next action
```

Dashboard 规则引擎只使用晨重完成度、当地时间、餐次状态、热量/蛋白质进度与体重趋势，不调用 LLM。

## Phase 3 视觉识别边界

```text
UploadFile → ImageValidationService → StorageProvider
                                      │
                                      ▼
MealAnalysisSession → VisionProvider → strict VisionMealResult
        │                                  │
        ├─ FoodMatchingService ◄───────────┘
        ├─ NutritionRangeService → Phase 2 NutritionCalculator
        └─ user confirm transaction → MealLog / MealItem / PersonalFoodMemory
```

图像、分析会话和草稿条目独立于正式餐食，因此 Provider 超时、无食物、草稿删除或过期都不会污染 Phase 2 数据。远程调用由 `VisionProvider` 协议隔离；默认 Mock 与真实 Provider 使用同一结构化契约。API 可同步内联处理 Mock，也可只排队给 Celery；客户端统一按状态轮询。

确认阶段对分析行加锁，在同一数据库事务内创建餐次、营养快照、确认状态和个人纠正记忆。任何未匹配条目或营养换算错误都会回滚整个餐次。AI 不计算最终营养，业务层只把识别克重交给现有确定性计算器。

Flutter 的 `local_vision_tasks` 与 Phase 2 `sync_outbox` 分离：餐食照片可能较大、需要用户查看草稿，不能像普通小 payload 一样静默重放。离线时保存应用私有图片和任务；用户显式恢复后上传。

## Phase 4 饮食教练边界

```text
Intent → Safety → Context → deterministic diet services → CoachProvider → schema validation
                         ├─ target / adherence / trend / TDEE
                         ├─ next meal / canteen / saved meal
                         └─ pending adjustment → explicit user decision
```

规则服务拥有数值真相，Provider 只负责自然语言。高风险请求由安全层短路。聊天动作不执行领域写入；目标调整通过独立、幂等、按用户隔离的审批 API，在事务中创建次日目标版本。详见 `PHASE4_DIET_COACH.md`。

## iOS 平台边界

- iOS 16+ 是主移动目标，Android 保留兼容构建；Linux 后端协议不依赖移动平台。
- iOS Runner 进入版本控制，Bundle ID 与显示名由非秘密 Xcode 配置覆盖。
- Token 进入 iOS Keychain；Drift、Outbox 和待上传图片只在应用沙盒内。
- `HealthDataProvider` 的 iPhone 优先级为 `AppleHealthProvider → ManualHealthProvider`。HealthKit entitlement 与分类只读授权已接入，拒绝、部分授权或无数据时保留手工路径。
- 提醒先采用本地通知，远程事件再接 APNs。服务器调度器只负责监督、去重和触发，不假定 iOS 应用常驻后台。
- staging/prod 只允许 HTTPS；不提交全局 ATS 例外。设备端不能使用 localhost 访问开发 Mac。
- Widget 与 Apple Watch 为未来扩展，不进入 Phase 5 交付范围。

## 可观测性

日志使用请求 ID 和结构化字段；禁止密码、完整 Token、API Key、体检全文与身体照片路径。后续接入指标：HTTP 延迟、任务失败率、通知命中率、AI Token/成本、检索质量。

## Phase 5 training and health flow

Flutter Training UI → Drift v3 / Outbox → FastAPI workout API → PostgreSQL training tables → deterministic progress/recovery services → AI explanation.

Apple Health access is isolated behind HealthDataProvider. Only structured summaries pass through /health/sync/summary; health_sync_state records per-type incremental cursors. Diet context consumes today_training_status, activity and recovery without coupling Phase 4 to plugin code.

## Phase 6 health knowledge and clinical context

```text
Vetted document → Extract/Chunk → EmbeddingProvider → pgvector + FTS
                                                        │
Lab image/PDF → private storage → per-page OCR → Draft → user confirm → LabResult
                                                        │
Question → Intent → Safety → minimal context → Hybrid/Rerank → Answer + Citation
```

Knowledge、Labs 与 Health AI 保持三个边界：知识导入不读取个人数据；OCR 只生成草稿；Health Context 只读取当前用户已确认的最少必要数据。`HealthSafetyService` 可在检索和 Provider 之前短路。Drift v4 只缓存已保存报告和趋势，不缓存原始体检文件或完整健康对话。

iOS Files 选择通过 Runner 内的 `UIDocumentPickerViewController` 完成，只接受 PDF；读取时使用 security-scoped access 并立即释放，不保存外部 URL。Camera/Photos 继续使用已有 `image_picker` 权限流程。

## Phase 7 supervision and reporting

```text
Domain facts ─► DailyTaskEngine ─► ReminderEngine ─► NotificationService
     │              │                 │                    └─ PushProvider
     │              └─ dashboard/today  └─ DND/cooldown/limits
     ├─► HealthReportService ─► cached structured snapshot ─► AI summary
     └─► HealthTimelineService (query projection, no duplicated event store)
```

Daily task and notification writes have database unique keys, so the 15-minute
Celery sweep is safe to retry. The scheduler computes in each user's timezone,
while persisted timestamps stay UTC. Reports use program-calculated metrics;
AI cannot replace or recalculate them. Proactive AI is rule-gated and daily
limited.

iOS fixed reminders are scheduled locally only after contextual permission.
Server-side reminders use a provider boundary and do not assume that iOS can be
woken to execute business logic. `MockPushProvider` is the default; Apple
credentials and the production HTTP/2 transport are external release gates.

The privacy lock wraps the authenticated app surface after a two-minute
background grace period. Export and deletion execute through authenticated
backend services; foreign-key cascades are enforced in PostgreSQL and explicitly
enabled for SQLite tests.
