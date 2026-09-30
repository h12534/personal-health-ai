# 知识导入

## 来源策略

优先 WHO、CDC、NIH/NIDDK/NHLBI、ACSM、ISSN、中国正式指南、临床指南、系统综述与 meta-analysis。`backend/app/data/knowledge_sources.json` 只保存候选 metadata 和官方链接，不提交受版权限制全文，也不会自动抓互联网。

## CLI

```bash
python -m app.scripts.ingest_knowledge path/to/file.pdf \
  --title "指南标题" \
  --source official_guideline \
  --publisher "发布机构" \
  --category blood_pressure \
  --evidence-level guideline \
  --source-url "https://..." \
  --published-at 2026-01-01 \
  --document-version 2026 \
  --document-type guideline \
  --language zh-CN
```

支持 PDF/HTML/Markdown/TXT。PDF 优先读取文本层；无可用文本层会以 `knowledge_pdf_ocr_required` 失败，等待受控 OCR pipeline，不把扫描页直接送入未知服务。

## Pipeline

1. 校验扩展名和大小，计算上传 checksum。
2. 提取并清洗文本，按标题/章节/段落建立语义边界。
3. 控制约 400–900 tokens，边界附近保留小量 overlap；超长段落安全拆分。
4. 保存文档 metadata、章节、来源、分类、content hash。
5. 按 `content_hash + embedding_model` 复用向量缓存。
6. 同内容返回 duplicate；同标题/publisher/language 的新版本创建新行并归档旧版本。
7. 原文件进入私有 StorageProvider，不提供公开 URL。

管理 API 支持列出、查看 chunks、启用/归档、重新 embedding 和软删除。更新来源由管理员手工触发；当前没有定时爬虫。
