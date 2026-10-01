# 安全与隐私

## 威胁模型

主要资产为凭据、健康档案、体检结果、身体照片、餐食图片和 AI 对话。主要风险包括服务器暴露、Token 泄露、对象越权、恶意上传、日志泄密、Prompt Injection、备份丢失。

## 控制措施

- Argon2id 密码 Hash；短时 Access Token；Refresh Token 只保存 SHA-256 摘要并轮换。
- 每个资源查询强制 `user_id`；UUID 不能替代授权。
- Nginx HTTPS 终止、限流、请求体上限和安全响应头。
- PostgreSQL/Redis 只在内部网络，不映射宿主端口；生产环境使用独立强密码。
- 文件使用 UUID 对象名、MIME/魔数/大小校验、私有权限与短期签名下载 URL。
- ORM 参数化查询；输出转义；CORS 精确白名单。
- 日志仅记录事件 ID、用户伪标识和统计量，不记录密码、Token、API Key、完整健康正文。
- AI 检索文档视为不可信数据；系统指令与证据分离，工具采用显式 allowlist。
- Secret 只通过环境/Secret Manager 注入；`.env` 永不提交。

## 备份

每日 PostgreSQL dump、图片与知识库增量备份；保留最近 7 个日备份、4 个周备份和关键月备份。备份加密后复制到不同故障域。每季度执行恢复演练；详见 `BACKUP_RESTORE.md`。

## 医疗边界

系统提供一般健康信息、趋势分析和行为支持，不给出诊断，不代替医生。明显异常或急症提示专业医疗帮助。算法调整需要足够记录完整度且遵循最低安全热量/减重速度约束。

## Phase 3 图片与视觉 Provider

- 上传只接受 JPEG/PNG/WEBP、最大 10 MB，并交叉验证 MIME、魔数、Pillow 解码格式、宽高和总像素，防止伪装文件与 decompression bomb。
- 服务端方向校正后统一重新编码 JPEG，不复制 EXIF/GPS；存储键为 `meal-analysis/YYYY/MM/UUID.jpg`，不使用客户端文件名。
- 图片位于私有 `StorageProvider`，API 不返回对象路径；默认 30 天后由 Celery Beat 删除。保留期设为 0 时，草稿期仍可重试，确认后立即删除原图；用户也可选择长期保留。删除未确认草稿会立即删除图片。
- 远程 Provider 默认无权限。用户必须显式开启 `allow_third_party_vision`；关闭后远程调用返回 403。API Key 仅从环境读取。
- Provider JSON 经过严格 Schema 和长度限制，不进入 HTML、SQL 或文件路径。原始响应默认 7 天后清除，不返回客户端，也不写普通日志。
- AI 结果不会直接写正式健康记录；用户必须确认。未匹配食物会阻止确认，失败事务不会留下半餐。
- 移动端离线图片保存在应用私有文档目录；确认、取消/隐私清理时删除。本地任务不保存 Provider Key。

## Phase 4 私人饮食教练

- BMR、TDEE、营养目标、体重趋势、下一餐区间与调整幅度全部由版本化规则计算；语言模型只能解释结构化结果，不能自行生成或覆盖健康数值。
- Diet Coach 按 Intent 构造最小必要上下文，不发送完整病历、完整聊天历史或无关健康数据。远程 Provider 凭据只从环境读取。
- 模型输出必须通过结构化 Schema 与响应校验；`suggested_actions` 仅是客户端操作入口，模型没有数据库写权限。
- 饮食目标调整默认关闭自动生效。每次建议保存输入快照哈希、规则版本、Prompt 版本、模型和指标快照；只有用户通过正式 API 确认后才创建新的有效目标。
- 调整要求足够的体重和饮食记录，并受最小热量、营养下限、100–200 kcal 小幅调整和 7–14 天冷却期约束；数据不足时保持当前计划。
- 明确拦截补偿性禁食、催吐、极端节食、脱水、减肥药滥用和过量运动补偿。胸痛、呼吸困难、意识异常或严重低血糖表现会终止普通饮食建议并提示立即寻求专业帮助。
- Personal Dietary Memory 只保存结构化、可查看和可删除的长期偏好；短期表达不会自动升级为长期记忆，系统推断使用较低置信度。
- 食堂、菜品、饥饿记录、Saved Meal、对话和建议均按 `user_id` 隔离；删除、编辑、确认和快速记录仍走正式鉴权 API。
- AI 使用量继续写入 `ai_usage_logs`，但普通日志不记录完整对话、完整 Coach Context、API Key 或可识别健康正文。

## Phase 6 体检与 RAG

- 体检上传交叉验证 MIME、魔数和实际解码；PDF 验证签名并逐页处理。原文件只进入私有 StorageProvider，API/日志不返回对象路径或正文。
- 第三方 OCR 默认关闭；每次远程处理必须显式授权。`retain_original=false` 会在确认后删除原文件，删除报告也会删除原文件并软删除关联结果。
- OCR 只写 Draft，用户确认前不进入正式结果、趋势或 AI context。简单范围不得自动产生 `critical`。
- Knowledge PDF/HTML/Markdown/TXT 只由受信管理流程导入；文档正文仍视为 untrusted evidence，不能覆盖系统指令或触发工具。
- 向量/全文 SQL 使用绑定参数；默认检索排除 archived、inactive 和 soft-deleted 版本。
- Health AI 危急症状在网络模型前短路；诊断和停药请求强制医疗边界。普通日志不写完整问题、回答、OCR 或个人 context。
- iOS Files picker 使用系统文档选择器和临时安全作用域访问，不持久化外部 URL/bookmark；本地只缓存结构化报告与趋势。

## Phase 7 监督与发布

- 任务、报告和通知服务全部按 `user_id` 查询；幂等键与数据库唯一约束阻止 Celery 重试导致的重复推送和报告。
- `notification_logs` 不保存锁屏全文。复查类 payload 强制改写为不含指标、数值和疾病名的通用文案。
- 生物识别默认关闭，验证在设备安全硬件/系统层完成。Token 仍使用 Keychain，不把面容/指纹模板或验证秘密传到服务器。
- 删除全部数据要求精确确认语，并删除私有餐食/体检文件。已有加密备份依保留策略到期，权限和删除语义需写入公开隐私政策。
- 生产启动校验长随机 Secret 和 HTTPS `PUBLIC_BASE_URL`。PostgreSQL/Redis 仅内网，TLS 在 Nginx/托管代理终止，iOS 不提交全局 ATS 例外。
- APNs `.p8`、AI Key、生产 `.env`、数据库 dump 和真实 Provider 评测样本都不得进入 Git。

