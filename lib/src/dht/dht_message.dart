import 'dart:typed_data';

import 'package:jtorrent/src/dht/struct/node_id.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';

enum DHTMessageType {
  query(bytes: [113]),
  response(bytes: [114]),
  error(bytes: [101]);

  const DHTMessageType({required this.bytes});

  final List<int> bytes;
}

abstract class DHTMessage {
  final List<int> tid;

  final DHTMessageType type;

  const DHTMessage({required this.tid, required this.type}) : assert(tid.length == 2);

  Uint8List get toUint8List;
}

abstract class QueryMessage extends DHTMessage {
  final String method;
  final Map<String, Object> arguments;

  QueryMessage({required super.tid, super.type = DHTMessageType.query, required this.method, required this.arguments});

  @override
  Uint8List get toUint8List => bEncode({
        't': tid,
        'y': Uint8List.fromList(type.bytes),
        'q': method,
        'a': arguments,
      });
}

class PingMessage extends QueryMessage {
  final NodeId selfId;

  PingMessage({required super.tid, required this.selfId}) : super(method: 'ping', arguments: {'id': selfId.id});
}
