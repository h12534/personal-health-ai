# iOS 通知依赖审计

审计日期：2026-10-01。主应用最低版本为 iOS 16.0。

| 依赖 | 锁定版本 | 官方要求/用途 | 结论 |
|---|---:|---|---|
| `flutter_local_notifications` | 22.3.1 | 支持 iOS 13+；Darwin 初始化可禁止自动申请权限 | 与 iOS 16+ / Flutter 3.47.5 兼容 |
| `timezone` | 0.11.1 | 时区化定时 | 已锁定 |
| `flutter_timezone` | 5.1.0 | 读取设备 IANA 时区 | 已锁定 |
| `local_auth` | 3.0.2 | Face ID / Touch ID，iOS 13+ | 与 iOS 16+ 兼容 |

审计来源：

- <https://pub.dev/packages/flutter_local_notifications>
- <https://pub.dev/packages/flutter_local_notifications/versions/22.3.1>
- <https://pub.dev/packages/local_auth>
- <https://pub.dev/packages/timezone>
- <https://pub.dev/packages/flutter_timezone>

## 授权流程

`IOSInitializationSettings` 将 alert/badge/sound 的启动申请全部设为 `false`。App 启动不弹系统权限；通知设置页先解释用途，只有用户点击“开启通知”才调用 iOS 权限 API。拒绝后不影响手工记录和报告。

`AppDelegate` 将 `UNUserNotificationCenter.delegate` 设为 Flutter AppDelegate，使前台回调和 Darwin action 正常转发。本地通知使用当前 IANA 时区；时区读取失败时使用 `Asia/Shanghai` 安全回退。

## 通知类别与动作

`HEALTH_TASK` 类别提供“已完成”和“打开 App”。完成动作会按 payload 中的 task type 查找当日 pending 任务并调用正式 API；没有匹配任务则不写数据。第一版不实现容易引入重复调度的“稍后提醒”快捷动作。

固定本地通知仅包括晨重、训练和睡眠准备，使用非精确定时；不申请后台常驻或精确闹钟能力。需要最新服务器数据的提醒交给 Celery + PushProvider。

## 隐私与发布门禁

- 锁屏 payload 不放体检数值、疾病名、完整问题或照片路径。
- 本地通知不需要 APNs entitlement。真实远程推送仍需 Apple Team ID、Key ID、`.p8` Auth Key、正式 Bundle ID 和 Push Notifications capability。
- 无凭据时 `PUSH_PROVIDER=mock`；不把模拟投递冒充为 APNs 实机验收。
- TestFlight 前必须在真机验证：首次解释页、允许/拒绝、设置中撤权、跨时区、锁屏脱敏、快捷完成、勿扰和应用被终止后的定时通知。
