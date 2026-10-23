import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chathalis/engine/usage_tracker.dart';

void main() {
  late int fakeNowMs;
  final t0 = DateTime(2026, 10, 23, 10, 0, 0).millisecondsSinceEpoch;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fakeNowMs = t0;
  });

  /// A tracker on mocked storage, so persistence round-trips are real.
  Future<UsageTracker> makeTracker() async {
    final prefs = await SharedPreferences.getInstance();
    final tracker = UsageTracker(storage: prefs, clock: () => fakeNowMs);
    await tracker.start();
    addTearDown(tracker.dispose);
    return tracker;
  }

  group('window bookkeeping', () {
    test('starts unlocked at zero percent', () async {
      final tracker = await makeTracker();
      expect(tracker.locked, isFalse);
      expect(tracker.fraction, 0);
      expect(tracker.percent, 0);
      expect(tracker.showHint, isFalse);
    });

    test('requests age out of the rolling hour', () async {
      final tracker = await makeTracker();
      tracker.record(); // t0
      fakeNowMs += 59 * 60 * 1000;
      tracker.record(); // t0+59min — both still counted
      expect(tracker.percent, 1); // 2/200 = 1%
      fakeNowMs += 2 * 60 * 1000; // t0+61min — the first has aged out
      tracker.refresh();
      expect(tracker.percent, 1); // 1/200 = 0.5% → 1 rounded
    });
  });

  group('filling the hour locks the cooldown', () {
    test('the 200th request in an hour starts a 1h05 lock', () async {
      final tracker = await makeTracker();
      // 200 requests spaced 17s apart all fit inside one hour.
      for (var i = 0; i < UsageTracker.hourlyLimit; i++) {
        fakeNowMs += 17 * 1000;
        tracker.record();
      }
      expect(tracker.locked, isTrue);
      expect(tracker.fraction, 1.0);
      expect(tracker.percent, 100);
      expect(tracker.remainingLock.inMinutes, greaterThan(60));
      expect(tracker.remainingLock.inMinutes, lessThanOrEqualTo(65));
    });

    test('the lock releases a fresh window afterwards', () async {
      final tracker = await makeTracker();
      for (var i = 0; i < UsageTracker.hourlyLimit; i++) {
        fakeNowMs += 17 * 1000;
        tracker.record();
      }
      fakeNowMs += UsageTracker.cooldown.inMilliseconds + 1000;
      expect(tracker.locked, isFalse);
      expect(tracker.fraction, 0); // the whole window was reset
      expect(tracker.showHint, isFalse);
    });
  });

  group('the 429 lock', () {
    test('pins the meter at 100% for the cooldown', () async {
      final tracker = await makeTracker();
      tracker.record();
      expect(tracker.percent, 1);
      tracker.onRateLimited();
      expect(tracker.locked, isTrue);
      expect(tracker.percent, 100);
      expect(tracker.remainingLock.inMinutes, greaterThan(60));
      expect(tracker.remainingLock.inMinutes, lessThanOrEqualTo(65));
    });

    test('applies exactly once — hammering retry never stacks the wait',
        () async {
      final tracker = await makeTracker();
      tracker.onRateLimited();
      final remaining = tracker.remainingLock;

      // Ten minutes later the user keeps trying, and keeps getting 429s.
      fakeNowMs += 10 * 60 * 1000;
      tracker.onRateLimited();
      fakeNowMs += 5 * 1000;
      tracker.onRateLimited();
      fakeNowMs += 5 * 1000;
      tracker.onRateLimited();

      expect(
        tracker.remainingLock.inMilliseconds,
        remaining.inMilliseconds - 10 * 60 * 1000 - 10 * 1000,
      );
    });

    test('a natural lock is not extended by a late 429', () async {
      final tracker = await makeTracker();
      for (var i = 0; i < UsageTracker.hourlyLimit; i++) {
        fakeNowMs += 17 * 1000;
        tracker.record();
      }
      final remaining = tracker.remainingLock;

      fakeNowMs += 5 * 60 * 1000;
      tracker.onRateLimited(); // the server agrees: still limited

      expect(
        tracker.remainingLock.inMilliseconds,
        remaining.inMilliseconds - 5 * 60 * 1000,
      );
    });

    test('a new 429 after a spent lock starts a new cooldown', () async {
      final tracker = await makeTracker();
      tracker.onRateLimited();
      fakeNowMs += UsageTracker.cooldown.inMilliseconds + 1000;
      expect(tracker.locked, isFalse);

      tracker.onRateLimited();
      expect(tracker.locked, isTrue);
      expect(tracker.remainingLock.inMinutes, greaterThan(60));
    });
  });

  group('persistence', () {
    test('a lock survives a restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final tracker = UsageTracker(storage: prefs, clock: () => fakeNowMs);
      tracker.onRateLimited();

      final revived = UsageTracker(storage: prefs, clock: () => fakeNowMs);
      await revived.start();
      addTearDown(revived.dispose);
      expect(revived.locked, isTrue);
      expect(revived.percent, 100);
    });

    test('an expired lock does not survive a restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final tracker = UsageTracker(storage: prefs, clock: () => fakeNowMs);
      tracker.onRateLimited();

      fakeNowMs += UsageTracker.cooldown.inMilliseconds + 1000;
      final revived = UsageTracker(storage: prefs, clock: () => fakeNowMs);
      await revived.start();
      addTearDown(revived.dispose);
      expect(revived.locked, isFalse);
      expect(revived.fraction, 0);
    });

    test('recent requests survive a restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final tracker = UsageTracker(storage: prefs, clock: () => fakeNowMs);
      for (var i = 0; i < 4; i++) {
        tracker.record();
      }
      fakeNowMs += 10 * 60 * 1000;

      final revived = UsageTracker(storage: prefs, clock: () => fakeNowMs);
      await revived.start();
      addTearDown(revived.dispose);
      expect(revived.percent, 2); // 4/200 = 2%
    });
  });
}
