import 'package:flutter/foundation.dart';

import '../gateway/models.dart';
import '../prompt/system_prompt.dart';

/// Token budget for replayed history: a 256k context window minus the 32k
/// output reservation and a generous safety margin for token-estimate drift.
const int historyTokenBudget = 190_000;

/// Assembles the wire messages for a turn: the system prompt plus as much
/// recent history as fits in the budget, then any in-flight tool traffic
/// from the current turn appended verbatim.
///
/// Reasoning text is never replayed — the gateway protocol treats it as
/// transient. Empty assistant turns (failures, stops before first byte) are
/// skipped so the model only ever sees complete exchanges, and [excludeId]
/// keeps the still-streaming assistant placeholder out of the replay while
/// its own tool rounds are in flight.
List<ApiMessage> composeApiMessages(
  List<ChatMessage> messages, {
  int budget = historyTokenBudget,
  String? excludeId,
  List<ApiMessage> tail = const [],
}) {
  const charsPerToken = 3.8;
  final history = <ApiMessage>[];
  var remaining = budget;
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.role == Role.system) continue;
    if (m.id == excludeId) continue;
    if (m.content.trim().isEmpty) continue;
    final cost = (m.content.length / charsPerToken).ceil() + 4;
    if (cost > remaining) break;
    remaining -= cost;
    history.add(ApiMessage(role: m.role, content: m.content));
  }
  return [
    ApiMessage(role: Role.system, content: HalisPrompt.build()),
    ...history.reversed,
    ...tail,
  ];
}

/// Logs nothing by default; swapped in tests if ever needed.
void debugLog(String message) {
  if (kDebugMode) {
    debugPrint('chathalis: $message');
  }
}
