# AI Training Coach Context

## 编排

TrainingCoachOrchestrator 的固定顺序：

1. TrainingIntentClassifier
2. TrainingContextBuilder
3. TrainingSafetyService
4. Program Services
5. 配置的 Coach Provider
6. TrainingChatResponse 结构化输出

## Intent

today_workout、exercise_help、progression、weight_selection、recovery、missed_workout、schedule_change、training_progress、pain_or_discomfort、cardio、steps、sleep_recovery 和 general_training。

## 最小上下文

- weight_selection：命中的动作、最近 3–5 次有效组、目标次数、RIR、今日恢复。
- today_workout：当前计划、下一训练日、今日完成状态、恢复与活动。
- recovery：睡眠、疲劳、上次 session RPE、静息心率基线、疼痛和近 7 天频率。
- missed_workout：当前计划和顺延规则，不读取全部饮食历史。

重量、e1RM、PR、容量与进阶由程序服务计算。LLM 只能解释结果。任何 plan/weight 调整以 suggested_action 返回，用户点击应用前不会修改记录。

## 安全

急性剧烈疼痛、明显肿胀、无法负重、胸痛、晕厥或严重呼吸困难会停止普通训练建议。吃多后跑两小时、抵消热量等惩罚性运动请求会被拒绝。错过训练只顺延，不双倍补课。
