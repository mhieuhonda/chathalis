import 'package:flutter_test/flutter_test.dart';
import 'package:chathalis/gateway/sse.dart';

void main() {
  group('SseDecoder', () {
    test('decodes single complete frame', () {
      final d = SseDecoder();
      expect(
        d.push('data: {"a":1}\n\n'),
        ['{"a":1}'],
      );
    });

    test('reassembles frames split across chunks', () {
      final d = SseDecoder();
      expect(d.push('data: {"hel'), isEmpty);
      expect(d.push('lo":"wörld"}\n'), ['{"hello":"wörld"}']);
    });

    test('emits several frames from one chunk', () {
      final d = SseDecoder();
      expect(
        d.push('data: one\n\ndata: two\n\ndata: three\n\n'),
        ['one', 'two', 'three'],
      );
    });

    test('handles CRLF line endings', () {
      final d = SseDecoder();
      expect(
        d.push('data: crlf\r\n\r\n'),
        ['crlf'],
      );
    });

    test('ignores comments, event and id lines', () {
      final d = SseDecoder();
      expect(
        d.push(': keepalive\nid: 7\nevent: x\ndata: payload\n\n'),
        ['payload'],
      );
    });

    test('keeps the sentinel DONE frame', () {
      final d = SseDecoder();
      expect(d.push('data: [DONE]\n\n'), ['[DONE]']);
    });

    test('accepts data without space after colon', () {
      final d = SseDecoder();
      expect(d.push('data:nospace\n'), ['nospace']);
    });

    test('drops empty data lines, flushes unterminated tail on close', () {
      final d = SseDecoder();
      expect(d.push('data: \n'), isEmpty);
      expect(d.push('data: tail'), isEmpty);
      expect(d.close(), ['tail']);
    });

    test('multiline chunk boundaries inside one frame', () {
      final d = SseDecoder();
      final out = <String>[];
      out.addAll(d.push('data: {"partial":'));
      out.addAll(d.push(' true}\ndata: next\n\n'));
      expect(out, ['{"partial": true}', 'next']);
    });
  });
}
