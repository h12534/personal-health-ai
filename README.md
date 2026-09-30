# Personal Health OS

一个面向个人长期使用的私人健康操作系统。项目从稳健减脂、保留肌肉和建立力量训练习惯出发，逐步连接身体数据、现实饮食、训练、活动、睡眠、体检、知识库、提醒和 AI 教练。

当前仓库已完成 Phase 0–4。除认证、档案、体重、手工/照片记餐外，现已具备程序化目标、7/14/28 天趋势、依从性、个人 TDEE、下一餐、食堂/常用餐、调整审批，以及带独立安全层的 Flutter AI 饮食教练。

移动端以 Apple iPhone / iOS 16+ 为首要交付目标；Android 作为次要兼容平台保留。后端继续部署到 Linux，Windows 可进行后端与 Flutter 静态开发，但 iOS 原生构建必须在 macOS + Xcode 上完成。

## 核心原则

- 计划服从现实生活：学校食堂、外卖与便利店都属于正常输入。
- 不根据单日体重改变热量；策略依据 7 日均值和连续趋势。
- 医疗安全独立于普通 AI Prompt；AI 不进行诊断或擅自调整药物。
- 确定性计算不用大模型，模型只做理解、视觉、总结和知识问答。
- 健康数据私有、最小化访问，敏感正文不进入普通日志。

## 架构

```text
Flutter ─HTTPS─► Nginx ─► FastAPI ─► PostgreSQL + pgvector
                              ├────► Redis / Celery
                              ├────► private StorageProvider
                              └────► AI Gateway / RAG
```

后端采用模块化单体。业务规则位于 Service，数据库查询位于 Repository，外部模型和文件系统位于 Provider；详情见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 目录

```text
backend/                 FastAPI、SQLAlchemy、Alembic、Celery、测试
mobile/                  Flutter 应用源码和 Widget 测试
deploy/nginx/            反向代理配置
scripts/                 运维脚本
storage/                 本地私有文件/备份挂载占位目录
.github/workflows/       后端与移动端 CI
```

设计基线：

- [PROJECT_PLAN.md](PROJECT_PLAN.md)
- [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md)
- [API_SPEC.md](API_SPEC.md)
- [AI_DESIGN.md](AI_DESIGN.md)
- [SECURITY.md](SECURITY.md)
- [ROADMAP.md](ROADMAP.md)
- [BACKUP_RESTORE.md](BACKUP_RESTORE.md)
- [PHASE2_NOTES.md](PHASE2_NOTES.md)
- [PHASE3_MEAL_VISION.md](PHASE3_MEAL_VISION.md)
- [REAL_VISION_TEST.md](REAL_VISION_TEST.md)
- [PHASE4_DIET_COACH.md](PHASE4_DIET_COACH.md)
- [DIET_ALGORITHM.md](DIET_ALGORITHM.md)
- [AI_COACH_CONTEXT.md](AI_COACH_CONTEXT.md)
- [CANTEEN_SYSTEM.md](CANTEEN_SYSTEM.md)
- [REAL_AI_COACH_TEST.md](REAL_AI_COACH_TEST.md)
- [IOS_READINESS_AUDIT.md](IOS_READINESS_AUDIT.md)
- [IOS_PLUGIN_AUDIT.md](IOS_PLUGIN_AUDIT.md)
- [IOS_BUILD_SETUP.md](IOS_BUILD_SETUP.md)
- [PRIVACY.md](PRIVACY.md)

## 本地后端

要求 Python 3.12+。

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".\backend[dev]"
Set-Location backend
$env:DATABASE_URL = "sqlite+aiosqlite:///./health_os.db"
alembic upgrade head
python -m app.scripts.seed_foods
python -m app.scripts.seed_exercises
uvicorn app.main:app --reload
```

打开 `http://127.0.0.1:8000/docs`。首次调用 `/api/v1/auth/register` 创建唯一账户，之后该实例会关闭第二个账户的注册。

质量检查：

```powershell
Set-Location backend
pytest -q
ruff check .
ruff format --check .
mypy --no-incremental app
```

Phase 3 默认使用 `VISION_PROVIDER=mock`，不需要 API Key。上传后结果仍是草稿，必须调用确认接口才会创建正式餐食。要启用远程兼容 Provider，设置 `VISION_PROVIDER=openai_compatible`、`VISION_BASE_URL`、`VISION_API_KEY`、`VISION_MODEL`，并由用户在“我的”页明确同意第三方图片分析。

Phase 4 默认使用 `COACH_PROVIDER=mock`。热量、蛋白质、趋势、TDEE、下一餐和调整建议始终由后端规则服务计算；远程模型只负责表达，且输出必须通过 strict schema。真实 Provider 配置见 `REAL_AI_COACH_TEST.md`。

仓库已提交并维护 iOS Runner，不再在日常流程中重建：

~~~bash
cd mobile
flutter pub get
export IOS_BUNDLE_ID=com.personal.healthcoach
export APP_DISPLAY_NAME='私人健康'
dart run tool/configure_ios.dart
flutter run \
  --dart-define=APP_ENV=dev \
  --dart-define=API_BASE_URL=https://dev-api.example.com/api/v1
~~~

iOS 相机/相册用途说明、iOS 16 最低版本和可配置 Bundle ID 已进入版本控制。客户端把图片限制到最长边 2048、JPEG 质量 86、移除 EXIF；离线任务和本地图片保存在 Drift/应用沙盒与 Application Support，用户可联网后继续或改用手工记录。

## Docker Compose

要求 Docker Engine/Compose。先创建环境文件并更换密码与 Secret：

```bash
cp .env.example .env
# 至少修改 APP_SECRET_KEY 与 POSTGRES_PASSWORD
docker compose up --build -d
docker compose ps
curl http://localhost:8080/health
```

Compose 包含 `backend`、`postgres`（pgvector）、`redis`、`worker` 和 `nginx`。数据库与 Redis 不映射公网端口。当前 Nginx 监听本地 HTTP 8080；生产环境必须在域名确定后配置 TLS 证书和 443。

迁移：

```bash
docker compose exec backend alembic upgrade head
```

## Flutter

要求 Flutter 3.47.5 stable。iOS Runner 已提交且是主移动端构建目标：

~~~bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign \
  --dart-define=APP_ENV=staging \
  --dart-define=API_BASE_URL=https://staging-api.example.com/api/v1
~~~

最后一条命令只能在 macOS + Xcode 执行。iPhone 不能通过 `localhost` 访问开发 Mac；应使用设备可达的 HTTPS 主机。开发环境可显式使用局域网 HTTP，但仓库不提交全局 ATS 放行；staging/prod 强制 HTTPS。完整签名、真机和 TestFlight 步骤见 `IOS_BUILD_SETUP.md`。

Android 兼容 Runner 仍由 CI 临时生成：

~~~bash
flutter create --platforms=android --org com.personal .
dart run tool/configure_platforms.dart
flutter build apk --debug
~~~

## 环境变量

关键变量见 `.env.example`：

- `APP_SECRET_KEY`：JWT 签名 Secret，生产环境至少 32 个随机字符。
- `DATABASE_URL`、`REDIS_URL`：内部服务连接。
- `CORS_ORIGINS`：精确白名单 JSON 数组。
- `UPLOAD_DIR`、`MAX_UPLOAD_BYTES`：私有上传位置和大小上限。
- `AI_PROVIDER`、`AI_BASE_URL`、`AI_API_KEY`、各模型名：AI Gateway 配置。默认 `disabled`，无 Key 也可运行 Phase 1。
- Flutter 编译参数 `APP_ENV`（dev/staging/prod）与 `API_BASE_URL`：iPhone API 环境。
- `IOS_BUNDLE_ID`、`APP_DISPLAY_NAME`：通过 `mobile/tool/configure_ios.dart` 生成本地、忽略的 Xcode 配置。

禁止把 `.env`、API Key、真实 Token 或数据库密码提交 Git。

## AI 与知识库

当前提供 `LLMProvider`、`VisionProvider`、`CoachProvider`、`EmbeddingProvider` 协议。Phase 4 的 Coach Orchestrator 已接入意图、安全、最小上下文、Mock/远程 Provider；Phase 2–4 的数值算法均不调用模型。

知识导入将在 Phase 6 提供命令；来源以 WHO、CDC、NIH/NIDDK、ACSM、正式临床指南与高质量系统综述为主，并保存版本、证据等级和 URL。

## 备份与恢复

生产环境需要执行 `scripts/backup.sh`，并把加密备份复制到另一故障域。默认策略为 7 个日备份、4 个周备份和关键月备份。恢复前停止写入/Worker，在隔离环境验证后再切换，详见 [BACKUP_RESTORE.md](BACKUP_RESTORE.md)。

## 当前限制

- 尚未实现训练、提醒、RAG、报告和体检 OCR；这些仍按路线图后续交付。
- 移动端当前离线 Outbox 覆盖餐次和餐次条目的创建；服务端已支持餐次/条目的完整 CRUD。
- Windows 可运行 Flutter analyze/test，但不能证明 iOS 原生构建；主移动 CI 使用 macOS 执行 `flutter build ios --no-codesign`，真机和签名仍需 Apple 环境。
- HTTPS 证书、域名、Push 凭据和真实 AI Key 都属于部署阶段配置，不在仓库中提供默认秘密。

## 常见问题

**为什么 Dashboard 的营养数字是 0？** 只有当天尚未记录餐食时才为 0。Phase 2 从餐次快照聚合真实数据，不用 AI 做加法。

**为什么一天体重上涨不触发减热量？** 水分、盐、碳水、排便、训练炎症和睡眠都会造成短期波动；系统至少看 7–14 天趋势。

**AI 未配置能否使用？** 可以。认证、档案、体重、趋势和规则型 Dashboard 不依赖模型。

## Phase 5：训练与 Apple Health

训练 Tab 已提供今日训练、计划、历史、动作库、进度、离线组记录、本地休息计时和 AI 私教。Apple Health 按步数、睡眠、静息心率与训练分别授权；无数据不会被显示为 0。完整说明见 PHASE5_TRAINING.md、HEALTHKIT_DESIGN.md 与 HEALTHKIT_REAL_DEVICE_TEST.md。
