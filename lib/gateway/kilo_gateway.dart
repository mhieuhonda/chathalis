import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/strings.dart';
import 'models.dart';
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
}

/// Stable error codes, in the spirit of deepseek-harness's error taxonomy.
enum HalisErrorCode { network, timeout, server, badRequest, cancelled, unknown }

class HalisError implements Exception {
  const HalisError(this.code, [this.detail]);

  final HalisErrorCode code;
  final String? detail;

  String get userMessage {
    switch (code) {
      case HalisErrorCode.network:
        return HalisStrings.errNetwork;
      case HalisErrorCode.timeout:
        return HalisStrings.errTimeout;
      case HalisErrorCode.server:
        return HalisStrings.errServer;
      case HalisErrorCode.badRequest:
      case HalisErrorCode.unknown:
        return HalisStrings.errUnknown;
      case HalisErrorCode.cancelled:
        return 'Đã dừng';
    }
  }

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
/// `reasoning`, `reasoning_details[]`).
class GatewayProtocol {
  String? _finishReason;
  TurnUsage? _usage;

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
    return out;
  }

  /// Events to emit once the byte stream has ended. A stream that ended
  /// without an explicit reason is treated as a normal stop.
  List<GatewayEvent> finish() {
    final reason =
        _finishReason == null ? FinishReason.stop : finishReasonFromWire(_finishReason);
    return [
      if (_usage != null) GatewayUsageInfo(_usage!),
      GatewayDone(reason),
    ];
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

  /// Never shown in the UI; see the system prompt for the public identity.
  static const String _model = 'kilo-auto/free';

  /// Output cap, in tokens — the gateway's own limit for this model.
  static const int maxOutputTokens = 32768;

  final Duration _connectTimeout;

  /// Streams a single assistant turn for [messages].
  ///
  /// The returned stream always terminates, either with a [GatewayDone] or a
  /// [GatewayFailed]. An aborted request yields [GatewayFailed] with code
  /// [HalisErrorCode.cancelled]; the engine keeps whatever partial content
  /// arrived before the abort.
  Stream<GatewayEvent> chat({
    required List<ApiMessage> messages,
    int maxTokens = maxOutputTokens,
    AbortHandle? abort,
    Duration idleTimeout = const Duration(seconds: 120),
  }) {
    final client = HttpClient();
    client.connectionTimeout = _connectTimeout;
    final protocol = GatewayProtocol();
    late final StreamController<GatewayEvent> controller;
    StreamSubscription? subscription;
    var userAborted = false;
    var idleTimedOut = false;
    Timer? watchdog;

    void teardown() {
      watchdog?.cancel();
      subscription?.cancel().catchError((_) {});
      client.close(force: true);
    }

    controller = StreamController<GatewayEvent>(
      onListen: () async {
        void fail(HalisError error) {
          controller.add(GatewayFailed(error));
        }

        try {
          abort?._onAbort(() {
            userAborted = true;
            teardown();
          });

          final body = jsonEncode({
            'model': _model,
            'messages': [
              for (final m in messages)
                {'role': m.role.name, 'content': m.content},
            ],
            'stream': true,
            'max_tokens': maxTokens,
          });

          final request =
              await client.openUrl('POST', Uri.parse(_endpoint));
          request.headers
            ..set(HttpHeaders.contentTypeHeader, 'application/json')
            ..set(HttpHeaders.acceptHeader, 'text/event-stream')
            ..set(HttpHeaders.userAgentHeader,
                'ChatHalis/1.0 (Android; +https://github.com/mhieuhonda/chathalis)');
          request.add(utf8.encode(body));
          await request.flush();

          final response = await request.done.timeout(_connectTimeout);
          if (response.statusCode != 200) {
            final text = await response
                .cast<List<int>>()
                .transform(utf8.decoder)
                .join()
                .timeout(const Duration(seconds: 10));
            throw _httpError(response.statusCode, text);
          }

          final sse = SseDecoder();
          void pulse() {
            watchdog?.cancel();
            watchdog = Timer(idleTimeout, () {
              idleTimedOut = true;
              client.close(force: true);
            });
          }

          pulse();
          final stream = response.cast<List<int>>().transform(utf8.decoder);
          subscription = stream.listen(
            (chunk) {
              pulse();
              for (final payload in sse.push(chunk)) {
                if (payload == '[DONE]') {
                  for (final e in protocol.finish()) {
                    controller.add(e);
                  }
                  teardown();
                  unawaited(controller.close());
                  return;
                }
                for (final e in protocol.applyPayload(payload)) {
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
                fail(HalisError(HalisErrorCode.network, e.toString()));
              }
              teardown();
              controller.close();
            },
            onDone: () {
              // Stream ended without an explicit [DONE] frame.
              sse.close();
              for (final e in protocol.finish()) {
                controller.add(e);
              }
              teardown();
              controller.close();
            },
            cancelOnError: true,
          );
        } on TimeoutException {
          fail(const HalisError(HalisErrorCode.timeout));
          teardown();
          controller.close();
        } catch (e) {
          if (userAborted) {
            fail(const HalisError(HalisErrorCode.cancelled));
          } else {
            fail(_classify(e));
          }
          teardown();
          controller.close();
        }
      },
      onCancel: () {
        teardown();
      },
    );

    return controller.stream;
  }

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
    final code = status >= 500
        ? HalisErrorCode.server
        : (status >= 400 ? HalisErrorCode.badRequest : HalisErrorCode.unknown);
    return HalisError(code, 'HTTP $status${message == null ? '' : ': $message'}');
  }
}

