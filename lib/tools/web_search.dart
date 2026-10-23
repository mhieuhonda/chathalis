import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'tool.dart';

/// The websearch tool: keyword search over the open web, no API key.
///
/// Results come back as a numbered list of `[title](url)` entries with a
/// short snippet each — enough for the model to answer from, or to pick a
/// page for the webfetch tool when it needs the full text.
class WebSearchTool extends HalisTool {
  @override
  String get name => 'websearch';

  @override
  String get description =>
      'Search the web for current information: news, weather, prices, '
      'releases, sports results, or any fact that may have changed after '
      'your training data. Returns result titles, links and snippets.';

  @override
  Map<String, dynamic> get parameters => const {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'The search query. Keywords work better than full sentences.',
          },
        },
        'required': ['query'],
      };

  /// Engines tried in order until one yields results. Different providers
  /// rate-limit different networks, so a chain keeps the tool useful when
  /// one of them starts throwing challenges.
  static const List<String> _engines = [
    'https://lite.duckduckgo.com/lite/',
    'https://html.duckduckgo.com/html/',
    'https://www.bing.com/search',
  ];

  static const Duration _timeout = Duration(seconds: 25);

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) return 'Error: the "query" argument is required.';

    Object? lastProblem;
    for (final engine in _engines) {
      try {
        final body = await _get(engine, query);
        final results = parseSearchResults(body);
        if (results.isEmpty) {
          lastProblem = 'no results parsed';
          continue;
        }
        return _render(results);
      } on TimeoutException {
        lastProblem = 'timed out';
      } catch (e) {
        lastProblem = e.toString();
      }
    }
    return 'Error: web search is unavailable right now ($lastProblem). '
        'Try again, or answer from your own knowledge and say it may be '
        'out of date.';
  }

  @override
  String labelFor(Map<String, dynamic> args) {
    final query = '${args['query'] ?? ''}'.trim();
    return query.length <= 48 ? query : '${query.substring(0, 48)}…';
  }

  Future<String> _get(String engine, String query) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse(engine).replace(
        queryParameters: {'q': query},
      );
      final request = await client
          .openUrl('GET', uri)
          .timeout(const Duration(seconds: 12));
      request.headers
        ..set(HttpHeaders.userAgentHeader, HalisTool.userAgent)
        ..set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml')
        ..set('Accept-Language', 'en-US,en;q=0.9');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}');
      }
      return await utf8.decodeStream(response).timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  /// Renders results the way they read best in a chat answer.
  String _render(List<SearchHit> results) {
    if (results.isEmpty) {
      return 'No search results found. Try a different query.';
    }
    final buffer = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer
        ..write('${i + 1}. [${_oneLine(r.title)}](${r.url})')
        ..writeln();
      if (r.snippet.isNotEmpty) {
        buffer
          ..writeln('   ${_oneLine(r.snippet)}')
          ..writeln();
      }
    }
    return buffer.toString().trim();
  }

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// One parsed search result.
class SearchHit {
  const SearchHit({required this.title, required this.url, this.snippet = ''});

  final String title;
  final String url;
  final String snippet;
}

/// Extracts organic results from either search layout. Public so it can be
/// unit-tested against recorded pages.
List<SearchHit> parseSearchResults(String html) {
  final doc = parser.parse(html);
  final hits = <SearchHit>[];

  // The html layout: self-contained result blocks.
  for (final block in doc.querySelectorAll('.result')) {
    final link = block.querySelector('a.result__a') ??
        block.querySelector('a[href]');
    if (link == null) continue;
    _addHit(
      hits,
      link,
      block.querySelector('.result__snippet')?.text.trim() ?? '',
    );
  }

  if (hits.isEmpty) {
    // The lite layout: a flat table where each title row may be followed
    // by its snippet row.
    final rows = doc.querySelectorAll('tr');
    for (var i = 0; i < rows.length; i++) {
      final link = rows[i].querySelector('a.result-link');
      if (link == null) continue;
      var snippet = '';
      for (var j = i + 1; j < rows.length && j <= i + 2; j++) {
        final cell = rows[j].querySelector('td.result-snippet');
        if (cell != null) {
          snippet = cell.text.trim();
          i = j;
          break;
        }
        if (rows[j].querySelector('a.result-link') != null) break;
      }
      _addHit(hits, link, snippet);
    }
  }

  if (hits.isEmpty) {
    // The Bing layout: result list items with a heading anchor and a
    // caption paragraph. Bing sometimes wraps outbound links in its own
    // redirector, which is unwrapped here.
    for (final block in doc.querySelectorAll('li.b_algo')) {
      final link = block.querySelector('h2 a[href]') ??
          block.querySelector('a[href]');
      if (link == null) continue;
      _addHit(
        hits,
        link,
        block.querySelector('.b_caption p')?.text.trim() ??
            block.querySelector('p')?.text.trim() ??
            '',
      );
    }
  }

  if (hits.isEmpty) {
    // Last resort: any anchor that resolves to an outbound page.
    for (final link in doc.querySelectorAll('a[href]')) {
      final url = _cleanUrl(link.attributes['href'] ?? '');
      if (url == null || url.contains('duckduckgo.com')) continue;
      final title = link.text.trim();
      if (title.isEmpty) continue;
      hits.add(SearchHit(title: title, url: url));
    }
  }

  return _dedupe(hits).take(_maxResults).toList();
}

const int _maxResults = 8;

void _addHit(List<SearchHit> hits, Element link, String snippet) {
  final url = _cleanUrl(link.attributes['href'] ?? '');
  if (url == null) return;
  final title = _cleanTitle(link.text);
  if (title.isEmpty) return;
  hits.add(SearchHit(title: title, url: url, snippet: snippet));
}

/// One of the engines bakes the site name and breadcrumb trail into the
/// heading anchor (`site.orghttps://… › topic › Page`); keep the page name.
String _cleanTitle(String raw) {
  var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.contains('›')) t = t.split('›').last.trim();
  final candidates = <int>[
    if (t.indexOf('http://') > 0) t.indexOf('http://'),
    if (t.indexOf('https://') > 0) t.indexOf('https://'),
  ];
  if (candidates.isNotEmpty) {
    candidates.sort();
    t = t.substring(0, candidates.first).trim();
  }
  return t;
}

/// Resolves the redirect wrappers the search engines put around outbound
/// links and drops ads and junk entries.
String? _cleanUrl(String href) {
  if (href.isEmpty) return null;
  var raw = href.trim();
  if (raw.startsWith('//')) raw = 'https:$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;

  // DuckDuckGo redirector: /l/?uddg=<encoded target>.
  if (uri.host.endsWith('duckduckgo.com') && uri.path.startsWith('/l/')) {
    final target = uri.queryParameters['uddg'];
    if (target == null || target.isEmpty) return null;
    final decoded = Uri.tryParse(Uri.decodeComponent(target));
    if (decoded == null || !decoded.hasScheme) return null;
    return decoded.toString();
  }

  // Bing redirector: /ck/a?...&u=a1<base64url target>.
  if (uri.host.endsWith('bing.com') && uri.path.startsWith('/ck/')) {
    final u = uri.queryParameters['u'];
    if (u == null || u.length < 8 || !u.startsWith('a1')) return null;
    final decoded = _base64UrlDecode(u.substring(2));
    if (decoded == null) return null;
    final target = Uri.tryParse(decoded);
    if (target == null || !target.hasScheme) return null;
    return target.toString();
  }

  if (raw.contains('duckduckgo.com/y.js')) return null; // sponsored
  if (!uri.hasScheme) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.toString();
}

String? _base64UrlDecode(String raw) {
  final normalized = raw.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized +
      '=' * ((4 - normalized.length % 4) % 4);
  try {
    return utf8.decode(base64Decode(padded), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

List<SearchHit> _dedupe(List<SearchHit> hits) {
  final seen = <String>{};
  final out = <SearchHit>[];
  for (final h in hits) {
    if (!seen.add(h.url)) continue;
    out.add(h);
  }
  return out;
}
