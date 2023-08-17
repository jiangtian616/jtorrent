import 'dart:io';
import 'dart:typed_data';

abstract interface class AnnounceConfigProvider {
  /// Torrent's info hash
  Uint8List get infoHash;

  /// Local peer id
  Uint8List get peerId;

  /// The parameter is only needed if the client is communicating to the tracker through a proxy (or a transparent web proxy/cache.)
  InternetAddress? get localIp;

  /// The port number that the client is listening on. Ports reserved for BitTorrent are typically 6881-6889
  int get localPort;

  /// Whether to return compact peer list, default is true
  bool get compact;

  /// Whether to return peer id, default is true and in ignored if compact is true
  bool get noPeerId;

  /// Number of peers that the client would like to receive from the tracker, default is 200
  int get numWant;

  /// Bytes amount we have uploaded to other peers
  int get uploaded;

  /// Bytes amount we have downloaded from other peers
  int get downloaded;

  /// Bytes amount we still have to download
  int get left;

  /// Request timeout, default is 10 seconds
  Duration get connectTimeout;

  /// Request timeout, default is 30 seconds
  Duration get receiveTimeout;
}
