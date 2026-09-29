# AI 与 RAG 设计

## Provider 边界

业务层只依赖以下协议：

- `LLMProvider.generate(request) -> LLMResponse`
- `VisionProvider.analyze_meal(image_bytes, content_type, context) -> VisionProviderResponse`
- `EmbeddingProvider.embed(texts) -> vectors`

`AIGateway` 负责超时、重试、熔断、结构化输出校验、Token/成本记录和 Provider 路由。API Key、Base URL、模型名全部来自环境或加密后台配置，业务代码不出现 SDK 调用。

Phase 3 已实现 `MockVisionProvider` 与 `OpenAICompatibleVisionProvider`。兼容 Provider 通过 `/chat/completions` 发送 data URL 并要求严格 JSON Schema；超时和尝试次数有硬上限。该实现细节封装在 Provider 内，可替换为其他远程或本地模型。

参考官方文档：[Responses API](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)、[图像输入](https://developers.openai.com/api/docs/guides/images-vision)、[Embeddings](https://developers.openai.com/api/docs/models/text-embedding-3-small)。

## 食物识别闭环

1. 验证 MIME、大小和解码结果，私有存储原图。
2. 构建最小上下文：餐次、食堂/商家、个人餐盘记忆。
3. Vision 只返回食物列表、克重范围、烹饪方式、隐藏油脂线索和置信度，不返回最终营养。
4. Personal Food Memory、自定义食物、精确名称、别名和模糊匹配依次解析到 Phase 2 食物库。
5. `NutritionCalculator` 按中心/上下限克重确定性计算营养；可能用油形成独立条目。
6. 用户确认/修改后在单事务内写正式餐次，并保存聚合纠正记忆。

绝不把照片估算包装成精确称量；UI 默认显示区间而非虚假精确值。

## Phase 3 结构化契约与成本

Prompt `meal_v1` 和 Pydantic `VisionMealResult` 共同约束无食物标记、最多 30 个食物、中心/范围克重、烹饪方式、可见与隐藏成分、可选用油范围以及两类视觉置信度。业务层再次验证额外字段、数值边界和范围顺序。Provider 文本永远不会作为 HTML、SQL 或路径使用。

`ai_usage_logs` 记录 Provider、模型、Prompt 对应分析、Token、图片数、延迟、状态、错误码和 Provider 可得的成本。通用兼容层不硬编码可能过期的模型价格；缺少账单信息时成本为 NULL。每天限额、重分析限额、原始响应限长和 Retention 均由环境配置。

远程视觉请求必须先获得 `allow_third_party_vision` 同意。Mock 在本机处理，不视为第三方。完整细节见 `PHASE3_MEAL_VISION.md`。

## RAG

导入 → 病毒/类型检查 → 文本清洗 → 语义 Chunk → Embedding → pgvector + 关键词索引 → Metadata。查询使用改写、混合召回、重排、有效版本过滤和证据阈值；证据不足时明确说明。

Metadata：`source, title, author, year, category, evidence_level, url, language, document_version, chunk_index, active`。来源白名单优先 WHO、CDC、NIH/NIDDK、ACSM、ISSN、正式指南和高质量系统综述。

## Context Builder

按问题路由最小数据。例如“今晚能否吃黄焖鸡”只读取今日摄入/目标、最近体重趋势、今日训练、饮食环境和相关知识片段，不发送完整档案。长期记忆结构化存储且可查看、修改、删除。

## Health Safety Layer

独立于普通 Prompt 的前后置规则：急症关键词与结构化信号优先中止普通建议并提示紧急就医；禁止催吐、危险脱水、极端节食、非法药物、类固醇滥用以及自行停药/改剂量。模型输出还需 schema 校验与安全后处理。

