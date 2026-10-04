# UI / UX Redesign — Impeccable Pass

状态：产品定位已确认，进入独立设计评审；尚未完成三方案比较或 Flutter 重设计。

## 范围与基线

- 工作分支：`feature/ui-redesign-impeccable`。
- 初始提交：`5ec6340d0b06e4cdfdfce38c63a1bd33c8cc76fb`。
- 初始工作树仅有已有、未跟踪的 `ui-preview/`；未覆盖该预览工程。
- 冻结新业务功能。保留现有接口、数据库、业务算法、认证、HealthKit、RAG / AI、离线同步、通知及测试检查。
- 目标平台为 Flutter / iPhone。Web 模拟预览不是 Flutter 实现，也不是 iOS 真机验收。
- 用户指定方向：Quiet Premium Health Intelligence；原生 iOS 系统字体、语义化浅色 / 深色主题、清晰的数据层级及可访问的交互。

## 官方工具安装记录

- 来源：官方 `pbakaus/impeccable`，未使用同名非官方替代包。
- 安装命令：`npx --yes --proxy=http://127.0.0.1:7897 impeccable@4.1.0 install --providers=codex --scope=project`。
- 首次安装因验证技能包时读取响应超时而失败；没有绕过完整性验证。
- 重试使用本机已有代理的进程级 HTTP / HTTPS 代理设置，安装成功。
- npm CLI 版本：`4.1.0`；安装后的技能元数据版本：`4.5.0`；Windows 引擎版本：`0.1.11`。三者分别记录，不混用版本号。
- 技能位置：`.agents/skills/impeccable/`。
- 项目 Hook 清单：`.codex/hooks.json`，包含 PostToolUse 与 Stop 检查。
- `impeccable context --target mobile/lib/features/health/presentation/health_screen.dart` 已运行一次，明确报告 `NO_PRODUCT_MD` / `PRODUCT_INIT_REQUIRED`。
- `impeccable hooks status` 实际显示 enabled、无忽略规则、无环境禁用覆盖。
- **Codex native hook approval entry unavailable in current environment.** 用户已明确说明当前没有可用审批入口，并授权不以此阻塞重设计。配置 enabled 不等于原生信任已批准；未修改信任记录、未使用 bypass、未禁用 Hook。不声称自动 Hook 已实际执行。
- 官方 Hook 文档的内置扫描扩展名不含 Dart。后续必须分别记录 Web 检测与 Flutter 原生审查覆盖，不能把 Web 检测通过当成 Flutter 检测通过。

## 当前截图证据

本轮已使用获准的隔离 Edge / Playwright 新建浏览器上下文，捕获现有模拟预览的七个状态：

| 状态 | 文件 |
| --- | --- |
| Dashboard | `artifacts/ui-redesign/before/01-dashboard.png` |
| Nutrition | `artifacts/ui-redesign/before/02-nutrition.png` |
| Training | `artifacts/ui-redesign/before/03-training.png` |
| Health Overview | `artifacts/ui-redesign/before/04-health-overview.png` |
| Health Indicator | `artifacts/ui-redesign/before/05-health-indicator.png` |
| Health AI | `artifacts/ui-redesign/before/06-health-ai.png` |
| Profile | `artifacts/ui-redesign/before/07-profile.png` |

捕获脚本：`ui-preview/scripts/capture-redesign-audit.mjs`，执行成功。未读取个人浏览器配置。

这些图片仅证明现有 **Mock Web Preview** 的呈现；正式 Flutter Before / After 与 Golden 证据尚未产生。

已直接查看的健康概览、指标详情与 AI 截图中可观察到：

- 健康概览的时间线介绍、报告卡和安全提示接近同等视觉权重，最新指标数值较小，页面下方留白较大。
- 异常提示依赖一个小橙点；需要保留实际报告参考范围，并增加可读文字 / 图标，不能新增诊断含义。
- 指标详情以两个等权边框卡呈现历史数据，变化关系不够直观。
- AI 页面主要是边框空状态和输入框；需优化入口、说明层级及加载 / 错误呈现，不能改变现有医学边界或虚构 AI 输出。

以上是基线观察，不是已经完成的官方双代理 critique，也不是完成后的改进结论。

## 门禁与待办

| 项目 | 真实状态 |
| --- | --- |
| 官方安装 | 完成 |
| 专用分支 | 完成 |
| 现有 Mock 预览截图 | 完成 |
| `/impeccable init` 产品定位确认 | 用户已确认，`PRODUCT.md` 已创建 |
| Codex 原生 Hook 审查 / 信任 | 当前审批入口不可用；按用户指示记录并继续，不绕过 |
| critique 双代理授权 | 用户明确允许两名独立只读评审，禁止并行修改业务代码 |
| 正式 Impeccable critique / audit | 未开始 |
| 三种健康概览视觉方案 | 未开始 |
| 单一参考方向选择 | 未开始 |
| Flutter tokens / 组件 / 页面修改 | 未开始；当前业务与 Flutter UI 未改 |
| 修改前 Flutter test | 49 项通过（47 项原有测试 + 2 项新增浅色 / 深色基线渲染）；使用 `UI_BASELINE=true` |
| Flutter analyze / 新设计 Golden | 新设计尚未实现，待修改后重新验证 |
| Before / After 对比及暗色 / 大字体 / 交互验证 | 未完成 |
| 阶段性 commit / push | 未执行 |

后续顺序：完成产品初始化与原生 Hook 审查 → 正式审查 → 三个同数据视觉方案 → 选定单一方向 → Flutter 原生落地 → 预览与测试 → 分阶段扩展其他页面并更新本报告。

不降低 lint，不跳过 / 禁用既有测试，不以 Mock 预览替代 Flutter 验证，不将待确认门禁写成已通过。

真实 Flutter 修改前截图已补充至 `artifacts/ui-redesign/flutter-before/health-overview-light.png` 与 `health-overview-dark.png`。这是 Windows 上 Flutter widget-test 引擎的渲染，不是 iOS Simulator 截图。中文测试字体来自固定 Google Fonts 提交、附 OFL 许可证，仅测试使用，不改变 App 的 iOS 系统字体。
