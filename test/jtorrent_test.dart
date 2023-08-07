import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/announce/announce_manager.dart';
import 'package:jtorrent/src/exchange/exchange_manager.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/model/torrent_announce_info.dart';
import 'package:jtorrent/src/model/torrent_download_info.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => hierarchicalLoggingEnabled = true);

  group('Announce', () {
    test('Test parse torrent', () async {
      Torrent torrent = Torrent.fromFileSync(File('/Users/jtmonster/IdeaProjects/jtorrent/test/torrent/sample.torrent'));
      assert(torrent.trackers.fold(0, (previousValue, element) => previousValue + element.length) == 137);
      assert(torrent.files.length == 1);
      assert(torrent.files.first.length == 2352463340);
    });

    test('Test announce manager', () async {
      Torrent torrent = Torrent.fromFileSync(File('/Users/jtmonster/IdeaProjects/jtorrent/test/torrent/manga.torrent'));

      AnnounceManager trackerManager = AnnounceManager(localPort: 6881, compact: true, noPeerId: true);

      Stream<TorrentAnnounceInfo> stream = trackerManager.scheduleAnnounce(
        torrent: torrent,
        torrentDownloadInfoGetter: null,
      );

      StreamSubscription subscription = stream.listen((info) {
        print(info);
      });
      await subscription.asFuture();
    });
  });

  group('Exchange', () {
    test('Test handshake message', () async {
      Torrent torrent = Torrent.fromFileSync(File('/Users/jtmonster/IdeaProjects/jtorrent/test/torrent/manga.torrent'));

      ExchangeManager exchangeManager = ExchangeManager(downloadPath: '/Users/JTMonster/IdeaProjects/jtorrent/test');
      AnnounceManager trackerManager = AnnounceManager(localPort: 6881, compact: true, noPeerId: true);

      Stream<TorrentAnnounceInfo> stream = trackerManager.scheduleAnnounce(
        torrent: torrent,
        torrentDownloadInfoGetter: (Uint8List infoHash) => TorrentTaskDownloadInfo(uploaded: 0, downloaded: 0, left: torrent.files.first.length),
      );

      StreamSubscription subscription = stream.listen((TorrentAnnounceInfo info) {
        exchangeManager.addNewTorrentTask(torrent, info.peers);
      });

      await subscription.asFuture();
    });
  }, timeout: Timeout(Duration(seconds: 1000)));
}
