# HealthKit 真机测试

## 前置条件

1. 一台运行 iOS 15 或更高版本的 iPhone。
2. Apple Developer Team、匹配的 Bundle ID 与包含 HealthKit capability 的 provisioning profile。
3. 在 macOS 使用 Xcode 打开 mobile/ios/Runner.xcodeproj。
4. Runner → Signing & Capabilities 中确认 HealthKit 已启用，Runner.entitlements 包含 com.apple.developer.healthkit。
5. 选择物理 iPhone 签名并安装 Debug build。

## 步数

1. 首次启动不应自动弹出 HealthKit 权限。
2. 我的 → 健康同步 → 仅开启“步数”。
3. 确认权限页只包含步数。
4. 在 Apple 健康中准备当天步数，再返回 App。
5. Dashboard 应显示聚合步数；关闭所有来源或没有记录时显示“暂无数据”，不是 0。
6. 重复同步不应在 step_logs 生成重复日记录。

## 睡眠与静息心率

分别开启两项并检查每次只出现相应新增权限。睡眠段允许 awake、core/light、deep、REM；App 只给恢复提示，不对单晚阶段作诊断。静息心率与多日个人基线联用。

## 训练摘要

开启“训练”后，从 Apple 健康读取一条训练记录。服务器 activity_logs 只保存开始、结束、类型与摘要，不保存路线或原始心率样本。

## 拒绝权限

在系统权限页拒绝某项，App 不崩溃、不把无数据写成 0，并允许用户继续手动记录。iOS 不公开读权限状态，UI 不显示虚假的“已授权”。

## 重新开启

前往设置 → 健康 → 数据访问与设备 → 本 App，重新打开权限，回到 App 关闭再开启对应同步开关后验证读取。

## 多设备来源

同时使用 iPhone 与 Apple Watch 产生步数。对比 Apple 健康当天总步数与 App，确认使用 HealthKit 聚合而非简单相加。

## 关闭与删除

关闭同步后不再产生新上传。调用服务器删除来源功能后，确认 healthkit 的 step_logs、sleep_logs、activity_logs 与 health_sync_state 被删除，手动数据保留。
