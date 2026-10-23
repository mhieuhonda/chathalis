import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:chathalis/gateway/models.dart';
import 'package:chathalis/tools/datetime_tool.dart';
import 'package:chathalis/tools/html_text.dart';
import 'package:chathalis/tools/tool.dart';
import 'package:chathalis/tools/web_fetch.dart';
import 'package:chathalis/tools/web_search.dart';

void main() {
  group('DatetimeTool', () {
    test('reports local time, offset, UTC and epoch', () async {
      final out = await DatetimeTool().run(const {});
      final now = DateTime.now();

      expect(out, contains('Local :'));
      expect(out, contains('UTC   :'));
      expect(out, contains('Epoch : ${now.millisecondsSinceEpoch ~/ 1000}'));
      // Weekday line agrees with the device clock.
      const weekdays = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ];
      expect(out, contains(weekdays[now.weekday - 1]));
    });

    test('accepts an empty argument payload', () async {
      final out = await DatetimeTool().run(const {});
      expect(out, isNot(contains('Error')));
    });
  });

  group('WebFetchTool argument validation', () {
    final tool = WebFetchTool();

    test('rejects a missing url without touching the network', () async {
      expect(await tool.run(const {}), startsWith('Error:'));
    });

    test('rejects non-http schemes', () async {
      final out = await tool.run(const {'url': 'file:///etc/passwd'});
      expect(out, contains('only http and https'));
    });

    test('rejects an out-of-range timeout', () async {
      final out = await tool.run({
        'url': 'https://example.com/',
        'timeout': 999,
      });
      expect(out, contains('between 1 and 120'));
    });
  });

  group('WebSearchTool', () {
    test('requires a query', () async {
      expect(await WebSearchTool().run(const {}), startsWith('Error:'));
    });

    test('parses the lite layout, decoding redirect links', () {
      const page = '''
      <html><body><table>
        <tr><td class="result-link"><a class="result-link"
            href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fflutter.dev%2Frelease">Flutter 3.47 release</a></td></tr>
        <tr><td class="result-snippet">What's new in 3.47.</td></tr>
        <tr><td class="result-link"><a class="result-link"
            href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdart.dev">Dart 3.13</a></td></tr>
        <tr><td class="result-snippet">The Dart SDK.</td></tr>
      </table></body></html>''';

      final hits = parseSearchResults(page);
      expect(hits, hasLength(2));
      expect(hits.first.url, 'https://flutter.dev/release');
      expect(hits.first.title, 'Flutter 3.47 release');
      expect(hits.first.snippet, "What's new in 3.47.");
      expect(hits[1].url, 'https://dart.dev');
    });

    test('parses the html layout with snippet blocks', () {
      const page = '''
      <html><body>
        <div class="result results_links">
          <h2><a class="result__a" href="https://news.ycombinator.com">Hacker News</a></h2>
          <a class="result__snippet" href="#">News for hackers.</a>
        </div>
        <div class="result results_links">
          <h2><a class="result__a" href="//duckduckgo.com/y.js?ad_domain=tea">Sponsored</a></h2>
          <a class="result__snippet" href="#">Buy things.</a>
        </div>
      </body></html>''';

      final hits = parseSearchResults(page);
      // The y.js redirect wrapper is dropped as an ad.
      expect(hits, hasLength(1));
      expect(hits.single.url, 'https://news.ycombinator.com');
    });

    test('parses the bing layout, unwrapping its redirector', () {
      const page = '''
      <html><body><ol id="b_results">
        <li class="b_algo"><div class="b_title"><h2><a
            href="https://www.bing.com/ck/a?!&amp;u=a1aHR0cHM6Ly9mbHV0dGVyLmRldi9yZWxlYXNlLW5vdGVz">Flutter release notes</a></h2></div>
          <div class="b_caption"><p class="b_lineclamp3">What's new in 3.47.</p></div></li>
        <li class="b_algo"><div><h2><a
            href="https://docs.example.com/api">API docs</a></h2>
          <p>Reference pages.</p></div></li>
      </ol></body></html>''';

      final hits = parseSearchResults(page);
      expect(hits, hasLength(2));
      expect(hits.first.url, 'https://flutter.dev/release-notes');
      expect(hits.first.title, 'Flutter release notes');
      expect(hits.first.snippet, "What's new in 3.47.");
      expect(hits[1].url, 'https://docs.example.com/api');
    });

    test('dedupes repeated urls and caps the result count', () {
      final buffer = StringBuffer('<html><body>');
      for (var i = 0; i < 12; i++) {
        buffer.write(
          '<div class="result"><a class="result__a" '
          'href="https://example.com/page$i">t$i</a>'
          '<a class="result__snippet">s$i</a></div>',
        );
        if (i.isEven) {
          buffer.write(
            '<div class="result"><a class="result__a" '
            'href="https://example.com/page$i">dup</a></div>',
          );
        }
      }
      buffer.write('</body></html>');
      final hits = parseSearchResults(buffer.toString());
      expect(hits, hasLength(8));
      expect(hits.map((h) => h.url).toSet(), hasLength(8));
    });

    test('search error text invites a fallback, not a crash', () async {
      // Empty query is refused; the wording matches the other tools.
      final out = await WebSearchTool().run(const {'query': '  '});
      expect(out, startsWith('Error:'));
      expect(out, contains('query'));
    });
  });

  group('HTML to readable text', () {
    test('drops scripts and chrome, keeps the article', () {
      const page = '''
      <html><head><title>Tea guide</title></head>
      <body>
        <script>window.tracker = 1;</script>
        <style>.a { color: red }</style>
        <nav><a href="/menu">Menu</a></nav>
        <article>
          <h1>Brewing tea</h1>
          <p>Water at <b>90°C</b>. Steep for <i>three</i> minutes.</p>
          <ul><li>Black tea</li><li>Green tea</li></ul>
          <p>See <a href="https://tea.example/more">the full guide</a>.</p>
        </article>
        <footer>© tea corp</footer>
      </body></html>''';

      final doc = parseHtml(page);
      expect(extractTitle(doc), 'Tea guide');

      final text = htmlToReadableText(doc);
      expect(text, contains('# Brewing tea'));
      expect(text, contains('Water at 90°C. Steep for three minutes.'));
      expect(text, contains('- Black tea'));
      expect(text, contains('- Green tea'));
      expect(text, contains('[the full guide](https://tea.example/more)'));
      expect(text, isNot(contains('tracker')));
      expect(text, isNot(contains('color: red')));
      expect(text, isNot(contains('Menu')));
      expect(text, isNot(contains('tea corp')));
    });

    test('tables survive as pipe rows', () {
      const page = '''
      <table><tr><th>Model</th><th>Year</th></tr>
      <tr><td>Halis</td><td>2026</td></tr></table>''';
      final text = htmlToReadableText(parseHtml(page));
      expect(text, contains('Model | Year'));
      expect(text, contains('Halis | 2026'));
    });

    test('output is capped with an ellipsis marker', () {
      final body = '<p>${'x' * (maxExtractedChars + 5000)}</p>';
      final text = htmlToReadableText(parseHtml(body));
      expect(text.length, lessThan(maxExtractedChars + 20));
      expect(text, endsWith('[…]'));
    });
  });

  group('Tool arguments', () {
    test('decodeToolArguments tolerates junk', () {
      expect(decodeToolArguments(''), isEmpty);
      expect(decodeToolArguments('not json'), isEmpty);
      expect(decodeToolArguments('[1,2]'), isEmpty);
      expect(decodeToolArguments('{"query":"x"}'), {'query': 'x'});
    });
  });

  group('Tool catalog', () {
    test('ships exactly websearch, webfetch and datetime', () {
      final tools = buildHalisTools();
      expect(tools.map((t) => t.name).toList(),
          ['websearch', 'webfetch', 'datetime']);
      for (final t in tools) {
        expect(t.description, isNotEmpty);
        expect(t.spec.name, t.name);
        // Schemas must be valid JSON maps on the wire.
        expect(jsonEncode(t.spec.parameters), isA<String>());
      }
    });

    test('labels stay short for chips', () {
      final search = WebSearchTool();
      expect(search.labelFor({'query': 'thời tiết Huế'}), 'thời tiết Huế');
      expect(
        search.labelFor({'query': 'q' * 100}),
        '${'q' * 48}…',
      );

      final fetch = WebFetchTool();
      expect(fetch.labelFor({'url': 'https://dart.dev/guides'}), 'dart.dev/guides');
      expect(fetch.labelFor({'url': 'https://dart.dev/'}), 'dart.dev');
    });
  });

  group('ToolUse persistence', () {
    test('round-trips through JSON', () {
      final uses = [
        ToolUse(tool: 'websearch', label: 'weather', ms: 812),
        ToolUse(tool: 'datetime', label: '23/10 14:02'),
      ];
      final decoded = ToolUse.listFromJson(ToolUse.listToJson(uses));
      expect(decoded, hasLength(2));
      expect(decoded.first.tool, 'websearch');
      expect(decoded.first.ms, 812);
      expect(decoded.last.ms, isNull);
      // Degenerate input never crashes a read.
      expect(ToolUse.listFromJson('not json'), isEmpty);
      expect(ToolUse.listFromJson('[]'), isEmpty);
    });
  });
}
