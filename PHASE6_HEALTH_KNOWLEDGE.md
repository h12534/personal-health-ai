# Phase 6：健康知识、体检与健康 AI

Phase 6 建立 `Personal Health Knowledge & Clinical Context Layer`，把经过筛选的知识来源、用户已确认的体检指标、长期趋势、最小必要个人上下文和独立安全规则组合起来。模型只负责解释；诊断、单位换算、参考范围判断、趋势和安全短路均由程序负责。

## 已交付

- PDF/HTML/Markdown/TXT 文档导入、语义分块、checksum 幂等、内容哈希缓存和版本归档。
- PostgreSQL `pgvector` + `tsvector` 混合召回、证据等级加权和 deterministic rerank；SQLite 提供可复现测试 fallback。
- 27 个要求中的知识分类、8 个证据等级和 vetted source metadata 清单；仓库不提交受版权限制全文。
- JPEG/PNG/WebP/PDF 体检上传、多页拆分、Mock/OpenAI-compatible OCR、可编辑 Draft 和显式确认。
- 21 个常见指标标准名/别名、程序化单位转换、报告原始参考范围、历史趋势和复查建议审批。
- `/api/v1/ai/health/chat`：Intent → Safety → minimal context → rewrite → retrieval → rerank → answer → citations。
- Flutter 健康页：报告、趋势、知识检索、引用卡片和健康 AI；Drift v4 离线缓存已确认报告与趋势。
- iOS 原生 Files PDF picker，立即读取用户选择的临时副本并释放 security-scoped access。

## 不做

不自动诊断、不远程问诊、不修改处方、不分析医学影像/皮肤照片、不自动全网搜索、不建立疾病预测分数。任何 OCR 值在用户确认前都不是正式健康数据；复查提醒只生成建议，必须由用户接受。

## 运行顺序

```bash
cd backend
alembic upgrade head
python -m app.scripts.seed_lab_tests
python -m app.scripts.ingest_knowledge ./document.pdf \
  --title "..." --source official --publisher "..." \
  --category blood_glucose --evidence-level guideline
```

默认 Embedding、OCR、Health Answer 均为 Mock，不需要付费 Key。真实 Provider 配置见 `.env.example`；远程 OCR 还要求每次上传显式授权。

## 验收边界

本地 SQLite 单元/场景测试验证业务闭环；`tests_postgres/test_phase6_postgres.py` 只在真实 PostgreSQL + pgvector 上运行。iOS 原生编译只能由 macOS CI/Xcode 证明，Windows 上的 `flutter analyze/test` 不等同于 iOS build 通过。
