# Apple Health / HealthKit 设计

## 插件选择

- 插件：health 13.3.1
- 许可证：MIT
- iOS 最低版本：15.0
- 集成方式：项目已启用 Flutter Swift Package Manager；插件 13.x 支持 SPM。
- 选择原因：维护活跃、公开 API 包含按类型授权、聚合步数、去重和 Apple Health / Health Connect 双平台抽象。

当前最新 13.3.2 与项目既有 flutter_secure_storage 9.2.4 的 Windows win32 约束冲突。为避免无关的安全存储大版本迁移，本阶段精确固定 13.3.1。

## Provider 边界

页面不直接调用插件。所有调用经由 HealthDataProvider：

- AppleHealthProvider：真实 iOS HealthKit。
- ManualHealthProvider：手动数据。
- MockHealthDataProvider：Windows、CI、Simulator 和业务测试。
- PrioritizedHealthDataProvider：按配置选择第一个可用来源。

## 第一阶段读取

支持 steps、walking_running_distance、active_energy_burned、resting_heart_rate、sleep、workouts。设置页展示步数、睡眠、静息心率与训练四个独立开关。第一次开启某项时才请求该项权限。

步数使用插件的 getTotalStepsInInterval，即 HealthKit 聚合查询，不直接累加 iPhone、Apple Watch 和第三方 App 样本。其他样本先按插件 UUID 去重，只上传 App 使用的每日摘要或睡眠/训练段。

## iOS 权限

Runner.entitlements 开启 com.apple.developer.healthkit，Xcode Runner target 声明 HealthKit capability，Info.plist 包含 NSHealthShareUsageDescription 与插件所需的 NSHealthUpdateUsageDescription。当前业务只读，不写回 Apple Health。

iOS 为保护隐私不会透露读取授权的精确结果，因此开关表示用户已在本 App 开启同步，不能声称 Apple 已授予读取权限。无数据、拒绝权限、设备锁定和不支持均是正常状态；无数据永远不转换为 0。

## 服务器最小化

服务端保存每日步数摘要、距离、活动能量、静息心率日值、睡眠段和训练摘要，不接收全部原始 HealthKit 样本。provider + source_record_id 提供幂等；health_sync_state 保存每个 data_type 的 cursor/anchor 与最后同步状态。

用户关闭同步后不再读取新数据；DELETE /api/v1/health/sync/{provider} 可删除该来源的服务器摘要。
