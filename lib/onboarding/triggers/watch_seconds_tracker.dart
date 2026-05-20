/// Tracker koji broji "kvalitetne" sekunde slušanja (tj. ne pauza) i okida
/// callback nakon thresholda. Koristi se u Episode screen-u da fire-a M2.
library;

import 'dart:async';

class WatchSecondsTracker {
  final int triggerAt;
  final void Function() onThreshold;

  Timer? _timer;
  int _seconds = 0;
  bool _fired = false;
  bool _running = false;

  WatchSecondsTracker({
    this.triggerAt = 30,
    required this.onThreshold,
  });

  void start() {
    if (_running || _fired) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      if (_seconds >= triggerAt && !_fired) {
        _fired = true;
        _timer?.cancel();
        _running = false;
        onThreshold();
      }
    });
  }

  void pause() {
    _running = false;
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
  }
}
