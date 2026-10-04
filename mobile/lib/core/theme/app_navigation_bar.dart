import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Platform tab-bar structure, one outlined icon family, no selection capsule.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar(
      {super.key, required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    // The framework clamps its internal label scaler; scale the base role here.
    final labelSize =
        MediaQuery.textScalerOf(context).scale(AppTypography.caption.fontSize!);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '主导航',
      child: BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        elevation: AppElevation.flat,
        backgroundColor: AppColors.of(context).surface,
        selectedItemColor: AppColors.of(context).primary,
        unselectedItemColor: AppColors.of(context).secondaryText,
        selectedFontSize: labelSize,
        unselectedFontSize: labelSize,
        selectedLabelStyle: AppTypography.caption
            .copyWith(fontSize: labelSize, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            AppTypography.caption.copyWith(fontSize: labelSize),
        iconSize: AppIconSize.navigation,
        onTap: onSelect,
        enableFeedback: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '首页'),
          BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_outlined), label: '饮食'),
          BottomNavigationBarItem(
              icon: Icon(Icons.fitness_center_outlined), label: '训练'),
          BottomNavigationBarItem(
              icon: Icon(Icons.health_and_safety_outlined), label: '健康'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}
