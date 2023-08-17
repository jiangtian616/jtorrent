import 'dart:async';

import 'package:jtorrent/src/announce/tracker.dart';
import 'package:jtorrent/src/exception/announce_exception.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/model/announce_response.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/util/log_util.dart';

import 'announce_request_options_provider.dart';

class AnnounceManager with AnnounceManagerEventDispatcher{
  AnnounceManager({required AnnounceConfigProvider announceConfigProvider}) : _announceConfigProvider = announceConfigProvider;

  AnnounceManager.fromTorrent({required Torrent torrent, required AnnounceConfigProvider announceConfigProvider})
      : _announceConfigProvider = announceConfigProvider {
    addTrackerServers(torrent.allTrackers);
  }

  /// Tracker servers
  final Map<Uri, Tracker> _trackers = {};

  /// Provide options when sending announce request
  final AnnounceConfigProvider _announceConfigProvider;

  bool _running = false;
  bool _disposed = false;

  void addTrackerServers(List<Uri> servers) {
    for (Uri uri in servers) {
      if (_trackers[uri] == null) {
        try {
          _trackers[uri] = Tracker.fromUri(uri, _announceConfigProvider);
        } on UnsupportedError catch (e) {}
      }
    }
  }

  void start() {
    if (_disposed) {
      throw AnnounceException('AnnounceManager has been closed');
    }
    if (_running) {
      return;
    }

    _running = true;
    _startAllTrackers();
  }

  void stop() {
    if (_disposed || !_running) {
      return;
    }
    _running = false;

    for (Tracker tracker in _trackers.values) {
      tracker.stop();
    }
  }

  void complete() {
    if (_disposed) {
      throw AnnounceException('AnnounceManager has been closed');
    }

    for (Tracker tracker in _trackers.values) {
      tracker.complete();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _running = false;
    _disposed = true;

    for (Tracker tracker in _trackers.values) {
      _unHookTracker(tracker);
      tracker.dispose(force: true);
    }

    super.dispose();
  }

  void _startAllTrackers() {
    for (Tracker tracker in _trackers.values) {
      _hookTracker(tracker);
      tracker.start();
    }
  }

  void _removeTracker(Tracker tracker) {
    tracker.close();
    _trackers.remove(tracker.uri);
  }

  void _hookTracker(Tracker tracker) {
    tracker.addOnAnnounceResponseCallback((response) => _processTrackerAnnounceResponse(tracker, response));
    tracker.addOnAnnounceErrorCallback((error) => _processTrackerAnnounceError(tracker, error));
  }

  void _unHookTracker(Tracker tracker) {
    tracker.removeOnAnnounceResponseCallback((response) => _processTrackerAnnounceResponse(tracker, response));
    tracker.removeOnAnnounceErrorCallback((error) => _processTrackerAnnounceError(tracker, error));
  }

  void _processTrackerAnnounceError(Tracker tracker, dynamic error) {
    if (_disposed) {
      return;
    }

    _removeTracker(tracker);
  }

  void _processTrackerAnnounceResponse(Tracker tracker, AnnounceResponse response) {
    if (_disposed) {
      return;
    }

    if (response.success) {
      Log.fine(
          'Announce to ${tracker.toString()} with ${_announceConfigProvider.infoHash.toHexString} success, result peer size : ${response.result!.peers.length}');

      _fireOnNewPeersFoundCallback(response.result!);
    } else {
      Log.info('Announce to ${tracker.toString()} with ${_announceConfigProvider.infoHash.toHexString} failed, reason: ${response.failureReason}');

      _removeTracker(tracker);
    }
  }
}

mixin AnnounceManagerEventDispatcher {
  final Set<void Function(AnnounceSuccessResponse)> _onNewPeersFoundCallbacks = {};

  void addOnNewPeersFoundCallback(void Function(AnnounceSuccessResponse) callback) {
    _onNewPeersFoundCallbacks.add(callback);
  }

  void removeOnNewPeersFoundCallback(void Function(AnnounceSuccessResponse) callback) {
    _onNewPeersFoundCallbacks.remove(callback);
  }

  void _fireOnNewPeersFoundCallback(AnnounceSuccessResponse response) {
    for (var callback in _onNewPeersFoundCallbacks) {
      Timer.run(() => callback(response));
    }
  }
  
  void dispose(){
    _onNewPeersFoundCallbacks.clear();
  }
}
