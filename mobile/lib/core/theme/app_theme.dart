import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: colors.primary, brightness: brightness)
            .copyWith(
      primary: colors.primary,
      onPrimary:
          brightness == Brightness.dark ? colors.background : colors.surface,
      secondary: colors.primary,
      onSecondary:
          brightness == Brightness.dark ? colors.background : colors.surface,
      secondaryContainer: colors.softTint,
      onSecondaryContainer: colors.primary,
      surface: colors.background,
      onSurface: colors.primaryText,
      onSurfaceVariant: colors.secondaryText,
      primaryContainer: colors.softTint,
      onPrimaryContainer: colors.primaryText,
      surfaceContainerLow: colors.surface,
      surfaceContainerHighest: colors.elevatedSurface,
      outlineVariant: colors.divider,
      error: colors.danger,
      onError:
          brightness == Brightness.dark ? colors.background : colors.surface,
    );
    final rounded = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large));
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [colors],
      textTheme: AppTypography.textTheme,
      scaffoldBackgroundColor: colors.background,
      dividerColor: colors.divider,
      cardTheme: CardThemeData(
        elevation: AppElevation.flat,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        shape: rounded,
      ),
      appBarTheme: AppBarTheme(
          backgroundColor: colors.background,
          foregroundColor: colors.primaryText,
          elevation: 0,
          scrolledUnderElevation: 0),
      iconTheme: IconThemeData(
          color: colors.secondaryText, size: AppIconSize.standard),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize:
            const Size(AppComponentSize.minTouch, AppComponentSize.button),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium)),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              minimumSize: const Size(
                  AppComponentSize.minTouch, AppComponentSize.minTouch))),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              minimumSize: const Size(
                  AppComponentSize.minTouch, AppComponentSize.minTouch))),
      chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.small)),
          side: BorderSide.none,
          selectedColor: colors.softTint),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle:
            AppTypography.secondary.copyWith(color: colors.secondaryText),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            borderSide: BorderSide(color: colors.primary)),
        fillColor: colors.elevatedSurface,
        filled: true,
      ),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: colors.surface,
          elevation: AppElevation.sheet,
          showDragHandle: true),
    );
  }
}
