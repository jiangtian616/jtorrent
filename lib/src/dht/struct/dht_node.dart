import 'dart:io';

import 'package:jtorrent/src/dht/struct/bucket.dart';

import 'node_id.dart';

class DHTNode {
  final NodeId id;

  final InternetAddress address;

  final int port;

  Bucket? bucket;

  DHTNode({required this.id, required this.address, required this.port});

  @override
  bool operator ==(Object other) => other is DHTNode && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
