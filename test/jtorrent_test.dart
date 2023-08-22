import 'dart:async';
import 'dart:io';

import 'package:jtorrent/src/dht/dht_manager.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/task/torrent_task.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group(
    'download',
    () {
      hierarchicalLoggingEnabled = true;
      Log.level = Level.FINEST;

      test('manga', () async {
        Torrent torrent = Torrent.fromFileSync(File('/Users/JTMonster/IdeaProjects/jtorrent/test/torrent/manga.torrent'));
        TorrentTask torrentTask = TorrentTask.fromTorrent(torrent, 'C:\\Users\\JTMonster\\IdeaProjects\\jtorrent\\test\\torrent');
        // TorrentTask torrentTask = TorrentTask.fromTorrent(torrent, '/Users/JTMonster/IdeaProjects/jtorrent/test/torrent');
        torrentTask.start();

        Timer.periodic(Duration(seconds: 1), (_) {
          print(torrentTask.getDebugInfo().format());
        });
        await Future.delayed(Duration(minutes: 10));
      });
    },
    timeout: Timeout(Duration(minutes: 10)),
  );

  group(
    'dht',
    () {
      hierarchicalLoggingEnabled = true;
      Log.level = Level.FINEST;

      test('dht', () async {
        Torrent torrent = Torrent.fromFileSync(File('/Users/JTMonster/IdeaProjects/jtorrent/test/torrent/manga.torrent'));

        DHTManager dhtManager = DHTManager();
        int port = await dhtManager.start();
        Log.info('dht port: $port');

        dhtManager.addNeededInfoHash(torrent.infoHash);
        dhtManager.tryAddNodeAddress(InternetAddress('39.111.79.152'), 6881);
        
        Timer.periodic(Duration(seconds: 1), (_) {
          dhtManager.printDebugInfo();
        });
        await Future.delayed(Duration(minutes: 10));
      });
    },
    timeout: Timeout(Duration(minutes: 10)),
  );
}
