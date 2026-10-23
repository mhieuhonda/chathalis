import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/strings.dart';
import '../data/chat_repository.dart';
import '../gateway/models.dart';

/// Root store: conversation list + aggregate stats, plus the app-level
/// settings (language, appearance) that survive restarts.
class AppStore extends ChangeNotifier {
  AppStore({ChatRepository? repository}) : _repo = repository ?? ChatRepository.instance;

  final ChatRepository _repo;

  List<Conversation> conversations = <Conversation>[];
  (int, int) counts = (0, 0);
  bool loaded = false;

  AppLocale locale = AppLocale.english;
  ThemeSetting theme = ThemeSetting.light;

  Strings get strings => Strings.of(locale);

  static const _prefLocale = 'app.locale';
  static const _prefTheme = 'app.theme';

  Future<void> load() async {
    final results = await Future.wait<dynamic>([
      _repo.listConversations(),
      _repo.counts(),
      _loadSettings(),
    ]);
    conversations = results[0] as List<Conversation>;
    counts = results[1] as (int, int);
    loaded = true;
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString(_prefLocale);
      if (savedLocale == 'vi') {
        locale = AppLocale.vietnamese;
      } else {
        locale = AppLocale.english; // default
      }
      final savedTheme = prefs.getString(_prefTheme);
      if (savedTheme == 'dark') {
        theme = ThemeSetting.dark;
      } else {
        theme = ThemeSetting.light; // default
      }
    } catch (_) {
      // Preferences are cosmetic — never block startup on them.
    }
  }

  Future<void> setLocale(AppLocale value) async {
    if (value == locale) return;
    locale = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefLocale, value == AppLocale.vietnamese ? 'vi' : 'en');
    } catch (_) {}
  }

  Future<void> setTheme(ThemeSetting value) async {
    if (value == theme) return;
    theme = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefTheme, value == ThemeSetting.dark ? 'dark' : 'light');
    } catch (_) {}
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

/// The two looks ChatHalis ships with. Light is the default.
enum ThemeSetting { light, dark }
