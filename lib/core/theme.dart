import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ChatHalis design tokens.
///
/// The visual language is monochrome-editorial: pure white paper, near-black
/// ink, a single cool "Halis blue" accent and hairline borders. Everything
/// else derives from these.
abstract final class HalisPalette {
  /// Pure white canvas.
  static const Color paper = Color(0xFFFFFFFF);

  /// Primary ink — text, user bubbles, primary actions.
  static const Color ink = Color(0xFF111114);

  /// Secondary text.
  static const Color inkSoft = Color(0xFF6E6E76);

  /// Tertiary text — timestamps, hints, disabled states.
  static const Color inkFaint = Color(0xFFA8A8B0);

  /// Raised neutral surface — thinking panel, composer, cards.
  static const Color surface = Color(0xFFF6F6F7);

  /// 1px separators.
  static const Color hairline = Color(0xFFE9E9EC);

  /// Halis blue — links, active states, focus, the wordmark dot.
  static const Color accent = Color(0xFF2B50E0);

  /// Tinted accent background.
  static const Color accentSoft = Color(0xFFEEF1FE);

  /// Errors.
  static const Color danger = Color(0xFFD93025);
  static const Color dangerSoft = Color(0xFFFDF0EF);

  /// Warnings — output-limit notices.
  static const Color warn = Color(0xFFB45309);
  static const Color warnSoft = Color(0xFFFCF4E9);

  /// Code blocks — the one deliberately dark surface.
  static const Color codeBg = Color(0xFF0E0E11);
  static const Color codeFg = Color(0xFFE8E8ED);
  static const Color codeMuted = Color(0xFF8B8B95);
}

/// Builds the app-wide [ThemeData] on top of [HalisPalette].
abstract final class HalisTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.light(
        primary: HalisPalette.ink,
        onPrimary: HalisPalette.paper,
        secondary: HalisPalette.inkSoft,
        onSecondary: HalisPalette.paper,
        surface: HalisPalette.paper,
        onSurface: HalisPalette.ink,
        error: HalisPalette.danger,
        onError: HalisPalette.paper,
      ),
      scaffoldBackgroundColor: HalisPalette.paper,
    );

    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: HalisPalette.paper,
        foregroundColor: HalisPalette.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: HalisPalette.paper,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: HalisPalette.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HalisPalette.paper,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: HalisPalette.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: HalisPalette.ink,
        contentTextStyle: TextStyle(
          color: HalisPalette.paper,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: HalisPalette.hairline,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
