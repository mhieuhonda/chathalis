import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chathalis/engine/chat_controller.dart';
import 'package:chathalis/engine/usage_tracker.dart';
import 'package:chathalis/gateway/kilo_gateway.dart';
import 'package:chathalis/gateway/models.dart';
import 'package:chathalis/tools/tool.dart';

/// A gateway that plays back scripted rounds: tool call, tool call, final
/// answer — recording what the engine actually sent so the loop's wire
/// behavior can be asserted.
class _ScriptedGateway extends KiloGateway {
  _ScriptedGateway(this.script);

  final List<List<GatewayEvent> Function()> script;
  int call = 0;
  final List<List<ToolSpec>?> toolsSeen = [];
  final List<List<Role>> rolesSeen = [];

  @override
  Stream<GatewayEvent> chat({
    required List<ApiMessage> messages,
    List<ToolSpec>? tools,
    int maxTokens = 32768,
    AbortHandle? abort,
    Duration idleTimeout = const Duration(seconds: 120),
  }) {
    toolsSeen.add(tools);
    rolesSeen.add([for (final m in messages) m.role]);
    final produce =
        call < script.length ? script[call++] : () => <GatewayEvent>[];
    return Stream.fromIterable(produce());
  }
}

class _EchoTool extends HalisTool {
  _EchoTool({this.delay = Duration.zero});

  Duration delay;
  int runs = 0;

  @override
  String get name => 'websearch';

  @override
  String get description => 'test double';

  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': const {}};

  @override
  Future<String> run(Map<String, dynamic> args) async {
    runs++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return '1. [Hue weather](https://example.com/hue)\nSunny, 31°C.';
  }

  @override
  String labelFor(Map<String, dynamic> args) => '${args['query'] ?? ''}';
}

GatewayEvent _ask(String id, String name, Map<String, dynamic> args) =>
    GatewayToolCallsReady([
      ToolCall(id: id, name: name, arguments: jsonEncode(args)),
    ]);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInitForTests();
  });

  test('tool request runs the tool, feeds the result back, then answers',
      () async {
    final tool = _EchoTool();
    final gateway = _ScriptedGateway([
      () => [
            const GatewayReasoningDelta('thinking about weather'),
            _ask('c1', 'websearch', {'query': 'thời tiết Huế'}),
            const GatewayDone(FinishReason.toolCalls),
          ],
      () => const [
            GatewayTextDelta('Hôm nay Huế nắng, 31°C.'),
            GatewayDone(FinishReason.stop),
          ],
    ]);
    final controller = _controller(gateway, [tool]);
    addTearDown(controller.dispose);

    await controller.send('thời tiết Huế hôm nay?');

    final reply = controller.messages.last;
    expect(reply.role, Role.assistant);
    expect(reply.content, 'Hôm nay Huế nắng, 31°C.');
    expect(reply.state, MessageState.ok);

    // The tool ran once and its trace landed on the message.
    expect(tool.runs, 1);
    expect(reply.toolUses, hasLength(1));
    expect(reply.toolUses.single.tool, 'websearch');
    expect(reply.toolUses.single.label, 'thời tiết Huế');
    expect(reply.toolUses.single.running, isFalse);
    expect(reply.toolUses.single.ms, isNotNull);

    // Tools were offered in both rounds; the second round replayed the
    // call and its result right after the user turn.
    expect(gateway.toolsSeen[0], isNotEmpty);
    expect(gateway.toolsSeen[1], isNotEmpty);
    expect(gateway.rolesSeen[1].last, Role.tool);
    // The still-streaming assistant placeholder is never replayed twice.
    expect(
      gateway.rolesSeen[1].where((r) => r == Role.assistant),
      hasLength(1),
    );
  });

  test('a tool that throws becomes readable error text for the model',
      () async {
    final broken = _BrokenTool();
    final gateway = _ScriptedGateway([
      () => [
            _ask('c1', 'websearch', {'query': 'x'}),
            const GatewayDone(FinishReason.toolCalls),
          ],
      () => const [
            GatewayTextDelta('Không tra được, nhưng...'),
            GatewayDone(FinishReason.stop),
          ],
    ]);
    final controller = _controller(gateway, [broken]);
    addTearDown(controller.dispose);

    await controller.send('anything');

    final reply = controller.messages.last;
    expect(reply.content, 'Không tra được, nhưng...');
    expect(gateway.rolesSeen[1].last, Role.tool);
  });

  test('an unknown tool name is reported back instead of crashing', () async {
    final gateway = _ScriptedGateway([
      () => [
            _ask('c1', 'nosuchtool', {'query': 'x'}),
            const GatewayDone(FinishReason.toolCalls),
          ],
      () => const [
            GatewayTextDelta('ok'),
            GatewayDone(FinishReason.stop),
          ],
    ]);
    final controller = _controller(gateway, [_EchoTool()]);
    addTearDown(controller.dispose);

    await controller.send('anything');
    expect(controller.messages.last.content, 'ok');
    expect(controller.messages.last.toolUses.single.tool, 'nosuchtool');
  });

  test('the round cap withdraws tools so a final answer always lands',
      () async {
    final tool = _EchoTool();
    List<GatewayEvent> askAgain() => [
          _ask('c', 'websearch', {'query': 'q'}),
          const GatewayDone(FinishReason.toolCalls),
        ];
    final gateway = _ScriptedGateway([
      askAgain, askAgain, askAgain, askAgain, askAgain, askAgain,
      // Seventh round: tools must be gone; the model answers in plain text.
      () => const [
            GatewayTextDelta('final answer'),
            GatewayDone(FinishReason.stop),
          ],
    ]);
    final controller = _controller(gateway, [tool]);
    addTearDown(controller.dispose);

    await controller.send('run forever');

    expect(tool.runs, 6); // rounds 0–5
    expect(gateway.toolsSeen.take(6).every((t) => t != null && t.isNotEmpty),
        isTrue);
    expect(gateway.toolsSeen[6], anyOf(isNull, isEmpty));
    expect(controller.messages.last.content, 'final answer');
    expect(controller.messages.last.toolUses, hasLength(6));
  });

  test('stop during a tool run interrupts the turn cleanly', () async {
    final slow = _EchoTool(delay: const Duration(seconds: 30));
    final gateway = _ScriptedGateway([
      () => [
            _ask('c1', 'websearch', {'query': 'q'}),
            const GatewayDone(FinishReason.toolCalls),
          ],
    ]);
    final controller = _controller(gateway, [slow]);
    addTearDown(controller.dispose);

    final sending = controller.send('slow query');
    // Let the round start, then hit stop while the tool is "running".
    await Future<void>.delayed(const Duration(milliseconds: 30));
    controller.stop();
    await sending;

    expect(controller.isStreaming, isFalse);
  });

  test('the usage meter counts a send once, tool rounds included',
      () async {
    final gateway = _ScriptedGateway([
      () => [
            _ask('c1', 'websearch', {'query': 'q'}),
            const GatewayDone(FinishReason.toolCalls),
          ],
      () => const [
            GatewayTextDelta('done'),
            GatewayDone(FinishReason.stop),
          ],
    ]);
    final usage = UsageTracker();
    final controller = ChatController(
      conversationId: 'conv-usage-${DateTime.now().microsecondsSinceEpoch}',
      isNewConversation: true,
      gateway: gateway,
      usage: usage,
      tools: [_EchoTool()],
    );
    addTearDown(controller.dispose);

    await controller.send('hi');
    expect(usage.fraction, closeTo(1 / UsageTracker.hourlyLimit, 1e-9));
  });
}

ChatController _controller(
  _ScriptedGateway gateway,
  List<HalisTool> tools,
) {
  return ChatController(
    conversationId: 'conv-${DateTime.now().microsecondsSinceEpoch}',
    isNewConversation: true,
    gateway: gateway,
    usage: UsageTracker(),
    tools: tools,
  );
}

class _BrokenTool extends HalisTool {
  @override
  String get name => 'websearch';

  @override
  String get description => 'always fails';

  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': const {}};

  @override
  Future<String> run(Map<String, dynamic> args) async {
    throw StateError('boom');
  }

  @override
  String labelFor(Map<String, dynamic> args) => '${args['query'] ?? ''}';
}

/// In-memory database factory so the controller's persistence never touches
/// the device.
void sqfliteFfiInitForTests() {
  // Imported lazily to keep this file's imports flat.
  if (_ffiReady) return;
  _ffiReady = true;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

bool _ffiReady = false;
