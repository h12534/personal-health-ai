import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}

