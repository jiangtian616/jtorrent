import 'dart:async';
import 'dart:io';

import 'package:jtorrent/src/announce/announce_manager.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/model/torrent_announce_info.dart';
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
}
