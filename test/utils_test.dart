import 'package:flutter_test/flutter_test.dart';
import 'package:chathalis/core/strings.dart';
import 'package:chathalis/core/utils.dart';

void main() {
  group('HalisUtils.titleFrom', () {
    test('uses the first non-empty line, whitespace collapsed', () {
      expect(
        HalisUtils.titleFrom('  Giúp tôi\nviết thư\n'),
        'Giúp tôi',
      );
    });

    test('skips leading blank lines', () {
      expect(
        HalisUtils.titleFrom('\n\n\nLên kế hoạch du lịch Huế và nhiều thứ khác'),
        'Lên kế hoạch du lịch Huế và nhiều thứ khác',
      );
    });

    test('cuts at a word boundary and adds an ellipsis', () {
      final title = HalisUtils.titleFrom('a ' * 60, max: 48);
      expect(title.length, lessThanOrEqualTo(49));
      expect(title.endsWith('…'), isTrue);
      expect(title.endsWith(' …'), isFalse); // no dangling space before the ellipsis
    });
  });

  group('HalisUtils.previewOf', () {
    test('flattens newlines and truncates', () {
      final p = HalisUtils.previewOf('dòng 1\ndòng 2 ' * 40, max: 40);
      expect(p.contains('\n'), isFalse);
      expect(p.length, lessThanOrEqualTo(41));
      expect(p.endsWith('…'), isTrue);
    });
  });

  group('HalisUtils.dayGroup', () {
    final now = DateTime(2026, 10, 23, 15, 0);

    test('buckets by recency', () {
      expect(HalisUtils.dayGroup(DateTime(2026, 10, 23, 9), now), 'today');
      expect(HalisUtils.dayGroup(DateTime(2026, 10, 22, 23), now), 'yesterday');
      expect(HalisUtils.dayGroup(DateTime(2026, 10, 19), now), 'last7');
      expect(HalisUtils.dayGroup(DateTime(2026, 9, 30), now), 'earlier');
    });
  });

  group('HalisUtils.shortDate', () {
    final now = DateTime(2026, 10, 23, 15, 0);
    final en = Strings.of(AppLocale.english);
    final vi = Strings.of(AppLocale.vietnamese);

    test('clock time for today', () {
      expect(HalisUtils.shortDate(DateTime(2026, 10, 23, 9, 5), en, now), '09:05');
    });

    test('yesterday label is localized', () {
      expect(HalisUtils.shortDate(DateTime(2026, 10, 22, 23), en, now), 'Yesterday');
      expect(HalisUtils.shortDate(DateTime(2026, 10, 22, 23), vi, now), 'Hôm qua');
    });

    test('weekday label is localized', () {
      // 2026-10-21 is a Wednesday.
      expect(HalisUtils.shortDate(DateTime(2026, 10, 21), en, now), 'Wed');
      expect(HalisUtils.shortDate(DateTime(2026, 10, 21), vi, now), 'T4');
    });
  });

  group('HalisUtils.uuid', () {
    test('produces valid v4 shape', () {
      final re = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      for (var i = 0; i < 50; i++) {
        expect(HalisUtils.uuid(), matches(re));
      }
    });
  });

  group('Strings', () {
    test('the Vietnamese output-limit notice stays exact', () {
      expect(
        Strings.of(AppLocale.vietnamese).truncatedNotice,
        'câu trả lời này đã bị ngắt vì đạt giới hạn đầu ra',
      );
    });

    test('english is the default bundle', () {
      expect(Strings.of(AppLocale.english).settings, 'Settings');
      expect(Strings.of(AppLocale.english).untitledConversation, 'Untitled chat');
    });

    test('bundles are cached per locale', () {
      expect(identical(Strings.of(AppLocale.english), Strings.of(AppLocale.english)),
          isTrue);
    });

    test('thinking time is localized', () {
      expect(Strings.of(AppLocale.english).humanDuration(4200), '4s');
      expect(Strings.of(AppLocale.vietnamese).humanDuration(4200), '4 giây');
      expect(Strings.of(AppLocale.english).humanDuration(75_000), '1m 15 s');
      expect(Strings.of(AppLocale.vietnamese).humanDuration(75_000), '1 phút 15');
    });

    test('data counts pluralize in english', () {
      expect(Strings.of(AppLocale.english).dataCounts(1, 1), '1 conversation · 1 message');
      expect(Strings.of(AppLocale.english).dataCounts(3, 5), '3 conversations · 5 messages');
      expect(Strings.of(AppLocale.vietnamese).dataCounts(3, 5), '3 cuộc trò chuyện · 5 tin nhắn');
    });
  });
}
