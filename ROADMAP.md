# 路线图

| 阶段 | 目标 | 退出条件 |
|---|---|---|
| 0 | 工程、容器、数据库、CI | API 可启动，迁移/健康检查/质量任务通过 |
| 1 | 登录、档案、体重、Dashboard | 纵向流程和趋势测试通过，移动端可操作 |
| 2（已完成） | 食物、餐次、营养、基础离线同步 | 手动记录闭环、真实 Dashboard、Outbox 与后端质量门通过 |
| 3（已完成） | 图像识别、确认、个人食物记忆 | 原始估计与确认值分离，可按历史校准；安全上传、Mock/远程 Provider、草稿 UI、Retention 和 PostgreSQL CI 已接通 |
| 4（已完成） | 私人 AI 饮食教练 | 程序化目标/趋势/TDEE、食堂/下一餐、审批、安全层、Mock/远程 Provider 与 Flutter 闭环通过 |
| iOS 就绪（已完成代码与文档） | iPhone 主目标、iOS Runner、权限/Keychain/CI/发布文档 | Windows analyze/test 已通过；macOS 无签名构建和真机验收作为外部平台门禁 |
| 5（已完成） | 训练 + Apple Health 第一阶段 | 计划、组次、RPE/RIR、历史 PR、保守递进、步数/睡眠/恢复通过 |
| 6（已完成） | 健康知识 RAG + 体检 + Health AI | 文档版本、pgvector/FTS、引用、OCR Draft、单位/趋势、安全与 iPhone 健康页通过 |
| 7（已完成代码） | 主动监督、通知、报告、时间线和 Beta 准备 | 幂等任务、勿扰/冷却、本地通知、日周月报、复查确认、非因果时间线、导出/删除和发布文档通过；外部凭据/真机门禁单列 |
| 8 | 真实 Provider 评测与本地模型选项 | 授权数据集、成本/延迟/召回质量和隐私门禁通过 |
| 10 | Health Connect（Android 兼容） | 权限、增量同步、去重与撤权通过 |
| 11 | 发布加固 | 移动端构建、安全审查、备份恢复、部署演练通过 |

每一阶段必须先通过迁移、测试、lint、类型检查和回归，再进入下一阶段。发布策略为 `main` + 短生命周期 `feature/*`；稳定阶段使用清晰、单一职责的提交。

iOS Widget 与 Apple Watch companion 保留为 Phase 11 之后的独立路线项；不提前进入 Phase 5。iOS 原生构建成功只能由 macOS + Xcode 或对应 CI 证明。

## Phase 5 — completed

- Exercise library, rule-based plans, workouts, set tracking, RPE/RIR, PRs and progress
- Activity, steps, sleep, resting heart rate and categorical recovery
- Apple Health provider first phase with per-type permission UI and Mock provider
- AI training coach plus nutrition/training context linkage
- iPhone-first training UX, Drift v3 offline storage and Outbox sync

## Phase 7 external gates

- macOS CI 的 iOS no-codesign build 和 Android 兼容 build（需添加 Git remote 启用 Actions）。
- Apple Team/Signing、真机 HealthKit/Face ID/通知和 TestFlight 验收。
- APNs 凭据与真实 HTTP/2 传输；当前默认 Mock。
- 生产域名/TLS/服务器和 PostgreSQL 恢复演练实跑。
- 25 张授权餐食图、授权体检样本和真实 Provider Key。
