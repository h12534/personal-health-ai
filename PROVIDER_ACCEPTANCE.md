# 真实 Provider 验收框架

验收数据必须取得所有者授权并去除不必要身份信息。样本、Provider 原始响应和评测输出不提交到仓库；仓库只保留无敏感内容的 manifest/schema 和聚合结果。

| Provider | 准确度 | 延迟 | 费用 | 错误率 | 隐私门禁 |
|---|---|---|---|---|---|
| LLM Coach/Health Answer | 结构 Schema、引用一致、安全拦截、不重算规则数值 | p50/p95 | 每请求/每月预估 | timeout/invalid/refusal | 数据区域、保留、训练用途、DPA |
| Vision | 食物识别、份量误差、最终热量误差、修改次数 | upload 到 Draft p50/p95 | 每图 | timeout/invalid/no-food | 图像保留、数据训练、地域 |
| Embedding/RAG | recall@k、来源召回、引用正确性、安全性 | retrieval/end-to-end p50/p95 | 导入+查询 | empty/timeout/dimension | 文档传输与保留 |
| OCR | 字段、数值、单位、参考范围准确率 | 每页/每报告 p50/p95 | 每页 | page/field/timeout | 体检原文件处理和删除 |

## Vision 集

`backend/tests/provider_eval/vision_manifest.csv` 预留 25 个样本位，覆盖家常菜、学校食堂、外卖、便利店、汤/混合菜和低光/遮挡场景。实际图片与授权证据未由项目所有者提供，因此当前行状态是 `awaiting_authorized_sample`，不伪造授权或准确率。每行必须填写授权引用、标准食物、标准份量/热量和存储路径后才允许运行。

报告最少输出：Top-1 食物正确率、份量 MAE/MAPE、确认后热量 MAE/MAPE、每餐用户修改次数、p50/p95 时延、失败率和每图成本。

## RAG 集

固定问题集位于 `backend/tests/rag_eval/cases.json`。切换真实 Embedding + LLM 后，保存 Provider/Model/版本、每题召回来源、引用是否支持结论、安全分类、延迟、Token 和成本。任何危急症状未短路、无证据却给出确定结论或引用不支持回答都是阻断级失败。

## OCR 集

`backend/tests/provider_eval/ocr_manifest.csv` 只记录授权、去标识和标注状态。评测必须分别计算字段名、数值、单位、参考下限/上限的准确率，并将“无法识别、留给用户确认”与错误填值分开计数。真实 OCR 的结果仍只是 Draft。
