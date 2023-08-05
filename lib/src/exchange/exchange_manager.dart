import 'dart:typed_data';

import 'package:jtorrent/src/exception/tracker_exception.dart';
import 'package:jtorrent/src/model/torrent_download_info.dart';

class ExchangeManager {
  
  
  final Map<Uint8List, TorrentTaskDownloadInfo> _taskDownloadInfoMap = {};

  TorrentTaskDownloadInfo? getTorrentTaskDownloadInfo(Uint8List infoHash) {
    return _taskDownloadInfoMap[infoHash];
  }

  void setTorrentTaskDownloadInfo(Uint8List infoHash, TorrentTaskDownloadInfo downloadInfo) {
    if (_taskDownloadInfoMap.containsKey(infoHash)) {
      throw TrackerException('TorrentTaskDownloadInfo already exists');
    }
    _taskDownloadInfoMap[infoHash] = downloadInfo;
  }
}
