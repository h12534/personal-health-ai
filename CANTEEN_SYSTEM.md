# 食堂系统

## 目标

食堂系统把“吃什么”落到用户真实可获得的食物，而不是生成不存在的标准餐。数据层级为：

```text
Canteen (用户所有)
  └─ CanteenStall
       └─ CanteenDish (单份营养快照、标签、可用状态)
```

每次读取档口或菜品都会联表校验食堂的 `user_id`。删除采用停用状态，历史餐食不被级联改写。

## 菜品信息

菜品保存名称、份量描述、热量、蛋白质、碳水、脂肪、纤维、收藏状态、来源和标签。数据可手动维护，也可通过 `learn-from-meal` 将 Phase 3 已由用户确认的拍照餐食关联到档口；未经确认的视觉结果不会成为正式菜品。

## 匹配算法

推荐输入来自 `NextMealPlanner` 的热量/蛋白范围：

```text
score = calorie_fit × 0.55 + protein_fit × 0.45
```

`calorie_fit` 表示离范围中心的相对距离，`protein_fit` 表示蛋白质目标满足程度。分数只用于内部候选排序，Flutter 不显示数字分；结果返回人类可读原因，不称为健康评分，也不把食物道德化。算法会过滤已停用食堂、档口和菜品。

## API 与 Flutter

- `GET/POST/PATCH /api/v1/canteens`（GET 返回食堂 → 活跃档口 → 可用菜品树）
- `POST /api/v1/canteens/{canteen_id}/stalls`，`PATCH /api/v1/canteens/stalls/{stall_id}`
- `POST /api/v1/canteens/stalls/{stall_id}/dishes`，`PATCH /api/v1/canteens/dishes/{dish_id}`
- `POST /api/v1/canteens/stalls/{stall_id}/learn-from-meal/{meal_id}`
- `GET /api/v1/canteens/recommendations?canteen_id=`
- `DELETE` 食堂、档口、菜品对应资源

Flutter 从饮食页“下一餐”卡片或 AI Tab 快捷入口进入学校饮食页，可维护食堂、档口、菜品和收藏，并显示热量、蛋白质与推荐原因。页面同时列出 Saved Meal，点击“一键记录”会创建带新 Meal ID 的餐次。没有数据时显示可行动的空状态。
