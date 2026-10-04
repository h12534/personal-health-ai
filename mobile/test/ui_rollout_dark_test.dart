import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';
import 'package:personal_health_os/core/theme/app_tokens.dart';
import 'package:personal_health_os/core/widgets/app_components.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  for (final dark in [false, true]) {
    final colors = dark ? AppColors.dark : AppColors.light;
    final theme = dark ? AppTheme.dark : AppTheme.light;
    test('all reading and interactive surfaces contrast dark=$dark', () {
      for (final background in [
        colors.background,
        colors.surface,
        colors.elevatedSurface,
        colors.softTint
      ]) {
        for (final text in [
          colors.primaryText,
          colors.secondaryText,
          colors.tertiaryText,
          colors.primary,
          colors.positive,
          colors.attention,
          colors.warning,
          colors.danger
        ]) {
          expect(contrast(text, background), greaterThanOrEqualTo(4.5),
              reason: '$text on $background');
        }
        expect(contrast(colors.accent, background), greaterThanOrEqualTo(3),
            reason: 'Accent is an icon tone, not ordinary body text.');
      }
      expect(theme.inputDecorationTheme.hintStyle!.color, colors.secondaryText);
      expect(theme.bottomSheetTheme.backgroundColor, colors.surface);
      expect(theme.dialogTheme.backgroundColor, colors.surface);
      expect(theme.scaffoldBackgroundColor, colors.background);
      expect(colors.background, isNot(Colors.black));
      expect(colors.background, isNot(colors.surface));
      expect(colors.surface, isNot(colors.elevatedSurface));
      final s = theme.colorScheme;
      for (final pair in [
        (s.primary, s.onPrimary),
        (s.error, s.onError),
        (s.secondaryContainer, s.onSecondaryContainer)
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    });
    testWidgets(
        'actual themed confirmation dialog dark=$dark retains action and safe error',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('记录晨重'),
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => NumberEntryDialog(
                              title: '记录今日晨重',
                              initialValue: '98.6',
                              unit: 'kg',
                              onSave: (_) async {
                                throw StateError('secret');
                              })))))));
      await tester.tap(find.text('记录晨重'));
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(find
          .descendant(
              of: find.byType(AlertDialog), matching: find.byType(Material))
          .first);
      expect(material.color, colors.surface);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('重试保存'), findsOneWidget);
      expect(find.text('secret'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
