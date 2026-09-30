# Phase 5：训练、活动、恢复与 Apple Health

Phase 5 在既有 Flutter、FastAPI、PostgreSQL 架构上增加训练闭环，不改变 Phase 0–4 的饮食、体重与 AI 契约。iPhone 是主要客户端，Android 仍保留兼容路径。

## 已实现链路

- 28 个幂等动作种子，覆盖深蹲、髋铰链、推、拉、核心、负重行走与低冲击有氧。
- 规则化训练计划：2 天全身、3 天全身、4 天上下肢；设备、偏好和身体限制参与动作选择。
- Workout Session 与每组稳定 UUID；RIR 优先输入，自动推导 RPE；热身组不计入有效容量。
- 最大重量、次数、估算 1RM、单组容量四类 PR。
- Double Progression、保守加重、保持重量、连续下降与恢复偏低时小幅回退。
- 步数、距离、活动能量、静息心率、睡眠、训练摘要和增量同步状态。
- RecoverySnapshot 只输出 good、normal、reduced、insufficient_data。
- AI 私教采用 Intent → Context → Safety → Program Service → LLM → Structured Output。
- AI 的加重结果只作为 suggested_action 返回；用户点击“应用建议”后才通过幂等接口写入计划目标重量，并保留调整审计记录。
- Drift v3 与 Outbox 支持离线开始训练、记录每组、结束训练及恢复网络后的幂等重放。
- Phase 4 NextMealPlanner 与饮食教练能读取 today_training_status、活动和恢复上下文。

## 安全边界

默认以每周 2–4 次可恢复的力量训练、日常步行和低冲击有氧为主。不会因为一次重量较大判断为高级训练者，不默认安排大量跑步、HIIT、力竭或惩罚性运动。胸痛、晕厥、严重呼吸困难、剧烈疼痛、明显肿胀或无法负重会进入安全分流。

## 运行

先执行数据库迁移与动作种子：

~~~shell
cd backend
alembic upgrade head
python -m app.scripts.seed_exercises
~~~

移动端依旧使用既有启动方式。Windows 与 CI 可注入 MockHealthDataProvider；真实 HealthKit 只在签名后的物理 iPhone 上验收。

## 暂不包含

Apple Watch App、摄像头动作纠正、医学康复计划、完整 RAG、补剂系统、社交排行榜、教练市场和商业化均不在本阶段。
