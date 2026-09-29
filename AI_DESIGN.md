# AI 与 RAG 设计

## Provider 边界

业务层只依赖以下协议：

- `LLMProvider.generate(request) -> LLMResponse`
- `VisionProvider.analyze_food(image, context) -> FoodEstimate`
- `EmbeddingProvider.embed(texts) -> vectors`

`AIGateway` 负责超时、重试、熔断、结构化输出校验、Token/成本记录和 Provider 路由。API Key、Base URL、模型名全部来自环境或加密后台配置，业务代码不出现 SDK 调用。

OpenAI 实现计划使用 Responses API；图像识别以 `input_image` 发送受控的临时 URL 或 data URL，并要求 JSON Schema 结构化结果。该实现细节封装在 Provider 内，可替换为 Gemini、Claude、OpenAI-compatible 或本地模型。

参考官方文档：[Responses API](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)、[图像输入](https://developers.openai.com/api/docs/guides/images-vision)、[Embeddings](https://developers.openai.com/api/docs/models/text-embedding-3-small)。

## 食物识别闭环

1. 验证 MIME、大小和解码结果，私有存储原图。
2. 构建最小上下文：餐次、食堂/商家、个人餐盘记忆。
3. Vision 返回食物列表、克重范围、烹饪方式、隐藏油脂风险、营养区间和置信度。
4. 标准食物库 + Personal Food Memory 校准。
5. 用户确认/修改后写正式餐次，同时保留 AI 原始估计用于后续校准。

绝不把照片估算包装成精确称量；UI 默认显示区间而非虚假精确值。

## RAG

导入 → 病毒/类型检查 → 文本清洗 → 语义 Chunk → Embedding → pgvector + 关键词索引 → Metadata。查询使用改写、混合召回、重排、有效版本过滤和证据阈值；证据不足时明确说明。

Metadata：`source, title, author, year, category, evidence_level, url, language, document_version, chunk_index, active`。来源白名单优先 WHO、CDC、NIH/NIDDK、ACSM、ISSN、正式指南和高质量系统综述。

## Context Builder

按问题路由最小数据。例如“今晚能否吃黄焖鸡”只读取今日摄入/目标、最近体重趋势、今日训练、饮食环境和相关知识片段，不发送完整档案。长期记忆结构化存储且可查看、修改、删除。

## Health Safety Layer

独立于普通 Prompt 的前后置规则：急症关键词与结构化信号优先中止普通建议并提示紧急就医；禁止催吐、危险脱水、极端节食、非法药物、类固醇滥用以及自行停药/改剂量。模型输出还需 schema 校验与安全后处理。

