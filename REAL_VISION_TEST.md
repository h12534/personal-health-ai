# 真实 Vision API 与授权图片测试

默认测试不调用付费服务。只有测试人员明确拥有 Provider 权限、API Key 和图片使用授权时，才执行本指南。

## 1. 准备环境

在未提交的 `.env` 中设置：

```dotenv
VISION_PROVIDER=openai_compatible
VISION_BASE_URL=https://your-compatible-endpoint.example/v1
VISION_API_KEY=replace-locally
VISION_MODEL=your-vision-model
VISION_TIMEOUT_SECONDS=45
VISION_MAX_ATTEMPTS=2
VISION_ASYNC_ENABLED=false
```

不要把 Key 写入命令历史、测试 fixture、日志、截图或 Git。测试账户还必须在“我的 → 图片隐私设置”中明确开启第三方视觉分析。

## 2. 授权图片集

在本地建立 `backend/tests/fixtures/images/`。该目录只放：

- 自己拍摄且明确同意用于测试的图片；
- 许可证允许测试使用的公开图片；
- 生成的合成图片。

不得提交用户真实隐私照片。建议准备 20–30 张，覆盖米饭套餐、盖浇饭、面条、饺子、鸡腿饭、炒菜、多格食堂餐盘、汤、水果、牛奶、包装食品、模糊图和非食物图。

为每张图片维护本地、不提交的人工标注：可见食物、称重值（若有）、合理重量范围、明显烹饪方式和是否可能用油。

## 3. 启动并测试

```powershell
Set-Location backend
alembic upgrade head
python -m app.scripts.seed_foods
uvicorn app.main:app --reload
```

通过 Flutter App 或 Swagger：

1. 上传一张授权图片到 `POST /api/v1/meals/analyze-image`。
2. 记录 Provider、模型、Prompt 版本、状态、延迟和警告。
3. 核对食物拆分、匹配、重量中心/区间和隐藏用油。
4. 修改草稿后确认，检查正式餐食、Dashboard 与每日营养。
5. 对非食物图确认返回 `no_food_detected`，不得硬猜。

## 4. 记录指标

第一版不设虚假的高准确率门槛。按图片记录：

- food detection precision / recall（可见食物层面）
- 匹配正确率与人工替换次数
- 有实称数据时的重量绝对误差和相对误差
- 用户确认营养相对中心估算的偏差
- 合理区间是否覆盖实称值
- 隐藏油误报/漏报
- Provider 延迟、失败率、Token 和实际账单成本

模型或 Prompt 变化时保留版本并重复同一授权集。任何结果都必须继续显示为草稿，不能因为离线评测表现较好而跳过用户确认。
