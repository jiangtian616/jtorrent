import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/dht/struct/node.dart';

import 'struct/node_id.dart';

class DHTNode extends AbstractNode {
  final InternetAddress ip;

  final int port;
  
  Uint8List? token;

  DHTNode({required super.id, required this.ip, required this.port});

  static Uint8List toCompactList(List<DHTNode> nodes) {
    List<int> list = [];

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      list.addAll(node.id.id);
      list.addAll(node.ip.rawAddress);
      list.addAll([node.port ~/ 256, node.port % 256]);
    }

    return Uint8List.fromList(list);
  }

  static List<DHTNode> parseCompactList(Uint8List? list) {
    if (list == null) {
      return [];
    }

    List<DHTNode> nodes = [];
    for (var i = 0; i < list.length; i += 26) {
      final id = NodeId(id: list.sublist(i, i + 20));
      final ip = InternetAddress.fromRawAddress(list.sublist(i + 20, i + 24));
      final port = list[i + 24] << 8 + list[i + 25];
      nodes.add(DHTNode(id: id, ip: ip, port: port));
    }

    return nodes;
  }

  @override
  String toString() {
    return 'DHTNode{ip: $ip, port: $port}';
  }

  @override
  bool operator ==(Object other) => other is DHTNode && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
