import 'dart:async';

import '../exception/announce_exception.dart';
import '../model/announce_response.dart';
import 'announce_request_options_provider.dart';
import 'http_tracker.dart';

enum AnnounceEventType { started, completed, stopped }

abstract class Tracker with TrackerEventDispatcher {
  final Uri uri;

  final AnnounceConfigProvider announceConfigProvider;

  Tracker({required this.uri, required this.announceConfigProvider});

  factory Tracker.fromUri(Uri uri, AnnounceConfigProvider announceConfigProvider) {
    if (uri.isScheme('http') || uri.isScheme('https')) {
      return HttpTracker(uri: uri, announceConfigProvider: announceConfigProvider);
    }
    throw UnsupportedError('Unsupported tracker scheme: ${uri.scheme}');
  }

  /// Tracker request interval in seconds, default is 30 minutes. Will be updated by tracker response
  int _announceInterval = 30 * 60;
  Timer? _announceTimer;

  bool _running = false;
  bool _disposed = false;

  Future<bool> start() {
    if (_disposed) {
      throw AnnounceException('This tracker has been disposed');
    }
    if (_running) {
      return Future.value(true);
    }

    _running = true;
    return announceInterval();
  }

  Future<void> stop() async {
    if (_disposed) return;

    _stopTimer();

    announceOnce(AnnounceEventType.stopped);

    return close();
  }

  Future<void> complete() async {
    if (_disposed) return;

    _stopTimer();

    announceOnce(AnnounceEventType.completed);

    return dispose();
  }

  Future<void> close();

  @override
  Future<void> dispose({bool force = false}) async {
    if (_disposed) return;
    _disposed = true;

    super.dispose();

    return close();
  }

  Future<bool> announceInterval() async {
    if (_disposed) {
      _running = false;
      return false;
    }

    AnnounceResponse response;
    try {
      response = await announceOnce(AnnounceEventType.started);
    } catch (e) {
      _fireOnAnnounceErrorCallback(e);
      return false;
    }

    _fireOnAnnounceResponseCallback(response);

    _updateTaskInterval(response);

    return true;
  }

  Future<AnnounceResponse> announceOnce(AnnounceEventType type);

  void _updateTaskInterval(AnnounceResponse response) {
    if (response.success == false) {
      return;
    }

    int newInterval = response.result!.minInterval ?? response.result!.interval;
    if (_announceInterval == newInterval) {
      return;
    }

    _announceInterval = newInterval;
    _announceTimer?.cancel();
    _announceTimer = Timer(Duration(seconds: newInterval), announceInterval);
  }

  void _stopTimer() {
    _announceTimer?.cancel();
    _announceTimer = null;
  }
}

mixin TrackerEventDispatcher {
  final Set<void Function(AnnounceResponse)> _onResponseCallbacks = {};
  final Set<void Function(dynamic error)> _onAnnounceErrorCallbacks = {};

  void addOnAnnounceResponseCallback(void Function(AnnounceResponse) callback) {
    _onResponseCallbacks.add(callback);
  }

  bool removeOnAnnounceResponseCallback(void Function(AnnounceResponse) callback) {
    return _onResponseCallbacks.remove(callback);
  }

  void addOnAnnounceErrorCallback(void Function(dynamic error) callback) {
    _onAnnounceErrorCallbacks.add(callback);
  }

  bool removeOnAnnounceErrorCallback(void Function(dynamic error) callback) {
    return _onAnnounceErrorCallbacks.remove(callback);
  }

  void _fireOnAnnounceResponseCallback(AnnounceResponse response) {
    for (var callback in _onResponseCallbacks) {
      Timer.run(() => callback(response));
    }
  }

  void _fireOnAnnounceErrorCallback(dynamic error) {
    for (var callback in _onAnnounceErrorCallbacks) {
      Timer.run(() => callback(error));
    }
  }
  
  void dispose(){
    _onResponseCallbacks.clear();
    _onAnnounceErrorCallbacks.clear();
  }
}
