import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../engine/app_store.dart';
import '../../engine/usage_tracker.dart';
import '../../gateway/models.dart';
import '../widgets/halis_mark.dart';
import 'code_block.dart';
import 'notices.dart';
import 'thinking_panel.dart';
import 'tool_trace.dart';

/// How an assistant reply is laid out: avatar on the left, then the thinking
/// panel, the markdown answer, and any notices — streaming or finished.
class AssistantView extends StatelessWidget {
  const AssistantView({
    super.key,
    required this.message,
    required this.isStreaming,
    required this.isLast,
    required this.onRegenerate,
    required this.onCopied,
  });

  final ChatMessage message;

  /// True while this message's turn is still being generated.
  final bool isStreaming;

  /// True for the newest assistant message in the conversation.
  final bool isLast;

  final VoidCallback onRegenerate;
  final VoidCallback onCopied;

  bool get _live => isStreaming;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().strings;
    final locked = context.watch<UsageTracker>().locked;
    final m = message;
    final hasBody = m.content.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: HalisAvatar(size: 28),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.toolUses.isNotEmpty) ...[
                ToolTraceView(uses: m.toolUses),
                const SizedBox(height: 10),
              ],
              if (m.reasoning.trim().isNotEmpty) ...[
                ThinkingPanel(
                  reasoning: m.reasoning,
                  streaming: _live && !hasBody,
                  reasoningMs: m.reasoningMs,
                ),
                const SizedBox(height: 10),
              ],
              if (hasBody)
                _MarkdownBody(
                  text: m.content,
                  streaming: _live,
                )
              else if (_live && m.reasoning.trim().isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: TypingDots(),
                ),
              if (m.truncated) const TruncationNotice(),
              if (m.state == MessageState.interrupted && !_live)
                const StoppedNotice(),
              if (m.state == MessageState.failed && !_live)
                ErrorCard(
                  message: m.error ?? s.errUnknown,
                  onRetry: onRegenerate,
                  // Regenerating replays the newest user turn, so the
                  // action only makes sense on the newest reply.
                  showRetry: !locked && isLast,
                ),
              if (!_live && hasBody) ...[
                const SizedBox(height: 6),
                _Actions(
                  message: m,
                  isLastAssistant: isLast,
                  onRegenerate: onRegenerate,
                  onCopied: onCopied,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.message,
    required this.isLastAssistant,
    required this.onRegenerate,
    required this.onCopied,
  });

  final ChatMessage message;
  final bool isLastAssistant;
  final VoidCallback onRegenerate;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().strings;
    return Row(
      children: [
        _GhostIcon(
          tooltip: s.copy,
          icon: Icons.copy_rounded,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: message.content));
            onCopied();
          },
        ),
        if (isLastAssistant) ...[
          const SizedBox(width: 4),
          _GhostIcon(
            tooltip: s.regenerate,
            icon: Icons.refresh_rounded,
            onTap: onRegenerate,
          ),
        ],
      ],
    );
  }
}

class _GhostIcon extends StatelessWidget {
  const _GhostIcon({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 15, color: c.inkSoft),
          ),
        ),
      ),
    );
  }
}

/// Markdown body with the ChatHalis typography and dark code blocks.
class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    // A caret appended while streaming: unclosed code fences pick it up
    // inside the block, everywhere else it reads as a plain cursor.
    final data = streaming ? '$text ▍' : text;

    // GptMarkdownTheme (the package's own inherited widget) carries our
    // typography without touching the material Theme, keeping the two
    // libraries' ThemeExtension types apart.
    return GptMarkdownTheme(
      gptThemeData: GptMarkdownThemeData(
        brightness: Theme.of(context).brightness,
        linkColor: c.accent,
        linkHoverColor: c.accent,
        h1: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: c.ink,
        ),
        h2: TextStyle(
          fontSize: 17.5,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: c.ink,
        ),
        h3: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: c.ink,
        ),
        inlineCode: InlineCodeStyle(
          fontFamily: 'JetBrainsMono',
          color: c.ink,
          backgroundColor: c.surface,
        ),
      ),
      child: GptMarkdown(
        data,
        isStreaming: false,
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: c.ink,
        ),
        codeBuilder: (context, name, code, closed) => CodeBlockView(
          language: name,
          code: code,
          closed: closed,
        ),
        onLinkTap: (url, title) => _openLink(url),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing on the device can open the link — silently ignore rather
      // than crash the chat over a bad href.
    }
  }
}
