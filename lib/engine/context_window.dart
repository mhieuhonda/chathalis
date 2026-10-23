import 'package:flutter/foundation.dart';

import '../gateway/models.dart';
import '../prompt/system_prompt.dart';

/// Token budget for replayed history: a 256k context window minus the 32k
/// output reservation and a generous safety margin for token-estimate drift.
const int historyTokenBudget = 190_000;

/// Assembles the wire messages for a turn: the system prompt plus as much
/// recent history as fits in the budget.
///
/// Reasoning text is never replayed — the gateway protocol treats it as
/// transient. Empty assistant turns (failures, stops before first byte) are
/// skipped so the model only ever sees complete exchanges.
List<ApiMessage> composeApiMessages(
  List<ChatMessage> messages, {
  int budget = historyTokenBudget,
}) {
  const charsPerToken = 3.8;
  final history = <ApiMessage>[];
  var remaining = budget;
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.role == Role.system) continue;
    if (m.content.trim().isEmpty) continue;
    final cost = (m.content.length / charsPerToken).ceil() + 4;
    if (cost > remaining) break;
    remaining -= cost;
    history.add((role: m.role, content: m.content));
  }
  return [
    (role: Role.system, content: HalisPrompt.identity),
    ...history.reversed,
  ];
}

/// Logs nothing by default; swapped in tests if ever needed.
void debugLog(String message) {
  if (kDebugMode) {
    debugPrint('chathalis: $message');
  }
}
