import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A minimal streaming HTTP/1.1 POST client built directly on [SecureSocket].
///
/// Why not [HttpClient]? Some API gateways front their endpoints with
/// request inspectors that hold a connection open indefinitely when the
/// request head and its body do not reach the server back-to-back —
/// precisely how [HttpClient] emits them. Writing the entire request as a
/// single buffer keeps every byte of the exchange contiguous on the wire
/// and sidesteps that stall entirely.
///
/// The client is one-shot: one request, one response, then the socket is
/// torn down. Response bodies are streamed either as-is, length-limited by
/// `content-length`, or reassembled from `transfer-encoding: chunked`
/// framing. No compression is negotiated, so no decompression is needed.
class SocketHttpResponse {
  SocketHttpResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final String reasonPhrase;

  /// Response headers with lower-cased keys.
  final Map<String, String> headers;

  /// Decoded body bytes. Ends when the body is complete; socket failures
  /// surface here as stream errors.
  final Stream<List<int>> body;

  String? header(String name) => headers[name.toLowerCase()];
}

/// Performs a single streaming POST over TLS.
///
/// [headTimeout] bounds everything up to and including the parsed response
/// head (connect, send, server think time before the status line).
/// [registerAbort] receives the kill switch; invoking it destroys the
/// socket, which errors the body stream at once.
///
/// [connect] exists for tests: it defaults to a verified TLS socket and can
/// be swapped for a plain loopback connection against a fixture server.
Future<SocketHttpResponse> socketHttpPost({
  required Uri uri,
  required Map<String, String> headers,
  required List<int> body,
  required Duration headTimeout,
  Duration connectTimeout = const Duration(seconds: 15),
  void Function(void Function() destroy)? registerAbort,
  Future<Socket> Function(Uri uri, Duration timeout)? connect,
}) async {
  if (uri.scheme != 'https') {
    throw ArgumentError.value(uri, 'uri', 'only https endpoints are supported');
  }

  final socket = await (connect ?? _defaultConnect)(uri, connectTimeout);
  socket.setOption(SocketOption.tcpNoDelay, true);

  var finished = false;
  void destroy() {
    if (finished) return;
    finished = true;
    socket.destroy();
  }

  registerAbort?.call(destroy);

  final headCompleter = Completer<_ResponseHead>();
  final headTimer = Timer(headTimeout, () {
    if (!headCompleter.isCompleted) {
      headCompleter.completeError(
        TimeoutException('no response head within ${headTimeout.inSeconds}s'),
      );
    }
    destroy();
  });

  // Body plumbing: bytes may arrive before the caller subscribes, so they
  // queue until [onListen] drains them.
  final bodyController = StreamController<List<int>>(sync: false);
  final pending = <List<int>>[];
  var delivered = false;
  var bodyEnded = false;
  Object? bodyFailure;

  void emit(List<int> bytes) {
    if (bytes.isEmpty) return;
    if (!delivered) {
      pending.add(bytes);
    } else if (!bodyController.isClosed) {
      bodyController.add(bytes);
    }
  }

  void endBody() {
    bodyEnded = true;
    if (delivered && !bodyController.isClosed) {
      unawaited(bodyController.close());
    }
  }

  void failBody(Object error) {
    bodyFailure = error;
    headTimer.cancel();
    // A failure before the head was parsed must reach the awaiting caller
    // as itself — a socket error is a network failure, not a 30s timeout.
    if (!headCompleter.isCompleted) headCompleter.completeError(error);
    if (delivered && !bodyController.isClosed) {
      bodyController.addError(error);
      unawaited(bodyController.close());
    }
    destroy();
  }

  bodyController.onListen = () {
    delivered = true;
    for (final chunk in pending) {
      bodyController.add(chunk);
    }
    pending.clear();
    if (bodyFailure != null) {
      bodyController.addError(bodyFailure!);
      unawaited(bodyController.close());
    } else if (bodyEnded && !bodyController.isClosed) {
      unawaited(bodyController.close());
    }
  };
  bodyController.onCancel = destroy;

  final headBuffer = BytesBuilder(copy: true);
  _BodyFramer? framer;

  socket.listen(
    (chunk) {
      if (finished) return;
      try {
        if (framer == null) {
          // Head and framer are installed together below, so a null framer
          // with a completed head only happens after a head timeout — the
          // socket is dead at that point and the bytes are irrelevant.
          if (headCompleter.isCompleted) return;
          headBuffer.add(chunk);
          final bytes = headBuffer.toBytes();
          final split = _findHeadEnd(bytes);
          if (split < 0) {
            if (bytes.length > _maxHeadBytes) {
              failBody(const HttpException('response head too large'));
            }
            return;
          }
          headTimer.cancel();
          final head = _parseHead(bytes, split);
          if (!headCompleter.isCompleted) headCompleter.complete(head);
          // Frame every status — error bodies must drain too, or the
          // failure path would wait on bytes that never surface.
          framer = _BodyFramer(head.chunked, head.contentLength)
            ..onEnd = endBody;
          emit(framer!.push(bytes.sublist(split + 4)));
          if (framer!.isDone) endBody();
          return;
        }
        emit(framer!.push(chunk));
        if (framer!.isDone) endBody();
      } catch (e) {
        failBody(e);
      }
    },
    onError: (Object e) => failBody(e),
    onDone: () {
      headTimer.cancel();
      if (!headCompleter.isCompleted) {
        headCompleter.completeError(
          const SocketException('connection closed before response head'),
        );
      }
      if (framer != null) emit(framer!.flush());
      endBody();
    },
    cancelOnError: true,
  );

  try {
    // The whole request — request line, headers, body — leaves in one
    // contiguous write.
    final request = BytesBuilder(copy: false);
    final path = (uri.path.isEmpty ? '/' : uri.path) +
        (uri.hasQuery ? '?${uri.query}' : '');
    request.add(utf8.encode('POST $path HTTP/1.1\r\n'));
    request.add(utf8.encode('host: ${uri.host}\r\n'));
    for (final entry in headers.entries) {
      request.add(utf8.encode('${entry.key}: ${entry.value}\r\n'));
    }
    request.add(utf8.encode('content-length: ${body.length}\r\n'));
    request.add(utf8.encode('\r\n'));
    request.add(body);
    socket.add(request.toBytes());
    await socket.flush();
  } catch (e) {
    headTimer.cancel();
    if (!headCompleter.isCompleted) headCompleter.completeError(e);
    failBody(e);
    rethrow;
  }

  final head = await headCompleter.future;
  return SocketHttpResponse(
    statusCode: head.statusCode,
    reasonPhrase: head.reasonPhrase,
    headers: head.headers,
    body: bodyController.stream,
  );
}

Future<Socket> _defaultConnect(Uri uri, Duration timeout) =>
    SecureSocket.connect(
      uri.host,
      uri.port == 0 ? 443 : uri.port,
      timeout: timeout,
    );

final class _ResponseHead {
  _ResponseHead({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
  });

  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;

  bool get chunked =>
      (headers['transfer-encoding'] ?? '').toLowerCase().contains('chunked');

  int? get contentLength => headers.containsKey('content-length')
      ? int.tryParse(headers['content-length']!.trim())
      : null;
}

const int _maxHeadBytes = 64 * 1024;

/// Offset of the blank line separating head from body, or -1.
int _findHeadEnd(List<int> bytes) {
  final end = bytes.length - 4;
  for (var i = 0; i <= end; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

_ResponseHead _parseHead(List<int> bytes, int headEnd) {
  final headText = latin1.decode(bytes.sublist(0, headEnd));
  final lines = headText.split('\r\n');
  if (lines.isEmpty || !lines.first.startsWith('HTTP/')) {
    throw const HttpException('malformed response status line');
  }
  final statusParts = lines.first.split(' ');
  final code =
      int.tryParse(statusParts.length > 1 ? statusParts[1] : '');
  if (code == null) {
    throw const HttpException('malformed response status code');
  }
  final headers = <String, String>{};
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final key = line.substring(0, colon).trim().toLowerCase();
    final value = line.substring(colon + 1).trim();
    headers[key] = headers.containsKey(key) ? '${headers[key]}, $value' : value;
  }
  return _ResponseHead(
    statusCode: code,
    reasonPhrase:
        statusParts.length > 2 ? statusParts.sublist(2).join(' ') : '',
    headers: headers,
  );
}

enum _ChunkState { size, data, chunkEnd, trailers }

/// Reassembles chunked transfer framing into raw body bytes.
///
/// Incremental: feed arbitrary byte fragments to [push], collect decoded
/// body bytes. After the terminating zero chunk and its trailer section the
/// decoder reports done and further input is ignored. Trailer lines are
/// consumed but not surfaced.
class ChunkedDecoder {
  final List<int> _buf = <int>[];
  _ChunkState _state = _ChunkState.size;
  int _remaining = 0;
  bool _done = false;

  bool get isDone => _done;

  List<int> push(List<int> bytes) {
    if (_done || bytes.isEmpty) return const <int>[];
    _buf.addAll(bytes);
    final out = <int>[];
    while (!_done) {
      switch (_state) {
        case _ChunkState.size:
          final nl = _findCrlf();
          if (nl < 0) return out;
          final line = latin1.decode(_buf.sublist(0, nl));
          _buf.removeRange(0, nl + 2);
          final size = int.tryParse(line.split(';').first.trim(), radix: 16);
          if (size == null) {
            throw const FormatException('bad chunk size');
          }
          if (size == 0) {
            _state = _ChunkState.trailers;
          } else {
            _remaining = size;
            _state = _ChunkState.data;
          }
        case _ChunkState.data:
          final take = _remaining < _buf.length ? _remaining : _buf.length;
          if (take > 0) {
            out.addAll(_buf.sublist(0, take));
            _buf.removeRange(0, take);
            _remaining -= take;
          }
          if (_remaining == 0) {
            _state = _ChunkState.chunkEnd;
          } else if (_buf.isEmpty) {
            return out;
          }
        case _ChunkState.chunkEnd:
          if (_buf.length < 2) return out;
          _buf.removeRange(0, 2);
          _state = _ChunkState.size;
        case _ChunkState.trailers:
          final nl = _findCrlf();
          if (nl < 0) {
            if (_buf.length > 16 * 1024) _done = true; // runaway trailers
            return out;
          }
          final blank = nl == 0;
          _buf.removeRange(0, nl + 2);
          if (blank) _done = true;
      }
    }
    return out;
  }

  /// Bytes still pending when the stream ended without a terminating chunk.
  List<int> flush() {
    final out = _state == _ChunkState.data ? List<int>.of(_buf) : const <int>[];
    _buf.clear();
    _done = true;
    return out;
  }

  int _findCrlf() {
    for (var i = 0; i + 1 < _buf.length; i++) {
      if (_buf[i] == 13 && _buf[i + 1] == 10) return i;
    }
    return -1;
  }
}

/// Frames a 200 body: chunked, content-length-bounded, or read-to-close.
class _BodyFramer {
  _BodyFramer(this.chunked, this.contentLength)
      : decoder = chunked ? ChunkedDecoder() : null;

  final bool chunked;
  final int? contentLength;
  final ChunkedDecoder? decoder;

  int seen = 0;
  bool isDone = false;
  void Function()? onEnd;

  List<int> push(List<int> bytes) {
    if (isDone || bytes.isEmpty) return const <int>[];
    if (decoder != null) {
      final out = decoder!.push(bytes);
      if (decoder!.isDone) _finish();
      return out;
    }
    if (contentLength != null) {
      final left = contentLength! - seen;
      if (left <= 0) {
        _finish();
        return const <int>[];
      }
      if (bytes.length <= left) {
        seen += bytes.length;
        if (seen >= contentLength!) _finish();
        return bytes;
      }
      final out = bytes.sublist(0, left);
      _finish();
      return out;
    }
    return bytes; // read to close
  }

  List<int> flush() {
    final tail = decoder?.flush() ?? const <int>[];
    _finish();
    return tail;
  }

  void _finish() {
    if (isDone) return;
    isDone = true;
    onEnd?.call();
  }
}
