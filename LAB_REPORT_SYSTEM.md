# 体检报告系统

## 数据流

```text
Camera / Photos / Files PDF
  → MIME + magic + decode validation
  → private StorageProvider
  → page split / text-layer extraction
  → LabOCRProvider
  → editable OCR Draft
  → explicit user confirmation
  → LabResult + trends
```

PDF 逐页处理：文本页直接送 Mock/解析 Provider，扫描页渲染为独立 PNG 后再交 OCR，避免把超大 PDF 一次发送。远程 Provider 必须在该次上传中设置明确同意；Mock 在本地执行。普通日志不记录报告正文、OCR 全文或对象路径。

## 标准化与判断

`lab_test_dictionary` 初始包含空腹血糖、HbA1c、血脂、ALT/AST/GGT、尿酸、肌酐/eGFR/BUN、血压、BMI、腰围、血常规和 TSH 等 21 项。别名只负责名称映射；单位换算由 `LabUnitConversionService` 进行，支持血糖、血脂、肌酐、尿酸和 HbA1c 常见单位。

医院提供的 `reference_min/max/text` 原样保存在 Draft 和正式结果中。简单范围只产生 `low/normal/high/unknown`；程序不会因普通越界自动标记 `critical`。AI 解释优先使用报告自己的范围，不能据单次值诊断。

## 用户控制

- Draft 可修改名称、标准名、数值、单位和参考范围。
- 确认可选择条目；确认前结果不进入趋势或 Health AI context。
- 可删除单个指标或整个报告；删除报告会软删除关联结果并删除原文件。
- `retain_original=false` 时确认后立即删除原文件。
- 复查建议默认 `suggested`，只有用户接受才进入 `accepted`；当前不自动创建系统通知。

Flutter Drift v4 缓存已保存报告和趋势，离线可查看；知识问答与新 OCR 仍要求服务器。
