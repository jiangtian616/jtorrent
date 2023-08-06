import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/exchange/exchange_manager.dart';
import 'package:jtorrent/src/model/announce_response.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/model/torrent_announce_info.dart';
import 'package:jtorrent/src/announce/http_announce_handler.dart';
import 'package:jtorrent/src/announce/announce_task.dart';

import '../exception/tracker_exception.dart';
import '../model/announce_request_options.dart';
import '../model/torrent_download_info.dart';
import 'announce_handler.dart';

class AnnounceManager {
  /// The port number that the client is listening on. Ports reserved for BitTorrent are typically 6881-6889
  int localPort;

  /// The parameter is only needed if the client is communicating to the tracker through a proxy (or a transparent web proxy/cache.)
  InternetAddress? localIp;

  /// Whether to return compact peer list, default is true
  bool compact;

  /// Whether to return peer id, default is true and in ignored if compact is true
  bool noPeerId;

  /// Number of peers that the client would like to receive from the tracker, default is 200
  int numWant;

  AnnounceManager({
    required this.localPort,
    this.localIp,
    this.compact = true,
    this.noPeerId = true,
    this.numWant = 100,
  }) : _announceHandlers = [const HttpAnnounceHandler()];

  final Map<Uint8List, AnnounceTask> _announceTaskMap = {};

  final List<AnnounceHandler> _announceHandlers;

  Stream<TorrentAnnounceInfo> scheduleAnnounce({required Torrent torrent, TorrentDownloadInfoGetter? torrentDownloadInfoGetter}) {
    if (_announceTaskMap[torrent.infoHash] == null) {
      AnnounceTask task = AnnounceTask(
        infoHash: torrent.infoHash,
        trackers: _filterSupportTrackers(torrent.trackers),
        totalFileSize: torrent.files.fold(0, (previousValue, element) => previousValue + element.length),
        torrentDownloadInfoGetter: torrentDownloadInfoGetter,
      );
      _announceTaskMap[torrent.infoHash] = task;

      for (Uri tracker in task.trackers) {
        _announce(task, tracker);

        task.announceTimers[tracker] = Timer(Duration(seconds: task.interval), () => _announce(task, tracker));
      }
    }

    return _transformStream(_announceTaskMap[torrent.infoHash]!.streamController.stream);
  }

  void stopScheduleAnnounce({required Uint8List infoHash}) {
    assert(_announceTaskMap[infoHash] != null);

    AnnounceTask task = _announceTaskMap[infoHash]!;
    for (Timer timer in task.announceTimers.values) {
      timer.cancel();
    }
    task.streamController.close();

    _announceTaskMap.remove(infoHash);
  }

  List<Uri> _filterSupportTrackers(List<List<Uri>> trackers) {
    return trackers
        .fold<List<Uri>>([], (previousValue, element) => previousValue..addAll(element))
        .where((tracker) => _supportTracker(tracker))
        .toList();
  }

  bool _supportTracker(Uri tracker) {
    return _announceHandlers.any((handler) => handler.support(tracker));
  }

  void _announce(AnnounceTask task, Uri tracker) {
    assert(_announceTaskMap[task.infoHash] != null);
    assert(_supportTracker(tracker));

    for (AnnounceHandler handler in _announceHandlers) {
      if (handler.support(tracker)) {
        AnnounceRequestOptions requestOptions = _generateTrackerRequestOptions(task, TrackerRequestType.started);
        Future<AnnounceResponse> responseFuture = handler.announce(task, requestOptions, tracker);

        responseFuture.then((response) {
          if (response.success) {
            _updateTaskInterval(task, tracker, response.result!);
            task.streamController.sink.add(response);
          } else {
            /// todo: This tracker server is not available for this torrent
            print(response.failureReason);
            task.trackers.remove(tracker);
            task.announceTimers.remove(tracker)?.cancel();
          }
        }).onError((error, stackTrace) {
          /// todo: Network error, retry
        });

        break;
      }
    }
  }

  Stream<TorrentAnnounceInfo> _transformStream(Stream<AnnounceResponse> stream) {
    return stream.transform(StreamTransformer.fromHandlers(handleData: (response, sink) {
      assert(response.success);
      assert(response.result != null);

      sink.add(TorrentAnnounceInfo(
        tracker: response.tracker,
        completePeerCount: response.result!.completePeerCount,
        incompletePeerCount: response.result!.inCompletePeerCount,
        peers: UnmodifiableSetView(response.result!.peers),
      ));
    }));
  }

  void _updateTaskInterval(AnnounceTask task, Uri tracker, AnnounceSuccessResponse response) {
    int newInterval = response.minInterval ?? response.interval;
    if (task.interval == newInterval) {
      return;
    }

    task.interval = newInterval;
    task.announceTimers.remove(tracker)?.cancel();
    task.announceTimers[tracker] = Timer(Duration(seconds: newInterval), () => _announce(task, tracker));
  }

  AnnounceRequestOptions _generateTrackerRequestOptions(AnnounceTask task, TrackerRequestType type) {
    TorrentTaskDownloadInfo? currentDownloadInfo = task.torrentDownloadInfoGetter?.call(task.infoHash);

    return AnnounceRequestOptions(
      type: type,
      localIp: localIp,
      localPort: localPort,
      compact: compact,
      noPeerId: noPeerId,
      numWant: numWant,
      uploaded: currentDownloadInfo?.uploaded ?? 0,
      downloaded: currentDownloadInfo?.downloaded ?? 0,
      left: currentDownloadInfo?.left ?? task.totalFileSize,
    );
  }
}
