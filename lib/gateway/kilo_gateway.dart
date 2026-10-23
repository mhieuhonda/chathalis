import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'socket_http.dart';
import 'sse.dart';

/// Cooperative cancellation token shared by the engine and the transport.
class AbortHandle {
  bool _aborted = false;
  final List<void Function()> _listeners = [];

  bool get isAborted => _aborted;

  void abort() {
    if (_aborted) return;
    _aborted = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void _onAbort(void Function() listener) {
    if (_aborted) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  /// Completes the moment [abort] fires. Used to race tool executions
  /// against the user's stop button; never completes otherwise, and the
  /// handle is discarded with the turn either way.
  Future<void> get cancelled {
    final c = Completer<void>();
    _onAbort(() {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }
}

/// Stable error codes shared by the transport and the engine. The transport
/// stays locale-free; the engine maps codes to user text.
enum HalisErrorCode {
  network,
  timeout,
  server,
  badRequest,
  rateLimited,
  cancelled,
  unknown,
}

class HalisError implements Exception {
  const HalisError(this.code, [this.detail]);

  final HalisErrorCode code;
  final String? detail;

  @override
  String toString() => 'HalisError($code${detail == null ? '' : ': $detail'})';
}

/// Typed events emitted while a turn streams, reduced by the chat engine.
sealed class GatewayEvent {
  const GatewayEvent();
}

final class GatewayReasoningDelta extends GatewayEvent {
  const GatewayReasoningDelta(this.text);
  final String text;
}

final class GatewayTextDelta extends GatewayEvent {
  const GatewayTextDelta(this.text);
  final String text;
}

final class GatewayUsageInfo extends GatewayEvent {
  const GatewayUsageInfo(this.usage);
  final TurnUsage usage;
}

/// Emitted once per turn when the model asked for tools, right before the
/// terminal [GatewayDone]. The calls arrive fully assembled — argument
/// fragments streamed across frames are stitched back together here.
final class GatewayToolCallsReady extends GatewayEvent {
  const GatewayToolCallsReady(this.calls);
  final List<ToolCall> calls;
}

final class GatewayDone extends GatewayEvent {
  const GatewayDone(this.reason);
  final FinishReason reason;
}

final class GatewayFailed extends GatewayEvent {
  const GatewayFailed(this.error);
  final HalisError error;
}

/// Pure translation of chat-completions SSE payloads into [GatewayEvent]s.
///
/// Kept free of I/O so it can be unit-tested against recorded chunks.
/// Understands the reasoning dialects seen on the wire (`reasoning_content`,
/// `reasoning`, `reasoning_details[]`) and reassembles streamed tool-call
/// fragments, which arrive indexed and split across arbitrary frame edges.
class GatewayProtocol {
  String? _finishReason;
  TurnUsage? _usage;
  final Map<int, _PendingToolCall> _pendingCalls = {};

  List<GatewayEvent> applyPayload(String payload) {
    final out = <GatewayEvent>[];
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return out; // ignore malformed frames
    }
    if (decoded is! Map<String, dynamic>) return out;

    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map<String, dynamic>) {
        final delta = choice['delta'];
        if (delta is Map<String, dynamic>) {
          final reasoning = _reasoningOf(delta);
          if (reasoning != null && reasoning.isNotEmpty) {
            out.add(GatewayReasoningDelta(reasoning));
          }
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            out.add(GatewayTextDelta(content));
          }
          _absorbToolCallDeltas(delta['tool_calls']);
        }
        final finish = choice['finish_reason'];
        if (finish is String && finish.isNotEmpty) {
          _finishReason = finish;
        }
      }
    }

    final usage = decoded['usage'];
    if (usage is Map<String, dynamic>) {
      final prompt = _toInt(usage['prompt_tokens']);
      final completion = _toInt(usage['completion_tokens']);
      if (prompt != null && completion != null) {
        final details = usage['completion_tokens_details'];
        int? reasoningTokens;
        if (details is Map<String, dynamic>) {
          reasoningTokens = _toInt(details['reasoning_tokens']);
        }
        _usage = TurnUsage(
          promptTokens: prompt,
          completionTokens: completion,
          reasoningTokens: reasoningTokens,
        );
      }
    }

    // An in-band error frame (no choices, just an error object) must not
    // be swallowed — the answer would silently truncate otherwise.
    if ((choices is! List || choices.isEmpty) && decoded['error'] != null) {
      final err = decoded['error'];
      String? message;
      if (err is Map<String, dynamic> && err['message'] is String) {
        message = err['message'] as String;
      } else if (err is String) {
        message = err;
      }
      out.add(GatewayFailed(
        HalisError(HalisErrorCode.server, message ?? 'stream error'),
      ));
    }
    return out;
  }

  /// Events to emit once the byte stream has ended. Tool calls come first
  /// (when the model requested any), then usage, then the terminal done.
  /// A stream that ended without an explicit reason is treated as a normal
  /// stop — unless tool calls accumulated, which makes the turn a tool
  /// round regardless of how the backend labelled it.
  List<GatewayEvent> finish() {
    var reason = _finishReason == null
        ? FinishReason.stop
        : finishReasonFromWire(_finishReason);
    final calls = _assembledCalls();
    if (calls.isNotEmpty && reason != FinishReason.toolCalls) {
      reason = FinishReason.toolCalls;
    }
    return [
      if (_usage != null) GatewayUsageInfo(_usage!),
      if (calls.isNotEmpty) GatewayToolCallsReady(calls),
      GatewayDone(reason),
    ];
  }

  void _absorbToolCallDeltas(Object? raw) {
    if (raw is! List) return;
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final index = _toInt(entry['index']) ?? _pendingCalls.length;
      final pending = _pendingCalls.putIfAbsent(index, _PendingToolCall.new);
      final id = entry['id'];
      if (id is String && id.isNotEmpty) pending.id = id;
      final fn = entry['function'];
      if (fn is! Map<String, dynamic>) continue;
      final name = fn['name'];
      if (name is String && name.isNotEmpty) pending.name.write(name);
      final args = fn['arguments'];
      if (args is String) pending.arguments.write(args);
    }
  }

  List<ToolCall> _assembledCalls() {
    final indices = _pendingCalls.keys.toList()..sort();
    final calls = <ToolCall>[];
    for (var i = 0; i < indices.length; i++) {
      final p = _pendingCalls[indices[i]]!;
      final name = p.name.toString();
      if (name.isEmpty) continue; // an index with no callable shape
      calls.add(ToolCall(
        id: p.id ?? 'call_$i',
        name: name,
        arguments: p.arguments.toString(),
      ));
    }
    return calls;
  }

  static String? _reasoningOf(Map<String, dynamic> delta) {
    final a = delta['reasoning_content'];
    if (a is String && a.isNotEmpty) return a;
    final b = delta['reasoning'];
    if (b is String && b.isNotEmpty) return b;
    final details = delta['reasoning_details'];
    if (details is List) {
      final buf = StringBuffer();
      for (final d in details) {
        if (d is Map<String, dynamic>) {
          final t = d['text'];
          if (t is String) buf.write(t);
        }
      }
      final s = buf.toString();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static int? _toInt(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : null);
}

/// Accumulates one tool call whose id, name and arguments may each be split
/// across many streamed frames.
final class _PendingToolCall {
  String? id;
  final StringBuffer name = StringBuffer();
  final StringBuffer arguments = StringBuffer();
}

/// Thin client for the Kilo Gateway — a keyless, OpenAI-compatible
/// chat-completions endpoint.
///
/// The model is fixed at compile time and is never surfaced anywhere in the
/// product. One [HttpClient] per request keeps abort cheap: tearing the
/// client down force-closes the socket mid-stream.
class KiloGateway {
  KiloGateway({Duration? connectTimeout})
      : _connectTimeout = connectTimeout ?? const Duration(seconds: 30);

  static const String _endpoint =
      'https://api.kilo.ai/api/gateway/chat/completions';

  /// Upper bound on how much of a non-200 body is read for diagnostics.
  static const int _maxErrorBody = 16 * 1024;

  /// Never shown in the UI; see the system prompt for the public identity.
  static const String _model = 'kilo-auto/free';

  /// Output cap, in tokens — the gateway's own limit for this model.
  static const int maxOutputTokens = 32768;

  final Duration _connectTimeout;

  /// Streams a single assistant turn for [messages].
  ///
  /// When [tools] is non-empty, the tool catalog is offered to the model; a
  /// turn that ends in tool calls is signalled by [GatewayToolCallsReady]
  /// plus a [GatewayDone] carrying [FinishReason.toolCalls].
  ///
  /// The returned stream always terminates, either with a [GatewayDone] or a
  /// [GatewayFailed]. An aborted request yields [GatewayFailed] with code
  /// [HalisErrorCode.cancelled]; the engine keeps whatever partial content
  /// arrived before the abort.
  Stream<GatewayEvent> chat({
    required List<ApiMessage> messages,
    List<ToolSpec>? tools,
    int maxTokens = maxOutputTokens,
    AbortHandle? abort,
    Duration idleTimeout = const Duration(seconds: 120),
  }) {
    final protocol = GatewayProtocol();
    final sse = SseDecoder();
    late final StreamController<GatewayEvent> controller;
    var userAborted = false;
    var idleTimedOut = false;
    var settled = false;
    Timer? watchdog;
    void Function()? kill;

    void teardown() {
      watchdog?.cancel();
      kill?.call();
    }

    void fail(HalisError error) {
      if (settled) return;
      settled = true;
      teardown();
      controller.add(GatewayFailed(error));
      unawaited(controller.close());
    }

    void succeed(List<GatewayEvent> events) {
      if (settled) return;
      settled = true;
      teardown();
      for (final e in events) {
        controller.add(e);
      }
      unawaited(controller.close());
    }

    controller = StreamController<GatewayEvent>(
      onListen: () async {
        try {
          // Registered before the socket exists so a stop request during
          // the connect window still flips the flag; the socket itself is
          // destroyed the moment [registerAbort] hands over the kill
          // switch (the listener fires immediately on an aborted handle).
          abort?._onAbort(() {
            userAborted = true;
            kill?.call();
          });

          final body = jsonEncode({
            'model': _model,
            'messages': [for (final m in messages) _wireMessage(m)],
            'stream': true,
            'max_tokens': maxTokens,
            if (tools != null && tools.isNotEmpty)
              'tools': [
                for (final t in tools)
                  {
                    'type': 'function',
                    'function': {
                      'name': t.name,
                      'description': t.description,
                      'parameters': t.parameters,
                    },
                  },
              ],
          });

          final response = await socketHttpPost(
            uri: Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'accept': 'text/event-stream',
              'user-agent':
                  'ChatHalis/1.0 (Android; +https://github.com/mhieuhonda/chathalis)',
            },
            body: utf8.encode(body),
            headTimeout: _connectTimeout,
            registerAbort: (destroy) {
              kill = destroy;
            },
          );

          if (userAborted) {
            fail(const HalisError(HalisErrorCode.cancelled));
            return;
          }
          if (response.statusCode != 200) {
            final text = await _drain(response.body);
            if (userAborted) {
              fail(const HalisError(HalisErrorCode.cancelled));
              return;
            }
            fail(_httpError(response.statusCode, text));
            return;
          }

          void pulse() {
            watchdog?.cancel();
            watchdog = Timer(idleTimeout, () {
              idleTimedOut = true;
              kill?.call();
            });
          }

          pulse();
          // utf8.decoder is incremental: it stitches multi-byte characters
          // that land split across TCP chunks — a certainty with streamed
          // Vietnamese text.
          response.body.transform(utf8.decoder).listen(
            (chunk) {
              if (settled) return;
              pulse();
              for (final payload in sse.push(chunk)) {
                if (payload == '[DONE]') {
                  succeed(protocol.finish());
                  return;
                }
                for (final e in protocol.applyPayload(payload)) {
                  // In-band failures terminate the turn right away — a
                  // late [DONE] must not append a second terminal.
                  if (e is GatewayFailed) {
                    fail(e.error);
                    return;
                  }
                  controller.add(e);
                }
              }
            },
            onError: (Object e) {
              if (userAborted) {
                fail(const HalisError(HalisErrorCode.cancelled));
              } else if (idleTimedOut) {
                fail(const HalisError(HalisErrorCode.timeout));
              } else {
                fail(_classify(e));
              }
            },
            onDone: () {
              // Stream ended without an explicit [DONE] frame — whatever
              // assembled so far still counts as a completed turn.
              for (final payload in sse.close()) {
                if (payload == '[DONE]') continue;
                for (final e in protocol.applyPayload(payload)) {
                  controller.add(e);
                }
              }
              succeed(protocol.finish());
            },
            cancelOnError: true,
          );
        } catch (e) {
          if (userAborted) {
            fail(const HalisError(HalisErrorCode.cancelled));
          } else {
            fail(_classify(e));
          }
        }
      },
      onCancel: () {
        settled = true;
        teardown();
      },
    );

    return controller.stream;
  }

  /// Reads an error body to text, bounded so a huge or hostile payload
  /// cannot stall the failure path.
  static Future<String> _drain(Stream<List<int>> body) async {
    final buffer = BytesBuilder(copy: true);
    var taken = 0;
    try {
      await for (final chunk in body) {
        final left = _maxErrorBody - taken;
        if (left <= 0) break;
        buffer.add(chunk.length > left ? chunk.sublist(0, left) : chunk);
        taken += chunk.length;
        if (taken >= _maxErrorBody) break;
      }
    } catch (_) {
      // The error body is best-effort; the status code already carries
      // the failure classification.
    }
    return utf8.decode(buffer.toBytes(), allowMalformed: true);
  }

  /// One [ApiMessage] in chat-completions wire shape. Tool results and
  /// assistant tool-call decisions follow the standard function-calling
  /// conventions of the protocol.
  static Map<String, dynamic> _wireMessage(ApiMessage m) => switch (m) {
        _ when m.role == Role.tool => {
            'role': 'tool',
            'content': m.content,
            'tool_call_id': m.toolCallId ?? '',
          },
        _ when m.role == Role.assistant && m.toolCalls.isNotEmpty => {
            'role': 'assistant',
            'content': m.content,
            'tool_calls': [
              for (final c in m.toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {'name': c.name, 'arguments': c.arguments},
                },
            ],
          },
        _ => {'role': m.role.name, 'content': m.content},
      };

  HalisError _classify(Object e) {
    if (e is HalisError) return e;
    if (e is SocketException || e is HttpException) {
      return HalisError(HalisErrorCode.network, e.toString());
    }
    return HalisError(HalisErrorCode.unknown, e.toString());
  }

  HalisError _httpError(int status, String body) {
    String? message;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map<String, dynamic> && err['message'] is String) {
          message = err['message'] as String;
        } else if (err is String) {
          message = err;
        }
      }
    } catch (_) {}
    final code = classifyStatus(status);
    return HalisError(code, 'HTTP $status${message == null ? '' : ': $message'}');
  }

  /// HTTP status → stable error code. 429 is the rate limit.
  @visibleForTesting
  static HalisErrorCode classifyStatus(int status) => switch (status) {
        429 => HalisErrorCode.rateLimited,
        >= 500 => HalisErrorCode.server,
        >= 400 => HalisErrorCode.badRequest,
        _ => HalisErrorCode.unknown,
      };
}

