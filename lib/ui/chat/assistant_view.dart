import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../gateway/models.dart';
import '../widgets/halis_mark.dart';
import 'code_block.dart';
import 'notices.dart';
import 'thinking_panel.dart';

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
                  message: m.error ?? HalisStrings.errUnknown,
                  onRetry: onRegenerate,
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
    return Row(
      children: [
        _GhostIcon(
          tooltip: HalisStrings.copy,
          icon: Icons.copy_rounded,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: message.content));
            onCopied();
          },
        ),
        if (isLastAssistant) ...[
          const SizedBox(width: 4),
          _GhostIcon(
            tooltip: HalisStrings.regenerate,
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
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: HalisPalette.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 15, color: HalisPalette.inkSoft),
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
    // A caret appended while streaming: unclosed code fences pick it up
    // inside the block, everywhere else it reads as a plain cursor.
    final data = streaming ? '$text ▍' : text;

    // GptMarkdownTheme (the package's own inherited widget) carries our
    // typography without touching the material Theme, keeping the two
    // libraries' ThemeExtension types apart.
    return GptMarkdownTheme(
      gptThemeData: GptMarkdownThemeData(
        brightness: Brightness.light,
        linkColor: HalisPalette.accent,
        linkHoverColor: HalisPalette.accent,
        h1: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: HalisPalette.ink,
        ),
        h2: const TextStyle(
          fontSize: 17.5,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: HalisPalette.ink,
        ),
        h3: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: HalisPalette.ink,
        ),
        inlineCode: const InlineCodeStyle(
          fontFamily: 'JetBrainsMono',
          color: HalisPalette.ink,
          backgroundColor: HalisPalette.surface,
        ),
      ),
      child: GptMarkdown(
        data,
        isStreaming: false,
        style: const TextStyle(
          fontSize: 15,
          height: 1.6,
          color: HalisPalette.ink,
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
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
