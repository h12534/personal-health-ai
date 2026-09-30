# RAG 设计

## 查询链路

```text
question
  → HealthIntentClassifier
  → HealthSafetyService（可短路）
  → HealthContextBuilder（最小必要个人数据）
  → HealthQueryRewriter（同义词与分类）
  → vector + PostgreSQL FTS
  → DeterministicReranker
  → evidence threshold 0.18
  → HealthAnswerProvider
  → structured citations
```

PostgreSQL 使用 64 维 `vector`（维度由当前迁移固定）、cosine distance、generated `tsvector`、GIN 全文/metadata 索引和 HNSW 向量索引。召回结果只包含 `active=true, archived=false, deleted_at IS NULL` 的当前文档。SQLite fallback 在单元测试中用 Python cosine + token overlap，不能替代 PostgreSQL 集成测试。

## 排序

第一版总分为向量相似度、文本重合度、证据等级和标题命中的确定性组合。指南、系统综述和 meta-analysis 获得较高证据加权；证据等级由导入者填写，模型不能猜。低于阈值的片段不进入回答；无证据时必须明确“当前知识库没有足够依据”。

## 引用和防幻觉

每条证据返回文档标题、publisher、年份、章节、链接、受限长度摘要、分类和证据等级。普通 Flutter UI 不显示 embedding、内部 chunk ID 或 score。OpenAI-compatible Health Answer Provider 的 system boundary 只允许使用给定 evidence 与 personal context；来源不会由模型自由生成。

## 评测

`backend/tests/rag_eval/cases.json` 含 36 个覆盖体重、营养、训练、睡眠、血糖、血脂、尿酸、脂肪肝、安全、诊断和停药的问题。每例定义 expected category、是否必须召回和禁止的不安全措辞。CI 单元测试使用 deterministic Mock Embedding；真实 PostgreSQL 测试验证 vector 类型、cosine、JSONB filter 和完整 hybrid service。
