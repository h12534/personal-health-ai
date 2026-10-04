import 'package:flutter/material.dart';

/// Semantic appearances. Only this file owns primitive palette values.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.accent,
    required this.positive,
    required this.attention,
    required this.warning,
    required this.danger,
    required this.background,
    required this.surface,
    required this.elevatedSurface,
    required this.primaryText,
    required this.secondaryText,
    required this.tertiaryText,
    required this.divider,
    required this.softTint,
  });

  final Color primary, accent, positive, attention, warning, danger;
  final Color background, surface, elevatedSurface;
  final Color primaryText, secondaryText, tertiaryText, divider, softTint;

  static const light = AppColors(
    primary: Color(0xFF176B60),
    accent: Color(0xFF997445),
    positive: Color(0xFF286C50),
    attention: Color(0xFF896022),
    warning: Color(0xFF925518),
    danger: Color(0xFFAB3E41),
    background: Color(0xFFF7F8F4),
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color(0xFFEEF2ED),
    primaryText: Color(0xFF182D29),
    secondaryText: Color(0xFF53645D),
    tertiaryText: Color(0xFF606E67),
    divider: Color(0xFFDCE3DC),
    softTint: Color(0xFFE6F1EB),
  );

  static const dark = AppColors(
    primary: Color(0xFF8DD2BC),
    accent: Color(0xFFD2B58D),
    positive: Color(0xFF9BCBB0),
    attention: Color(0xFFE2BC7A),
    warning: Color(0xFFEBB389),
    danger: Color(0xFFF1A4A7),
    background: Color(0xFF111D1A),
    surface: Color(0xFF1A2924),
    elevatedSurface: Color(0xFF24372F),
    primaryText: Color(0xFFEAF1E9),
    secondaryText: Color(0xFFB6C5BB),
    tertiaryText: Color(0xFFA0B2A7),
    divider: Color(0xFF384C41),
    softTint: Color(0xFF223D32),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AppColors copyWith({Color? primary, Color? surface}) => AppColors(
        primary: primary ?? this.primary,
        accent: accent,
        positive: positive,
        attention: attention,
        warning: warning,
        danger: danger,
        background: background,
        surface: surface ?? this.surface,
        elevatedSurface: elevatedSurface,
        primaryText: primaryText,
        secondaryText: secondaryText,
        tertiaryText: tertiaryText,
        divider: divider,
        softTint: softTint,
      );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: mix(primary, other.primary),
      accent: mix(accent, other.accent),
      positive: mix(positive, other.positive),
      attention: mix(attention, other.attention),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      elevatedSurface: mix(elevatedSurface, other.elevatedSurface),
      primaryText: mix(primaryText, other.primaryText),
      secondaryText: mix(secondaryText, other.secondaryText),
      tertiaryText: mix(tertiaryText, other.tertiaryText),
      divider: mix(divider, other.divider),
      softTint: mix(softTint, other.softTint),
    );
  }
}

abstract final class AppTypography {
  static const pageTitle = TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: -.5);
  static const heroMetric = TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w500,
      height: 1.1,
      letterSpacing: -1.2,
      fontFeatures: [FontFeature.tabularFigures()]);
  static const sectionTitle =
      TextStyle(fontSize: 21, fontWeight: FontWeight.w600, height: 1.3);
  static const cardTitle =
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35);
  static const body =
      TextStyle(fontSize: 17, fontWeight: FontWeight.w400, height: 1.5);
  static const secondary =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45);
  static const caption =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4);
  static const metricLabel =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4);
  static const metric = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w500,
      height: 1.2,
      fontFeatures: [FontFeature.tabularFigures()]);

  static TextTheme get textTheme => const TextTheme(
        displayLarge: heroMetric,
        headlineMedium: pageTitle,
        headlineSmall: sectionTitle,
        titleLarge: sectionTitle,
        titleMedium: cardTitle,
        bodyLarge: body,
        bodyMedium: secondary,
        bodySmall: caption,
        labelLarge: cardTitle,
        labelMedium: metricLabel,
        labelSmall: caption,
      );
}

abstract final class AppSpacing {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0;
  static const page = 20.0, section = 24.0, xl = 32.0, xxl = 40.0, wide = 48.0;
  static const pageInsets = EdgeInsets.fromLTRB(page, lg, page, xl);
}

abstract final class AppRadius {
  static const small = 6.0, medium = 10.0, large = 12.0, hero = 16.0;
}

abstract final class AppElevation {
  static const flat = 0.0, sheet = 0.0;
}

abstract final class AppMotion {
  static const feedback = Duration(milliseconds: 120);
  static const transition = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;
  static Duration duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : transition;
}

abstract final class AppIconSize {
  static const small = 18.0, standard = 22.0, navigation = 24.0;
}

abstract final class AppComponentSize {
  static const minTouch = 44.0, button = 48.0, tabBar = 64.0, chart = 132.0;
}
