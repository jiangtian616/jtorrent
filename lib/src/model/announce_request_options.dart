import 'dart:io';

import '../announce/tracker.dart';

class AnnounceRequestOptions {
  /// Request type
  final AnnounceEventType type;

  /// Inherited from [TrackerManager.localIp]
  final InternetAddress? localIp;

  /// Inherited from [TrackerManager.localPort]
  final int localPort;

  /// Inherited from [TrackerManager.compact]
  final bool compact;

  /// Inherited from [TrackerManager.noPeerId]
  final bool noPeerId;

  /// Inherited from [TrackerManager.numWant]
  int numWant;

  /// Bytes uploaded
  int uploaded;

  /// Bytes downloaded
  int downloaded;

  /// Bytes left
  int left;

  AnnounceRequestOptions({
    required this.type,
    this.localIp,
    required this.localPort,
    required this.compact,
    required this.noPeerId,
    required this.numWant,
    required this.uploaded,
    required this.downloaded,
    required this.left,
  });
}
