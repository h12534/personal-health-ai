import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../../core/network/api_client.dart';

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
        const ListTile(
          leading: Icon(Icons.settings_outlined),
          title: Text('提醒与隐私设置'),
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
