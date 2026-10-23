import 'dart:math';

import 'strings.dart';

/// Small helpers shared across the app.
///
/// Anything that produces user-visible text takes the [Strings] bundle so
/// wording stays with the active locale; utilities here stay mechanical.
abstract final class HalisUtils {
  /// Cryptographically-random UUID v4.
  static String uuid() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    final h = b.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// `14:05` style clock time.
  static String clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Short label for a conversation tile: `14:05` today, `Wed` this week,
  /// `12/03` this year, `12/03/2025` otherwise.
  static String shortDate(DateTime t, Strings s, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(t.year, t.month, t.day);
    final diffDays = today.difference(day).inDays;
    if (diffDays <= 0) return clock(t);
    if (diffDays == 1) return s.yesterday;
    if (diffDays < 7) return s.weekdayShort(t.weekday);
    final d = t.day.toString().padLeft(2, '0');
    final m = t.month.toString().padLeft(2, '0');
    if (t.year == n.year) return '$d/$m';
    return '$d/$m/${t.year}';
  }

  /// Group key used to bucket conversations on the home screen.
  static String dayGroup(DateTime t, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final diffDays = DateTime(n.year, n.month, n.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    if (diffDays <= 0) return 'today';
    if (diffDays == 1) return 'yesterday';
    if (diffDays < 7) return 'last7';
    return 'earlier';
  }

  /// Turns the first user message into a compact conversation title,
  /// cutting at a word boundary.
  static String titleFrom(String text, {int max = 48}) {
    final firstLine =
        text.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final compact =
        firstLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= max) return compact;
    final cut = compact.substring(0, max);
    final lastSpace = cut.lastIndexOf(' ');
    return '${(lastSpace > max ~/ 2 ? cut.substring(0, lastSpace) : cut).trimRight()}…';
  }

  /// One-line preview for the home list.
  static String previewOf(String text, {int max = 90}) {
    final flat = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max).trimRight()}…';
  }
}
