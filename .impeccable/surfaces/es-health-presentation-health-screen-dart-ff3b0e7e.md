---
version: 1
slug: "es-health-presentation-health-screen-dart-ff3b0e7e"
primary_target: "mobile/lib/features/health/presentation/health_screen.dart"
related_targets: ["mobile/lib/core/theme/app_theme.dart"]
---

# Health Overview Reference

Mode: Operate. Primary target: `mobile/lib/features/health/presentation/health_screen.dart`.

## Direction contract

THESIS: 用真实报告归属、指标值与可核对的历史变化建立私人健康感，拒绝说明 Banner → 报告 Card → 安全 Card 的等权堆叠。保留原有业务与医学边界。

OWN-WORLD: Data-forward Health Intelligence。深青绿交互、微暖纸白底、清晰系统字体、数字等宽；一个指标焦点，次级资料用无框排版和轻分隔。Warm Personal Wellness 只体现为同一系统的中性表面温度与文案，不混入第二套视觉语法。

STORY: 先知道数据属于哪次报告，再读检测值、报告标记与参考范围；有真实历史时核对日期和变化，无历史时明确说明。指标详情和原有 AI 问答继续可达，不新增诊断或健康评分。

FIRST VIEWPORT: 原生安全区内大标题和明确四栏目；概览首个主数据组占主要阅读区域，次级历史证据与报告入口在下方，安全说明降为可展开的轻量入口。单手主导航保留五目的地，缩放后内容可滚动。签名交互是触摸历史点读取所属日期 / 值，变化只描述数据，不标记为医学好坏。

FORM: 用户于本轮明确固定数据导向主方向，优先于随机分配；实际 concept seed `b52e144b`，assigned index 4。候选文化来源为私人相册、自然观察日志、精密地图、潮汐日期记录、博物馆说明、瑞士数字排版、年度时间册；仅借用日期与对齐纪律，不引入票券、印章、像素字、控制台或陌生导航。所有 challenger 在熟悉度与信息清晰度上均不胜出；保留的纪律是证据归属、对齐、非颜色状态与时间组织。

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Evidence and limits

三套同数据候选优先采用真实 Flutter 组件渲染，不以 AI 图片替代运行代码；尚未收到构建路径问题回复，不保存项目长期 `buildPath` 默认。Windows Flutter widget-test 渲染与 Golden 是当前可执行证据，不称为 iOS Simulator。iOS 真机字体、VoiceOver、手势、动态岛与性能留作实际 iPhone 验收。
