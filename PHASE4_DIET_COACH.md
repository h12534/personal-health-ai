# Phase 4：私人 AI 饮食教练与个性化饮食计划

Phase 4 已在 `feature/phase4-diet-coach` 上完成首个可运行闭环。它复用 Phase 1 的档案/体重和 Phase 2–3 的营养/餐食数据，不重建旧模块。

## 交付范围

- 程序化每日目标：Mifflin–St Jeor BMR、活动系数、目标阶段、最大 20% 缺口、热量下限、蛋白质策略。
- 体重趋势：7 日均值、前 7 日均值、14/28 日变化、周变化率、稳定度和保守平台期判断。
- 饮食依从性：记录完整度、热量目标命中、蛋白质目标命中和组合分数。
- 个体能量模型：28 日摄入/体重趋势估算 observed TDEE；不足 21 个完整日时回退公式值。
- 下一餐规划：根据今日剩余目标和当前餐次生成范围；超过目标时不跳餐、不惩罚。
- 饮食调整：规则层只生成 ±150 kcal 的待审批建议；用户接受后从次日建立新目标版本，可拒绝，受冷却期约束。
- 食堂：个人食堂、档口、菜品和基于下一餐范围的可解释排序。
- 常用餐：保存营养快照，一键幂等写入正式餐食。
- 饥饿记录与个人饮食记忆。
- AI 教练：意图分类、最小上下文、安全层、规则服务、Mock/远程 Provider、结构化输出校验、对话审计。
- Flutter：真实 AI Tab、快捷问题、受控 Action、饥饿记录、周趋势/调整审批、下一餐卡片、Saved Meal 一键记录，以及食堂 → 档口 → 菜品维护/收藏/推荐页。

## 核心边界

```text
message
  → IntentClassifier
  → CoachSafetyService
  → CoachContextBuilder
  → deterministic services / memory
  → CoachProvider (仅表达)
  → CoachGeneratedReply validation
  → suggested actions (不执行业务写入)
```

AI 不计算 BMR、TDEE、营养合计、平台期或目标调整，也不直接执行记录餐食、修改目标等动作。聊天记录可以保存用于会话连续性；响应中的 `suggested_actions` 由客户端映射到 allowlist，并通过正式业务 API 执行，模型本身没有写库权限。

急症、医疗诊断/用药以及暴食补偿请求由确定性安全层直接处理，不发送给普通教练 Provider。远程 Provider 不可用时，核心目标、趋势、下一餐、食堂和审批流程仍可用。

## 数据迁移

`0004_phase4_diet_coach` 增加：

- `health_profiles.current_goal_phase`
- `health_profiles.allow_auto_diet_adjustment`
- `health_profiles.adjustment_cooldown_days`
- `diet_adjustments`
- `hunger_logs`
- `canteens / canteen_stalls / canteen_dishes`
- `personal_dietary_memories`
- `personal_energy_models`
- `saved_meals / saved_meal_items`
- `coach_conversations / coach_messages`

结构化列在 PostgreSQL 使用 JSONB、SQLite 测试使用 JSON variant。迁移已通过 `upgrade head → downgrade base → upgrade head` 和 `alembic check`。

## 默认运行方式

`COACH_PROVIDER=mock`，不需要 Key。真实兼容 Provider 的人工验证见 [REAL_AI_COACH_TEST.md](REAL_AI_COACH_TEST.md)。算法说明见 [DIET_ALGORITHM.md](DIET_ALGORITHM.md)，上下文与安全设计见 [AI_COACH_CONTEXT.md](AI_COACH_CONTEXT.md)，食堂说明见 [CANTEEN_SYSTEM.md](CANTEEN_SYSTEM.md)。

## 验收命令

```powershell
.\.venv\Scripts\python.exe -m ruff check backend/app backend/tests
.\.venv\Scripts\python.exe -m mypy backend/app
.\.venv\Scripts\python.exe -m pytest backend/tests -q

Set-Location mobile
flutter analyze
flutter test
flutter build apk --debug
```

本机已使用 Android SDK 36、Build Tools 36、JDK 17 完成 `flutter doctor`、`flutter analyze`、9 个 Flutter 测试和 debug APK 构建。后端 48 个测试、Ruff、严格 mypy，以及 Alembic 完整升降级/一致性检查均已通过。PostgreSQL 16 集成测试与 APK 构建仍保留在仓库 CI；本机没有 Docker/PostgreSQL 服务，且仓库没有远程地址，因此无法伪造远端 CI 结果。
