import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/chat_repository.dart';
import '../gateway/models.dart';

/// Root store: conversation list + aggregate stats for home and settings.
class AppStore extends ChangeNotifier {
  AppStore({ChatRepository? repository}) : _repo = repository ?? ChatRepository.instance;

  final ChatRepository _repo;

  List<Conversation> conversations = <Conversation>[];
  (int, int) counts = (0, 0);
  bool loaded = false;

  Future<void> load() async {
    final results = await Future.wait<dynamic>([
      _repo.listConversations(),
      _repo.counts(),
    ]);
    conversations = results[0] as List<Conversation>;
    counts = results[1] as (int, int);
    loaded = true;
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    await _repo.deleteConversation(id);
    await load();
  }

  Future<void> clearAll() async {
    await _repo.clearAll();
    await load();
  }
}
