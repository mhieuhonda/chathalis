import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chathalis/core/strings.dart';
import 'package:chathalis/core/theme.dart';
import 'package:chathalis/data/chat_repository.dart';
import 'package:chathalis/engine/app_store.dart';
import 'package:chathalis/engine/chat_controller.dart';
import 'package:chathalis/engine/usage_tracker.dart';
import 'package:chathalis/gateway/models.dart';
import 'package:chathalis/ui/chat/chat_screen.dart';

/// The composer strip and input gate, driven the way a real 429 plays out:
/// the meter fills, the strip appears, and the lock freezes the input.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  late UsageTracker usage;

  Future<void> pumpComposer(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    usage = UsageTracker(storage: prefs)..start();
    final store = AppStore(repository: _FakeRepository())..load();
    final chat = ChatController(
      conversationId: 'test-conv',
      repository: _FakeRepository(),
      usage: usage,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStore>.value(value: store),
          ChangeNotifierProvider<UsageTracker>.value(value: usage),
          ChangeNotifierProvider<ChatController>.value(value: chat),
        ],
        child: MaterialApp(
          theme: HalisTheme.light(),
          home: const Scaffold(body: ComposerProxy()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no strip below 80%, and the input is live', (tester) async {
    await pumpComposer(tester);
    usage.record();
    await tester.pumpAndSettle();

    final s = Strings.of(AppLocale.english);
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);
    expect(find.text(s.inputHint), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    usage.dispose();
  });

  testWidgets('the strip surfaces at 80% with a percentage', (tester) async {
    await pumpComposer(tester);
    for (var i = 0; i < 160; i++) {
      usage.record();
    }
    await tester.pumpAndSettle();

    expect(usage.percent, 80);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.textContaining('80%'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    usage.dispose();
  });

  testWidgets('a 429 locks the input, pins the strip red, and counts down',
      (tester) async {
    await pumpComposer(tester);
    usage.onRateLimited();
    await tester.pumpAndSettle();

    final s = Strings.of(AppLocale.english);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.textContaining(s.usageLockedStrip(usage.remainingLock)),
        findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);

    // The gate: the field goes inert while the lock stands.
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    usage.dispose();
  });
}

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
