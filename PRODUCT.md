# Personal Health OS

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

仅供项目拥有者本人长期日常使用的私人健康工具。主要使用场景是 iPhone 上查看个人趋势、记录饮食和训练、理解体检报告及获得有边界的个人健康建议。

## Product Purpose

将现有健康、饮食、训练与 AI 辅助流程整合为私人 Personal Health OS。成功意味着信息一眼可读、记录高效、长期使用不疲劳，且不会把辅助建议误认为临床诊断。

## Positioning

iOS First 的私人健康系统，不是面向医院、健身房、减肥打卡或企业管理的商业产品。个人长期上下文及现有离线记录 / 同步流程是产品体验的一部分。

## Operating Context

- 现有技术栈为 Flutter，iPhone 优先；不得重建为 React / Web。
- 项目拥有者有真实 iPhone，没有本地 Mac。不得要求购买 Mac 才能继续开发或预览。
- 现有 `ui-preview/` 是使用合成数据的独立 Web 模拟预览，不代表原生构建、真实 API 或真机验收。
- 当前工作只重构 UI / UX，不增加新的业务模块。

## Capabilities and Constraints

保留现有 API、数据库、健康 / 饮食 / 训练算法、HealthKit、RAG、AI Provider、认证、通知、离线同步和业务测试。主要修改边界为 presentation、theme、design tokens、shared widgets、navigation UI、动画及响应式布局。

已有功能与数据缺失状态必须如实展示。不得虚构综合健康评分、趋势、医学结论、AI 输出或新的服务能力。体检状态与参考范围采用报告已有字段。

## Brand Commitments

用户于本轮明确确认：Quiet Premium Health Intelligence；安静、高级、可信、智能、个人化、数据清晰。以 Data-forward Health Intelligence 为主，加入适量 Warm Personal Wellness 的温度，统一为一个方向而非拼接多套风格。

不要医院系统、健身房 App、廉价减肥打卡、企业后台、广告感、商业化或游戏化视觉。允许并优先采用 iOS 系统字体。参考成熟 iOS 的克制，但不直接复制 Apple Health。

## Evidence on Hand

- Flutter 实现：`mobile/lib/`；业务与控件测试：`mobile/test/`。
- 现有 Mock 预览截图：`artifacts/ui-redesign/before/`，仅用于现状观察。
- 现有体检数据模型提供检测值、单位、报告参考范围、状态、检测时间与历史趋势接口；展示层不得扩展其医学含义。
- 本轮尚无 iOS Simulator 或 iPhone 截图、VoiceOver 实测及滚动性能实测；不能以浏览器图或 Flutter 测试渲染代替这些验收结论。

## Product Principles

1. 真实数据与清晰状态优先于装饰或虚构洞察。
2. 日常记录效率与个人长期可读性优先于短期视觉刺激。
3. 原生 iOS 的导航、手势、触摸与辅助功能习惯优先于 Web 风格规则。
4. 界面重构不改变业务、安全边界与已有测试门禁。
5. 健康解释保持温和、精确且非诊断；颜色不作为唯一状态信息。

## Accessibility & Inclusion

支持系统文字缩放 / Dynamic Type、VoiceOver semantics、浅色和深色外观、至少 44pt 点击区域、Safe Area / Dynamic Island / Home Indicator 和 Reduce Motion。优先可读性、明确的状态文字及单手操作，不使用强制细字、低对比文字或炫技动画。
