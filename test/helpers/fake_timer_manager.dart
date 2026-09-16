import 'dart:async';

import 'package:clock/clock.dart';

import 'package:ably_pubsub_device/src/realtime/timer_manager.dart';

/// A controllable fake clock for testing.
///
/// Unlike `Clock.fixed`, this clock can be advanced using [advance].
/// Use with [withClock] to control time in tests.
///
/// Usage:
/// ```dart
/// final fakeClock = TestClock();
///
/// withClock(fakeClock, () {
///   print(clock.now()); // Initial time
///   fakeClock.advance(Duration(hours: 1));
///   print(clock.now()); // 1 hour later
/// });
/// ```
class TestClock extends Clock {
  TestClock([DateTime? initialTime])
      : _currentTime = initialTime ?? DateTime.now();

  DateTime _currentTime;

  @override
  DateTime now() => _currentTime;

  /// Advances the clock by the given duration.
  void advance(Duration duration) {
    _currentTime = _currentTime.add(duration);
  }

  /// Sets the clock to a specific time.
  void setTime(DateTime time) {
    _currentTime = time;
  }
}

/// A fake TimerManager for testing that allows manual time control.
///
/// This class works with [TestClock] to provide coordinated time control:
/// - [elapseTime] advances the clock AND fires any due timers
/// - Timers are tracked by their scheduled fire time based on clock.now()
///
/// Usage:
/// ```dart
/// final testClock = TestClock();
/// final fakeTimers = FakeTimerManager(testClock);
///
/// withClock(testClock, () async {
///   final client = PubSubClient.forTesting(
///     timerManager: fakeTimers,
///     ...
///   );
///
///   // Advance time and fire due timers
///   fakeTimers.elapseTime(Duration(seconds: 5));
/// });
/// ```
class FakeTimerManager implements TimerManager {
  FakeTimerManager(this._clock);

  final TestClock _clock;
  final Map<String, _FakeTimerEntry> _timers = {};
  final Map<String, _FakePeriodicTimerEntry> _periodicTimers = {};

  @override
  void schedule({
    required Object owner,
    required String name,
    required Duration duration,
    required void Function() callback,
  }) {
    final key = _makeKey(owner, name);

    // Cancel existing timer with same key
    cancel(owner: owner, name: name);

    final fireAt = _clock.now().add(duration);

    _timers[key] = _FakeTimerEntry(
      owner: owner,
      name: name,
      fireAt: fireAt,
      callback: callback,
    );
  }

  @override
  void schedulePeriodic({
    required Object owner,
    required String name,
    required Duration period,
    required void Function(Timer) callback,
  }) {
    final key = _makeKey(owner, name);

    cancel(owner: owner, name: name);

    final nextFireAt = _clock.now().add(period);
    final fakeTimer = _FakePeriodicTimer();

    _periodicTimers[key] = _FakePeriodicTimerEntry(
      owner: owner,
      name: name,
      period: period,
      nextFireAt: nextFireAt,
      callback: callback,
      timer: fakeTimer,
    );
  }

  @override
  void cancel({required Object owner, required String name}) {
    final key = _makeKey(owner, name);
    _timers.remove(key);
    final periodicEntry = _periodicTimers.remove(key);
    periodicEntry?.timer.cancel();
  }

  @override
  void cancelAll({required Object owner}) {
    final keysToRemove = <String>[];

    for (final entry in _timers.entries) {
      if (entry.value.owner == owner) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _timers.remove(key);
    }

    keysToRemove.clear();

    for (final entry in _periodicTimers.entries) {
      if (entry.value.owner == owner) {
        entry.value.timer.cancel();
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _periodicTimers.remove(key);
    }
  }

  @override
  bool isActive({required Object owner, required String name}) {
    final key = _makeKey(owner, name);
    return _timers.containsKey(key) || _periodicTimers.containsKey(key);
  }

  @override
  void dispose() {
    _timers.clear();
    for (final entry in _periodicTimers.values) {
      entry.timer.cancel();
    }
    _periodicTimers.clear();
  }

  /// Advances the clock by [duration] and fires any timers that are due.
  ///
  /// This method:
  /// 1. Advances the TestClock
  /// 2. Fires any one-shot timers whose fireAt time has passed
  /// 3. Fires any periodic timers that are due (potentially multiple times)
  ///
  /// Timers are fired in order of their scheduled time.
  void elapseTime(Duration duration) {
    _clock.advance(duration);
    _fireExpiredTimers();
  }

  /// Fires all timers that are due based on current clock time.
  ///
  /// Can be called after manually advancing the clock.
  void fireExpiredTimers() {
    _fireExpiredTimers();
  }

  void _fireExpiredTimers() {
    final now = _clock.now();

    // Fire one-shot timers
    // Sort by fire time to ensure deterministic order
    final expiredTimers = _timers.entries
        .where((e) => !e.value.fireAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.value.fireAt.compareTo(b.value.fireAt));

    for (final entry in expiredTimers) {
      _timers.remove(entry.key);
      // Schedule callback asynchronously via microtask, matching real Timer
      // behavior. This prevents synchronous execution chains that cause
      // unhandled Future errors in tests.
      scheduleMicrotask(entry.value.callback);
    }

    // Fire periodic timers
    for (final entry in _periodicTimers.entries.toList()) {
      final periodicEntry = entry.value;
      if (periodicEntry.timer.isCancelled) {
        _periodicTimers.remove(entry.key);
        continue;
      }

      // Fire as many times as needed to catch up
      while (!periodicEntry.nextFireAt.isAfter(now) &&
          !periodicEntry.timer.isCancelled) {
        // Schedule callback asynchronously via microtask
        final timer = periodicEntry.timer;
        final cb = periodicEntry.callback;
        scheduleMicrotask(() => cb(timer));
        periodicEntry.nextFireAt =
            periodicEntry.nextFireAt.add(periodicEntry.period);
      }
    }
  }

  /// Returns the number of pending timers (for debugging/testing).
  int get pendingTimerCount => _timers.length + _periodicTimers.length;

  /// Returns info about pending timers (for debugging).
  List<String> get pendingTimerInfo {
    final now = _clock.now();
    final info = <String>[];
    for (final entry in _timers.entries) {
      final remaining = entry.value.fireAt.difference(now);
      info.add('One-shot: ${entry.value.name} fires in $remaining');
    }
    for (final entry in _periodicTimers.entries) {
      final remaining = entry.value.nextFireAt.difference(now);
      info.add('Periodic: ${entry.value.name} next in $remaining');
    }
    return info;
  }

  String _makeKey(Object owner, String name) {
    return '${owner.hashCode}_$name';
  }
}

class _FakeTimerEntry {
  _FakeTimerEntry({
    required this.owner,
    required this.name,
    required this.fireAt,
    required this.callback,
  });

  final Object owner;
  final String name;
  final DateTime fireAt;
  final void Function() callback;
}

class _FakePeriodicTimerEntry {
  _FakePeriodicTimerEntry({
    required this.owner,
    required this.name,
    required this.period,
    required this.nextFireAt,
    required this.callback,
    required this.timer,
  });

  final Object owner;
  final String name;
  final Duration period;
  DateTime nextFireAt;
  final void Function(Timer) callback;
  final _FakePeriodicTimer timer;
}

/// A fake Timer for periodic timer entries.
class _FakePeriodicTimer implements Timer {
  bool _isCancelled = false;
  int _tick = 0;

  @override
  void cancel() {
    _isCancelled = true;
  }

  @override
  bool get isActive => !_isCancelled;

  bool get isCancelled => _isCancelled;

  @override
  int get tick => _tick;

  void incrementTick() => _tick++;
}
