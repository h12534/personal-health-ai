# Health AI Context

`HealthContextBuilder` 按意图选择最小必要数据，而不是把整个健康档案和全部体检结果发送给模型。

| Intent | Context |
|---|---|
| `lab_explanation` / `metabolic_health` | 档案摘要 + 已确认且未删除的相关体检指标 |
| `medical_diagnosis_request` | 同上，但由 Safety 强制诊断边界 |
| `weight_health` | 7/14/28 天程序化体重趋势、今日营养、训练上下文、恢复状态 |
| `sleep_health` | 恢复与相关训练摘要 |
| `exercise_health` | 恢复与今日训练摘要 |
| `nutrition_health` | 今日程序化营养聚合 |
| general/symptom/medication | 档案摘要；无关体检数据不读取 |

只使用 `review_status=confirmed`、`user_confirmed=true`、未软删除并属于当前用户的数据。报告参考范围随指标进入 context。BMR、TDEE、热量、7 日均值、PR、训练量和单位转换继续由既有程序服务计算；RAG 和模型不能覆盖这些值。

Provider 获得 `intent + question + personal_context + evidence`，返回自然语言。持久化消息保存结构化响应、Provider/模型和规则版本；普通日志不输出完整对话。`ai_usage_logs` 分别记录 `health_chat`、`rag_retrieval`、`rerank`、`embedding` 和 `lab_ocr`。
