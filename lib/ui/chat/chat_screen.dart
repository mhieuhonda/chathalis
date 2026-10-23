import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../engine/app_store.dart';
import '../../engine/chat_controller.dart';
import '../../engine/usage_tracker.dart';
import '../../gateway/models.dart';
import '../widgets/halis_mark.dart';
import 'assistant_view.dart';
import 'composer.dart';
import 'user_bubble.dart';

/// One conversation: message stream + composer.
class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.existingTitle,
  });

  final String conversationId;
  final String? existingTitle;

  static Route<void> route({
    required String conversationId,
    String? existingTitle,
  }) {
    return MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: conversationId,
        existingTitle: existingTitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatController(
        conversationId: conversationId,
        isNewConversation: existingTitle == null,
        strings: context.read<AppStore>().strings,
      )..load(),
      child: const _ChatView(),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView();

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final ScrollController _scroll = ScrollController();
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.offset > 320;
      if (show != _showJump) setState(() => _showJump = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final s = context.watch<AppStore>().strings;
    final c = context.halis;
    final isNew = chat.messages.isEmpty;
    // New conversations hold the placeholder title until the first send;
    // loaded ones may have an empty title stored. Both read as "Untitled".
    final title = chat.title.isEmpty || chat.title == 'ChatHalis'
        ? s.untitledConversation
        : chat.title;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) context.read<AppStore>().load();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                s.assistantByline,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: c.inkFaint,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: s.chatOptions,
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => _openMenu(chat),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: isNew
            ? _EmptyChat()
            : Column(
                children: [
                  Divider(height: 1, color: c.hairline),
                  Expanded(
                    child: Stack(
                      children: [
                        _MessageList(scroll: _scroll),
                        if (_showJump)
                          Positioned(
                            right: 16,
                            bottom: 12,
                            child: _JumpToBottom(scroll: _scroll),
                          ),
                      ],
                    ),
                  ),
                  const ComposerProxy(),
                ],
              ),
      ),
    );
  }

  Future<void> _openMenu(ChatController chat) async {
    final s = context.read<AppStore>().strings;
    final c = context.halis;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(s.rename,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: c.danger),
              title: Text(
                s.deleteConversation,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, color: c.danger),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await _renameDialog(chat);
      case 'delete':
        final ok = await _confirm(
          context,
          title: s.deleteConversation,
          body: s.deleteConversationConfirm,
          confirm: s.delete,
          danger: true,
        );
        if (ok == true && mounted) {
          final store = context.read<AppStore>();
          await store.deleteConversation(chat.conversationId);
          if (mounted) {
            Navigator.of(context).pop(); // back to home
          }
        }
    }
  }

  Future<void> _renameDialog(ChatController chat) async {
    final s = context.read<AppStore>().strings;
    final controller = TextEditingController(text: chat.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.renameTitle,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.renameHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(s.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await chat.renameTo(name);
    }
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  bool danger = false,
}) {
  final c = context.halis;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final s = context.read<AppStore>().strings;
      return AlertDialog(
        title: Text(title,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: Text(body,
            style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: danger
                ? TextButton.styleFrom(foregroundColor: c.danger)
                : null,
            child: Text(confirm),
          ),
        ],
      );
    },
  );
}

/// Composer wrapper kept separate so both layouts share it. The hourly
/// usage strip surfaces only when the budget is running low or locked.
class ComposerProxy extends StatelessWidget {
  const ComposerProxy({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final usage = context.watch<UsageTracker>();
    final s = context.watch<AppStore>().strings;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (usage.showHint)
          _UsageStrip(
            locked: usage.locked,
            text: usage.locked
                ? s.usageLockedStrip(usage.remainingLock)
                : s.usageNear(usage.percent),
          ),
        Composer(
          streaming: chat.isStreaming,
          locked: usage.locked,
          onSend: chat.send,
          onStop: chat.stop,
        ),
      ],
    );
  }
}

/// One-line budget reminder that sits just above the composer.
class _UsageStrip extends StatelessWidget {
  const _UsageStrip({required this.locked, required this.text});

  final bool locked;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    final color = locked ? c.danger : c.warn;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: locked ? c.dangerSoft : c.warnSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            locked ? Icons.hourglass_top_rounded : Icons.bolt_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                text,
                key: ValueKey<String>(text),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final s = context.watch<AppStore>().strings;
    final messages = chat.messages;
    // Reverse list: index 0 is the newest, so streaming growth pins itself
    // to the viewport bottom without manual scrolling.
    return ListView.builder(
      controller: scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[messages.length - 1 - i];
        final isLastMessage = i == 0;
        final isStreamingThis = chat.isStreaming && isLastMessage;
        final isLastAssistant =
            isLastMessage && m.role == Role.assistant;

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _Entrance(
            child: m.role == Role.user
                ? UserBubble(text: m.content)
                : AssistantView(
                    message: m,
                    isStreaming: isStreamingThis,
                    isLast: isLastAssistant,
                    onRegenerate: chat.regenerate,
                    onCopied: () => _toast(context, s.copied),
                  ),
          ),
        );
      },
    );
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// Subtle fade + rise when a message first appears.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _JumpToBottom extends StatelessWidget {
  const _JumpToBottom({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Material(
      color: c.ink,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.keyboard_double_arrow_down_rounded,
              size: 20, color: c.paper),
        ),
      ),
    );
  }
}

/// First-run greeting with a few starting points.
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().strings;
    final c = context.halis;
    return LayoutBuilder(builder: (context, dims) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: dims.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 64),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: c.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: HalisMark(size: 36, color: c.paper),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  s.chatGreetingTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.chatGreetingSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: c.inkSoft,
                  ),
                ),
                const SizedBox(height: 28),
                const _Suggestions(),
                const SizedBox(height: 28),
                const ComposerProxy(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatController>();
    final s = context.watch<AppStore>().strings;
    return Column(
      children: [
        for (final suggestion in s.suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SuggestionTile(text: suggestion, onTap: () => chat.send(suggestion)),
          ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.hairline, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_outward_rounded, size: 15, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
