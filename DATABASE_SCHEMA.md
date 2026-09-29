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

## 完整演进清单

后续迁移按领域增加：`body_metrics, waist_logs, food_items, food_aliases, meal_logs, meal_items, meal_images, food_recognition_results, personal_food_memories, canteens, canteen_foods, diet_goals, diet_plans, exercise_library, training_plans, training_days, training_exercises, workout_sessions, workout_sets, activity_logs, step_logs, water_logs, sleep_logs, lab_reports, lab_results, body_photos, reminders, notification_logs, daily_reports, weekly_reports, monthly_reports, knowledge_documents, knowledge_chunks, ai_conversations, ai_messages, ai_memories, ai_provider_configs, ai_usage_logs, system_settings, audit_logs`。

知识库采用 `vector` 列并同时保留 `tsvector`，支持向量与关键词的混合检索；版本查询默认过滤 `active=true` 和最新 `document_version`。

