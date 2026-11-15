import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class AniTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AniColors.olive,
      onPrimary: AniColors.paper,
      primaryContainer: AniColors.statusNormalBg,
      onPrimaryContainer: AniColors.oliveDark,
      secondary: AniColors.gold,
      onSecondary: AniColors.paper,
      secondaryContainer: AniColors.statusBantayBg,
      onSecondaryContainer: AniColors.ink,
      tertiary: AniColors.sand,
      onTertiary: AniColors.ink,
      error: AniColors.statusDelikado,
      onError: AniColors.paper,
      surface: AniColors.paper,
      onSurface: AniColors.ink,
      onSurfaceVariant: AniColors.muted,
      surfaceContainerLowest: AniColors.paper,
      surfaceContainerLow: AniColors.paper,
      surfaceContainer: AniColors.cream,
      surfaceContainerHigh: AniColors.cream,
      surfaceContainerHighest: AniColors.sand,
      outline: AniColors.sand,
      outlineVariant: AniColors.line,
    );

    // Sizes tuned for small phones and readability outdoors; condensed face
    // lets us stay slightly larger than Material defaults.
    const textTheme = TextTheme(
      displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.1),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, height: 1.25),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
      titleSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
      bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, height: 1.4),
      bodyMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.4),
      bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.35),
      labelLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.2),
      labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2),
      labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 1.2),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: aniFontFamily,
      scaffoldBackgroundColor: AniColors.cream,
      canvasColor: AniColors.cream,
      dividerColor: AniColors.line,
      splashFactory: InkRipple.splashFactory,
    );

    final text = base.textTheme
        .merge(textTheme)
        .apply(bodyColor: AniColors.ink, displayColor: AniColors.ink, fontFamily: aniFontFamily);

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: AniColors.cream,
        foregroundColor: AniColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: const CardThemeData(
        color: AniColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AniRadius.card,
          side: BorderSide(color: AniColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AniColors.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AniColors.olive,
          foregroundColor: AniColors.paper,
          disabledBackgroundColor: AniColors.sand,
          disabledForegroundColor: AniColors.muted,
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: AniRadius.button),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AniColors.olive,
          side: const BorderSide(color: AniColors.sand),
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(borderRadius: AniRadius.button),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AniColors.olive, textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AniColors.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: AniSpacing.lg, vertical: AniSpacing.md),
        border: const OutlineInputBorder(
          borderRadius: AniRadius.tile,
          borderSide: BorderSide(color: AniColors.line),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AniRadius.tile,
          borderSide: BorderSide(color: AniColors.line),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AniRadius.tile,
          borderSide: BorderSide(color: AniColors.olive, width: 2),
        ),
        hintStyle: text.bodyMedium?.copyWith(color: AniColors.muted),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AniColors.olive,
        linearTrackColor: AniColors.line,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AniColors.oliveDark,
        contentTextStyle: text.bodyMedium?.copyWith(color: AniColors.paper),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
