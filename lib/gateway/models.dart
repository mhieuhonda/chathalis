// Domain types shared by the gateway client, the engine and storage.

import 'dart:convert';

/// Who authored a message. [Role.tool] carries a tool result back to the
/// model — it never appears in the visible transcript.
enum Role { system, user, assistant, tool }

/// Lifecycle of a persisted message.
enum MessageState { ok, interrupted, failed }

/// A message inside a conversation.
///
/// The streaming engine mutates the assistant message in place while a turn
/// is being generated; a snapshot is written to storage when the turn ends.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    this.content = '',
    this.reasoning = '',
    this.state = MessageState.ok,
    this.error,
    this.truncated = false,
    this.reasoningMs,
    this.seq,
    List<ToolUse>? toolUses,
  }) : toolUses = toolUses ?? <ToolUse>[];

  final String id;
  final Role role;

  /// The visible answer text.
  String content;

  /// Chain-of-thought text, shown in the collapsible thinking panel.
  String reasoning;

  MessageState state;

  /// Error detail when [state] is [MessageState.failed].
  String? error;

  /// True when the turn ended because the 32k output cap was reached.
  bool truncated;

  /// How long the model thought before answering, in milliseconds.
  int? reasoningMs;

  final DateTime createdAt;

  /// Monotonic order inside the conversation (assigned on insert).
  final int? seq;

  bool get isBusy => false; // placeholder for future streaming marker

  /// What Halis did to produce this reply — searches, pages read, time
  /// checks — in the order they ran. Rendered as small chips above the
  /// answer and persisted with the message.
  final List<ToolUse> toolUses;
}

/// One tool execution attached to an assistant reply.
class ToolUse {
  ToolUse({
    required this.tool,
    required this.label,
    this.ms,
    this.running = false,
  });

  /// Stable tool identifier, e.g. `websearch`.
  final String tool;

  /// Human-readable summary of what was done: the query, the URL, the
  /// reported time.
  String label;

  /// How long the tool took, in milliseconds (null while still running).
  int? ms;

  /// True between the call being issued and its result arriving.
  bool running;

  Map<String, dynamic> toJson() => {
        'tool': tool,
        'label': label,
        if (ms != null) 'ms': ms,
      };

  static List<ToolUse> listFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic> && e['tool'] is String)
            ToolUse(
              tool: e['tool']! as String,
              label: (e['label'] ?? '') as String,
              ms: e['ms'] is int ? e['ms'] as int : null,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String listToJson(List<ToolUse> uses) =>
      jsonEncode([for (final u in uses) u.toJson()]);
}

/// A conversation as shown on the home screen.
class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastPreview = '',
  });

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String lastPreview;
}

/// A request for the model to call a tool, as decided in a streamed turn.
class ToolCall {
  const ToolCall({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;

  /// Raw JSON text of the arguments, exactly as the model produced it.
  final String arguments;
}

/// The wire-level description of a tool offered to the model.
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;

  /// JSON-schema map describing the tool's arguments.
  final Map<String, dynamic> parameters;
}

/// A message assembled for the gateway: the system prompt, replayed
/// history, an in-flight assistant tool-call decision, or a tool result.
class ApiMessage {
  ApiMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolCallId,
  });

  /// An assistant turn that asks for tools to run.
  ApiMessage.toolRequest({
    required String content,
    required List<ToolCall> toolCalls,
  }) : this(
          role: Role.assistant,
          content: content,
          toolCalls: toolCalls,
        );

  /// The result of one executed tool, keyed to its call id.
  ApiMessage.toolResult({required String callId, required String content})
      : this(role: Role.tool, content: content, toolCallId: callId);

  final Role role;
  final String content;

  /// Present when the assistant asked for tools ([Role.assistant] only).
  final List<ToolCall> toolCalls;

  /// Present on [Role.tool] messages, matching the originating call id.
  final String? toolCallId;
}

/// Token accounting for a finished turn, when the gateway reports it.
class TurnUsage {
  const TurnUsage({
    required this.promptTokens,
    required this.completionTokens,
    this.reasoningTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int? reasoningTokens;
}

/// Why a turn ended — mirrors the chat-completions `finish_reason`
/// vocabulary. [FinishReason.toolCalls] means the model asked for tools and
/// the engine must run them, then continue the turn.
enum FinishReason { stop, length, contentFilter, toolCalls, other }

FinishReason finishReasonFromWire(String? raw) {
  switch (raw) {
    case 'stop':
      return FinishReason.stop;
    case 'length':
      return FinishReason.length;
    case 'content_filter':
      return FinishReason.contentFilter;
    case 'tool_calls':
      return FinishReason.toolCalls;
    default:
      return FinishReason.other;
  }
}
