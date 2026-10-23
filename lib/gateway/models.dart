// Domain types shared by the gateway client, the engine and storage.

/// Who authored a message.
enum Role { system, user, assistant }

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
  });

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

/// Message sent over the wire to the gateway.
typedef ApiMessage = ({Role role, String content});

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

/// Why a turn ended — mirrors the OpenAI `finish_reason` vocabulary.
enum FinishReason { stop, length, contentFilter, other }

FinishReason finishReasonFromWire(String? raw) {
  switch (raw) {
    case 'stop':
      return FinishReason.stop;
    case 'length':
      return FinishReason.length;
    case 'content_filter':
      return FinishReason.contentFilter;
    default:
      return FinishReason.other;
  }
}
