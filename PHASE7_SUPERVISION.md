# Phase 7 主动监督系统

Phase 7 将体重、饮食、训练、步数、睡眠、恢复、体检和知识问答组合成一个克制的日常执行层。系统不生成“健康总分”，不将相关性表述为因果，不以羞辱或焦虑文案推动完成。

## 数据流

```text
Celery Beat (15 min)
  └─ DailyTaskEngine ───────┐
       ├─ auto-completion         │
       ├─ ReminderEngine ────├─► PushProvider (Mock/APNs boundary)
       ├─ ProactiveCoach rules   │
       └─ HealthReportService ──┘

Flutter Dashboard ─► tasks / reports / timeline / follow-ups
                   └─► iOS local fixed reminders
```

`DailyTaskEngine` 使用 `user_id + task_date + dedup_key` 唯一约束保证 Scheduler 重试幂等。已有晨重、餐次、训练、步数、睡眠、HealthKit 同步或营养目标记录时，对应任务自动完成。过期 pending 任务转为 `expired`。

任务类型覆盖 `weigh_in` 、三餐记录、`nutrition_target`、`steps`、`workout`、`water`、`sleep`、`health_sync`、`lab_recheck` 和 `custom`。Dashboard 只显示优先级最高的 3–6 项，完整列表放在“今日任务”页。

## 提醒规则

- 已完成、跳过、过期或取消的任务不提醒。
- `gentle / standard / strict` 只改变每日上限；三种模式都受勿扰、冷却和去重约束。
- 勿扰时段支持跨夜，普通健康提醒不绕过勿扰。
- 同一任务按类型设置 2–24 小时冷却；`notification_logs.dedup_key` 再防止重复投递。
- 餐次使用用户窗口，不强制固定吃饭时刻。蛋白质、热量、步数和恢复文案只给温和建议。
- 锁屏上的体检复查始终改写为“你有一项健康复查提醒”，不包含指标数值、疾病名或完整问题。

本地通知只承担用户明确开启的晨重、训练和睡眠固定时间任务。服务器处理蛋白质不足、复查、报告等需要实时数据的复杂判断。iPhone 不被假定为长期后台存活。

## 报告与主动 AI

日/周/月报的结构指标全部由程序计算，AI 只接收计算快照并生成摘要和下一步建议。报告以周期唯一键缓存，保存规则版本、Prompt 版本、输入 Hash、Provider 和 Model；手动重生成受次数限制。数据不完整仍会生成简报。

`ProactiveCoachService` 只在明确规则命中时工作，已实现连续 3 天睡眠不足触发，同一触发每日去重，全局每日限额为 1–3。其他触发将在复用现有安全算法后增加，不用无意义问候消耗调用和注意力。

## Timeline 与复查

`HealthTimelineService` 是 Query Projection，不复制业务事实。当前投影体重、餐次、训练、PR、步数、睡眠、体检、饮食/训练调整和报告。腰围与身体照片在建立历史记录表后再进入投影；目前 Profile 只有当前腰围值，不伪造历史。

跨域页并列体重、步数、睡眠和 HbA1c 的同期变化。`CorrelationGuard` 在 UI 和 API 中明示“相关不等于因果”。

体检建议创建的 follow-up 初始为 `suggested`，只有用户确认后才会进入定时任务。用户可改期或取消。

## 隐私和用户控制

- Face ID / Touch ID 锁默认关闭，用户开启后应用从后台超过 2 分钟恢复时重新验证。Token 仍保留在 Keychain。
- JSON/CSV 导出覆盖档案、体重、饮食、训练、睡眠、步数、体检、任务、复查和设置。
- 删除所有数据要求精确输入 `DELETE MY DATA`，删除当前账号及外键级联数据，并删除私有餐食/体检文件。已生成的加密备份按运维保留策略过期，不在请求中直接改写历史归档。
