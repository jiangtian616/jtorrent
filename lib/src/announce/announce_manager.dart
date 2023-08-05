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
import 'package:jtorrent/src/announce/announce_dispatcher.dart';

class AnnounceManager {
  AnnounceManager({required int localPort, InternetAddress? localIp, required ExchangeManager exchangeManager})
      : _announceDispatcher = AnnounceDispatcher(
          localPort: localPort,
          localIp: localIp,
          exchangeManager: exchangeManager,
          handlers: [const HttpAnnounceHandler()],
        );

  final Map<Uint8List, AnnounceTask> _announceTaskMap = {};

  final AnnounceDispatcher _announceDispatcher;

  set localPort(int value) {
    _announceDispatcher.localPort = value;
  }

  set localIp(InternetAddress? value) {
    _announceDispatcher.localIp = value;
  }

  set compact(bool value) {
    _announceDispatcher.compact = value;
  }

  set noPeerId(bool value) {
    _announceDispatcher.noPeerId = value;
  }

  AnnounceTask addAnnounceTask(Torrent torrent) {
    if (_announceTaskMap.containsKey(torrent.infoHash)) {
      return _announceTaskMap[torrent.infoHash]!;
    }

    AnnounceTask task = AnnounceTask(infoHash: torrent.infoHash, trackers: torrent.trackers);
    _announceTaskMap[torrent.infoHash] = task;
    return task;
  }

  Stream<TorrentAnnounceInfo> scheduleAnnounceTask(AnnounceTask task) {
    assert(_announceTaskMap[task.infoHash] != null);

    Stream<AnnounceResponse> responseStream = _announceDispatcher.scheduleAnnounceTask(task);

    Stream<TorrentAnnounceInfo> result = responseStream.transform(StreamTransformer.fromHandlers(handleData: (response, sink) {
      assert(response.success && response.result != null);

      sink.add(TorrentAnnounceInfo(
        tracker: response.tracker,
        completePeerCount: response.result!.completePeerCount,
        incompletePeerCount: response.result!.inCompletePeerCount,
        peers: UnmodifiableSetView(response.result!.peers),
      ));
    }));

    return result;
  }

  void stopScheduleAnnounceTask(AnnounceTask task) {
    assert(_announceTaskMap[task.infoHash] != null);

    _announceDispatcher.stopScheduleAnnounceTask(task);
    _announceTaskMap.remove(task.infoHash);
  }
}
