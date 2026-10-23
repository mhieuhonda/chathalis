import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'html_text.dart';
import 'tool.dart';

/// The webfetch tool: read one page from the web and hand its text to the
/// model.
///
/// Companion to websearch — search finds the page, this reads it. HTML is
/// reduced to readable markdown-flavoured text; plain text and JSON pass
/// through untouched. Everything is bounded: a size cap on the download,
/// a character cap on the output, and a caller-tunable timeout.
class WebFetchTool extends HalisTool {
  @override
  String get name => 'webfetch';

  @override
  String get description =>
      'Fetch the content of a web page by URL and return its readable text. '
      'Use this when a websearch snippet is not enough — documentation, '
      'articles, release notes — or when the user shares a direct link. '
      'Only http and https URLs work, and only text content can be read.';

  @override
  Map<String, dynamic> get parameters => const {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'The http or https URL to read.',
          },
          'timeout': {
            'type': 'integer',
            'description':
                'Optional timeout in seconds, between 1 and 120. '
                'Defaults to 30.',
          },
        },
        'required': ['url'],
      };

  static const int _maxDownloadBytes = 2 * 1024 * 1024;
  static const int _maxOutputChars = 24 * 1024;
  static const int _defaultTimeoutSeconds = 30;
  static const int _maxTimeoutSeconds = 120;

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final rawUrl = '${args['url'] ?? ''}'.trim();
    if (rawUrl.isEmpty) return 'Error: the "url" argument is required.';

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      return 'Error: "$rawUrl" is not a valid URL.';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Error: only http and https URLs can be fetched.';
    }

    final timeout = _timeoutFrom(args);
    if (timeout == null) {
      return 'Error: "timeout" must be an integer between 1 and '
          '$_maxTimeoutSeconds seconds.';
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .openUrl('GET', uri)
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.userAgentHeader, HalisTool.userAgent)
        ..set(HttpHeaders.acceptHeader,
            'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5')
        ..set('Accept-Language', 'en-US,en;q=0.9');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return 'Error: the server answered HTTP ${response.statusCode} '
            'for ${_display(uri)}.';
      }
      return await _read(response, uri, timeout);
    } on SocketException {
      return 'Error: could not connect to ${_display(uri)}.';
    } on TimeoutException {
      return 'Error: ${_display(uri)} took longer than '
          '${timeout.inSeconds}s to answer.';
    } on HttpException catch (e) {
      return 'Error: failed to fetch ${_display(uri)} (${e.message}).';
    } catch (e) {
      return 'Error: failed to fetch ${_display(uri)}.';
    } finally {
      client.close(force: true);
    }
  }

  @override
  String labelFor(Map<String, dynamic> args) {
    final uri = Uri.tryParse('${args['url'] ?? ''}'.trim());
    if (uri == null || uri.host.isEmpty) return '${args['url'] ?? ''}';
    final path = uri.path;
    return path.isEmpty || path == '/'
        ? uri.host
        : '${uri.host}${path.length > 32 ? '…' : path}';
  }

  Duration? _timeoutFrom(Map<String, dynamic> args) {
    final v = args['timeout'];
    if (v == null) return const Duration(seconds: _defaultTimeoutSeconds);
    final seconds = v is int ? v : int.tryParse('$v');
    if (seconds == null ||
        seconds < 1 ||
        seconds > _maxTimeoutSeconds) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  /// Reads the body within the byte cap, then converts by content type.
  Future<String> _read(
    HttpClientResponse response,
    Uri uri,
    Duration timeout,
  ) async {
    final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
    final mime = (contentType ?? '').split(';').first.trim().toLowerCase();

    if (mime.startsWith('image/') ||
        mime.startsWith('audio/') ||
        mime.startsWith('video/') ||
        mime == 'application/pdf' ||
        mime.startsWith('font/')) {
      return 'Error: $_display(uri) serves '
          '${mime.isEmpty ? 'binary' : mime} content, which cannot be read '
          'as text.';
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response) {
      received += chunk.length;
      if (received > _maxDownloadBytes) {
        return 'Error: $_display(uri) sent more than '
            '${_maxDownloadBytes ~/ (1024 * 1024)} MB of data.';
      }
      builder.add(chunk);
    }
    final body = decodeBody(builder.takeBytes());

    if (mime.contains('html') || mime.isEmpty) {
      final doc = parseHtml(body);
      final title = extractTitle(doc);
      final text = htmlToReadableText(doc);
      if (text.trim().isEmpty) {
        return 'The page at $_display(uri) contains no readable text.';
      }
      final clipped = _clip(text);
      return title.isEmpty
          ? clipped
          : 'Title: ${_oneLine(title)}\n\n$clipped';
    }
    return _clip(body);
  }

  String _clip(String text) {
    if (text.length <= _maxOutputChars) return text;
    return '${text.substring(0, _maxOutputChars)}\n\n[… the rest of the '
        'page was left out — fetch a more specific page if you need it]';
  }

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _display(Uri? uri) =>
      uri == null ? 'the page' : uri.toString();

  /// Tolerant decode: a stray invalid byte should not kill an otherwise
  /// readable page.
  static String decodeBody(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);
}
