import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../model/announce_response.dart';
import '../model/torrent_download_info.dart';

class AnnounceTask {
  /// Info hash of torrent file
  final Uint8List infoHash;

  /// Available Tracker servers, from torrent file at first
  final List<Uri> trackers;

  /// Total size of all files need to be downloaded in bytes
  final int totalSize;

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

  /// Number of peers that the client would like to receive from the tracker, default is 50
  int numWant;

  /// Tracker request interval in seconds, default is 30 minutes. Will be updated by tracker response
  int interval;

  AnnounceTask({
    required this.infoHash,
    required this.trackers,
    required this.totalSize,
    required this.torrentDownloadInfoGetter,
    this.connectTimeOut = const Duration(seconds: 10),
    this.receiveTimeOut = const Duration(seconds: 30),
    this.numWant = 50,
    this.interval = 30 * 60,
  }) : announceTimers = {};

  String generateInfoHashString() {
    return Uri.encodeQueryComponent(String.fromCharCodes(infoHash), encoding: latin1);
  }

  @override
  String toString() {
    return 'AnnounceTask{infoHash: $infoHash, trackers: $trackers, totalSize: $totalSize, announceTimers: $announceTimers, torrentDownloadInfoGetter: $torrentDownloadInfoGetter, streamController: $streamController, connectTimeOut: $connectTimeOut, receiveTimeOut: $receiveTimeOut, numWant: $numWant, interval: $interval}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnounceTask &&
          runtimeType == other.runtimeType &&
          infoHash == other.infoHash &&
          trackers == other.trackers &&
          totalSize == other.totalSize &&
          announceTimers == other.announceTimers &&
          torrentDownloadInfoGetter == other.torrentDownloadInfoGetter &&
          streamController == other.streamController &&
          connectTimeOut == other.connectTimeOut &&
          receiveTimeOut == other.receiveTimeOut &&
          numWant == other.numWant &&
          interval == other.interval;

  @override
  int get hashCode =>
      infoHash.hashCode ^
      trackers.hashCode ^
      totalSize.hashCode ^
      announceTimers.hashCode ^
      torrentDownloadInfoGetter.hashCode ^
      streamController.hashCode ^
      connectTimeOut.hashCode ^
      receiveTimeOut.hashCode ^
      numWant.hashCode ^
      interval.hashCode;
}

typedef TorrentDownloadInfoGetter = TorrentTaskDownloadInfo? Function(Uint8List infohash);
