import 'dart:io';
import 'dart:typed_data';

class Peer {
  /// A string of length 20 in bytes, correspond to peer_id in request. Null in compact mode
  final String? peerId;

  /// Peer IP address
  final InternetAddress ip;

  /// Peer port
  final int port;

  const Peer({this.peerId, required this.ip, required this.port});

  static Uint8List toCompactList(List<Peer> peers) {
    List<int> list = [];

    for (var i = 0; i < peers.length; i++) {
      final peer = peers[i];
      list.addAll(peer.ip.rawAddress);
      list.addAll([peer.port ~/ 256, peer.port % 256]);
    }

    return Uint8List.fromList(list);
  }

  static List<Peer> parseCompactList(Uint8List? rawPeers) {
    if (rawPeers == null) {
      return [];
    }

    List<Peer> peers = [];
    for (int i = 0; i < rawPeers.length; i += 6) {
      final ip = InternetAddress.fromRawAddress(rawPeers.sublist(i, i + 4));
      final port = (rawPeers[i + 4] << 8)+ rawPeers[i + 5];
      peers.add(Peer(ip: ip, port: port));
    }
    
    return peers;
  }

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
