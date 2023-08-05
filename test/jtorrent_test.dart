import 'dart:async';
import 'dart:io';

import 'package:jtorrent/src/announce/announce_manager.dart';
import 'package:jtorrent/src/announce/announce_task.dart';
import 'package:jtorrent/src/exchange/exchange_manager.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/model/torrent_announce_info.dart';
import 'package:jtorrent/src/model/torrent_download_info.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    test('Test parse torrent', () async {
      var result = Torrent.fromFileSync(File('/Users/jtmonster/IdeaProjects/jtorrent/test/torrent/sample.torrent'));
      assert(result.trackers.fold(0, (previousValue, element) => previousValue + element.length) == 137);
      assert(result.files.length == 1);
      assert(result.files.first.length == 2352463340);
    });

    test('Test tracker manager', () async {
      Torrent torrent = Torrent.fromFileSync(File('/Users/jtmonster/IdeaProjects/jtorrent/test/torrent/1.torrent'));

      ExchangeManager exchangeManager = ExchangeManager();
      exchangeManager.setTorrentTaskDownloadInfo(
        torrent.infoHash,
        TorrentTaskDownloadInfo(uploaded: 0, downloaded: 0, left: torrent.files.first.length),
      );

      AnnounceManager trackerManager = AnnounceManager(localPort: 6881, exchangeManager: exchangeManager)
        ..compact = true
        ..noPeerId = true;

      AnnounceTask task = trackerManager.addAnnounceTask(torrent);
      Stream<TorrentAnnounceInfo> stream = trackerManager.scheduleAnnounceTask(task);
      StreamSubscription subscription = stream.listen((info) {
        print(info);
      });
      await subscription.asFuture();
    });
  });
}
