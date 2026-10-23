import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/strings.dart';
import '../core/utils.dart';
import '../data/chat_repository.dart';
import '../gateway/kilo_gateway.dart';
import '../gateway/models.dart';
import '../tools/tool.dart';
import 'context_window.dart';
import 'usage_tracker.dart';

/// Drives a single conversation: sending turns, streaming them into the
/// message list, aborting, retrying and regenerating.
///
/// A turn is a sequence of typed gateway events reduced into message state.
/// When the model asks for a tool, the engine runs it on the device, hands
/// the result back and lets the model continue — up to [_maxToolRounds]
/// rounds, after which the tools are withdrawn so a final answer always
/// lands. Aborting keeps the partial answer; transport failures are retried
/// with backoff before an error is surfaced.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.conversationId,
    this.isNewConversation = false,
    Strings? strings,
    ChatRepository? repository,
    KiloGateway? gateway,
    UsageTracker? usage,
    List<HalisTool>? tools,
  })  : _repo = repository ?? ChatRepository.instance,
        _gateway = gateway ?? KiloGateway(),
        _strings = strings ?? Strings.of(AppLocale.english),
        _usage = usage ?? UsageTracker.instance,
        _tools = tools ?? buildHalisTools() {
    _toolSpecs = [for (final t in _tools) t.spec];
    _toolRegistry = {for (final t in _tools) t.name: t};
  }

  final String conversationId;
  final bool isNewConversation;
  final ChatRepository _repo;
  final KiloGateway _gateway;
  final Strings _strings;
  final UsageTracker _usage;
  final List<HalisTool> _tools;

  late List<ToolSpec> _toolSpecs;
  late Map<String, HalisTool> _toolRegistry;

  /// Ordered oldest → newest.
  final List<ChatMessage> messages = <ChatMessage>[];

  String title = 'ChatHalis';
  bool loaded = false;
  bool _manualTitle = false;

  bool _streaming = false;
  bool get isStreaming => _streaming;

  AbortHandle? _activeAbort;
  Timer? _notifyTimer;
  bool _dirty = false;
  int _attempt = 0;
  bool _disposed = false;

  static const int _maxRetries = 2;

  /// Upper bound on tool rounds within one user-visible turn. Past it the
  /// tools are withdrawn and the model writes the best answer it can from
  /// what it has gathered — a safety valve, not a target.
  static const int _maxToolRounds = 6;

  /// Hard ceiling for a single tool execution, covering each tool's own
  /// timeouts with headroom.
  static const Duration _toolBudget = Duration(seconds: 150);

  static const Duration _throttle = Duration(milliseconds: 90);

  // ------------------------------------------------------------ lifecycle

  Future<void> load() async {
    if (loaded) return;
    final conv = await _repo.getConversation(conversationId);
    if (conv != null) title = conv.title;
    messages.addAll(await _repo.listMessages(conversationId));
    loaded = true;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _activeAbort?.abort();
    _notifyTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------- actions

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _streaming || _usage.locked) return;

    if (isNewConversation || !messages.any((m) => m.role == Role.user)) {
      final effectiveTitle = _manualTitle ? title : HalisUtils.titleFrom(text);
      final conv = Conversation(
        id: conversationId,
        title: effectiveTitle,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastPreview: HalisUtils.previewOf(text),
      );
      await _repo.ensureConversation(conv);
      if (isNewConversation) {
        title = effectiveTitle;
      }
    }

    final user = ChatMessage(
      id: HalisUtils.uuid(),
      role: Role.user,
      content: text,
      createdAt: DateTime.now(),
    );
    messages.add(user);
    await _repo.insertMessage(conversationId, user);
    _notify();

    _usage.record(); // one request per send, retries included
    await _runTurn();
  }

  /// Drops the last assistant reply (if any) and produces a new one.
  Future<void> regenerate() async {
    if (_streaming || _usage.locked) return;
    while (messages.isNotEmpty && messages.last.role == Role.assistant) {
      final last = messages.removeLast();
      await _repo.deleteMessage(last.id);
    }
    if (messages.isEmpty || messages.last.role != Role.user) return;
    _notify();
    _usage.record();
    await _runTurn();
  }

  void stop() {
    _activeAbort?.abort();
  }

  /// Renames the conversation everywhere (memory + storage).
  Future<void> renameTo(String name) async {
    if (name.trim().isEmpty) return;
    title = name.trim();
    _manualTitle = true;
    if (messages.any((m) => m.role == Role.user)) {
      await _repo.renameConversation(conversationId, title);
    }
    _notify();
  }

  // --------------------------------------------------------------- engine

  Future<void> _runTurn() async {
    final assistant = ChatMessage(
      id: HalisUtils.uuid(),
      role: Role.assistant,
      createdAt: DateTime.now(),
    );
    messages.add(assistant);

    _streaming = true;
    _notify();

    final abort = AbortHandle();
    _activeAbort = abort;
    _attempt = 0;

    // Tool traffic of the turn in progress: the assistant's call decisions
    // and the results, replayed verbatim while the turn continues.
    final toolTraffic = <ApiMessage>[];
    var rounds = 0;

    while (!_disposed) {
      final result = await _streamOnce(
        assistant,
        abort,
        toolTraffic,
        allowTools: rounds < _maxToolRounds,
      );
      switch (result) {
        case _TurnResult.toolRound:
          rounds++;
          _attempt = 0; // each round gets a fresh retry budget
          continue;
        case _TurnResult.done:
          _streaming = false;
          _activeAbort = null;
          await _persist(assistant);
          _notify();
          return;
        case _TurnResult.aborted:
          _streaming = false;
          _activeAbort = null;
          assistant.state = MessageState.interrupted;
          await _persist(assistant);
          _notify();
          return;
        case _TurnResult.retryable:
          _attempt++;
          if (_attempt > _maxRetries) {
            _streaming = false;
            _activeAbort = null;
            assistant.state = MessageState.failed;
            assistant.error = _messageFor(_lastError);
            await _persist(assistant);
            _notify();
            return;
          }
          await Future<void>.delayed(_backoff(_attempt));
          continue;
        case _TurnResult.fatal:
          _streaming = false;
          _activeAbort = null;
          assistant.state = MessageState.failed;
          assistant.error = _messageFor(_lastError);
          await _persist(assistant);
          _notify();
          return;
      }
    }
  }

  HalisError? _lastError;

  /// Maps a transport failure to localized user-facing text. The gateway
  /// only deals in codes; wording lives with the active locale.
  String _messageFor(HalisError? error) => switch (error?.code) {
        HalisErrorCode.network => _strings.errNetwork,
        HalisErrorCode.timeout => _strings.errTimeout,
        HalisErrorCode.server => _strings.errServer,
        HalisErrorCode.rateLimited => _strings.errRateLimited,
        HalisErrorCode.cancelled => _strings.stoppedInline,
        _ => _strings.errUnknown,
      };

  Future<_TurnResult> _streamOnce(
    ChatMessage assistant,
    AbortHandle abort,
    List<ApiMessage> toolTraffic, {
    required bool allowTools,
  }) async {
    var sawContent = false;
    var sawReasoning = false;
    final contentStart = assistant.content.length;
    final reasoningStart = DateTime.now();
    DateTime? reasoningEnd;
    List<ToolCall>? requestedCalls;
    _lastError = null;

    try {
      final stream = _gateway.chat(
        messages: composeApiMessages(
          messages,
          excludeId: assistant.id,
          tail: toolTraffic,
        ),
        tools: allowTools ? _toolSpecs : null,
        abort: abort,
      );
      await for (final event in stream) {
        switch (event) {
          case GatewayReasoningDelta(:final text):
            if (!sawReasoning) {
              sawReasoning = true;
              reasoningEnd = null;
            }
            assistant.reasoning += text;
            _scheduleNotify();
          case GatewayTextDelta(:final text):
            if (sawReasoning && reasoningEnd == null) {
              reasoningEnd = DateTime.now();
              assistant.reasoningMs =
                  reasoningEnd.difference(reasoningStart).inMilliseconds;
            }
            sawContent = true;
            assistant.content += text;
            _scheduleNotify();
          case GatewayToolCallsReady(:final calls):
            requestedCalls = calls;
          case GatewayUsageInfo():
            break;
          case GatewayDone(:final reason):
            if (sawReasoning && reasoningEnd == null) {
              assistant.reasoningMs =
                  DateTime.now().difference(reasoningStart).inMilliseconds;
            }
            if (reason == FinishReason.length) {
              assistant.truncated = true;
            }
            if (requestedCalls != null && requestedCalls.isNotEmpty) {
              final round = await _executeToolRound(
                assistant,
                abort,
                requestedCalls,
                assistant.content.substring(contentStart),
              );
              if (round == null) return _TurnResult.aborted;
              toolTraffic.addAll(round);
              return _TurnResult.toolRound;
            }
            return _TurnResult.done;
          case GatewayFailed(:final error):
            _lastError = error;
            if (error.code == HalisErrorCode.cancelled) {
              return _TurnResult.aborted;
            }
            if (error.code == HalisErrorCode.rateLimited) {
              // The server says the hour is up — pin the meter at 100% and
              // let the lock run exactly once, however often this fires.
              _usage.onRateLimited();
              return _TurnResult.fatal;
            }
            if (!sawContent && !sawReasoning) {
              final retryable = error.code == HalisErrorCode.network ||
                  error.code == HalisErrorCode.timeout ||
                  error.code == HalisErrorCode.server;
              return retryable ? _TurnResult.retryable : _TurnResult.fatal;
            }
            return _TurnResult.fatal;
        }
      }
      // Stream ended without a terminal event — treat as done.
      return _TurnResult.done;
    } catch (e) {
      _lastError = HalisError(HalisErrorCode.unknown, e.toString());
      return _TurnResult.fatal;
    }
  }

  /// Runs every tool the model asked for in this round and produces the
  /// wire messages to replay: the call decision, then one result message
  /// per call. Returns null when the turn was aborted mid-way — partial
  /// results are then dropped, mirroring how partial text is kept only on
  /// clean stops.
  Future<List<ApiMessage>?> _executeToolRound(
    ChatMessage assistant,
    AbortHandle abort,
    List<ToolCall> calls,
    String roundContent,
  ) async {
    final round = <ApiMessage>[
      ApiMessage.toolRequest(content: roundContent, toolCalls: calls),
    ];

    for (final call in calls) {
      if (abort.isAborted || _disposed) return null;

      final tool = _toolRegistry[call.name];
      final args = decodeToolArguments(call.arguments);
      final entry = ToolUse(
        tool: call.name,
        label: tool?.labelFor(args) ?? call.name,
        running: true,
      );
      assistant.toolUses.add(entry);
      _scheduleNotify();

      final outcome = await _runOneTool(call, abort);
      if (abort.isAborted || _disposed) return null;
      entry
        ..running = false
        ..ms = outcome.ms;
      _scheduleNotify();

      round.add(
        ApiMessage.toolResult(callId: call.id, content: outcome.content),
      );
    }
    return round;
  }

  /// Executes one tool call, converting every failure mode into text the
  /// model can read and react to. Never throws, never hangs forever, and a
  /// stop request cuts the wait short instead of waiting out a slow site.
  Future<({String content, int ms})> _runOneTool(
    ToolCall call,
    AbortHandle abort,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final tool = _toolRegistry[call.name];
      if (tool == null) {
        return (
          content: 'Error: unknown tool "${call.name}". Available tools: '
              '${_toolRegistry.keys.join(", ")}.',
          ms: watch.elapsedMilliseconds,
        );
      }
      final args = decodeToolArguments(call.arguments);
      final run = tool.run(args).timeout(_toolBudget);
      final stopped = abort.cancelled.then<String>(
        (_) => 'Error: the request was stopped while the tool was running.',
      );
      final content = await Future.any([run, stopped]);
      return (content: content, ms: watch.elapsedMilliseconds);
    } on TimeoutException {
      return (
        content: 'Error: the tool call took too long and was stopped.',
        ms: watch.elapsedMilliseconds,
      );
    } catch (e) {
      return (
        content: 'Error: the tool call failed (${_shortReason(e)}).',
        ms: watch.elapsedMilliseconds,
      );
    }
  }

  static String _shortReason(Object e) {
    final text = e.toString().trim();
    return text.length <= 160 ? text : '${text.substring(0, 160)}…';
  }

  Future<void> _persist(ChatMessage m) async {
    if (m.content.trim().isEmpty &&
        m.reasoning.trim().isEmpty &&
        m.state != MessageState.failed) {
      // Nothing worth keeping — drop the empty placeholder entirely.
      messages.remove(m);
      return;
    }
    try {
      await _repo.insertMessage(conversationId, m);
    } catch (_) {
      // Storage failures must never crash the chat loop.
      debugPrint('chathalis: failed to persist message');
    }
  }

  // ------------------------------------------------------------- plumbing

  static Duration _backoff(int attempt) {
    final base = 600 * math.pow(2, attempt - 1).toDouble();
    final jitter = math.Random().nextDouble() * 0.3 * base;
    return Duration(milliseconds: (base + jitter).round());
  }

  void _notify() {
    if (_disposed) return;
    _dirty = false;
    notifyListeners();
  }

  /// Coalesces delta bursts into ~10 UI frames per second so the stream
  /// stays smooth without flooding the widget tree with rebuilds.
  void _scheduleNotify() {
    if (_disposed) return;
    _dirty = true;
    _notifyTimer ??= Timer(_throttle, () {
      _notifyTimer = null;
      if (_dirty) _notify();
    });
  }
}

enum _TurnResult { done, toolRound, aborted, retryable, fatal }
