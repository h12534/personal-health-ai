# 数据库设计

## 通用约定

- 主键使用 UUID；时间为带时区 UTC。
- 可修改的业务表统一 `created_at`、`updated_at`，健康事实在需要时增加 `deleted_at`。
- 单用户不等于无权限：所有用户数据查询都必须带 `user_id`。
- PostgreSQL 不暴露公网；连接只存在于 Compose 内网。

## Phase 1 实体

### users

`id, email(unique), password_hash, is_active, is_superuser, created_at, updated_at`

### auth_sessions

`id, user_id, refresh_token_hash(unique), expires_at, revoked_at, user_agent, created_at, updated_at`

索引：`user_id`、`expires_at`。刷新时撤销旧会话并签发新会话，降低 Token 重放窗口。

### health_profiles

`id, user_id(unique), birth_date, sex, height_cm, target_weight_kg, waist_cm, body_fat_percent, resting_heart_rate, activity_level, primary_goal, training_experience, daily_exercise_minutes, school_life, available_equipment, dietary_environment, food_preferences, disliked_foods, allergies, known_health_risks, medications, doctor_advice, timezone, created_at, updated_at`

高敏感字段不进入普通日志；数据库备份必须加密保存。

### weight_logs

`id, user_id, measured_on, weight_kg, note, source, created_at, updated_at, deleted_at`

部分唯一索引：有效记录 `(user_id, measured_on)` 唯一。查询索引：`(user_id, measured_on desc)`。

## Phase 2 实体

### food_items

系统食物与自定义食物共用一表，避免复制模型。核心字段为 `id, owner_user_id(nullable), name, normalized_name, brand, category, source, source_id, data_source_name, data_source_url, is_custom, is_active, serving_description, serving_unit, serving_weight_g, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g`，以及可空的糖、钠、钾、钙、铁和时间/软删除字段。

约束：外部/种子记录按 `(source, source_id)` 唯一；自定义记录必须有 `owner_user_id`。索引覆盖 `normalized_name`、`category` 与所有者。

### food_aliases / food_favorites

- `food_aliases`：`id, food_id, alias, normalized_alias, language, created_at, updated_at`；同一食物的规范化别名唯一。
- `food_favorites`：`id, user_id, food_id, created_at, updated_at`；`(user_id, food_id)` 唯一并按用户索引。

### meal_logs

`id, user_id, meal_type, eaten_at, note, source, idempotency_key, total_calories, total_protein, total_carbs, total_fat, total_fiber, created_at, updated_at, deleted_at`

缓存总量只由 `MealService._recalculate` 在条目增、改、软删除时更新。索引为 `(user_id, eaten_at)`；`(user_id, idempotency_key)` 唯一。

### meal_items

`id, meal_id, food_id(nullable), food_name_snapshot, amount, amount_unit, weight_g, calories, protein, carbs, fat, fiber, nutrition_source, idempotency_key, created_at, updated_at, deleted_at`

营养和名称均为写入时快照，食物库后续修正不会重写历史。索引为 `(meal_id, deleted_at)`；`(meal_id, idempotency_key)` 唯一。

### nutrition_goals

`id, user_id, effective_from, effective_to, calorie_target, protein_target_g, carbs_target_g, fat_target_g, fiber_target_g, water_target_ml, source, reason, created_at, updated_at, deleted_at`

目标按生效日期查询，`(user_id, effective_from)` 唯一。创建新版本会结束此前生效版本；补录历史版本时会自动截到下一版本前一天，避免区间重叠。不把当前值塞入档案表。

## 完整演进清单

后续迁移按领域增加：`body_metrics, waist_logs, meal_images, food_recognition_results, personal_food_memories, canteens, canteen_foods, diet_plans, exercise_library, training_plans, training_days, training_exercises, workout_sessions, workout_sets, activity_logs, step_logs, water_logs, sleep_logs, lab_reports, lab_results, body_photos, reminders, notification_logs, daily_reports, weekly_reports, monthly_reports, knowledge_documents, knowledge_chunks, ai_conversations, ai_messages, ai_memories, ai_provider_configs, ai_usage_logs, system_settings, audit_logs`。

知识库采用 `vector` 列并同时保留 `tsvector`，支持向量与关键词的混合检索；版本查询默认过滤 `active=true` 和最新 `document_version`。

