import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';

class AnnounceTask {
  /// Info hash of torrent file
  final Uint8List infoHash;

  /// Available Tracker servers in torrent file
  final List<List<Uri>> trackers;

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
    this.connectTimeOut = const Duration(seconds: 10),
    this.receiveTimeOut = const Duration(seconds: 30),
    this.numWant = 50,
    this.interval = 30 * 60,
  });

  String generateInfoHashString() {
    return Uri.encodeQueryComponent(String.fromCharCodes(infoHash), encoding: latin1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnounceTask &&
          runtimeType == other.runtimeType &&
          infoHash == other.infoHash &&
          trackers == other.trackers &&
          connectTimeOut == other.connectTimeOut &&
          receiveTimeOut == other.receiveTimeOut &&
          numWant == other.numWant &&
          interval == other.interval;

  @override
  int get hashCode =>
      infoHash.hashCode ^ trackers.hashCode ^ connectTimeOut.hashCode ^ receiveTimeOut.hashCode ^ numWant.hashCode ^ interval.hashCode;
}
