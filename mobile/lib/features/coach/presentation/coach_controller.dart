import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/coach_models.dart';

final coachOverviewProvider = FutureProvider<CoachOverviewModel>((ref) {
  return ref.watch(apiClientProvider).fetchCoachOverview();
});

final nextMealProvider = FutureProvider<NextMealPlanModel>((ref) {
  return ref.watch(apiClientProvider).fetchNextMeal();
});

final weightTrendProvider = FutureProvider<WeightTrendModel>((ref) {
  return ref.watch(apiClientProvider).fetchWeightTrend();
});

final canteensProvider = FutureProvider<List<CanteenModel>>((ref) {
  return ref.watch(apiClientProvider).fetchCanteens();
});

final savedMealsProvider = FutureProvider<List<SavedMealModel>>((ref) {
  return ref.watch(apiClientProvider).fetchSavedMeals();
});

final canteenRecommendationsProvider =
    FutureProvider<List<CanteenRecommendationModel>>((ref) {
  return ref.watch(apiClientProvider).fetchCanteenRecommendations();
});

final coachChatProvider =
    AsyncNotifierProvider<CoachChatController, List<CoachBubble>>(
  CoachChatController.new,
);

class CoachChatController extends AsyncNotifier<List<CoachBubble>> {
  String? _conversationId;

  @override
  Future<List<CoachBubble>> build() async => const [];

  Future<void> send(String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty || state.isLoading) return;
    final previous = state.valueOrNull ?? const <CoachBubble>[];
    state = AsyncData([
      ...previous,
      CoachBubble(text: message, fromUser: true),
    ]);
    try {
      final reply = await ref
          .read(apiClientProvider)
          .sendCoachMessage(message, conversationId: _conversationId);
      _conversationId = reply.conversationId;
      state = AsyncData([
        ...(state.valueOrNull ?? const <CoachBubble>[]),
        CoachBubble(
          text: reply.message,
          fromUser: false,
          actions: reply.actions,
          safetyNotice: reply.safetyNotice,
        ),
      ]);
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }
}

class AdjustmentController {
  const AdjustmentController(this.ref);

  final WidgetRef ref;

  Future<void> decide(String id, bool accept) async {
    await ref.read(apiClientProvider).decideDietAdjustment(id, accept);
    ref.invalidate(coachOverviewProvider);
  }
}
