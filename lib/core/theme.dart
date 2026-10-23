import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ChatHalis design tokens for one brightness.
///
/// The visual language is monochrome-editorial: a quiet paper canvas,
/// near-opposite ink, a single cool "Halis blue" accent and hairline
/// borders. Light is the product default; dark is the same language with
/// the values inverted — never a hue-for-hue swap.
@immutable
class HalisStyle extends ThemeExtension<HalisStyle> {
  const HalisStyle({
    required this.paper,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.surface,
    required this.hairline,
    required this.accent,
    required this.accentSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warn,
    required this.warnSoft,
    required this.codeBg,
    required this.codeFg,
    required this.codeMuted,
    required this.shadow,
  });

  /// Canvas background.
  final Color paper;

  /// Primary ink — text, user bubbles, primary actions.
  final Color ink;

  /// Secondary text.
  final Color inkSoft;

  /// Tertiary text — timestamps, hints, disabled states.
  final Color inkFaint;

  /// Raised neutral surface — thinking panel, composer, cards.
  final Color surface;

  /// 1px separators.
  final Color hairline;

  /// Halis blue — links, active states, focus, the wordmark dot.
  final Color accent;

  /// Tinted accent background.
  final Color accentSoft;

  /// Errors.
  final Color danger;
  final Color dangerSoft;

  /// Warnings — output-limit notices, near-limit usage.
  final Color warn;
  final Color warnSoft;

  /// Code blocks — deliberately dark in light mode, raised in dark.
  final Color codeBg;
  final Color codeFg;
  final Color codeMuted;

  /// Composer drop shadow.
  final Color shadow;

  /// Tokens for the light (default) look.
  static const HalisStyle light = HalisStyle(
    paper: Color(0xFFFFFFFF),
    ink: Color(0xFF111114),
    inkSoft: Color(0xFF6E6E76),
    inkFaint: Color(0xFFA8A8B0),
    surface: Color(0xFFF6F6F7),
    hairline: Color(0xFFE9E9EC),
    accent: Color(0xFF2B50E0),
    accentSoft: Color(0xFFEEF1FE),
    danger: Color(0xFFD93025),
    dangerSoft: Color(0xFFFDF0EF),
    warn: Color(0xFFB45309),
    warnSoft: Color(0xFFFCF4E9),
    codeBg: Color(0xFF0E0E11),
    codeFg: Color(0xFFE8E8ED),
    codeMuted: Color(0xFF8B8B95),
    shadow: Color(0x0D111114),
  );

  /// Tokens for the dark look — same geometry, inverted values.
  static const HalisStyle dark = HalisStyle(
    paper: Color(0xFF0E0E11),
    ink: Color(0xFFECECF1),
    inkSoft: Color(0xFFA2A2AC),
    inkFaint: Color(0xFF666670),
    surface: Color(0xFF17171B),
    hairline: Color(0xFF26262C),
    accent: Color(0xFF6C87F5),
    accentSoft: Color(0xFF1B2337),
    danger: Color(0xFFEF6A56),
    dangerSoft: Color(0xFF2A1714),
    warn: Color(0xFFEBA55B),
    warnSoft: Color(0xFF2A1F12),
    codeBg: Color(0xFF16161C),
    codeFg: Color(0xFFE8E8ED),
    codeMuted: Color(0xFF8B8B95),
    shadow: Color(0x66000000),
  );

  @override
  HalisStyle copyWith({
    Color? paper,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? surface,
    Color? hairline,
    Color? accent,
    Color? accentSoft,
    Color? danger,
    Color? dangerSoft,
    Color? warn,
    Color? warnSoft,
    Color? codeBg,
    Color? codeFg,
    Color? codeMuted,
    Color? shadow,
  }) =>
      HalisStyle(
        paper: paper ?? this.paper,
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        inkFaint: inkFaint ?? this.inkFaint,
        surface: surface ?? this.surface,
        hairline: hairline ?? this.hairline,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        danger: danger ?? this.danger,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        warn: warn ?? this.warn,
        warnSoft: warnSoft ?? this.warnSoft,
        codeBg: codeBg ?? this.codeBg,
        codeFg: codeFg ?? this.codeFg,
        codeMuted: codeMuted ?? this.codeMuted,
        shadow: shadow ?? this.shadow,
      );

  @override
  HalisStyle lerp(HalisStyle? other, double t) {
    if (other == null) return this;
    return HalisStyle(
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnSoft: Color.lerp(warnSoft, other.warnSoft, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeFg: Color.lerp(codeFg, other.codeFg, t)!,
      codeMuted: Color.lerp(codeMuted, other.codeMuted, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Reads the active [HalisStyle] from the material theme.
extension HalisStyleX on BuildContext {
  HalisStyle get halis => Theme.of(this).extension<HalisStyle>()!;
}

/// Builds the app-wide [ThemeData] on top of [HalisStyle].
abstract final class HalisTheme {
  static ThemeData light() => _build(Brightness.light, HalisStyle.light);

  static ThemeData dark() => _build(Brightness.dark, HalisStyle.dark);

  static ThemeData _build(Brightness brightness, HalisStyle s) {
    final isLight = brightness == Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      colorScheme: isLight
          ? ColorScheme.light(
              primary: s.ink,
              onPrimary: s.paper,
              secondary: s.inkSoft,
              onSecondary: s.paper,
              surface: s.paper,
              onSurface: s.ink,
              error: s.danger,
              onError: s.paper,
            )
          : ColorScheme.dark(
              primary: s.ink,
              onPrimary: s.paper,
              secondary: s.inkSoft,
              onSecondary: s.paper,
              surface: s.paper,
              onSurface: s.ink,
              error: s.danger,
              onError: s.paper,
            ),
      scaffoldBackgroundColor: s.paper,
      extensions: <ThemeExtension<dynamic>>[s],
    );

    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: s.paper,
        foregroundColor: s.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: s.paper,
          systemNavigationBarIconBrightness:
              isLight ? Brightness.dark : Brightness.light,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? s.paper : s.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? s.paper : s.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: isLight ? s.paper : s.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: s.ink,
        contentTextStyle: TextStyle(
          color: s.paper,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: s.hairline,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
