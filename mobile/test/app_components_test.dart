import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/network/api_exception.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';

void main() {
  test('safe errors distinguish known codes and never expose raw content', () {
    expect(
        UiFailure.title(
            const ApiException('secret', code: 'ai_not_configured')),
        'AI 暂不可用');
    expect(
        UiFailure.title(
            const ApiException('secret', code: 'invalid_access_token')),
        '登录状态需要更新');
    expect(UiFailure.title(const ApiException('无法连接服务器，请检查网络和 API 地址。')),
        '连接暂不可用');
    expect(UiFailure.message(StateError('secret')), isNot(contains('secret')));
  });
  test('dates and tabular display values use explicit decimal policy', () {
    expect(AppFormat.number(98.6, decimals: 1), '98.6');
    expect(AppFormat.number(7420, grouped: true), '7,420');
    expect(AppFormat.date(DateTime(2026, 9, 28)), '9月28日');
    expect(AppFormat.time(DateTime(2026, 9, 28, 14, 3)), '14:03');
  });
  testWidgets('unknown or zero target is not represented as 0 percent',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
            body: ProgressMetric(
                label: '步数',
                value: '暂无数据',
                amount: null,
                target: 0,
                unit: '步'))));
    expect(find.text('目标待设置'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('static skeleton settles with Reduce Motion', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: const Scaffold(body: LoadingState())));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
