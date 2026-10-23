import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chathalis/app.dart';
import 'package:chathalis/core/strings.dart';
import 'package:chathalis/data/chat_repository.dart';
import 'package:chathalis/engine/usage_tracker.dart';
import 'package:chathalis/gateway/models.dart';

/// Pumps the real app shell over a fake repository, so the provider wiring,
/// the default (light, English) look and the settings surface are exercised
/// the way a cold boot would — without touching SQLite.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('boots to the empty home, light and English by default',
      (tester) async {
    final usage = await pumpApp(tester);

    // Empty-state copy comes from the English bundle.
    final en = Strings.of(AppLocale.english);
    expect(find.text(en.homeEmptyTitle), findsOneWidget);
    expect(find.text(en.homeEmptyCta), findsOneWidget);
    expect(find.text(en.newChat), findsOneWidget);

    // Light default.
    final ctx = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx).brightness, Brightness.light);

    usage.dispose();
  });

  testWidgets('settings opens with usage, preferences and data sections',
      (tester) async {
    final usage = await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final s = Strings.of(AppLocale.english);
    expect(find.text(s.settings), findsOneWidget);
    expect(find.text(s.usageSection.toUpperCase()), findsOneWidget);
    expect(find.text(s.usageTitle), findsOneWidget);
    expect(find.text(s.appearanceTitle), findsOneWidget);
    expect(find.text(s.languageTitle), findsOneWidget);

    // The data card sits below the fold in the test viewport.
    await tester.scrollUntilVisible(find.text(s.dataStoredLocally), 250);
    expect(find.text(s.clearAllData), findsOneWidget);

    usage.dispose();
  });

  testWidgets('switching to dark mode repaints the canvas', (tester) async {
    final usage = await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final s = Strings.of(AppLocale.english);
    await tester.tap(find.text(s.appearanceDark));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx).brightness, Brightness.dark);

    usage.dispose();
  });

  testWidgets('vietnamese takes over the whole shell from settings',
      (tester) async {
    final usage = await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // The language segment sits below the fold in the test viewport.
    await tester.scrollUntilVisible(find.text('Tiếng Việt'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();

    final s = Strings.of(AppLocale.vietnamese);
    expect(find.text(s.settings), findsOneWidget); // app bar
    // The list stayed scrolled at the language card, so the visible proof
    // of the flip is right around it.
    expect(find.text(s.appearanceTitle), findsOneWidget);
    await tester.scrollUntilVisible(find.text(s.dataStoredLocally), 250);
    expect(find.text(s.clearAllData), findsOneWidget);

    usage.dispose();
  });

  testWidgets('the usage card pins at 100% while the 429 lock stands',
      (tester) async {
    final usage = await pumpApp(tester);

    usage.onRateLimited();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final s = Strings.of(AppLocale.english);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text(s.usageLimitReached), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);

    usage.dispose();
  });
}

/// In-memory repository stand-in: no SQLite, no plugin calls.
class _FakeRepository implements ChatRepository {
  @override
  Future<void> clearAll() async {}

  @override
  Future<void> createConversation(Conversation c) async {}

  @override
  Future<void> deleteConversation(String id) async {}

  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<void> ensureConversation(Conversation c) async {}

  @override
  Future<Conversation?> getConversation(String id) async => null;

  @override
  Future<void> insertMessage(String conversationId, ChatMessage m) async {}

  @override
  Future<List<Conversation>> listConversations() async => const <Conversation>[];

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async =>
      const <ChatMessage>[];

  @override
  Future<void> renameConversation(String id, String title) async {}

  @override
  Future<(int, int)> counts() async => (0, 0);
}

/// A fresh app + tracker per test, so no state leaks between them.
Future<UsageTracker> pumpApp(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  final usage = UsageTracker(storage: prefs)..start();
  await tester.pumpWidget(ChatHalisApp(usage: usage, repository: _FakeRepository()));
  await tester.pumpAndSettle();
  return usage;
}
