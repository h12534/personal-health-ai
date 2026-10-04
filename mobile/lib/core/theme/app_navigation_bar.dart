import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Platform tab-bar structure, one outlined icon family, no selection capsule.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar(
      {super.key, required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        elevation: AppElevation.flat,
        backgroundColor: AppColors.of(context).surface,
        selectedItemColor: AppColors.of(context).primary,
        unselectedItemColor: AppColors.of(context).secondaryText,
        selectedFontSize: AppTypography.caption.fontSize!,
        unselectedFontSize: AppTypography.caption.fontSize!,
        iconSize: AppIconSize.navigation,
        onTap: onSelect,
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
      );
}
