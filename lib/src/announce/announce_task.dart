import 'dart:async';
import 'dart:typed_data';

import '../model/announce_response.dart';
import '../model/torrent_download_info.dart';

class AnnounceTask {
  /// Info hash of torrent file
  final Uint8List infoHash;

  /// Available Tracker servers, from torrent file at first
  final List<Uri> trackers;

  /// Total file size in bytes which need to download
  final int totalFileSize;

  /// Announce request timers, key is tracker url
  Map<Uri, Timer> announceTimers;

  /// Torrent download info getter while announce
  TorrentDownloadInfoGetter? torrentDownloadInfoGetter;

  /// Announce response stream controller
  StreamController<AnnounceResponse> streamController = StreamController.broadcast();

  /// Request timeout, default is 10 seconds
  Duration connectTimeOut;

  /// Request timeout, default is 30 seconds
  Duration receiveTimeOut;

  /// Tracker request interval in seconds, default is 30 minutes. Will be updated by tracker response
  int interval;

  AnnounceTask({
    required this.infoHash,
    required this.trackers,
    required this.totalFileSize,
    required this.torrentDownloadInfoGetter,
    this.connectTimeOut = const Duration(seconds: 10),
    this.receiveTimeOut = const Duration(seconds: 30),
    this.interval = 30 * 60,
  }) : announceTimers = {};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnounceTask &&
          runtimeType == other.runtimeType &&
          infoHash == other.infoHash &&
          trackers == other.trackers &&
          announceTimers == other.announceTimers &&
          torrentDownloadInfoGetter == other.torrentDownloadInfoGetter &&
          streamController == other.streamController &&
          connectTimeOut == other.connectTimeOut &&
          receiveTimeOut == other.receiveTimeOut &&
          interval == other.interval;

  @override
  int get hashCode =>
      infoHash.hashCode ^
      trackers.hashCode ^
      announceTimers.hashCode ^
      torrentDownloadInfoGetter.hashCode ^
      streamController.hashCode ^
      connectTimeOut.hashCode ^
      receiveTimeOut.hashCode ^
      interval.hashCode;

  @override
  String toString() {
    return 'AnnounceTask{infoHash: $infoHash, trackers: $trackers, announceTimers: $announceTimers, torrentDownloadInfoGetter: $torrentDownloadInfoGetter, streamController: $streamController, connectTimeOut: $connectTimeOut, receiveTimeOut: $receiveTimeOut, interval: $interval}';
  }
}

typedef TorrentDownloadInfoGetter = TorrentTaskDownloadInfo? Function(Uint8List infohash);
