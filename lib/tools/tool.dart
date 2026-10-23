import 'dart:convert';

import '../gateway/models.dart';
import 'datetime_tool.dart';
import 'web_fetch.dart';
import 'web_search.dart';

/// A capability Halis can invoke mid-turn: a named function with a JSON
/// schema, executed on the device, whose text result is fed back to the
/// model so the turn can continue.
///
/// Implementations are deliberately small and dependency-free: each tool
/// owns its network I/O, timeout and error text. Errors are returned as
/// readable strings (never thrown across the engine boundary) so the model
/// can adapt — retry differently, pick another source, or answer with a
/// caveat.
abstract class HalisTool {
  /// Stable identifier offered to the model, e.g. `websearch`.
  String get name;

  /// One or two sentences telling the model what the tool is for and when
  /// to reach for it.
  String get description;

  /// JSON-schema map describing the accepted arguments.
  Map<String, dynamic> get parameters;

  /// Runs the tool. Must always terminate (internal timeouts) and must
  /// never throw; failures come back as `Error: …` text.
  Future<String> run(Map<String, dynamic> args);

  /// Short text for the activity chip shown above the answer while the
  /// tool runs: the query, the URL, the reported time.
  String labelFor(Map<String, dynamic> args);

  ToolSpec get spec => ToolSpec(
        name: name,
        description: description,
        parameters: parameters,
      );

  /// Shared HTTP identity for the bundled tools. Browser-flavoured so
  /// sites that filter non-browser agents still serve their pages.
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Mobile Safari/537.36 ChatHalis/1.2';
}

/// The tools every Halis ships with, in display order.
List<HalisTool> buildHalisTools() => [
      WebSearchTool(),
      WebFetchTool(),
      DatetimeTool(),
    ];

/// Parses raw model arguments into a typed map, tolerating empty payloads
/// and the sloppy JSON shapes small models occasionally emit.
Map<String, dynamic> decodeToolArguments(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final value = jsonDecode(raw);
    if (value is Map) {
      return {for (final k in value.keys) '$k': value[k]};
    }
  } catch (_) {}
  return const {};
}
