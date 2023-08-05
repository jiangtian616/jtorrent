import 'dart:io';

class Peer {
  /// A string of length 20, correspond to peer_id in request. Null in compact mode
  final String? peerId;
  
  /// Peer IP address
  final InternetAddress ip;
  
  /// Peer port
  final int port;

  const Peer({this.peerId, required this.ip, required this.port});

  @override
  String toString() {
    return 'Peer{peerId: $peerId, ip: $ip, port: $port}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Peer && runtimeType == other.runtimeType && peerId == other.peerId && ip == other.ip && port == other.port;

  @override
  int get hashCode => peerId.hashCode ^ ip.hashCode ^ port.hashCode;
}
