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

  group('HalisUtils.humanDuration', () {
    test('formats thinking time in Vietnamese', () {
      expect(HalisUtils.humanDuration(300), '<1 giây');
      expect(HalisUtils.humanDuration(4200), '4 giây');
      expect(HalisUtils.humanDuration(75_000), '1 phút 15');
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

  group('HalisStrings', () {
    test('the output-limit notice is exact', () {
      expect(
        HalisStrings.truncatedNotice,
        'câu trả lời này đã bị ngắt vì đạt giới hạn đầu ra',
      );
    });
  });
}
