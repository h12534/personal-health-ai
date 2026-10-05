import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/theme/app_navigation_bar.dart';
import 'package:personal_health_os/core/theme/app_theme.dart';

void main() {
  for (final width in [320.0, 393.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets(
          'navigation $width ${dark ? 'dark' : 'light'} scales and activates',
          (tester) async {
        final height = width == 320
            ? 568.0
            : width == 393
                ? 852.0
                : 932.0;
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final handle = tester.ensureSemantics();
        int? selected;
        try {
          await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 44, bottom: 34),
                  viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
                body: ListView.builder(
                    itemCount: 100,
                    itemBuilder: (_, index) => Text('合成内容 $index')),
                bottomNavigationBar: AppNavigationBar(
                    index: 3, onSelect: (value) => selected = value)),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final navRect = tester.getRect(find.byType(AppNavigationBar));
          expect(navRect.bottom, height);
          for (final label in ['首页', '饮食', '训练', '健康', '我的']) {
            expect(tester.getRect(find.text(label)).bottom,
                lessThanOrEqualTo(height - 34));
          }
          await tester.drag(find.byType(ListView), const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(AppNavigationBar)), navRect);
          final bar = tester
              .widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
          expect(bar.selectedFontSize, 26);
          expect(bar.selectedLabelStyle?.fontWeight, FontWeight.w600);
          expect(tester.getSize(find.text('首页')).height, greaterThan(26));
          for (final label in ['首页', '饮食', '训练', '健康', '我的']) {
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          final healthNode = tester.getSemantics(find.text('健康'));
          expect(healthNode.getSemanticsData().flagsCollection.isSelected,
              Tristate.isTrue);
          expect(healthNode.getSemanticsData().hasAction(SemanticsAction.tap),
              isTrue);
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await tester.tap(find.text('训练'));
          expect(selected, 2);
        } finally {
          handle.dispose();
        }
      });
    }
  }
}
