import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/utils.dart';
import '../data/chat_repository.dart';
import '../gateway/kilo_gateway.dart';
import '../gateway/models.dart';
import 'context_window.dart';

/// Drives a single conversation: sending turns, streaming them into the
/// message list, aborting, retrying and regenerating.
///
/// The shape follows the agent loops of opencode and deepseek-harness:
/// a turn is a sequence of typed gateway events reduced into message state;
/// aborting keeps the partial answer; transport failures are retried with
/// backoff before an error is surfaced.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.conversationId,
    this.isNewConversation = false,
    ChatRepository? repository,
    KiloGateway? gateway,
  })  : _repo = repository ?? ChatRepository.instance,
        _gateway = gateway ?? KiloGateway();

  final String conversationId;
  final bool isNewConversation;
  final ChatRepository _repo;
  final KiloGateway _gateway;

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
    if (text.isEmpty || _streaming) return;

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

    await _runTurn();
  }

  /// Drops the last assistant reply (if any) and produces a new one.
  Future<void> regenerate() async {
    if (_streaming) return;
    while (messages.isNotEmpty && messages.last.role == Role.assistant) {
      final last = messages.removeLast();
      await _repo.deleteMessage(last.id);
    }
    if (messages.isEmpty || messages.last.role != Role.user) return;
    _notify();
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

    while (!_disposed) {
      final result = await _streamOnce(assistant, abort);
      switch (result) {
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
            assistant.error = _lastError?.userMessage;
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
          assistant.error = _lastError?.userMessage;
          await _persist(assistant);
          _notify();
          return;
      }
    }
  }

  HalisError? _lastError;

  Future<_TurnResult> _streamOnce(ChatMessage assistant, AbortHandle abort) async {
    var sawContent = false;
    var sawReasoning = false;
    final reasoningStart = DateTime.now();
    DateTime? reasoningEnd;
    _lastError = null;

    try {
      final stream = _gateway.chat(
        messages: _composeApiMessages(),
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
            return _TurnResult.done;
          case GatewayFailed(:final error):
            _lastError = error;
            if (error.code == HalisErrorCode.cancelled) {
              return _TurnResult.aborted;
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

  /// System prompt + recent history, trimmed to the token budget.
  /// Reasoning text is never replayed to the gateway.
  List<ApiMessage> _composeApiMessages() => composeApiMessages(messages);

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

  /// Coalesces delta bursts into ~10 UI frames per second, the way opencode
  /// batches provider events before publishing.
  void _scheduleNotify() {
    if (_disposed) return;
    _dirty = true;
    _notifyTimer ??= Timer(_throttle, () {
      _notifyTimer = null;
      if (_dirty) _notify();
    });
  }
}

enum _TurnResult { done, aborted, retryable, fatal }
