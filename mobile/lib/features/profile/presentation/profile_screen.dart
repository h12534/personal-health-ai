import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/app_components.dart';
import '../../coach/presentation/coach_screen.dart';
import 'health_sync_screen.dart';
import 'beta_debug_screen.dart';
import 'report_issue_screen.dart';
import '../../supervision/presentation/supervision_screens.dart';

final visionPrivacyProvider = FutureProvider<VisionPrivacySettings>((ref) {
  return ref.watch(apiClientProvider).fetchVisionPrivacy();
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _privacySaving = false;
  bool _loggingOut = false;

  @override
  Widget build(BuildContext context) {
    final privacy = ref.watch(visionPrivacyProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const RootPageHeader(
            title: '我的', subtitle: '你的私人健康空间。同步、提醒与数据使用，由你决定。'),
        AppSection(
            title: '同步与提醒',
            child: Column(children: [
              ListTile(
                leading: Icon(Icons.settings_outlined),
                title: const Text('健康同步'),
                subtitle: const Text('Apple Health · 四类数据分别控制'),
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
                subtitle: const Text('提醒方式、时间与勿扰'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const NotificationSettingsScreen()),
              ),
            ])),
        AppSection(
            title: '健康记录',
            child: Column(children: [
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
            ])),
        AppSection(
            title: '你的教练',
            child: ListRow(
                title: 'AI 饮食教练',
                subtitle: '结合已有记录，理解下一步',
                icon: Icons.chat_bubble_outline,
                onTap: () => _open(context,
                    const Scaffold(body: SafeArea(child: CoachScreen()))))),
        AppSection(
            title: '隐私与数据',
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('App 锁与数据'),
                subtitle: const Text('Face ID / Touch ID、导出和删除'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const PrivacyDataScreen()),
              ),
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('餐食图片使用方式'),
                  children: [
                    privacy.when(
                      loading: () => const Text('正在读取图片隐私设置…'),
                      error: (error, _) => EmptyState(
                          title: '图片设置暂不可用',
                          message: UiFailure.message(error),
                          actionLabel: '重新读取图片设置',
                          onAction: () =>
                              ref.invalidate(visionPrivacyProvider)),
                      data: (settings) => Column(children: [
                        SwitchListTile(
                            value: settings.allowThirdParty,
                            title: const Text('允许第三方视觉分析餐食照片'),
                            subtitle: const Text('关闭时不向第三方 AI 发送餐食照片。'),
                            onChanged: _privacySaving
                                ? null
                                : (v) => _setThirdPartyVision(
                                    context, ref, settings, v)),
                        SwitchListTile(
                            value: settings.retainImages,
                            title: const Text('长期保留餐食图片'),
                            subtitle: const Text('关闭时按服务端保留期删除图片，不删除营养记录。'),
                            onChanged: _privacySaving
                                ? null
                                : (v) => _changeRetention(
                                    context, ref, settings, v)),
                        if (_privacySaving) const Text('正在保存图片使用选择…'),
                      ]),
                    ),
                  ]),
            ])),
        AppSection(
            title: '支持与账号',
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('报告问题'),
                subtitle: const Text('Bug、数据、AI、提醒或 UI 问题'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const ReportIssueScreen()),
              ),
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('高级与诊断'),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.developer_mode_outlined),
                      title: const Text('Beta 诊断'),
                      subtitle: const Text('版本、环境、同步、权限与服务状态'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, const BetaDebugScreen()),
                    )
                  ]),
            ])),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: _loggingOut ? null : _logout,
          icon: const Icon(Icons.logout),
          label: Text(_loggingOut ? '正在退出…' : '退出登录'),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('退出暂时无法完成，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _setThirdPartyVision(
    BuildContext context,
    WidgetRef ref,
    VisionPrivacySettings current,
    bool value,
  ) async {
    if (_privacySaving) return;
    setState(() => _privacySaving = true);
    try {
      if (value && !current.allowThirdParty) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
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
    } finally {
      if (mounted) setState(() => _privacySaving = false);
    }
  }

  Future<void> _changeRetention(BuildContext context, WidgetRef ref,
      VisionPrivacySettings current, bool value) async {
    if (_privacySaving) return;
    setState(() => _privacySaving = true);
    try {
      await _updatePrivacy(
          context,
          ref,
          VisionPrivacySettings(
              allowThirdParty: current.allowThirdParty, retainImages: value));
    } finally {
      if (mounted) setState(() => _privacySaving = false);
    }
  }

  Future<void> _updatePrivacy(
    BuildContext context,
    WidgetRef ref,
    VisionPrivacySettings settings,
  ) async {
    try {
      await ref.read(apiClientProvider).updateVisionPrivacy(settings);
      ref.invalidate(visionPrivacyProvider);
      if (!mounted) return;
      await ref.read(visionPrivacyProvider.future);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片设置结果暂时无法确认，请重新读取后再试。')),
        );
      }
    }
  }
}
