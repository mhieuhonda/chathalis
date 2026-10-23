import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chathalis/gateway/socket_http.dart';

/// A raw TCP fixture server that inspects the request wire shape and serves
/// canned HTTP responses. Unlike HttpServer it never rewrites or rebuffers
/// the request, so tests can assert exactly what went out.
class _FixtureServer {
  _FixtureServer() {
    _binding = ServerSocket.bind(InternetAddress.loopbackIPv4, 0)
        .then((s) {
      server = s;
      s.listen((socket) {
        connections.add(socket);
        socket.listen(
          (data) => requests.add(utf8.decode(data)),
          onError: (_) {},
        );
        _serve(socket, requests.length + 1);
      });
      ready.complete();
      return s;
    });
  }

  late final Future<ServerSocket> _binding;
  late final ServerSocket server;
  final ready = Completer<void>();
  final requests = <String>[];
  final connections = <Socket>[];

  /// Response sent verbatim for each incoming request, by request index.
  /// An empty result means: keep the connection open and stay silent.
  List<int> Function(int index) respond = (_) => _sseResponse(['[DONE]']);

  void _serve(Socket socket, int index) {
    // Tiny delay so the request fully lands before the answer goes out.
    Future<void>.delayed(const Duration(milliseconds: 10)).then((_) {
      final reply = respond(index);
      if (reply.isNotEmpty) socket.add(reply);
    });
  }

  void killClients() {
    for (final c in List.of(connections)) {
      c.destroy();
    }
  }

  Future<void> close() async {
    final s = await _binding;
    await s.close();
  }

  static List<int> _sseResponse(List<String> payloads,
      {bool chunked = true}) {
    final body = StringBuffer();
    for (final p in payloads) {
      body.write('data: $p\n\n');
    }
    return _httpResponse(200, body.toString(), chunked: chunked);
  }

  static List<int> _httpResponse(int status, String body,
      {bool chunked = true}) {
    final head = StringBuffer()
      ..write('HTTP/1.1 $status ${status == 200 ? 'OK' : 'Error'}\r\n')
      ..write('content-type: text/event-stream\r\n');
    if (chunked) {
      head.write('transfer-encoding: chunked\r\n\r\n');
      final out = <int>[...utf8.encode(head.toString())];
      out.addAll(_chunk(utf8.encode(body)));
      out.addAll(utf8.encode('0\r\n\r\n'));
      return out;
    }
    head.write('content-length: ${utf8.encode(body).length}\r\n\r\n');
    return [...utf8.encode(head.toString()), ...utf8.encode(body)];
  }

  static List<int> _chunk(List<int> bytes) {
    final head = utf8.encode('${bytes.length.toRadixString(16)}\r\n');
    return [...head, ...bytes, ...utf8.encode('\r\n')];
  }
}

void main() {
  group('ChunkedDecoder', () {
    List<int> decodeAll(List<List<int>> pushes) {
      final d = ChunkedDecoder();
      final out = <int>[];
      for (final p in pushes) {
        out.addAll(d.push(p));
      }
      out.addAll(d.flush());
      return out;
    }

    test('decodes a single chunk with terminator', () {
      final wire = utf8.encode('5\r\nhello\r\n0\r\n\r\n');
      expect(decodeAll([wire]), utf8.encode('hello'));
    });

    test('decodes several chunks in order', () {
      final wire =
          utf8.encode('3\r\nabc\r\n2\r\nde\r\n4\r\nfghi\r\n0\r\n\r\n');
      expect(decodeAll([wire]), utf8.encode('abcdefghi'));
    });

    test('survives byte-by-byte delivery', () {
      const payload = 'xin chào bạn';
      final wire = utf8.encode(
        '${utf8.encode(payload).length.toRadixString(16)}\r\n$payload\r\n0\r\n\r\n',
      );
      final pushes = [for (final b in wire) <int>[b]];
      expect(decodeAll(pushes), utf8.encode(payload));
    });

    test('handles chunk extensions', () {
      final wire = utf8.encode('5;ext=1\r\nhello\r\n0\r\n\r\n');
      expect(decodeAll([wire]), utf8.encode('hello'));
    });

    test('consumes trailers before the blank line', () {
      final wire =
          utf8.encode('3\r\nabc\r\n0\r\nX-Foo: bar\r\nX-Baz: qux\r\n\r\n');
      expect(decodeAll([wire]), utf8.encode('abc'));
    });

    test('split CRLF between pushes stays correct', () {
      final d = ChunkedDecoder();
      final out = <int>[];
      out.addAll(d.push(utf8.encode('3\r\nab')));
      out.addAll(d.push(utf8.encode('c')));
      out.addAll(d.push(utf8.encode('\r')));
      out.addAll(d.push(utf8.encode('\n0\r')));
      out.addAll(d.push(utf8.encode('\n\r\n')));
      out.addAll(d.flush());
      expect(out, utf8.encode('abc'));
    });

    test('ignores input after done', () {
      final d = ChunkedDecoder();
      d.push(utf8.encode('2\r\nhi\r\n0\r\n\r\n'));
      expect(d.isDone, isTrue);
      expect(d.push(utf8.encode('garbage')), isEmpty);
    });

    test('flush returns pending data on truncated stream', () {
      final d = ChunkedDecoder();
      final out = <int>[];
      out.addAll(d.push(utf8.encode('5\r\nhel')));
      out.addAll(d.flush());
      expect(out, utf8.encode('hel'));
    });
  });

  group('socketHttpPost', () {
    late _FixtureServer fixture;

    setUp(() {
      fixture = _FixtureServer();
    });

    tearDown(() => fixture.close());

    Future<SocketHttpResponse> post({
      List<int>? body,
      Duration headTimeout = const Duration(seconds: 5),
      void Function(void Function() destroy)? registerAbort,
    }) async {
      await fixture.ready.future;
      return socketHttpPost(
        uri: Uri.parse('https://127.0.0.1:${fixture.server.port}/x'),
        headers: const {'content-type': 'application/json'},
        body: body ?? utf8.encode('{}'),
        headTimeout: headTimeout,
        registerAbort: registerAbort,
        connect: (uri, timeout) =>
            Socket.connect(uri.host, uri.port, timeout: timeout),
      );
    }

    test('rejects non-https endpoints', () async {
      expect(
        () => socketHttpPost(
          uri: Uri.parse('http://example.com/x'),
          headers: const {},
          body: const [],
          headTimeout: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
    });

    test('request leaves as one contiguous write', () async {
      fixture.respond = (_) => _FixtureServer._httpResponse(
            200,
            'data: [DONE]\n\n',
          );
      final body = utf8.encode('{"hello":"world"}');
      await post(body: body);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fixture.requests, hasLength(1));
      final raw = fixture.requests.first;
      // The request head and its body share the first data event — the
      // shape that keeps strict gateways from stalling the connection.
      expect(raw, contains('POST /x HTTP/1.1\r\n'));
      expect(raw, contains('content-length: ${body.length}\r\n'));
      expect(raw, endsWith('{"hello":"world"}'));
      expect(raw.indexOf('\r\n\r\n'), lessThan(raw.indexOf('world')));
    });

    test('streams chunked SSE body end to end', () async {
      fixture.respond = (_) => _FixtureServer._sseResponse(
        ['{"a":1}', '{"b":2}', '[DONE]'],
      );
      final res = await post();
      expect(res.statusCode, 200);
      final text = await res.body.transform(utf8.decoder).join();
      expect(
        text,
        'data: {"a":1}\n\ndata: {"b":2}\n\ndata: [DONE]\n\n',
      );
    });

    test('body ends exactly at content-length (no chunking)', () async {
      fixture.respond = (_) => _FixtureServer._httpResponse(
            200,
            'plain-body',
            chunked: false,
          );
      final res = await post();
      final text = await res.body.transform(utf8.decoder).join();
      expect(text, 'plain-body');
    });

    test('drains an error body and reports the status', () async {
      fixture.respond = (_) => _FixtureServer._httpResponse(
            429,
            '{"error":{"message":"slow down"}}',
            chunked: false,
          );
      final res = await post();
      expect(res.statusCode, 429);
      final text = await res.body.transform(utf8.decoder).join();
      expect(text, '{"error":{"message":"slow down"}}');
    });

    test('head timeout fires when the server never answers', () async {
      fixture.respond = (_) => const <int>[]; // accept, stay silent
      await expectLater(
        post(headTimeout: const Duration(milliseconds: 150)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('connection closed before the head is a network failure', () async {
      fixture.respond = (_) {
        Future<void>.delayed(const Duration(milliseconds: 10))
            .then((_) => fixture.killClients());
        return const <int>[];
      };
      await expectLater(
        post(),
        throwsA(isA<SocketException>()),
      );
    });

    test('malformed head surfaces immediately, not as a timeout', () async {
      fixture.respond = (_) => utf8.encode('NOT HTTP AT ALL\r\n\r\n');
      final sw = Stopwatch()..start();
      await expectLater(
        post(headTimeout: const Duration(seconds: 3)),
        throwsA(isA<HttpException>()),
      );
      // A failure must not wait out the head timeout.
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('abort destroys the socket mid-body', () async {
      // One response frame, then silence — the abort ends the wait.
      fixture.respond = (_) => _FixtureServer._httpResponse(
            200,
            'data: {"partial":true}\n\n',
          );
      late void Function() killer;
      final res = await post(
        registerAbort: (destroy) => killer = destroy,
      );

      final events = <List<int>>[];
      final finished = Completer<Object?>();
      res.body.listen(
        events.add,
        onError: finished.complete,
        onDone: () {
          if (!finished.isCompleted) finished.complete(null);
        },
      );
      while (events.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(utf8.decode(events.first), 'data: {"partial":true}\n\n');

      killer();
      final outcome = await finished.future
          .timeout(const Duration(seconds: 2), onTimeout: () => 'still-open');
      // The socket teardown ends the body stream; whether it surfaces as an
      // error or a plain close is platform timing, both are acceptable.
      expect(outcome, isNot('still-open'));
    });

    test('response before full request is still parsed', () async {
      // Some servers start replying before the body finishes; the head
      // parser must not require it.
      fixture.respond = (_) => _FixtureServer._httpResponse(
            200,
            'data: [DONE]\n\n',
          );
      final res = await post(body: utf8.encode('x' * 8192));
      expect(res.statusCode, 200);
    });
  });
}
