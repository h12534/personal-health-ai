# AI 教练上下文与安全层

## 意图

`IntentClassifier` 支持：`meal_decision, meal_recommendation, daily_summary, nutrition_question, weight_progress, diet_plan, overeating_recovery, hunger, restaurant_choice, canteen_choice, food_comparison, general_chat, unsupported_medical, emergency_health`。

当前版本优先使用可审计关键词规则；高风险意图排在普通意图之前。未来可以增加小模型分类器，但输出仍必须落入固定枚举并经过安全层。

## 最小上下文

`CoachContextBuilder` 按意图读取：

| 上下文 | 使用意图 |
|---|---|
| 阶段、活动、饮食环境、过敏/不喜欢 | 全部 |
| 可查看/删除的个人饮食记忆 | 全部 |
| 今日营养与下一餐范围 | 餐食、饥饿、食堂、每日总结 |
| 依从性与体重趋势 | 体重、计划、每日总结 |

不会把密码、Token、图片路径、Provider Key 或无关完整健康档案发送给 Provider。上下文带 `coach_context_v1`，便于审计与回归。

## 安全层

前置确定性规则：

- 急症：直接提示联系当地急救（中国大陆 120）并寻求身边帮助。
- 诊断/用药：拒绝诊断和调整药物，建议专业评估。
- 暴食补偿、催吐、极端断食、惩罚性运动：直接给出非惩罚恢复信息和求助提示。

这些响应使用 `provider=safety_layer, model=deterministic-v1`，不调用普通 Provider。普通输出还必须通过 `CoachGeneratedReply` 严格校验。

## 结构化响应

```json
{
  "conversation_id": "uuid",
  "intent": "canteen_choice",
  "message": "...",
  "suggested_actions": [
    {"type": "open_canteen", "label": "查看食堂", "target_id": null}
  ],
  "safety_notice": null,
  "provider": "mock",
  "model": "mock-coach-v1",
  "context_version": "coach_context_v1"
}
```

远程兼容实现使用 Chat Completions 的 strict JSON Schema。Schema 中对象禁止额外字段，所有字段均为 required；可空字段使用 null union。参考官方 [Structured Outputs 指南](https://developers.openai.com/api/docs/guides/structured-outputs)。

## 写入边界

聊天接口会保存对话用于连续性和审计，但不会根据模型输出写入体重、餐食、饥饿或营养目标。`suggested_actions` 只允许固定的客户端导航动作。真正的饮食调整使用独立审批 API，并由服务端重查所有权、状态和当前目标。
