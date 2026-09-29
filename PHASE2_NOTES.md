# Phase 2 饮食与营养说明

## 范围

Phase 2 建立确定性的营养数据底座，不包含图片识别、OCR、RAG、自动 TDEE 学习或 AI 饮食建议。自定义食物合并在 `food_items`，以 `owner_user_id + is_custom + source=user` 区分。

## 食物数据

`backend/app/data/seed_foods.json` 当前包含 42 项常见食物及中英文/常用别名，使用稳定 `source_id`。数值采用公开营养数据库的常见通用值并作适合手工记录的合理舍入，数据源字段指向 USDA FoodData Central；它们不是品牌标签或医疗级精密测量。

导入命令：

```powershell
Set-Location backend
python -m app.scripts.seed_foods
```

脚本按 `(source, source_id)` upsert：首次插入，再次执行更新现有行并同步别名，不生成重复数据。

## 份量与营养计算

所有服务端计算经 `PortionConversionService` 和 `NutritionCalculator`：

```text
weight_g = amount                         unit = g
weight_g = amount × serving_weight_g      unit = 食物配置的 ml/piece/bowl/cup/serving/custom
nutrient = nutrient_per_100g × weight_g / 100
```

代码不根据“鸡蛋”等名称写特例。可用单位由食物的 `serving_unit` 和 `serving_weight_g` 配置。服务端使用 `Decimal` 并统一量化到 0.001；UI 将 kcal 显示为整数、宏量营养显示为一位小数。条目保存名称、换算重量、营养值和数据来源快照。

## 聚合与目标

`DailyNutritionService` 使用用户档案时区构造当地日期的 UTC 边界，一次读取日期范围内餐次，再按早餐/午餐/晚餐/加餐聚合。区间接口包含没有记录的日期，最长 366 天。

`NutritionGoalService` 保存带 `effective_from/effective_to` 的历史版本。程序建议只作为保守初值，结合最近体重、身高、年龄、性别和活动水平；热量设有性别相关下限和 3500 kcal 上限。写接口硬校验 1200–10000 kcal，拒绝 1000 kcal 等危险输入。

## 离线同步

Flutter 使用手写 Drift 数据库层（不需要代码生成），表包括：

- `local_meals`
- `local_meal_items`
- `sync_outbox`
- `food_cache`

新增餐食在一个 SQLite 事务内写本地记录和 Outbox。本地 UUID 同时构成稳定 `Idempotency-Key`。补传严格先餐次、后条目；餐次成功后回填 `server_id`，条目再使用服务器餐次 ID。网络错误只把操作标记为 `failed` 并保存截断错误摘要，不丢弃本地记录；启动、打开饮食页和网络恢复都会重试。

当前离线范围是餐次/条目创建及尚未同步条目的本地修改/取消。已同步条目的编辑、删除需要在线调用服务端；后续如扩大多设备冲突处理，再引入版本号和冲突界面，不提前实现通用 CRDT。

## Dashboard 规则

Dashboard 从当天餐次缓存读取热量、蛋白质、碳水、脂肪、纤维，并读取指定日期生效的营养目标。下一步建议按固定优先级判断：晨重缺失、午餐缺失、热量达到目标、傍晚蛋白质进度不足、体重趋势过快或继续积累趋势。刷新不调用 AI。

## 验证入口

```powershell
Set-Location backend
alembic upgrade head
alembic check
python -m app.scripts.seed_foods
pytest -q
ruff check .
ruff format --check .
mypy --no-incremental app
```

Flutter：

```bash
cd mobile
flutter create --platforms=android,ios --org dev.personalhealthos .
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

本机没有 Flutter SDK 时，只可用官方 Dart SDK完成格式和语法解析；不得把这报告成 Flutter analyze/test 通过。仓库 CI 会使用稳定版 Flutter 执行完整移动端门禁。
