import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:jtorrent/src/dht/dht_message.dart';
import 'package:jtorrent/src/dht/dht_node.dart';
import 'package:jtorrent/src/dht/struct/node_id.dart';
import 'package:jtorrent/src/exception/dht_exception.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';

import '../constant/common_constants.dart';
import '../model/peer.dart';
import 'struct/bucket.dart';

class DHTManager with DHTManagerEventDispatcher {
  Duration queryTimeout = Duration(seconds: 15);

  static const Duration refreshPeriod = Duration(minutes: 15);

  bool _initialized = false;
  bool connecting = false;
  bool connected = false;

  final Map<Uint8List, List<Peer>> _infoHash2PeersMap = {};

  final Bucket<DHTNode> _root = Bucket(rangeBegin: NodeId.min, rangeEnd: NodeId.max);

  late final DHTNode _selfNode;

  final Set<DHTNode> _discardNodes = {};

  RawDatagramSocket? _socket;

  final Map<Uint8List, ({DHTMessage message, Timer timer})> _pendingRequests = {};

  final Map<DHTNode, Timer> _refreshTimer = {};

  Future<void> start() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    connecting = true;
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on Exception catch (e) {
      return _fireOnConnectFailedCallBack(e);
    }

    _selfNode = DHTNode(id: NodeId.random(), ip: _socket!.address, port: _socket!.port);
    _addNode(_selfNode);

    connected = true;
    _fireOnConnectedCallBack(_socket!.port);

    _socket!.listen(
      (RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          _processResponse(_socket!.receive());
        } else {
          Log.warning('Unknown event: $event');
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        return _fireOnConnectInterruptedCallBack(error);
      },
      onDone: () {
        return _fireOnDisconnectedCallBack();
      },
    );
  }

  void close() {
    assert(_socket != null);

    connecting = false;
    connected = false;

    _socket!.close();
  }

  Future<void> tryAddNodeAddress(InternetAddress ip, int port) async {
    if (_root.contains((node) => node.ip == ip && node.port == port)) {
      return;
    }

    _sendPing(ip, port);
  }

  Future<void> _processResponse(Datagram? datagram) async {
    if (datagram == null) {
      Log.fine('Received null datagram');
      return;
    }

    Map data;
    try {
      data = bDecode(datagram.data);
    } on BDecodingException catch (e) {
      Log.warning('Received invalid datagram: ${datagram.data}', e);
      return;
    }

    dynamic y = data[keyType];
    if (y is! Uint8List) {
      Log.warning('Received invalid message type: $y');
      return;
    }

    DHTMessageType type;
    try {
      type = DHTMessageType.fromBytes(y);
    } on DHTException catch (e) {
      Log.warning('Received invalid message type: $y', e);
      return;
    }

    dynamic tid = data[keyTransactionId];
    if (tid is! Uint8List) {
      Log.warning('Received invalid transaction id: $tid');
      return;
    }

    switch (type) {
      case DHTMessageType.query:
        dynamic q = data[keyQueryMethod];
        if (q is! Uint8List) {
          Log.warning('Received invalid query method: $q');
          return;
        }

        String method;
        try {
          method = utf8.decode(q);
        } on Exception catch (e) {
          Log.warning('Received invalid query method: $q', e);
          return;
        }

        dynamic arguments = data[keyQueryArguments];
        dynamic id = arguments[keyNodeId];
        if (arguments is! Map) {
          Log.warning('Received invalid query arguments: $arguments');
          return;
        }
        if (id is! Uint8List) {
          Log.warning('Received invalid node id: $id');
          return;
        }

        switch (method) {
          case methodPing:
            return _processPingMessage(PingMessage(id: NodeId(id: id))..tid = tid);
          case methodFindNode:
            dynamic target = arguments[keyTarget];
            if (target is! Uint8List) {
              Log.warning('Received invalid target: $target');
              return;
            }

            return _processFindNodeMessage(FindNodeMessage(id: NodeId(id: id), target: NodeId(id: target))..tid = tid);
          case methodGetPeers:
            dynamic infoHash = arguments[keyInfoHash];
            if (infoHash is! Uint8List) {
              Log.warning('Received invalid info hash: $infoHash');
              return;
            }

            return _processGetPeersMessage(GetPeersMessage(id: NodeId(id: id), infoHash: infoHash)..tid = tid);
          case methodAnnouncePeer:
            dynamic infoHash = arguments[keyInfoHash];
            dynamic port = arguments[keyPort];
            dynamic token = arguments[keyToken];

            if (infoHash is! Uint8List) {
              Log.warning('Received invalid info hash: $infoHash');
              return;
            }
            if (port is! int) {
              Log.warning('Received invalid port: $port');
              return;
            }
            if (token is! Uint8List) {
              Log.warning('Received invalid token: $token');
              return;
            }

            return _processAnnouncePeerMessage(
              AnnouncePeerMessage(
                id: NodeId(id: id),
                infoHash: infoHash,
                port: port,
                token: token,
              )..tid = tid,
            );
          default:
            return Log.severe('Unknown query method: ${data[keyQueryMethod]}');
        }
      case DHTMessageType.response:
        dynamic body = data[keyResponse];
        dynamic id = body[keyNodeId];
        dynamic token = body[keyToken];
        dynamic rawNodes = body[keyNodes];
        dynamic rawPeers = body[keyValues];

        if (body is! Map) {
          Log.warning('Received invalid response body: $body');
          return;
        }
        if (id is! Uint8List) {
          Log.warning('Received invalid node id: $id');
          return;
        }
        if (token != null && token is! Uint8List) {
          Log.warning('Received invalid token: $token');
          return;
        }
        if (rawNodes != null && rawNodes is! Uint8List) {
          Log.warning('Received invalid nodes: $rawNodes');
          return;
        }
        if (rawPeers != null && rawPeers is! Uint8List) {
          Log.warning('Received invalid peers: $rawPeers');
          return;
        }

        List<DHTNode> nodes = DHTNode.parseCompactList(body[keyNodes]);
        List<Peer> peers = Peer.parseCompactList(body[keyValues]);

        return _processResponseMessage(
          ResponseMessage(
            tid: tid,
            node: DHTNode(id: NodeId(id: id), ip: datagram.address, port: datagram.port),
            nodes: nodes,
            peers: peers,
            token: token,
          ),
        );
      case DHTMessageType.error:
        dynamic body = data[keyError];
        dynamic code = body[0];
        dynamic error = body[1];

        if (body is! List) {
          Log.warning('Received invalid error body: $body');
          return;
        }
        if (code is! int) {
          Log.warning('Received invalid error code: $code');
          return;
        }
        if (error is! String) {
          Log.warning('Received invalid error message: $error');
          return;
        }

        return _processErrorMessage(ErrorMessage(tid: tid, code: code, message: error));
      default:
        Log.severe('Unknown message type: $type');
    }
  }

  Future<void> _sendPing(InternetAddress ip, int port) async {
    assert(_socket != null);
    Log.finest('Sending ping message to $ip:$port');

    _sendQueryMessage(PingMessage(id: _selfNode.id), ip, port);
  }

  Future<void> _sendFindNode(DHTNode node) async {
    assert(_socket != null);
    Log.finest('Sending find node message to ${node.ip}:${node.port}');

    _sendQueryMessage(FindNodeMessage(id: _selfNode.id, target: _selfNode.id), node.ip, node.port);
  }

  Future<void> _sendGetPeers(DHTNode node, Uint8List infoHash) async {
    assert(_socket != null);
    Log.finest('Sending get peers message to ${node.ip}:${node.port}');

    _sendQueryMessage(GetPeersMessage(id: _selfNode.id, infoHash: infoHash), node.ip, node.port);
  }

  Future<void> _sendQueryMessage(QueryMessage message, InternetAddress ip, int port) async {
    if (!connected) {
      Log.fine('Not connected to DHT network, ignoring query message: $message');
      return;
    }

    Uint8List tid = _generateTransactionId();
    while (_pendingRequests[tid] != null) {
      tid = _generateTransactionId();
    }
    message.tid = tid;

    if (message is! AnnouncePeerMessage) {
      Timer timer = Timer(queryTimeout, () => _processQueryTimeout(tid));
      _pendingRequests[tid] = (message: message, timer: timer);
    }

    _socket!.send(message.toUint8List, ip, port);
  }

  void _processQueryTimeout(Uint8List tid) {}

  Uint8List _generateTransactionId() {
    Random random = Random();
    List<int> id = List.generate(CommonConstants.transactionIdLength, (index) => random.nextInt(1 << 8));
    return Uint8List.fromList(id);
  }

  Future<void> _processPingMessage(PingMessage pingMessage) async {}

  Future<void> _processFindNodeMessage(FindNodeMessage findNodeMessage) async {}

  Future<void> _processGetPeersMessage(GetPeersMessage getPeersMessage) async {}

  Future<void> _processAnnouncePeerMessage(AnnouncePeerMessage announcePeerMessage) async {}

  void _processResponseMessage(ResponseMessage response) {
    if (_pendingRequests[response.tid] == null) {
      Log.info('DHT received response with unknown transaction id: ${response.tid}');
      return;
    }

    ({DHTMessage message, Timer timer}) record = _pendingRequests.remove(response.tid)!;
    record.timer.cancel();

    if (_refreshTimer[response.node] != null) {
      _refreshTimer[response.node]!.cancel();
      _refreshTimer[response.node] = Timer(refreshPeriod, () => _refreshDHTNode(response.node));
    }

    switch (record.message.runtimeType) {
      case PingMessage:
        return _processPingResponse(record.message as PingMessage, response);
      case FindNodeMessage:
        return _processFindNodeResponse(record.message as FindNodeMessage, response);
      case GetPeersMessage:
        return _processGetPeersResponse(record.message as GetPeersMessage, response);
      default:
        Log.severe('DHT received unknown message type: ${record.message.runtimeType}');
    }
  }

  Future<void> _processErrorMessage(ErrorMessage message) async {
    Log.info('DHT received error message: $message');
  }

  void _processPingResponse(PingMessage message, ResponseMessage response) {
    Log.finest('DHT received ping response: ${response.node}');

    bool added = _addNode(response.node);
    if (!added) {
      Log.fine('DHT received ping response but failed to add node: ${response.node}');
      _discardNodes.add(response.node);
      return;
    }

    Log.finest('DHT added node: ${response.node}');

    _sendFindNode(response.node);
  }

  void _processFindNodeResponse(FindNodeMessage message, ResponseMessage response) {
    assert(_root.containsNode(response.node));
    Log.finest('DHT received find node response: ${response.node}');

    if (response.nodes == null) {
      Log.warning('DHT received find node response but no nodes found');
      return;
    }

    for (DHTNode node in response.nodes!) {
      if (_addNode(node)) {
        for (Uint8List infoHash in _infoHash2PeersMap.keys) {
          _sendGetPeers(node, infoHash);
        }
        _sendFindNode(node);
      }
    }
  }

  void _processGetPeersResponse(GetPeersMessage message, ResponseMessage response) {
    assert(_root.containsNode(response.node));
    Log.finest('DHT received get peers response: ${response.node}');

    if (response.nodes == null && response.peers == null) {
      Log.warning('DHT received get peers response but no nodes or peers found');
      return;
    }
    if (response.token == null) {
      Log.warning('DHT received get peers response but no token found');
      return;
    }

    _root.getNode(response.node)!.token = response.token;

    if (response.peers != null) {
      _infoHash2PeersMap[message.infoHash]?.addAll(response.peers!);
      _fireOnNewPeersFoundCallBack(message.infoHash, response.peers!);
    }

    if (response.nodes != null) {
      for (DHTNode node in response.nodes!) {
        if (_addNode(node)) {
          for (Uint8List infoHash in _infoHash2PeersMap.keys) {
            _sendGetPeers(node, infoHash);
          }
          _sendFindNode(node);
        }
      }
    }
  }

  void _refreshDHTNode(DHTNode node) {}

  bool _addNode(DHTNode node) {
    assert(node.bucket == null);

    bool added = _root.addNode(node);
    if (!added) {
      return false;
    }

    assert(node.bucket != null);

    if (node.bucket == _selfNode.bucket && _selfNode.bucket!.size >= Bucket.maxBucketSize) {
      _selfNode.bucket!.split();
    }

    return true;
  }
}

mixin DHTManagerEventDispatcher {
  final Set<void Function(int)> _onConnectedCallBacks = {};
  final Set<void Function(dynamic)> _onConnectFailedCallBacks = {};
  final Set<void Function(dynamic)> _onConnectInterruptedCallBacks = {};
  final Set<void Function()> _onDisconnectedCallBacks = {};
  final Set<void Function(dynamic)> _onSendMessageFailedCallBacks = {};

  final Set<void Function(Uint8List infoHash, List<Peer> peers)> _onNewPeersFoundCallBacks = {};

  void addOnConnectedCallBack(void Function(int) callback) => _onConnectedCallBacks.add(callback);

  bool removeOnConnectedCallBack(void Function(int) callback) => _onConnectedCallBacks.remove(callback);

  void _fireOnConnectedCallBack(int port) {
    for (var callback in _onConnectedCallBacks) {
      Timer.run(() {
        callback(port);
      });
    }
  }

  void addOnConnectFailedCallBack(void Function(dynamic) callback) => _onConnectFailedCallBacks.add(callback);

  bool removeOnConnectFailedCallBack(void Function(dynamic) callback) => _onConnectFailedCallBacks.remove(callback);

  void _fireOnConnectFailedCallBack(dynamic error) {
    for (var callback in _onConnectFailedCallBacks) {
      Timer.run(() {
        callback(error);
      });
    }
  }

  void addOnConnectInterruptedCallBack(void Function(dynamic) callback) => _onConnectInterruptedCallBacks.add(callback);

  bool removeOnConnectInterruptedCallBack(void Function(dynamic) callback) => _onConnectInterruptedCallBacks.remove(callback);

  void _fireOnConnectInterruptedCallBack(dynamic error) {
    for (var callback in _onConnectInterruptedCallBacks) {
      Timer.run(() {
        callback(error);
      });
    }
  }

  void addOnDisconnectedCallBack(void Function() callback) => _onDisconnectedCallBacks.add(callback);

  bool removeOnDisconnectedCallBack(void Function() callback) => _onDisconnectedCallBacks.remove(callback);

  void _fireOnDisconnectedCallBack() {
    for (var callback in _onDisconnectedCallBacks) {
      Timer.run(() {
        callback();
      });
    }
  }

  void addOnSendMessageFailedCallBack(void Function(dynamic) callback) => _onSendMessageFailedCallBacks.add(callback);

  bool removeOnSendMessageFailedCallBack(void Function(dynamic) callback) => _onSendMessageFailedCallBacks.remove(callback);

  void _fireOnSendMessageFailedCallBack(dynamic error) {
    for (var callback in _onSendMessageFailedCallBacks) {
      Timer.run(() {
        callback(error);
      });
    }
  }

  void addOnNewPeersFoundCallBack(void Function(Uint8List infoHash, List<Peer> peers) callback) => _onNewPeersFoundCallBacks.add(callback);

  bool removeOnNewPeersFoundCallBack(void Function(Uint8List infoHash, List<Peer> peers) callback) => _onNewPeersFoundCallBacks.remove(callback);

  void _fireOnNewPeersFoundCallBack(Uint8List infoHash, List<Peer> peers) {
    for (var callback in _onNewPeersFoundCallBacks) {
      Timer.run(() {
        callback(infoHash, peers);
      });
    }
  }
}
