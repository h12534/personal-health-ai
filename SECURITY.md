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

