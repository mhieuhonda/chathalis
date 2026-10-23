/// Incremental decoder for Server-Sent Events streams.
///
/// Handles chunk boundaries, CRLF line endings and comment lines. Each
/// `data:` line is surfaced as its own payload — exactly the framing used by
/// OpenAI-compatible chat-completions streams.
class SseDecoder {
  String _pendingLine = '';

  /// Feeds decoded text and returns every complete data payload.
  List<String> push(String chunk) {
    final out = <String>[];
    var start = 0;
    while (true) {
      final nl = chunk.indexOf('\n', start);
      if (nl < 0) break;
      _consume(_pendingLine + chunk.substring(start, nl), out);
      _pendingLine = '';
      start = nl + 1;
    }
    _pendingLine += chunk.substring(start);
    return out;
  }

  /// Flushes the last line if the stream ended without a trailing newline.
  List<String> close() {
    if (_pendingLine.isEmpty) return const <String>[];
    final out = <String>[];
    _consume(_pendingLine, out);
    _pendingLine = '';
    return out;
  }

  void _consume(String rawLine, List<String> out) {
    var line = rawLine;
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.isEmpty || line.startsWith(':')) return;
    if (!line.startsWith('data:')) return; // event:/id:/retry: — unused
    var payload = line.substring(5);
    if (payload.startsWith(' ')) payload = payload.substring(1);
    if (payload.isNotEmpty) out.add(payload);
  }
}
