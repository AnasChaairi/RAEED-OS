import 'package:flutter/material.dart';

/// RAEED colours, taken from the logo.
abstract final class RaeedColors {
  /// Main colour: buttons, selected tabs, links.
  static const blue = Color(0xFF0060CC);

  /// Sky gradient, for headers and illustrations only.
  static const skyStart = Color(0xFF0090FC);
  static const skyEnd = Color(0xFF00D8FC);

  /// Star orange, for highlights. Text on top of it is always [ink].
  static const starStart = Color(0xFFF0A800);
  static const starEnd = Color(0xFFF06C00);
  static const starSoft = Color(0xFFFFF4DA);

  static const ink = Color(0xFF0B2545);
  static const grey = Color(0xFF5A6B80);
  static const background = Color(0xFFF4F9FF);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFEAF3FD);
  static const line = Color(0xFFD7E4F2);
  static const error = Color(0xFFC2341D);

  static const sky = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [skyStart, skyEnd],
  );

  static const star = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [starStart, starEnd],
  );
}

abstract final class RaeedFonts {
  /// Titles.
  static const display = 'Baloo Bhaijaan 2';

  /// Everything else.
  static const body = 'IBM Plex Sans Arabic';
}

ThemeData buildRaeedTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RaeedColors.blue,
    primary: RaeedColors.blue,
    onPrimary: Colors.white,
    secondary: RaeedColors.starStart,
    onSecondary: RaeedColors.ink,
    surface: RaeedColors.surface,
    onSurface: RaeedColors.ink,
    onSurfaceVariant: RaeedColors.grey,
    outline: RaeedColors.line,
    error: RaeedColors.error,
  );

  const display = TextStyle(fontFamily: RaeedFonts.display, fontWeight: FontWeight.w700, color: RaeedColors.ink);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: RaeedFonts.body).textTheme;
  final textTheme = base
      .apply(bodyColor: RaeedColors.ink, displayColor: RaeedColors.ink)
      .copyWith(
        headlineLarge: display.copyWith(fontSize: 28, height: 1.3),
        headlineMedium: display.copyWith(fontSize: 24, height: 1.3),
        headlineSmall: display.copyWith(fontSize: 21, height: 1.3),
        titleLarge: display.copyWith(fontSize: 20, height: 1.3),
      );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: RaeedFonts.body,
    textTheme: textTheme,
    scaffoldBackgroundColor: RaeedColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: RaeedColors.background,
      foregroundColor: RaeedColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        textStyle: const TextStyle(fontFamily: RaeedFonts.body, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: RaeedFonts.body, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RaeedColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: RaeedColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: RaeedColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: RaeedColors.blue, width: 1.5)),
      labelStyle: const TextStyle(color: RaeedColors.grey),
      hintStyle: const TextStyle(color: RaeedColors.grey),
    ),
    cardTheme: CardThemeData(
      color: RaeedColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: RaeedColors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: RaeedColors.surface,
      indicatorColor: RaeedColors.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: RaeedFonts.body,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? RaeedColors.blue : RaeedColors.grey,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? RaeedColors.blue : RaeedColors.grey),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: RaeedColors.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
