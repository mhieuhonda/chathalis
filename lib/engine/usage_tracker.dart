import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the hourly chat budget: up to [hourlyLimit] requests inside any
/// rolling hour.
///
/// Filling the window — or a 429 arriving from the gateway — locks chatting
/// for [cooldown] (the hour plus a 5-minute buffer). The lock is applied
/// exactly once per lock window: hammering send during a lock, or tripping
/// a second 429, never extends the wait. The UI never shows request counts,
/// only a percentage.
class UsageTracker extends ChangeNotifier {
  UsageTracker({SharedPreferences? storage, int Function()? clock})
      : _prefs = storage,
        _now = clock ?? _defaultNow;

  /// The app-wide tracker. Loads persisted state and keeps itself fresh.
  static final UsageTracker instance = UsageTracker()..start();

  static const int hourlyLimit = 200;

  /// Rolling window the limit is measured over.
  static const Duration window = Duration(hours: 1);

  /// Wait after maxing out: the server's hour plus a 5-minute buffer.
  static const Duration cooldown = Duration(hours: 1, minutes: 5);

  static const String _prefWindow = 'usage.window';
  static const String _prefLockedUntil = 'usage.locked_until';

  static int _defaultNow() => DateTime.now().millisecondsSinceEpoch;

  final SharedPreferences? _prefs;
  final int Function() _now;

  /// Timestamps of the requests inside the window, oldest first.
  final List<int> _windowMs = <int>[];

  int? _lockedUntilMs;
  Timer? _tick;

  int _nowMs() => _now();

  // ---------------------------------------------------------------- state

  /// True while the cooldown blocks new messages.
  bool get locked {
    _silentlyExpire();
    return _lockedUntilMs != null;
  }

  /// Time left before chatting works again. Zero when unlocked.
  Duration get remainingLock {
    _silentlyExpire();
    final until = _lockedUntilMs;
    if (until == null) return Duration.zero;
    final left = until - _nowMs();
    return left <= 0 ? Duration.zero : Duration(milliseconds: left);
  }

  /// Used fraction of the limit, `0.0–1.0`. A standing lock forces `1.0`
  /// so the meter reads full, exactly like a caught 429.
  double get fraction {
    _silentlyPrune();
    _silentlyExpire();
    if (_lockedUntilMs != null) return 1;
    return _windowMs.length / hourlyLimit;
  }

  /// Whole percent for display, never above 100.
  int get percent => (fraction * 100).round().clamp(0, 100);

  /// True when the composer strip should surface the budget.
  bool get showHint => locked || fraction >= 0.8;

  // --------------------------------------------------------------- actions

  /// Called just before a request goes out. Filling the window locks.
  void record() {
    _silentlyPrune();
    _silentlyExpire();
    if (_lockedUntilMs != null) return; // defensive; the UI gates this
    _windowMs.add(_nowMs());
    if (_windowMs.length >= hourlyLimit) {
      _lockedUntilMs = _nowMs() + cooldown.inMilliseconds;
    }
    _persist();
    notifyListeners();
  }

  /// A 429 came back. Applies the cooldown exactly once — repeats while a
  /// lock already stands are ignored, so the wait can never stack.
  void onRateLimited() {
    _silentlyExpire();
    if (_lockedUntilMs != null) return; // first 429 already started the clock
    _lockedUntilMs = _nowMs() + cooldown.inMilliseconds;
    _windowMs.clear();
    _persist();
    notifyListeners();
  }

  // -------------------------------------------------------------- plumbing

  /// Loads persisted state and starts a light ticker that ages the window
  /// out and releases expired locks.
  Future<void> start() async {
    SharedPreferences? prefs = _prefs;
    prefs ??= await _tryPrefs();
    if (prefs != null) {
      _loadFrom(prefs);
    }
    _silentlyPrune();
    _silentlyExpire();
    _tick ??= Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    // The screen may already be painted; surface whatever was restored.
    if (prefs != null) notifyListeners();
  }

  /// Re-evaluates time-based state; notifies when something changed.
  void refresh() {
    final lockGone = _silentlyExpire();
    final windowShrank = _silentlyPrune();
    if (lockGone) _persist();
    if (lockGone || windowShrank) notifyListeners();
  }

  Future<SharedPreferences?> _tryPrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null; // storage is best-effort; the meter still works in memory
    }
  }

  void _loadFrom(SharedPreferences prefs) {
    _windowMs.clear();
    final raw = prefs.getString(_prefWindow);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _windowMs.addAll(
              decoded.whereType<num>().map((n) => n.toInt()).toList());
        }
      } catch (_) {}
    }
    _lockedUntilMs = prefs.getInt(_prefLockedUntil);
  }

  void _persist() {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      _silentlyPrune();
      prefs.setString(_prefWindow, jsonEncode(_windowMs));
      final lockedUntil = _lockedUntilMs;
      if (lockedUntil == null) {
        prefs.remove(_prefLockedUntil);
      } else {
        prefs.setInt(_prefLockedUntil, lockedUntil);
      }
    } catch (_) {}
  }

  /// Drops requests older than the window. Returns true if any were dropped.
  bool _silentlyPrune() {
    final cutoff = _nowMs() - window.inMilliseconds;
    var dropped = false;
    while (_windowMs.isNotEmpty && _windowMs.first <= cutoff) {
      _windowMs.removeAt(0);
      dropped = true;
    }
    return dropped;
  }

  /// Releases an expired lock and resets the window. Returns true if the
  /// lock was standing and is now gone.
  bool _silentlyExpire() {
    final lockedUntil = _lockedUntilMs;
    if (lockedUntil == null) return false;
    if (_nowMs() < lockedUntil) return false;
    _lockedUntilMs = null;
    _windowMs.clear(); // a finished lock means a fresh hour
    return true;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
