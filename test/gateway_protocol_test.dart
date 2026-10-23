import 'package:flutter_test/flutter_test.dart';
import 'package:chathalis/gateway/kilo_gateway.dart';
import 'package:chathalis/gateway/models.dart';

void main() {
  group('GatewayProtocol', () {
    test('reasoning arrives via the `reasoning` dialect', () {
      final p = GatewayProtocol();
      final events = p.applyPayload(
        '{"choices":[{"index":0,"delta":{"content":"","role":"assistant",'
        '"reasoning":"The user wants"},"finish_reason":null}]}',
      );
      expect(events, hasLength(1));
      expect(events.first, isA<GatewayReasoningDelta>());
      expect((events.first as GatewayReasoningDelta).text, 'The user wants');
    });

    test('reasoning arrives via reasoning_content dialect', () {
      final p = GatewayProtocol();
      final events = p.applyPayload(
        '{"choices":[{"delta":{"reasoning_content":"hmm"}}]}',
      );
      expect((events.first as GatewayReasoningDelta).text, 'hmm');
    });

    test('reasoning arrives via reasoning_details array', () {
      final p = GatewayProtocol();
      final events = p.applyPayload(
        '{"choices":[{"delta":{"reasoning_details":['
        '{"type":"reasoning.text","text":"a","index":0},'
        '{"type":"reasoning.text","text":"b","index":0}]}}]}',
      );
      expect((events.first as GatewayReasoningDelta).text, 'ab');
    });

    test('text deltas flow through', () {
      final p = GatewayProtocol();
      final events = p.applyPayload(
        '{"choices":[{"delta":{"content":" sắc."}}]}',
      );
      expect((events.first as GatewayTextDelta).text, ' sắc.');
    });

    test('finish frame captures stop and usage', () {
      final p = GatewayProtocol();
      p.applyPayload(
        '{"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}',
      );
      p.applyPayload(
        '{"choices":[{"delta":{"content":""},"finish_reason":"stop"}],'
        '"usage":{"prompt_tokens":28,"completion_tokens":527,"total_tokens":555,'
        '"completion_tokens_details":{"reasoning_tokens":487}}}',
      );
      final finish = p.finish();
      expect(finish, hasLength(2));
      expect(finish.last, isA<GatewayDone>());
      expect((finish.last as GatewayDone).reason, FinishReason.stop);
      final usage = finish.first as GatewayUsageInfo;
      expect(usage.usage.promptTokens, 28);
      expect(usage.usage.completionTokens, 527);
      expect(usage.usage.reasoningTokens, 487);
    });

    test('finish_reason length maps to truncation', () {
      final p = GatewayProtocol();
      // Recorded live from the gateway when max_tokens clipped the turn.
      p.applyPayload(
        '{"choices":[{"index":0,"delta":{"content":"","role":"assistant",'
        '"reasoning":null},"finish_reason":"length",'
        '"native_finish_reason":"length"}]}',
      );
      p.applyPayload(
        '{"choices":[{"index":0,"delta":{"content":""},"finish_reason":"length"}],'
        '"usage":{"prompt_tokens":30,"completion_tokens":80,"total_tokens":110}}',
      );
      final finish = p.finish();
      expect((finish.last as GatewayDone).reason, FinishReason.length);
    });

    test('malformed frames are ignored, not fatal', () {
      final p = GatewayProtocol();
      expect(p.applyPayload('not json'), isEmpty);
      expect(p.applyPayload('{"nope": 1}'), isEmpty);
      expect(p.applyPayload('[1,2,3]'), isEmpty);
    });

    test('backend identity fields in the frame are ignored', () {
      // The router's frames leak the resolved backend model in `model`.
      // The protocol must swallow it — it is never surfaced in the product.
      final p = GatewayProtocol();
      final events = p.applyPayload(
        '{"id":"gen-1","object":"chat.completion.chunk",'
        '"model":"some-backend/free","provider":"SomeVendor",'
        '"choices":[{"delta":{"content":"hi"}}]}',
      );
      expect(events, hasLength(1));
      expect((events.first as GatewayTextDelta).text, 'hi');
    });

    test('missing finish_reason defaults to stop', () {
      final p = GatewayProtocol();
      final finish = p.finish();
      expect((finish.last as GatewayDone).reason, FinishReason.stop);
    });

    test('tool call fragments reassemble across frames', () {
      // Recorded live: id and name land first, arguments trickle in pieces.
      final p = GatewayProtocol();
      final events = [
        ...p.applyPayload(
          '{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc",'
          '"type":"function","function":{"name":"websearch","arguments":""}}]}}]}',
        ),
        ...p.applyPayload(
          '{"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"function":{"arguments":"{\\"query\\": \\"Flutter 3.47"}}]}}]}',
        ),
        ...p.applyPayload(
          '{"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"function":{"arguments":" release notes\\"}"}}]}}]}',
        ),
        ...p.applyPayload(
          '{"choices":[{"delta":{},"finish_reason":"tool_calls",'
          '"native_finish_reason":"tool_calls"}]}',
        ),
      ];
      expect(events, isEmpty); // nothing visible streams for tool calls

      final finish = p.finish();
      final ready = finish.whereType<GatewayToolCallsReady>().toList();
      expect(ready, hasLength(1));
      final calls = ready.single.calls;
      expect(calls, hasLength(1));
      expect(calls.single.id, 'call_abc');
      expect(calls.single.name, 'websearch');
      expect(calls.single.arguments, '{"query": "Flutter 3.47 release notes"}');
      expect((finish.last as GatewayDone).reason, FinishReason.toolCalls);
    });

    test('two parallel tool calls keep their own buffers', () {
      final p = GatewayProtocol();
      p.applyPayload(
        '{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a",'
        '"function":{"name":"websearch","arguments":"{\\"query\\":\\"x\\"}"}}]}}]}',
      );
      p.applyPayload(
        '{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b",'
        '"function":{"name":"datetime","arguments":"{}"}}]}}]}',
      );
      p.applyPayload('{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}');
      final calls = p.finish().whereType<GatewayToolCallsReady>().single.calls;
      expect(calls.map((c) => c.name), ['websearch', 'datetime']);
      expect(calls.map((c) => c.id), ['a', 'b']);
    });

    test('accumulated calls promote a plain stop to a tool round', () {
      // Some backends finish tool turns with `stop`; the calls themselves
      // are the authoritative signal.
      final p = GatewayProtocol();
      p.applyPayload(
        '{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c",'
        '"function":{"name":"datetime","arguments":"{}"}}]},'
        '"finish_reason":"stop"}]}',
      );
      final finish = p.finish();
      expect(finish.whereType<GatewayToolCallsReady>(), hasLength(1));
      expect((finish.last as GatewayDone).reason, FinishReason.toolCalls);
    });
  });

  group('KiloGateway.classifyStatus', () {
    test('429 is the rate limit, never a generic client error', () {
      expect(KiloGateway.classifyStatus(429), HalisErrorCode.rateLimited);
    });

    test('5xx stays a server error, other 4xx a bad request', () {
      expect(KiloGateway.classifyStatus(503), HalisErrorCode.server);
      expect(KiloGateway.classifyStatus(400), HalisErrorCode.badRequest);
      expect(KiloGateway.classifyStatus(200), HalisErrorCode.unknown);
    });
  });
}
