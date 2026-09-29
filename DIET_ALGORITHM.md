# 饮食算法

所有核心数值均由确定性代码计算，版本入口位于 `backend/app/services/`。LLM 只能解释结果。

## 每日能量目标

Mifflin–St Jeor：

```text
BMR = 10 × weight_kg + 6.25 × height_cm - 5 × age + sex_offset
sex_offset: male=5, female=-161, unspecified=-78
TDEE_formula = BMR × activity_factor
```

活动系数为 sedentary 1.20、light 1.35、moderate 1.50、high 1.70，未知时 1.30。目标阶段：

| 阶段 | TDEE 调整 |
|---|---:|
| fat_loss | -15% |
| maintenance | 0% |
| recomposition | -5% |
| muscle_gain | +8% |

`NutritionSafetyPolicy` 把能量缺口限制在最多 20%，并应用性别相关保守下限（男性 1500、女性 1200、未指定 1350 kcal）。最终目标按 25 kcal 取整。缺档案/身高/体重时维持旧接口的低置信度回退（100 kg、176 cm、21 岁），并在 `safety_notes` 明确提示补资料。

## 蛋白质与宏量营养

当当前体重大于目标体重 120% 时，蛋白质计算使用：

```text
adjusted_weight = target_weight + 0.25 × (current_weight - target_weight)
```

否则使用当前体重。系数按阶段为 1.4–1.8 g/kg，结果限制在 75–220 g。脂肪使用调整体重的 0.7 g/kg 且不少于 40 g，剩余能量分配给碳水。纤维默认 25 g，饮水默认 2500 ml。这些是产品初始策略，不替代临床营养处方。

## 体重趋势与平台期

- 当前 7 日与前 7 日分别取实际存在记录的均值。
- 14/28 日变化比较窗口起止各最多 7 天的均值，降低单日波动影响。
- 周变化率优先使用 14 日变化除以 2。
- 稳定度使用近 14 日总体标准差。
- 方向阈值：7 日差绝对值小于 0.15 kg 视为稳定。

平台期只在以下条件全部满足时判定：

1. 近 14 天至少 10 次体重记录；
2. 组合依从性至少 80%；
3. 有足够的 28 天跨度；
4. 28 天首尾平滑差绝对值小于 0.35 kg。

数据不足时返回 `plateau=false, plateau_eligible=false`，不会因为几天不动就减热量。

## 饮食依从性

完整日定义为至少两餐。热量命中为目标的 90%–110%，蛋白质命中为至少目标的 90%。

```text
overall = logging_rate × 0.4
        + calorie_adherence_rate × 0.3
        + protein_adherence_rate × 0.3
```

没有完整记录的日子不会被误判为“吃得少”，而是降低记录完整度。

## Observed / Blended TDEE

观察窗口为 28 天。只有至少 21 个完整饮食日和至少 8 次体重记录时才计算：

```text
observed_tdee = average_intake - weight_change_kg × 7700 / span_days
```

用窗口两端最多 4 次体重均值代替单次值。观察值限制在公式值的 75%–125%，置信度随完整度增加、最高 0.85：

```text
blended = formula × (1-confidence) + observed × confidence
```

数据不足时 `observed_tdee=null, confidence=0, blended=formula`。

## 下一餐与调整

下一餐根据当地时段和已记录餐次选择，热量以全天目标的 15%–35% 为中心并结合剩余额度，蛋白质给出范围。即使当日超过目标，也会返回正常的小餐范围和“不跳餐、不惩罚”的策略。

调整建议仅在趋势可判断且依从性充足时生成：减脂平台期建议 -150 kcal；周下降超过体重 1% 时建议 +150 kcal。接受后从次日建立新 `nutrition_goal`，保留旧版本；拒绝不改变目标。默认冷却 14 天。
