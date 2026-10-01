# 备份与恢复

`scripts/backup.sh`/生产 Cron 将 PostgreSQL custom-format dump 和完整私有数据目录归档写入不公开的备份目录，生成 SHA-256 校验和。生产环境应把归档加密并复制到另一台主机或对象存储。

恢复前先停止写入和 Worker，验证归档校验和，在隔离环境恢复 PostgreSQL，再恢复文件目录，最后执行迁移和冒烟测试。不要直接覆盖唯一的生产副本；先创建当前状态快照。保留策略默认为 7 daily / 4 weekly / 3 monthly，可通过 `BACKUP_RETENTION_*` 调整。

Phase 6 后备份范围必须包含 knowledge metadata/chunks/ingestion jobs、lab dictionary/reports/results/OCR 状态、Health AI conversation metadata 和 `UPLOAD_DIR` 下的 knowledge/lab private objects。恢复演练需验证 vector extension/HNSW/FTS 索引可重建、文档 active/archive 版本正确、报告原文件与数据库 object key 一致，并抽样验证已确认 Lab Trend；不得把解密后的体检文件复制到普通日志或共享目录。

Phase 7 还必须验证 `daily_tasks`、`notification_logs`、`health_reports`、`health_followups` 和用户删除语义。自动 PostgreSQL 演练、安全目标库命名和执行记录见 [RESTORE_TEST.md](RESTORE_TEST.md)。

