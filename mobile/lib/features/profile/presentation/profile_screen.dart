import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../../core/network/api_client.dart';
import 'health_sync_screen.dart';
import '../../supervision/presentation/supervision_screens.dart';

final visionPrivacyProvider = FutureProvider<VisionPrivacySettings>((ref) {
  return ref.watch(apiClientProvider).fetchVisionPrivacy();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(visionPrivacyProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('我的', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        const ListTile(
          leading: Icon(Icons.badge_outlined),
          title: Text('身体与健康档案'),
          subtitle: Text('身高、目标、饮食环境与训练条件'),
        ),
        const ListTile(
          leading: Icon(Icons.monitor_heart_outlined),
          title: Text('体重趋势'),
          subtitle: Text('7 日均值与连续趋势'),
        ),
        ListTile(
          leading: Icon(Icons.settings_outlined),
          title: const Text('健康同步'),
          subtitle: const Text('Apple Health · 按数据类型分别控制'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const HealthSyncScreen(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('通知设置'),
          subtitle: const Text('提醒强度、时间、勿扰与本地通知'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const NotificationSettingsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.summarize_outlined),
          title: const Text('日报 / 周报 / 月报'),
          subtitle: const Text('结构化趋势与温和的下一步建议'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const ReportsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.timeline_outlined),
          title: const Text('健康时间线'),
          subtitle: const Text('身体、饮食、训练和体检的统一记录'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const HealthTimelineScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.event_repeat_outlined),
          title: const Text('健康复查'),
          subtitle: const Text('只有你确认后才创建复查任务'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const FollowupsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('隐私锁与数据'),
          subtitle: const Text('Face ID / Touch ID、导出和删除'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const PrivacyDataScreen()),
        ),
        Card(
          child: privacy.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: LinearProgressIndicator(),
            ),
            error: (_, __) => ListTile(
              title: const Text('无法加载图片隐私设置'),
              trailing: IconButton(
                onPressed: () => ref.invalidate(visionPrivacyProvider),
                icon: const Icon(Icons.refresh),
              ),
            ),
            data: (settings) => Column(
              children: [
                SwitchListTile(
                  value: settings.allowThirdParty,
                  title: const Text('允许第三方视觉服务分析餐食照片'),
                  subtitle: const Text('关闭时不会把餐食图片发送给远程第三方 AI 服务。'),
                  onChanged: (value) => _setThirdPartyVision(
                    context,
                    ref,
                    settings,
                    value,
                  ),
                ),
                SwitchListTile(
                  value: settings.retainImages,
                  title: const Text('长期保留已上传餐食图片'),
                  subtitle: const Text('关闭时按服务端保留期自动删除；营养记录不会删除。'),
                  onChanged: (value) => _updatePrivacy(
                    context,
                    ref,
                    VisionPrivacySettings(
                      allowThirdParty: settings.allowThirdParty,
                      retainImages: value,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _setThirdPartyVision(
    BuildContext context,
    WidgetRef ref,
    VisionPrivacySettings current,
    bool value,
  ) async {
    if (value && !current.allowThirdParty) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('启用第三方图片识别？'),
          content: const Text(
            '启用后，餐食图片会发送给服务器配置的第三方 AI 服务商进行菜品与份量识别。'
            '图片仅生成可编辑草稿，API Key 始终保留在服务器。你可以随时关闭此权限。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不启用'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('同意并启用'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    if (!context.mounted) return;
    await _updatePrivacy(
      context,
      ref,
      VisionPrivacySettings(
        allowThirdParty: value,
        retainImages: current.retainImages,
      ),
    );
  }

  Future<void> _updatePrivacy(
    BuildContext context,
    WidgetRef ref,
    VisionPrivacySettings settings,
  ) async {
    try {
      await ref.read(apiClientProvider).updateVisionPrivacy(settings);
      ref.invalidate(visionPrivacyProvider);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('隐私设置保存失败，请检查网络后重试。')),
        );
      }
    }
  }
}
