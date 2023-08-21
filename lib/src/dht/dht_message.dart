import 'dart:typed_data';

import 'package:jtorrent/src/dht/dht_node.dart';
import 'package:jtorrent/src/dht/struct/node_id.dart';
import 'package:jtorrent/src/exception/dht_exception.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';

import '../model/peer.dart';

const String keyTransactionId = 't';
const String keyType = 'y';
const String keyQueryMethod = 'q';
const String keyResponse = 'r';
const String keyError = 'e';
const String keyQueryArguments = 'a';
const String keyNodeId = 'id';
const String keyTarget = 'target';
const String keyInfoHash = 'info_hash';
const String keyPort = 'port';
const String keyToken = 'token';
const String keyNodes = 'nodes';
const String keyValues = 'values';

const String methodPing = 'ping';
const String methodFindNode = 'find_node';
const String methodGetPeers = 'get_peers';
const String methodAnnouncePeer = 'announce_peer';

enum DHTMessageType {
  query(bytes: [113]),
  response(bytes: [114]),
  error(bytes: [101]);

  const DHTMessageType({required this.bytes});

  factory DHTMessageType.fromBytes(List<int> bytes) {
    switch (bytes[0]) {
      case 113:
        return query;
      case 114:
        return response;
      case 101:
        return error;
      default:
        throw DHTException('Unknown DHT message type: $bytes');
    }
  }

  final List<int> bytes;
}

abstract class DHTMessage {
  late final Uint8List tid;

  final DHTMessageType type;

  DHTMessage({required this.type});
}

abstract class QueryMessage extends DHTMessage {
  final String method;
  final Map<String, Object> arguments;

  QueryMessage({super.type = DHTMessageType.query, required this.method, required this.arguments});

  Uint8List get toUint8List => bEncode({
        keyTransactionId: tid,
        keyType: Uint8List.fromList(type.bytes),
        keyQueryMethod: method,
        keyQueryArguments: arguments,
      });
}

class PingMessage extends QueryMessage {
  final NodeId id;

  PingMessage({required this.id}) : super(method: methodPing, arguments: {keyNodeId: id.id});
}

class FindNodeMessage extends QueryMessage {
  final NodeId id;
  final NodeId target;

  FindNodeMessage({required this.id, required this.target}) : super(method: methodFindNode, arguments: {keyNodeId: id.id, keyTarget: target.id});
}

class GetPeersMessage extends QueryMessage {
  final NodeId id;
  final Uint8List infoHash;

  GetPeersMessage({required this.id, required this.infoHash}) : super(method: methodGetPeers, arguments: {keyNodeId: id.id, keyInfoHash: infoHash});
}

class AnnouncePeerMessage extends QueryMessage {
  final NodeId id;
  final Uint8List infoHash;
  final int port;
  final Uint8List token;

  AnnouncePeerMessage({required this.id, required this.infoHash, required this.port, required this.token})
      : super(method: methodAnnouncePeer, arguments: {keyNodeId: id.id, keyInfoHash: infoHash, keyPort: port, keyToken: token});
}

class ResponseMessage extends DHTMessage {
  @override
  final Uint8List tid;

  final DHTNode node;

  final List<DHTNode>? nodes;

  final List<Peer>? peers;

  final Uint8List? token;

  ResponseMessage({super.type = DHTMessageType.response, required this.tid, required this.node, this.nodes, this.peers, this.token})
      : assert(tid.length == 2);

  Uint8List get toUint8List => bEncode({
        keyTransactionId: tid,
        keyType: Uint8List.fromList(type.bytes),
        keyResponse: {
          keyNodeId: node.id.id,
          if (nodes != null) keyNodes: DHTNode.toCompactList(nodes!),
          if (peers != null) keyValues: Peer.toCompactList(peers!),
          if (token != null) keyToken: token,
        },
      });
}

class ErrorMessage extends DHTMessage {
  @override
  final Uint8List tid;

  final int code;
  final String message;

  ErrorMessage({super.type = DHTMessageType.error, required this.tid, required this.code, required this.message}) : assert(tid.length == 2);

  Uint8List get toUint8List => bEncode({
        keyTransactionId: tid,
        keyType: Uint8List.fromList(type.bytes),
        keyError: [code, message],
      });
}
