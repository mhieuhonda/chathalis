import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../engine/app_store.dart';
import '../../gateway/models.dart';
import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/halis_mark.dart';

/// The conversation list, grouped by recency.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = store.strings;
    final c = context.halis;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            HalisMark(size: 20, color: c.ink),
            const SizedBox(width: 7),
            Text(
              '${s.appName}.',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).push(SettingsScreen.route()),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewChat(context),
        backgroundColor: c.ink,
        foregroundColor: c.paper,
        elevation: 0,
        highlightElevation: 0,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        icon: const Icon(Icons.edit_outlined, size: 19),
        label: Text(
          s.newChat,
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      body: !store.loaded
          ? const SizedBox.shrink()
          : store.conversations.isEmpty
              ? _EmptyHome()
              : _ConversationGroups(conversations: store.conversations),
    );
  }

  void _openNewChat(BuildContext context) {
    Navigator.of(context).push(
      ChatScreen.route(conversationId: HalisUtils.uuid()),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().strings;
    final c = context.halis;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: c.ink,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: HalisMark(size: 40, color: c.paper),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              s.homeEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              s.homeEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.55, color: c.inkSoft),
            ),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                ChatScreen.route(conversationId: HalisUtils.uuid()),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: c.ink,
                foregroundColor: c.paper,
                minimumSize: const Size(0, 52),
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: Text(
                s.homeEmptyCta,
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationGroups extends StatelessWidget {
  const _ConversationGroups({required this.conversations});

  final List<Conversation> conversations;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().strings;
    // conversations are already sorted newest-first; bucket them by day.
    final buckets = <String, List<Conversation>>{};
    const order = ['today', 'yesterday', 'last7', 'earlier'];
    for (final c in conversations) {
      final key = HalisUtils.dayGroup(c.updatedAt);
      (buckets[key] ??= []).add(c);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final key in order)
          if (buckets.containsKey(key)) ...[
            _GroupLabel(label: switch (key) {
              'today' => s.today,
              'yesterday' => s.yesterday,
              'last7' => s.last7Days,
              _ => s.earlier,
            }),
            for (final c in buckets[key]!)
              _ConversationTile(conversation: c),
          ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: c.inkFaint,
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final s = store.strings;
    final c = context.halis;
    final title =
        conversation.title.isEmpty ? s.untitledConversation : conversation.title;

    return Dismissible(
      key: ValueKey('conv-${conversation.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: c.dangerSoft,
        child: Icon(Icons.delete_outline_rounded, color: c.danger),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => store.deleteConversation(conversation.id),
      child: Material(
        color: c.paper,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            ChatScreen.route(
              conversationId: conversation.id,
              existingTitle: conversation.title,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: c.ink,
                        ),
                      ),
                      if (conversation.lastPreview.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          conversation.lastPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.inkSoft),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  HalisUtils.shortDate(conversation.updatedAt, s),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: c.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final s = context.read<AppStore>().strings;
    final c = context.halis;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          s.deleteConversation,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Text(
          s.deleteConversationConfirm,
          style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
