import 'package:flutter_test/flutter_test.dart';
import 'package:chathalis/engine/context_window.dart';
import 'package:chathalis/gateway/kilo_gateway.dart';
import 'package:chathalis/gateway/models.dart';
import 'package:chathalis/prompt/system_prompt.dart';

ChatMessage _msg(Role role, String content) => ChatMessage(
      id: '${role.name}-${DateTime.now().microsecondsSinceEpoch}-$content',
      role: role,
      content: content,
      createdAt: DateTime.now(),
    );

void main() {
  group('composeApiMessages', () {
    test('system prompt always leads, identity core intact', () {
      final out = composeApiMessages([_msg(Role.user, 'xin chào')]);
      expect(out.first.role, Role.system);
      expect(out.first.content, contains(HalisPrompt.identity));
      expect(out.first.content, contains('Today is'));
      expect(out, hasLength(2));
    });

    test('keeps conversation order (oldest → newest)', () {
      final out = composeApiMessages([
        _msg(Role.user, 'câu 1'),
        _msg(Role.assistant, 'trả lời 1'),
        _msg(Role.user, 'câu 2'),
      ]);
      expect(out.map((m) => m.role).toList(),
          [Role.system, Role.user, Role.assistant, Role.user]);
      expect(out[1].content, 'câu 1');
      expect(out[3].content, 'câu 2');
    });

    test('drops empty assistant turns but keeps interrupted partials', () {
      final interrupted = _msg(Role.assistant, 'trả lời dở');
      interrupted.state = MessageState.interrupted;
      final out = composeApiMessages([
        _msg(Role.user, 'câu 1'),
        _msg(Role.assistant, ''),
        interrupted,
        _msg(Role.user, 'tiếp đi'),
      ]);
      expect(out.map((m) => m.content),
          containsAll(['câu 1', 'trả lời dở', 'tiếp đi']));
      expect(out.where((m) => m.content.isEmpty), isEmpty);
    });

    test('trims oldest turns when the budget overflows', () {
      // ~1 token per 3.8 chars; make each turn cost ~10 tokens.
      final turn = 'x' * 30; // 8 tokens + 4 overhead ≈ 12
      final messages = <ChatMessage>[
        for (var i = 0; i < 10; i++) ...[
          _msg(Role.user, '$turn $i'),
          _msg(Role.assistant, '$turn $i'),
        ],
      ];
      final out = composeApiMessages(messages, budget: 60);
      // System + as many recent turns as fit, oldest ones dropped.
      expect(out.first.role, Role.system);
      expect(out.length, lessThan(messages.length + 1));
      expect(out.last.content, contains('9'));
      // The very first user message must have been dropped.
      expect(out.where((m) => m.content == '$turn 0'), isEmpty);
    });

    test('reasoning text is never replayed', () {
      final m = _msg(Role.assistant, 'short');
      m.reasoning = 'chuyện suy nghĩ bên trong' * 500;
      final out = composeApiMessages([_msg(Role.user, 'q'), m]);
      expect(out.last.content, 'short');
      expect(out.any((x) => x.content.contains('suy nghĩ')), isFalse);
    });

    test('tool traffic is appended after the replayed history', () {
      final tail = [
        ApiMessage.toolRequest(
          content: '',
          toolCalls: const [
            ToolCall(id: 'c1', name: 'websearch', arguments: '{"query":"x"}'),
          ],
        ),
        ApiMessage.toolResult(callId: 'c1', content: '1. [A](https://a)\nhi'),
      ];
      final out = composeApiMessages(
        [_msg(Role.user, 'hôm nay thời tiết thế nào?')],
        tail: tail,
      );
      expect(out.last.role, Role.tool);
      expect(out.last.toolCallId, 'c1');
      expect(out[out.length - 2].toolCalls, isNotEmpty);
      expect(out[out.length - 2].role, Role.assistant);
    });

    test('32k output cap is the configured max of the gateway client', () {
      expect(KiloGateway.maxOutputTokens, 32768);
    });
  });
}
