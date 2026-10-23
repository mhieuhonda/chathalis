import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chathalis/data/chat_repository.dart';
import 'package:chathalis/gateway/models.dart';

/// Real-schema coverage over in-memory ffi SQLite. These are plain tests —
/// no widget binding — so real async works normally.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ChatRepository repo;
  late String convId;

  setUp(() async {
    repo = ChatRepository.instance;
    convId = 'conv-${DateTime.now().microsecondsSinceEpoch}';
    final conv = Conversation(
      id: convId,
      title: 'test conversation',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await repo.ensureConversation(conv);
  });

  ChatMessage msg(String role, String text) => ChatMessage(
        id: 'm-${DateTime.now().microsecondsSinceEpoch}-$text',
        role: role == 'user' ? Role.user : Role.assistant,
        content: text,
        createdAt: DateTime.now(),
      );

  test('messages land in seq order and keep their state', () async {
    await repo.insertMessage(convId, msg('user', 'question'));
    await repo.insertMessage(convId, msg('assistant', 'answer'));

    final messages = await repo.listMessages(convId);
    expect(messages.length, 2);
    expect(messages.map((m) => m.role), [Role.user, Role.assistant]);
    expect(messages.first.seq!, lessThan(messages.last.seq!));
  });

  test('deleting a conversation cascades to its messages', () async {
    await repo.insertMessage(convId, msg('user', 'to be deleted'));
    await repo.deleteConversation(convId);
    expect(await repo.listMessages(convId), isEmpty);
    expect(await repo.getConversation(convId), isNull);
  });

  test('inserting a message refreshes the conversation preview', () async {
    await repo.insertMessage(convId, msg('user', 'hello preview'));
    final conv = await repo.getConversation(convId);
    expect(conv, isNotNull);
    expect(conv!.lastPreview, contains('hello preview'));
  });

  test('counts track conversations and messages', () async {
    final before = await repo.counts();
    await repo.insertMessage(convId, msg('user', 'counting'));
    final after = await repo.counts();
    expect(after.$1, before.$1);
    expect(after.$2, greaterThan(before.$2));
  });

  test('a stored empty title round-trips as empty', () async {
    final conv = Conversation(
      id: 'empty-title',
      title: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await repo.ensureConversation(conv);
    final loaded = await repo.getConversation('empty-title');
    expect(loaded!.title, isEmpty); // the UI localizes the fallback
  });
}
