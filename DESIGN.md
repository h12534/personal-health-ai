---
name: Personal Health OS
description: Quiet Premium Health Intelligence — data-forward, privately personal, gently warm.
colors:
  primary: "#176B60"
  accent: "#997445"
  positive: "#286C50"
  attention: "#896022"
  warning: "#925518"
  danger: "#AB3E41"
  background: "#F7F8F4"
  surface: "#FFFFFF"
  elevated-surface: "#EEF2ED"
  primary-text: "#182D29"
  secondary-text: "#53645D"
  tertiary-text: "#606E67"
  divider: "#DCE3DC"
  soft-tint: "#E6F1EB"
  dark-primary: "#8DD2BC"
  dark-accent: "#D2B58D"
  dark-positive: "#9BCBB0"
  dark-attention: "#E2BC7A"
  dark-warning: "#EBB389"
  dark-danger: "#F1A4A7"
  dark-background: "#111D1A"
  dark-surface: "#1A2924"
  dark-elevated-surface: "#24372F"
  dark-primary-text: "#EAF1E9"
  dark-secondary-text: "#B6C5BB"
  dark-tertiary-text: "#A0B2A7"
  dark-divider: "#384C41"
  dark-soft-tint: "#223D32"
typography:
  page-title:
    fontFamily: "system-ui"
    fontSize: "32px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.5px"
  hero-metric:
    fontFamily: "system-ui"
    fontSize: "48px"
    fontWeight: 500
    lineHeight: 1.1
    letterSpacing: "-1.2px"
  section-title:
    fontFamily: "system-ui"
    fontSize: "21px"
    fontWeight: 600
    lineHeight: 1.3
  card-title:
    fontFamily: "system-ui"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.35
  body:
    fontFamily: "system-ui"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.5
  secondary:
    fontFamily: "system-ui"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.45
  caption:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
  metric-label:
    fontFamily: "system-ui"
    fontSize: "15px"
    fontWeight: 500
    lineHeight: 1.4
  metric:
    fontFamily: "system-ui"
    fontSize: "26px"
    fontWeight: 500
    lineHeight: 1.2
rounded:
  small: "6px"
  medium: "10px"
  large: "12px"
  hero: "16px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  page: "20px"
  section: "24px"
  xl: "32px"
  xxl: "40px"
  wide: "48px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.medium}"
    height: "48px"
  button-tonal:
    backgroundColor: "{colors.soft-tint}"
    textColor: "{colors.primary}"
    rounded: "{rounded.medium}"
    height: "48px"
  input:
    backgroundColor: "{colors.elevated-surface}"
    textColor: "{colors.primary-text}"
    rounded: "{rounded.medium}"
  navigation:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    typography: "{typography.caption}"
  selected-segment:
    backgroundColor: "{colors.soft-tint}"
    textColor: "{colors.primary}"
    rounded: "{rounded.small}"
  metric-focus:
    backgroundColor: "{colors.soft-tint}"
    textColor: "{colors.primary-text}"
    rounded: "{rounded.hero}"
    padding: "24px"
---

# Design System: Personal Health OS

## Overview

Quiet Premium Health Intelligence. The confirmed direction is Data-forward Health Intelligence, with restrained Warm Personal Wellness. Clear evidence, a readable number, and personal context take priority over decoration. The product should feel private and dependable, not clinical, commercial, competitive, or administrative.

This document describes the implemented Flutter theme and Health Overview reference screen. Other pages currently inherit the theme but await page-by-page redesign. Source of truth: `mobile/lib/core/theme/app_tokens.dart`, `app_theme.dart`, and the health presentation widgets. Portable `px` values above correspond to Flutter logical pixels before text scaling, not physical screen pixels. The platform resolves its own system font; `system-ui` is a portable description, not a new runtime font override.

## Colors

### Primary

Deep teal anchors selected navigation, the primary metric, and actions. It is not a health score. Soft tint groups one primary interactive metric without giving every section a container.

### Secondary

Warm accent offers a restrained personal tone. Attention and danger communicate the report's existing flags, not newly inferred severity. Pair every state color with readable text and, where useful, one simple icon.

### Neutral

Warm off-white is the page foundation; a clean surface supports navigation and sheets. Elevated surface is tonal, not shadow-driven. Dark mode maintains the same information hierarchy using its corresponding semantic roles.

The Evidence Rule: report flags and reference context are authoritative; color must never invent a diagnosis or imply a conclusion unavailable in the data. Normal-size reference text and state text have automated minimum contrast checks of 4.5:1 against the tested surfaces. Disabled controls and decorative rules are separate cases.

## Typography

Use the platform system font, including the iOS system Latin and Chinese fallbacks. The production app does not bundle the screenshot test font. Page titles orient; the hero metric owns the first reading; unit, date, and report range remain subordinate but readable. Hero and metric roles use tabular figures.

Respect `MediaQuery.textScalerOf(context)`. Do not clamp Dynamic Type or hide content to fit. Long Chinese text wraps. Base typography above is not a fixed rendered size when accessibility scaling is enabled.

## Layout

Use the defined spacing scale. The reference page has open sections, one metric surface, then a dated trend, complete-report action, contextual AI entry, and a progressively disclosed safety notice. This is a reference composition, not a prohibition on all cards elsewhere.

Allow headers to wrap, charts to grow with text, and details to scroll. Respect SafeArea and the framework's bottom navigation inset. Keep actions at least (44 logical pixels) in each tap-target dimension. Icon sizes use the shared small, regular, and navigation roles (18 / 22 / 24 logical pixels).

## Elevation & Depth

Flat semantic surfaces separate content; cards and sheets use zero explicit elevation. No app-wide blur, expensive shader, strong Material shadow, or artificial depth. The current implementation has not been profiled on a physical iPhone; do not claim 60/120fps verification from a widget test.

## Shapes

Small radius marks selected segments; medium radius shapes buttons and fields; large radius supports ordinary surfaces; hero radius belongs to the main metric. Roundness is structural, not a reason to wrap every block or create large navigation capsules.

## Components

Buttons use the theme's minimum height; the frontmatter height is a minimum, not a text-clipping fixed height. Inputs are softly filled with an explicit focused outline. Bottom navigation is a stable five-destination solid surface, text plus one consistent outlined Material icon family, no pill indicator. This is native-feeling Flutter, not an SF Symbols claim.

MetricFocus presents name, current value, unit, report flag, date context, and report range. Its merged accessibility node includes an actual tap action. HealthMetricRow carries textual state. LabTrendChart positions data by real date, filters incompatible units/non-finite values, uses a zero-origin positive-value scale with sparse grid rules, and exposes a readable point selector. It does not draw reference lines for unavailable ranges or infer medical trends.

Loading is static skeleton plus explanatory text; no shimmering attention demand. Empty/error states offer the existing upload/retry path. Unconfirmed OCR drafts are separate from confirmed report evidence. Offline freshness is not fabricated when its metadata is unavailable.

Programmatic tab changes use the shared short transition and resolve to zero duration for Reduce Motion. Bottom destination changes use selection haptic only when the selected destination actually changes. New hero-expansion or chart animation is not claimed. The sidecar browser snippets illustrate these components; they are not the Flutter implementation.

## Do's and Don'ts

- Do foreground real numbers, their units, dates, source context, and report ranges.
- Do use semantic colors, named typography, the spacing/radius scale, and one icon language.
- Do make state text and accessibility actions useful without seeing color.
- Do keep the same hierarchy in light and dark mode and test large Chinese text.
- Don't invent health scores, weekly status, trend conclusions, freshness, or AI output.
- Don't use nested cards, outlines everywhere, oversized navigation capsules, fluorescent green, purple AI gradients, or gamification.
- Don't sacrifice tap targets, text scaling, or known medical boundaries for a screenshot.
- Don't treat browser screenshots or Windows test-engine goldens as physical iPhone acceptance.
