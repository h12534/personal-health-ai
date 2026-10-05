# UI Redesign — Phase 2 App-wide Design System Rollout

状态：**本地实现、自动化回归和双独立代码／截图评审完成**。固定 C — Data-forward Health Intelligence，加入克制的 Warm Personal Wellness。没有新方向、重建项目或新增业务模块；没有 push、merge、公开部署或真机验收声明。

工作分支：`feature/ui-redesign-impeccable`。Phase 2 基线：`6f3f1e0`；最终受测源码提交：`4f44df3`。报告日期：2026-10-05（Asia/Shanghai）。历史 Phase 1 报告可在 `6f3f1e0:UI_REDESIGN_REPORT.md` 查阅；阶段过程见 [UI_ROLLOUT_PROGRESS.md](UI_ROLLOUT_PROGRESS.md)。

产品始终为 iOS First、私人长期使用的 Personal Health OS，Quiet Premium Health Intelligence。范围为 Flutter theme、presentation、展示适配、测试与文档。API、模型、控制器、数据库、算法、服务、RAG、HealthKit、离线同步、认证业务和通知规则保持原实现。生产登录宿主的视图连续性修复属于 presentation；认证成功仍进入原 PrivacyGate。

## 1. Navigation redesign

保持首页／饮食／训练／健康／我的五个入口及 IndexedStack。统一 solid surface、outlined 图标、文字层级；取消巨大选中胶囊和重背景。选中同时使用字重，颜色不是唯一信号。

Flutter 底部导航内部限制标签缩放的问题通过传入已按用户文字比例计算的样式解决，而非关闭 Dynamic Type。320／393／430 宽度、浅深色、200% 字号的点击、选中语义和 44pt guideline 已测试。实际切换才触发原有 selection haptic；触感尚未真机体验。

## 2. Home redesign

Today／Action Dashboard：日期与问候 → 今日重点 → 主数字 → 今日任务 → 下一步建议。今日重点只读取真实 pending 任务并保持服务端顺序，skipped 不冒充待办。AI／Rule 下一步建议只出现一次，不生成“健康状态”评分。

重点突出体重、热量、蛋白质、步数、训练；其他宏量与饮水保留在渐进展开区域。任务使用开放列表，不再各占一张卡。加载、刷新、重试统一。晨重输入验证有限值及原允许范围，等待保存、阻止重复、失败保留输入。

## 3. Nutrition redesign

热量和蛋白质优先；碳水、脂肪、纤维次级展开。真实下一餐区间与策略组成核心建议。餐次采用 section／meal row／food items；拍照与相册是明确主动作，没有 Material FAB。

Draft Review 突出总估计、热量区间、项目、重量编辑与底部确认；warnings 保留，model／confidence／match 细节折叠，不删除证据。数量验证、失败保留及等待保存不改变原计算、UUID、idempotency key、confirm payload、清理或 provider invalidation。

最终 Polish 将搜索、手动添加和食堂辅助流程统一为 Detail Header、弱单位和开放分组。搜索结果 lazy slivers，键盘出现时筛选仍可滚动访问；手动添加保留原 amount／unit／营养计算。食堂三个既有编辑器在成功保存后才关闭；未新增 Saved Meal 创建功能。

实际离线控制器会提供四个预填零 aggregate：初始 fixture 没覆盖这个形状，B 找到后增加精确回归，修复 UI 的数据存在判定，没有把零制造成已记录餐食。基础 nutrition Golden 故意没有 photo callback；生产页与 nutrition-flow 场景有真实动作，不把基础截图的禁用态误称为生产功能失效。

## 4. Training redesign

“今天练什么”以开放计划和动作列表呈现。kg／reps／RIR 行内快速输入，操作自然高度、有限值验证、等待防重、失败保留。IndexedStack 保持训练中的视图状态。前台休息计时器显示动作和剩余时间，不全屏遮挡；不宣称新增后台计时能力。

PR 直接显示原记录的日期、单位与 confidence。共用图表展示每个已加载完成 session 的实际最大非热身重量；频率明确为已加载历史。没有新加估算 1RM 公式，也不把最大重量冒称 e1RM。原计划、repository、UUID、progression、volume 与同步不变。

已知 difficulty／equipment／movement 标签转为自然中文，未知原值保留。没有金币、彩带或游戏化庆祝。

## 5. AI redesign

私人教练而非 ChatGPT clone：真实 overview、nextActions、可选 7／14 日体重上下文；四个快速问题，食堂独立入口。没有虚构 sleep、readiness、恢复评分或医学判断。

用户／教练通过排版、留白和 surface 区分，不用装饰头像、渐变或聊天气泡。引用与证据默认折叠；医疗边界保持明确。对话 lazy scroll，等待／失败在输入区附近可见。presentation 历史恢复兼容 AsyncError 是否带 previous value；失败保留完整输入，重试不复制失败对象，不改会话 ID 或请求上下文。

饥饿记录与调整操作有等待和失败恢复；实际 declined 状态显示准确，不偷改后端枚举。Health AI 同样采用角色、证据、安全错误和小屏 composer 规则。

## 6. Profile redesign

Sectioned Settings：真实现有入口分组，去除无操作的 placeholder；没有虚构档案、目标设置或社交功能。个人信息只显示已有事实。

Apple Health 的步数、睡眠、静息心率、训练维持独立状态；未知权限仍为未知，免费个人配置禁用 HealthKit 时明确说明。Face ID 的入口称“App 锁”。监督模式用自然中文并解释既有差异和服务端限制，不改变通知规则。

隐私、导出、删除与确认操作等待结果并保留恢复路径。诊断入口渐进展开；Beta Diagnostics 不做耗时的装饰升级。保存 toggle 后同步失败的真实部分成功场景已增加回归，UI 重新读取已保存设置，而非显示过期状态。

## 7. Shared components

[app_components.dart](mobile/lib/core/widgets/app_components.dart) 建立三种 Header：RootPageHeader／DetailPageHeader／DataDetailHeader，以及 AppSection、MetricRow、MetricHero、ProgressMetric、InsightBlock、TaskRow、ListRow、EmptyState、ErrorState、LoadingState、BottomActionArea、TrendIndicator。另有 AsyncActionButton、AwaitedEntryDialog、数字编辑和统一日期格式；不抽象业务规则。

[AppTrendChart](mobile/lib/core/widgets/app_trend_chart.dart) 统一真实日期位置、有限值、细线、稀疏网格、实际纵轴、44pt 点选择。按 point index 选择，支持重复日期；clinical adapter 保留 canonical unit、原始点精度、每个报告自己的参考范围与合法负值。既有模型摘要的三位小数策略不变。不能比较的单位有说明，不伪造参考线、范围或医学结论。

静态 skeleton 无无限 shimmer。No meals／workout／labs／report／timeline／conversation 采用简短说明和现有 next action；知识页区分没有数据与没有搜索匹配。离线为轻量文字，已知权限、HealthKit disabled、AI unavailable 有各自语境，不暴露原始异常。

限制：现有 ApiException 不保留 HTTP status。UiFailure 只翻译可确认的代码、连接错误及支持的平台权限错误；不能凭一般异常可靠区分所有 500。保留安全通用恢复文本，并记录限制，没有为 UI 擅改 API wrapper。

健康上传、OCR 核对／编辑、报告、时间线、任务与 followup 都复用状态／等待／恢复模式。编辑器成功后才关闭；失败保留值、原 payload 和权限流程不变。ISO 只保留在原机器可读导出，不作为普通页面日期。

## 8. Design tokens changes

复用 Phase 1 palette、spacing、radius、motion 与图标语言，没有新增第四套风格或页面专属色盘。

数据承载的七种字体角色（heroMetric、metric、metricLabel、cardTitle、body、secondary、caption）统一请求 tabular figures；数字突出、单位减弱但不丢失，目标也显示单位。保留平台系统字体，测试字体未进入生产 assets。

Dialog 明确 semantic surface／透明 tint／zero elevation／共享 radius，hint 使用可读的 secondaryText。组件最小目标 44、操作最小高 48；文字增加时不是固定裁切高度。主要动作、tonal、selected、attention／warning／danger 在 theme 和测试中统一。

[DESIGN.md](DESIGN.md) 和 [sidecar](.impeccable/design.json) 仅合并实际覆盖与规范事实，保留已确认方向和 primitives。sidecar 色阶／HTML snippets 仍只是规范面板示意，不是 Flutter runtime、另一个实现路径或新 App token。

## 9. Dark Mode

不是机械反白：保留 near-black background、surface、elevated surface、soft tint 四层语义；正文、弱单位、状态、图表、导航、divider、dialog 与 sheet 保持浅色同一信息层级。OLED 不全页纯黑。

自动检查两种 appearance 的普通正文／状态文字在四种表面均 >=4.5:1，accent 图标 >=3:1，primary／tonal／danger 文字组合达标。禁用态和装饰 divider 不假充正文对比度。实际生产晨重 dialog 的浅深截图含 modal overlay、98.6 和 helper text；不是泛用数字框替代品。

## 10. Accessibility

| 已执行的本地检查 | 结果／边界 |
| --- | --- |
| 320×568／393×852／430×932、浅深色、200% text scaler | 六个主要页面及辅助流程无 layout exception，保留长中文与滚动 |
| 44pt／iOSTapTargetGuideline／SemanticsAction.tap | Root 与 Health AI 的实际交互目标测试通过，非仅目测 |
| 非单一颜色语义 | 状态文字／icon、选中字重、明确 action |
| Reduce Motion | 程序化过渡零时长；不以字体缩小补偿布局 |
| 两种 chat 的模拟 300pt viewInsets | send 可点击且在键盘上方；完整失败输入保留、可重试 |
| FoodSearch 300pt inset | 原 320／200% 两主题 29px overflow 被实际测试复现，sliver header 修复后通过 |

Scaffold 会从 body MediaQuery 移除 viewInsets，因此通过 LayoutBuilder 使用真实可用高度。短 chat 布局压缩装饰 header／intro，调整可见输入行数，不截断 controller 文本、不 clamp Dynamic Type、不删功能。四张小屏 composer capture 的实际 body 为 320×268；没有绘制或宣称真实 iOS 键盘。

这些是 Windows widget-test／语义证据。系统 SF／中文字体、真实 Dynamic Type、VoiceOver 阅读顺序／操作、硬件键盘、Safe Area、返回手势和 haptic 仍待 iPhone。iPad／横屏／Split View 不在本轮验证范围。不要求拥有本地 Mac。

## 11. Golden tests

**54 个 Golden 比对通过**：固定 C 的 26 个场景 × 浅深色 = 52；另保留 Phase 1 的 Clinical／Warm 两张历史对照回归，不代表重开方向探索。

26 个场景：dashboard、nutrition、training、health-overview、coach、profile；nutrition-flow、meal-draft、training-progress、coach-conversation；health-sync、notifications、privacy-data；health-chat、health-knowledge、lab-draft、health-data-detail；reports-empty、timeline-empty、weight-editor；health-keyboard-small、coach-keyboard-small；login、food-search、add-food、canteen。

引擎为 Flutter 3.47.5 Windows widget-test；普通 viewport 393×852，固定 test-only Noto Sans SC 与既有 icon assets。字体 provenance 见 [测试资产说明](mobile/test/assets/README.md)。全为 synthetic 数据，没有真实报告、照片或健康记录。

Golden 更新均在主代理查看实际图片／差异后按指定名称刷新，不 Accept All。最后一轮只显式加入八张辅助流程图片、刷新四张弱单位的既有图片；其余 42 张保持。最后 FoodSearch sliver 修复没有改变任何 Golden。最终比对与全套测试 **不带 --update-goldens**。

modal 首次错误 capture boundary、small composer 首次透明 surface 属于证据 fixture 问题，已改为实际 Navigator overlay／opaque Material 并重新人工确认，未把错误截图当完成证据。

## 12. Flutter analyze

最终受测代码对应 `4f44df3`：

```text
flutter analyze --no-pub
No issues found! (ran in 11.5s)
```

本地实际执行成功，exit 0。没有降低 lint、删除检查或忽略警告。最后源码修改后已复测；此后的提交只更新文档。

Windows 非 ASCII 测试工作区临时使用经核实的 X: alias 与项目缓存，不改业务配置。收尾用真实 E: 路径执行 `flutter pub get --offline` 恢复依赖路径，仅移除已核实的 alias，不删除项目或缓存，也不升级依赖。

## 13. Flutter test

最终实际完整执行 `flutter test --no-pub`：**203 tests passed，exit 0**，包括 54 Golden。最后额外指定 Polish + Golden 的 67 项也通过。Phase 1 为 63，本轮增加 140；原有业务回归继续执行，没有 skip／disable。

严格依次完成门禁，不六页同时实现。每阶段 analyze → whole suite → 截图人工查看 → A 只读 finish → B 独立只读 finish → scoped commit，再进入下一阶段：

| 顺序 | 门禁 | 当时全套通过数量 |
| --- | --- | ---: |
| 1 | Navigation | 69 |
| 2 | Home | 79 |
| 3 | Nutrition + Draft | 99 |
| 4 | Training | 109 |
| 5 | AI | 120 |
| 6 | Profile | 136 |
| 7 | Shared States | 160 |
| 8 | Dark | 166 |
| 9 | Accessibility | 182 |
| 10 | Final Polish | 203 |

关键真实失败及修复：

- 四个零 aggregate 的离线形状、慢重试导致失败对象重复、toggle 已保存但同步失败后的过期展示：补精确场景并修复 UI，不改 controller。
- 小屏键盘 chat／FoodSearch 溢出：按实际约束改布局，不缩字、不隐藏筛选。
- A 发现生产 `auth.when` 在 loading 中卸载 Login：两个真实 HealthOsApp 测试先复现，修复视图连续性后断言相同 controller identity 和完整失败 email／password；成功后的 PrivacyGate 路径经源码检查保持不变。没有只靠独立 Login fixture 声称修好，也不把失败场景测试冒称成功登录测试。
- 训练 `beginner` 自然中文化后既有字面断言失败：仅更新预期“入门”，保留行为断言；弱单位 Golden 先看实际 diff，再指定刷新。
- Modal／small-body Golden 的 capture 纠正见第 11 节，没有绕过 visual regression。

相对 `6f3f1e0` 的 backend、network／database／privacy、feature data、controllers、iOS／Android 工程、pubspec／lock 和 workflows 的受保护范围 diff 为空。lib 的其余变更仅 presentation、theme、shared widgets 与 app 视图宿主。Git diff whitespace 检查通过。

本分支没有触发新的 GitHub CI／macOS build。旧 Release Candidate run 不作为当前 UI 分支 CI 通过证据；本报告也不声称签名、IPA、TestFlight 或物理安装完成。

## 14. Before / After screenshots

六个主要页面的实际 Flutter 证据：

| 页面 | Before Light | Before Dark | After Light | After Dark |
| --- | --- | --- | --- | --- |
| Home | [Before](docs/ui-redesign/phase2-before/dashboard-light.png) | [Before](docs/ui-redesign/phase2-before/dashboard-dark.png) | [After](mobile/test/goldens/dashboard-light.png) | [After](mobile/test/goldens/dashboard-dark.png) |
| Nutrition | [Before](docs/ui-redesign/phase2-before/nutrition-light.png) | [Before](docs/ui-redesign/phase2-before/nutrition-dark.png) | [After](mobile/test/goldens/nutrition-light.png) | [After](mobile/test/goldens/nutrition-dark.png) |
| Training | [Before](docs/ui-redesign/phase2-before/training-light.png) | [Before](docs/ui-redesign/phase2-before/training-dark.png) | [After](mobile/test/goldens/training-light.png) | [After](mobile/test/goldens/training-dark.png) |
| Health Overview | [Before](docs/ui-redesign/phase2-before/health-overview-light.png) | [Before](docs/ui-redesign/phase2-before/health-overview-dark.png) | [After](mobile/test/goldens/health-overview-light.png) | [After](mobile/test/goldens/health-overview-dark.png) |
| AI Coach | [Before](docs/ui-redesign/phase2-before/coach-light.png) | [Before](docs/ui-redesign/phase2-before/coach-dark.png) | [After](mobile/test/goldens/coach-light.png) | [After](mobile/test/goldens/coach-dark.png) |
| Profile | [Before](docs/ui-redesign/phase2-before/profile-light.png) | [Before](docs/ui-redesign/phase2-before/profile-dark.png) | [After](mobile/test/goldens/profile-light.png) | [After](mobile/test/goldens/profile-dark.png) |

Before provenance 见 [README](docs/ui-redesign/phase2-before/README.md)：Home／Nutrition／Training Light 来自 Phase 1；其 Dark 在 Navigation 提交后、对应页面修改前采集。AI／Profile 使用原 Phase 1 production source，在添加实际 harness 时采集，并含最终导航；不是老导航的单变量比较。Health 保留 Phase 1 Reference。

Nutrition 原 aggregate-only fixture 没有 meal list；[nutrition-flow](mobile/test/goldens/nutrition-flow-light.png) 和 [meal-draft](mobile/test/goldens/meal-draft-light.png) 是额外 After 场景，不伪装成相同数据 Before。更多操作证据：[训练进度](mobile/test/goldens/training-progress-light.png)、[教练对话](mobile/test/goldens/coach-conversation-light.png)、[Health AI](mobile/test/goldens/health-chat-light.png)、[指标详情](mobile/test/goldens/health-data-detail-light.png)、[OCR 核对](mobile/test/goldens/lab-draft-light.png)、[健康同步](mobile/test/goldens/health-sync-light.png)、[晨重弹窗](mobile/test/goldens/weight-editor-dark.png)、[小屏键盘布局](mobile/test/goldens/health-keyboard-small-dark.png)。全部浅深图在 [Golden 目录](mobile/test/goldens)。

本地手机浏览器入口：[同一 Wi-Fi 预览](http://192.168.1.18:4173/?redesign=1)；[电脑预览](http://localhost:4173/?redesign=1)；[首页全屏截图](http://192.168.1.18:4173/assets/ui-redesign/dashboard-light.png)。地址依赖本机服务持续运行及同一网络，不是永久公开链接。

预览已执行 TypeScript／Vite build；28 个受保护 runtime 文件完整性通过。隔离 Edge 验证 6 页面 × Light／Dark／Before 共 18 状态，served PNG SHA256 与 Flutter source 一致，评审控件实际渲染 >=44px，无 page error／external request，原交互 Mock 导航保留。主代理查看实际预览截图；本机 LAN HTTP 200，尚未声称用户 iPhone 已亲测。

`?redesign=1` 是真实 Flutter 静态截图 gallery，图内按钮不能操作，也没有原生权限。原 `/` 保留既有交互 Mock，未冒称全新 Flutter UI。Standalone AI Golden 的导航 index 是 fixture 宿主上下文，不是新增第六入口。预览只用 synthetic 数据，没有真实 API／模型／secrets。未公开部署。

## 15. Impeccable final audit

官方 Impeccable 已在 Phase 1 从 `pbakaus/impeccable` 安装（CLI 4.1.0、skill metadata 4.5.0、Windows engine 0.1.11）；没有改用 fork 或绕过 integrity。Phase 2 context 仅运行一次，不重做 shape 或视觉 workshop。

各页按 critique → layout → typeset → 必要时 colorize → distill → polish → audit 方法落地，结合 native adapt／harden／extract。所有实现由主代理完成；A（视觉／排版／层级／品牌）与 B（交互／信息架构／无障碍／真实场景）独立只读评审，不并行改业务代码。

A 最终 Final Polish 限定范围 Nielsen **34/40**，specificity **8/10**，无剩余 P1／必修 P2。该分数不是全产品综合评分，也不是将历史不同 scope 的 baseline 拼成改善曲线。

B 的独立 native audit：**PlatformConformanceVerdict PASS（code-layer）**，**14/20，Good**：

| 维度 | 分数 | 证据与限制 |
| --- | ---: | --- |
| Accessibility | 3/4 | widget semantics／44pt／200%／contrast；真实 VoiceOver 未执行 |
| Performance | 2/4 | lazy 搜索／对话、无强 blur、静态 skeleton；食堂大集合与设备 profile 待测 |
| Appearance | 4/4 | 固定 tokens、L/D、实际截图一致，无 default-template／card soup 主导 |
| Platform | 3/4 | iOS-first 导航／输入／返回语义；系统手势和触感待真机 |
| Adaptivity | 2/4 | 三种 portrait 尺寸及模拟键盘；iPad／横屏／Split View 未覆盖 |

最终无 P0／P1 阻断；一项非阻断 P2 见第 16 节。以上不是自动 detector 的 clean verdict。Dart detector 返回空列表表示不支持，不等于 Flutter 已无问题；本轮 native 证据是源码、widget tests、实际图片和两方审查。

> Codex native hook approval entry unavailable in current environment.

配置 enabled 不等于实际 native approval 或 Hook 执行。遵照用户指示未因此阻塞设计，没有信任绕过、禁用 Hook、修安全配置或反复等待批准。critique 归档与 surface briefs 保留在 `.impeccable/`，不为漂亮分数重写历史。

## 16. Remaining visual debt

UI RC 更新（2026-10-05）：下述 Phase 2 eager 食堂债务已以 10 食堂／50 档口／1000 菜品与 lazy slivers 关闭，具体执行与物理性能限制见 [UI_RC_ACCEPTANCE_REPORT](UI_RC_ACCEPTANCE_REPORT.md)。这里保留原始阶段判断，不把历史评分或测试数量冒称当前结果。

一项非阻断 P2：`mobile/lib/features/coach/presentation/canteen_screen.dart` 的 `_SavedMeals`（本轮第 394 行）仍以 eager Column 构建集合，类似食堂分组也沿用既有 eager 结构。大量数据可能增加 layout／memory 成本；没有设备 profile，不能写成已测量的卡顿或帧率退化。

建议后续仅针对实际大数据 fixture 与 iPhone profile 使用 `$impeccable optimize`；确认瓶颈后再决定 lazy／sliver，不为假设重建模块。若有修复，最后 `$impeccable polish` + native audit，不重开方向。

其他是尚未验证的边界，不冒称已发现缺陷：真实 VoiceOver／系统字体／Dynamic Type／Safe Area／返回手势／触感；大量历史数据滚动、复杂 chart、原生 sheet／键盘；iPad／横屏／Split View。原 Icon family 保持一致，但不是 SF Symbols 或“所有控件原生 UIKit”的声明。

现有 API status 丢失的精细错误分类限制见第 7 节。没有为关闭视觉债务改业务层或接入新服务。

真机验收可以沿项目允许的云构建／个人安装路线完成，不要求购买或拥有本地 Mac；静态 Safari 预览不能关闭 HealthKit、Face ID、Camera、Notifications 等原生门禁。

## 17. Git commits

按用户要求留在 `feature/ui-redesign-impeccable`：

| 提交 | 内容 |
| --- | --- |
| `317a1f5` | design(nav): apply final navigation language |
| `b64a831` | design(home): redesign today dashboard |
| `35066cc` | design(nutrition): redesign nutrition flow |
| `1cfab6d` | design(training): redesign workout experience |
| `f3d8f29` | design(ai): redesign personal health coach |
| `8d72e15` | design(profile): redesign settings and profile |
| `f55b36a` | design(states): unify loading empty error states |
| `ae6f61a` | design(dark): complete app-wide dark mode |
| `17500aa` | test(ui): expand golden and accessibility coverage |
| `4f44df3` | design(polish): unify auxiliary flows and preserve failed input |
| 本报告所在 docs 提交，SHA 以 git log 为准 | docs(ui): finalize app-wide design report |

Phase 1 已有 `af8916d / 4459ee4 / a7653c4 / e9bc527 / af42dd2 / 6f3f1e0` 保留，没有改写提交历史。

所有 tracked Phase 2 实现、测试、规范与 Flutter evidence 分阶段提交。原先未跟踪的 `ui-preview/` 保留为本地预览工程，不把整个旧 runtime／依赖项目或零散不完整文件混进本轮 Flutter 提交；`mobile/test/failures/` 保留本地人工复核的 Golden 差异诊断。它们不作为最终 failed test 结果，也未为“干净”删除用户文件。因此不能宣称全部工作树 clean。

## 18. 是否建议 push

**从本地 presentation 回归与设计审查角度，已具备请求 push 审批的条件；本轮仍按用户要求不 push、不 merge main。** 当前 tracked 改动已提交，本机预览可看。

Phase 2 当时未推送。当前 UI RC 用户已明确授权仅推 feature 分支用于真实 CI，仍禁止 merge。当前证据见 [UI_RC_ACCEPTANCE_REPORT](UI_RC_ACCEPTANCE_REPORT.md)，不以旧 RC run 替代。之后通过允许安装路线进行 iPhone 验收；不把本地 UI 完成冒称签名或真机门禁关闭。

## UI RC Before / After provenance

原始 Before 与 Phase 1 Reference 保留 [phase2-before](docs/ui-redesign/phase2-before/README.md)。提交 55fea20 的十二张 Phase 2 Final 已在任何 RC Golden 刷新前无损保存到 [phase2-final](docs/ui-redesign/phase2-final/README.md)，原 After 链接可继续指向当前回归基线但不再被误当作不可变历史。最新 RC 的 32 张实际截图见 [UI_RC_PREVIEW](docs/ui-redesign/UI_RC_PREVIEW/README.md) 及哈希 manifest。

本轮解决已证实的性能、对比度、回复到达、编辑精度、删除确认、搜索样式、键盘溢出与折叠期间 busy state 问题；未换 C 方向，未修改业务层。剩余设备边界与最终 CI 结果单独记录在 RC 报告。

### UI RC cloud gate status (actual results)

后续用户明确授权74标准版＋12免费版合成PNG作为短期Actions artifact，且禁止新增截图进入源码／Git history。当前修复链仅保存逐像素RGBA SHA-256、尺寸及审查来源；此前含新增PNG的未推送本地提交保留为本地快照，不会随feature推送。公开截图包仍是既有32张，新云端图片将经自动安全检查后仅保留1天；原40张本地成果属于授权前历史，不能冒称当前已发布文件。具体真实结果以最新RC报告为准。

当前 [run37272234650](https://github.com/h12534/personal-health-ai/actions/runs/37272234650) 的 release-audit、backend、PostgreSQL、Android 真实成功；macOS 的格式／analyze及188项非Golden测试成功，但74项跨 Windows/macOS 截图比对失败，随后 iOS build 未运行。因此本次 UI RC **不是 CI 全绿，不建议 merge**。

免费个人安装配置另发现固定 HealthKit 手动记录说明挤压大字／键盘布局，已在本地修复并保留完整能力边界。标准／个人HealthKit尝试／免费手动版各262tests及74Golden全通过；12张新免费版基线人工查看，额外8张纳入当前40PNG截图包。原始Before、Phase1、Phase2Final均未改写。

仅两张获准的合成云端界面及其差异图已查看；全量 macOS 独立基线的人工验收仍需完整截图。扩大 GitHub artifact 上传被安全审核拒绝，已经向用户请求74标准版＋12免费版的明确合成PNG上传授权，未绕过拒绝。当前完整状态、提交SHA、JobID及下一步在 [UI_RC_ACCEPTANCE_REPORT](UI_RC_ACCEPTANCE_REPORT.md)，不把历史阶段成功冒称本轮门禁通过。
