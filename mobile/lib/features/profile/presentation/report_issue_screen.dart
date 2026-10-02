import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/diagnostics/local_diagnostics.dart';

class ReportIssueScreen extends ConsumerStatefulWidget {
  const ReportIssueScreen({super.key});

  @override
  ConsumerState<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends ConsumerState<ReportIssueScreen> {
  final _summary = TextEditingController();
  String _category = 'bug';
  bool _includeDiagnostics = true;

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('报告问题')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: '问题类型'),
              items: const [
                DropdownMenuItem(value: 'bug', child: Text('Bug')),
                DropdownMenuItem(value: 'data', child: Text('数据错误')),
                DropdownMenuItem(value: 'ai', child: Text('AI 回答问题')),
                DropdownMenuItem(value: 'reminder', child: Text('提醒问题')),
                DropdownMenuItem(value: 'ui', child: Text('UI 问题')),
              ],
              onChanged: (value) => setState(() => _category = value ?? 'bug'),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('issue-summary'),
              controller: _summary,
              maxLength: 500,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '问题描述',
                hintText: '请勿填写 Token、密钥或完整健康报告正文。',
                alignLabelWithHint: true,
              ),
            ),
            CheckboxListTile(
              value: _includeDiagnostics,
              title: const Text('附加脱敏诊断上下文'),
              subtitle: const Text('只含版本、环境与本地错误类型，不含健康正文。'),
              onChanged: (value) =>
                  setState(() => _includeDiagnostics = value ?? false),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('copy-issue-report'),
              onPressed: _copy,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('生成并复制问题报告'),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Beta 阶段暂不自动上传；你可以检查内容后粘贴到私有 Issue。'),
            ),
          ],
        ),
      );

  Future<void> _copy() async {
    final summary = _summary.text.trim();
    if (summary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写问题描述')),
      );
      return;
    }
    final report = <String, Object?>{
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'category': _category,
      'summary': summary,
      'app_version': AppConfig.appVersion,
      'build_number': AppConfig.buildNumber,
      'api_environment': AppConfig.apiEnvironment,
      if (_includeDiagnostics)
        'diagnostic_events': await ref.read(localDiagnosticsProvider).read(),
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('问题报告已复制，请检查后提交')),
      );
    }
  }
}
