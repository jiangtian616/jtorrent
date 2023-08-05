import 'dart:async';
import 'dart:io';

import 'package:jtorrent/src/exchange/exchange_manager.dart';
import 'package:jtorrent/src/model/announce_request_options.dart';
import 'package:jtorrent/src/announce/announce_task.dart';
import 'package:jtorrent/src/announce/announce_handler.dart';

import '../exception/tracker_exception.dart';
import '../model/announce_response.dart';
import '../model/torrent_download_info.dart';

class AnnounceDispatcher {
  /// The port number that the client is listening on. Ports reserved for BitTorrent are typically 6881-6889
  int localPort;

  /// The parameter is only needed if the client is communicating to the tracker through a proxy (or a transparent web proxy/cache.)
  InternetAddress? localIp;

  /// Whether to return compact peer list, default is true
  bool compact = true;

  /// Whether to return peer id, default is true and in ignored if compact is true
  bool noPeerId = true;

  final List<AnnounceHandler> _handlers;

  final ExchangeManager _downloadManager;

  final Map<AnnounceTask, _AnnounceDispatchInfo> _taskInfoMap = {};

  AnnounceDispatcher({
    required this.localPort,
    this.localIp,
    required List<AnnounceHandler> handlers,
    required ExchangeManager exchangeManager,
  })  : _handlers = handlers,
        _downloadManager = exchangeManager;

  Stream<AnnounceResponse> scheduleAnnounceTask(AnnounceTask task) {
    assert(_taskInfoMap[task] == null);

    _AnnounceDispatchInfo info = _AnnounceDispatchInfo(trackers: filterSupportTrackers(task.trackers));
    _taskInfoMap[task] = info;

    for (Uri tracker in info.trackers) {
      _announce(task, tracker);

      info.announceTimers[tracker] = Timer(Duration(seconds: task.interval), () => _announce(task, tracker));
    }
    return info.streamController.stream;
  }

  void stopScheduleAnnounceTask(AnnounceTask task) {
    assert(_taskInfoMap[task] != null);

    _AnnounceDispatchInfo info = _taskInfoMap[task]!;
    for (Timer timer in info.announceTimers.values) {
      timer.cancel();
    }
    info.streamController.close();

    _taskInfoMap.remove(task);
  }

  void _announce(AnnounceTask task, Uri tracker) {
    assert(_taskInfoMap[task] != null);
    assert(_supportTracker(tracker));

    _AnnounceDispatchInfo info = _taskInfoMap[task]!;
    for (AnnounceHandler handler in _handlers) {
      if (handler.support(tracker)) {
        AnnounceRequestOptions requestOptions = _generateTrackerRequestOptions(task, TrackerRequestType.start);
        Future<AnnounceResponse> responseFuture = handler.announce(task, requestOptions, tracker);

        responseFuture.then((response) {
          if (response.success) {
            _updateInterval(task, tracker, response.result!);
            info.streamController.sink.add(response);
          } else {
            /// todo: This tracker server is not available for this torrent
            print(response.failureReason);
            info.trackers.remove(tracker);
            info.announceTimers.remove(tracker)?.cancel();
          }
        }).onError((error, stackTrace) {
          /// todo: Network error, retry
        });

        break;
      }
    }
  }

  AnnounceRequestOptions _generateTrackerRequestOptions(AnnounceTask task, TrackerRequestType type) {
    TorrentTaskDownloadInfo? currentDownloadInfo = _downloadManager.getTorrentTaskDownloadInfo(task.infoHash);
    if (currentDownloadInfo == null) {
      throw TrackerException('TorrentTaskDownloadInfo not found for ${task.infoHash}');
    }

    return AnnounceRequestOptions(
      type: type,
      localIp: localIp,
      localPort: localPort,
      compact: compact,
      noPeerId: noPeerId,
      uploaded: currentDownloadInfo.uploaded,
      downloaded: currentDownloadInfo.downloaded,
      left: currentDownloadInfo.left,
    );
  }

  List<Uri> filterSupportTrackers(List<List<Uri>> trackers) {
    return trackers
        .fold<List<Uri>>([], (previousValue, element) => previousValue..addAll(element))
        .where((tracker) => _supportTracker(tracker))
        .toList();
  }

  bool _supportTracker(Uri tracker) {
    return _handlers.any((handler) => handler.support(tracker));
  }

  void _updateInterval(AnnounceTask task, Uri tracker, AnnounceSuccessResponse response) {
    int newInterval = response.minInterval ?? response.interval;
    if (task.interval == newInterval) {
      return;
    }

    task.interval = newInterval;
    _AnnounceDispatchInfo? info = _taskInfoMap[task];
    info?.announceTimers.remove(tracker)?.cancel();
    info?.announceTimers[tracker] = Timer(Duration(seconds: newInterval), () => _announce(task, tracker));
  }
}

class _AnnounceDispatchInfo {
  /// Available Tracker servers, may be different from the original trackers list [AnnounceTask]
  final List<Uri> trackers;

  final Map<Uri, Timer> announceTimers = {};

  final StreamController<AnnounceResponse> streamController = StreamController();

  _AnnounceDispatchInfo({required this.trackers});
}
