import 'dart:io';

class AnnounceRequestOptions {
  /// Request type
  final TrackerRequestType type;

  /// Inherited from [TrackerManager.localIp]
  final InternetAddress? localIp;

  /// Inherited from [TrackerManager.localPort]
  final int localPort;

  /// Inherited from [TrackerManager.compact]
  final bool compact;

  /// Inherited from [TrackerManager.noPeerId]
  final bool noPeerId;

  /// Bytes uploaded
  final int? uploaded;

  /// Bytes downloaded
  final int? downloaded;

  /// Bytes left
  final int? left;

  AnnounceRequestOptions({
    required this.type,
    this.localIp,
    required this.localPort,
    required this.compact,
    required this.noPeerId,
    this.uploaded,
    this.downloaded,
    this.left,
  });
}

enum TrackerRequestType { start, complete, stopped }
