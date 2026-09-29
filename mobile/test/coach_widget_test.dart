import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/features/coach/data/coach_models.dart';
import 'package:personal_health_os/features/coach/presentation/coach_controller.dart';
import 'package:personal_health_os/features/coach/presentation/coach_screen.dart';

class _FakeCoachChat extends CoachChatController {
  @override
  Future<List<CoachBubble>> build() async => const [];
}

void main() {
  testWidgets('coach screen shows weekly trend and quick prompts',
      (tester) async {
    const overview = CoachOverviewModel(
      headline: '看趋势，不追逐单日波动。',
      observations: ['记录完整'],
      nextActions: ['继续执行'],
      trend: WeightTrendModel(
        direction: 'stable',
        plateau: false,
        plateauEligible: false,
        note: '数据不足，不判断平台期。',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coachOverviewProvider.overrideWith((ref) async => overview),
          coachChatProvider.overrideWith(_FakeCoachChat.new),
        ],
        child: const MaterialApp(home: Scaffold(body: CoachScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 饮食教练'), findsOneWidget);
    expect(find.text('本周趋势'), findsOneWidget);
    expect(find.text('数据不足，不判断平台期。'), findsOneWidget);
    expect(find.text('今天吃什么？'), findsOneWidget);
    expect(find.text('食堂怎么选？'), findsOneWidget);
    expect(find.text('打开食堂'), findsOneWidget);
  });
}
