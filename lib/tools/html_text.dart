import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

/// Turns a raw HTML document into the readable text a language model wants:
/// paragraphs, headings, list bullets and links, with scripts, styles,
/// chrome and layout noise gone.
///
/// The output is markdown-flavoured rather than strictly plain so structure
/// survives the trip — headings keep their level, links stay clickable.

/// Hard cap on extracted text, in characters, so a runaway page can never
/// flood the model's context.
const int maxExtractedChars = 96 * 1024;

/// Tags whose entire subtree is dropped.
const Set<String> _skipped = {
  'script', 'style', 'noscript', 'template', 'iframe', 'object', 'embed',
  'svg', 'canvas', 'form', 'input', 'select', 'button', 'nav', 'aside',
  'footer', 'header', 'dialog', 'meta', 'link', 'head',
};

/// Block-level tags that end the current paragraph.
const Set<String> _blocks = {
  'p', 'div', 'section', 'article', 'main', 'address', 'blockquote',
  'details', 'summary', 'fieldset', 'figcaption', 'figure', 'dl', 'dt',
  'dd', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'table',
  'tr', 'pre', 'hr', 'br', 'center',
};

Document parseHtml(String source) => parser.parse(source);

/// The page title, trimmed, or the empty string.
String extractTitle(Document doc) =>
    doc.querySelector('title')?.text.trim() ?? '';

/// Renders the document body as readable markdown-flavoured text.
String htmlToReadableText(Document doc) {
  final body = doc.body;
  if (body == null) return '';
  final out = _Renderer();
  out.walk(body);
  return out.finish();
}

class _Renderer {
  final StringBuffer _out = StringBuffer();
  int _listDepth = 0;

  /// Last code unit written: 0 means nothing yet, 10 means a newline.
  int _last = 0;

  bool get _atLineStart => _last == 0 || _last == 10;

  void walk(Node node) {
    if (node is! Element) {
      if (node is Text) _write(_squeeze(node.text));
      return;
    }
    final tag = node.localName ?? '';
    if (_skipped.contains(tag)) return;

    switch (tag) {
      case 'br':
        _newline();
        return;
      case 'hr':
        _endParagraph();
        _write('\n---\n');
        _endParagraph();
        return;
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _endParagraph();
        final level = switch (tag) {
          'h1' => 1,
          'h2' => 2,
          'h3' => 3,
          'h4' => 4,
          _ => 4,
        };
        _write('${'#' * level} ${_squeeze(node.text.trim())}');
        _endParagraph();
        return;
      case 'li':
        _newline();
        _write('${'  ' * (_listDepth - 1)}- ');
        for (final child in node.nodes) {
          walk(child);
        }
        return;
      case 'ul' || 'ol':
        _endParagraph();
        _listDepth++;
        for (final child in node.nodes) {
          walk(child);
        }
        _listDepth--;
        _endParagraph();
        return;
      case 'tr':
        _endParagraph();
        final cells = node.children
            .where((c) => c.localName == 'td' || c.localName == 'th')
            .map((c) => _squeeze(c.text.trim()))
            .where((c) => c.isNotEmpty)
            .toList();
        if (cells.isNotEmpty) _write(cells.join(' | '));
        _endParagraph();
        return;
      case 'pre':
        _endParagraph();
        _write('```\n${node.text.trim()}\n```');
        _endParagraph();
        return;
      case 'img':
        final alt = node.attributes['alt'];
        if (alt != null && alt.trim().isNotEmpty) {
          _write('(${_squeeze(alt.trim())})');
        }
        return;
      case 'a':
        final href = node.attributes['href']?.trim() ?? '';
        final text = _squeeze(node.text.trim());
        final absolute = _absoluteUrl(href);
        if (text.isNotEmpty && absolute != null) {
          _write('[$text]($absolute)');
        } else if (text.isNotEmpty) {
          _write(text);
        }
        return;
      default:
        break;
    }

    final isBlock = _blocks.contains(tag);
    if (isBlock) _endParagraph();
    for (final child in node.nodes) {
      walk(child);
    }
    if (isBlock) _endParagraph();
  }

  void _write(String text) {
    if (text.isEmpty) return;
    _out.write(text);
    _last = text.codeUnitAt(text.length - 1);
  }

  void _newline() {
    if (!_atLineStart) {
      _out.writeln();
      _last = 10;
    }
  }

  void _endParagraph() {
    if (_last == 0) return;
    if (_last == 10) {
      _out.writeln();
    } else {
      _out.writeln();
      _out.writeln();
    }
    _last = 10;
  }

  String finish() {
    final lines = _out.toString().split('\n').map((l) => l.trimRight());
    final kept = <String>[];
    var blanks = 0;
    for (final line in lines) {
      if (line.isEmpty) {
        blanks++;
        if (blanks > 1) continue;
        kept.add('');
      } else {
        blanks = 0;
        kept.add(line);
      }
    }
    var text = kept.join('\n').trim();
    if (text.length > maxExtractedChars) {
      text = '${text.substring(0, maxExtractedChars)}\n\n[…]';
    }
    return text;
  }
}

/// Resolves link targets, dropping anchors, javascript: URLs and relative
/// fragments that mean nothing outside the original page.
String? _absoluteUrl(String href) {
  if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
    return null;
  }
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  if (uri.hasScheme) return uri.scheme.startsWith('http') ? uri.toString() : null;
  if (uri.hasAuthority) return 'https:$href';
  return null;
}

/// Collapses runs of whitespace into single spaces.
String _squeeze(String text) => text.replaceAll(RegExp(r'\s+'), ' ');
