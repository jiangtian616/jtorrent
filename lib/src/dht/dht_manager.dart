import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:jtorrent/src/dht/dht_message.dart';
import 'package:jtorrent/src/dht/dht_node.dart';
import 'package:jtorrent/src/dht/struct/node_distance.dart';
import 'package:jtorrent/src/dht/struct/node_id.dart';
import 'package:jtorrent/src/exception/dht_exception.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';

import '../constant/common_constants.dart';
import '../model/peer.dart';
import 'struct/bucket.dart';

abstract class DHTManager {
  Duration queryTimeout = Duration(seconds: 15);

  static const Duration nodeRefreshPeriod = Duration(minutes: 15);
  static const Duration tokenExpireTime = Duration(minutes: 10);

  final Set<String> _neededInfoHashes = {};

  bool _disposed = false;
  bool _paused = false;

  DHTManager._();

  factory DHTManager() {
    return _DHTManager();
  }

  Future<int> start();

  void pause() {
    if (_disposed) {
      throw DHTException('DHTManager has been disposed');
    }

    if (_paused) {
      return;
    }
    _paused = true;
  }

  void resume() {
    if (_disposed) {
      throw DHTException('DHTManager has been disposed');
    }

    if (!_paused) {
      return;
    }
    _paused = false;
  }

  void dispose();

  bool addNeededInfoHash(Uint8List infoHash) {
    return _neededInfoHashes.add(infoHash.toHexString);
  }

  bool removeNeededInfoHash(Uint8List infoHash) {
    return _neededInfoHashes.remove(infoHash.toHexString);
  }

  Future<void> tryAddNodeAddress(InternetAddress ip, int port);

  void announcePeer(Uint8List infoHash, int port, {bool impliedPort = false});

  void printDebugInfo();
}

class _DHTManager extends DHTManager with DHTManagerEventDispatcher {
  bool _initialized = false;
  bool _connected = false;

  final Completer<int> _initCompleter = Completer<int>();

  final Map<String, List<Peer>> _infoHashTable = {};

  final Bucket<DHTNode> _root = Bucket();
  late final DHTNode _selfNode;

  RawDatagramSocket? _socket;
  final Completer<void> _socketCompleter = Completer<void>();

  final Map<String, ({QueryMessage message, Timer timer})> _pendingTransactions = {};

  final Map<DHTNode, Timer> _refreshTimer = {};

  final Map<({InternetAddress ip, int port}), ({Uint8List token, Timer timer})> _tokenTimer = {};

  _DHTManager() : super._();

  @override
  Future<int> start() async {
    if (_initialized) {
      return _initCompleter.future;
    }
    _initialized = true;

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    _selfNode = DHTNode(id: NodeId.random(), ip: _socket!.address, port: _socket!.port);
    _addNodeAndSplit(_selfNode);

    _connected = true;

    _socket!.listen(
      (RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          _processResponse(_socket!.receive());
        }
        if (event == RawSocketEvent.write && !_socketCompleter.isCompleted) {
          _socketCompleter.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        return _fireOnConnectInterruptedCallBack(error);
      },
      onDone: () {
        return _fireOnDisconnectedCallBack();
      },
    );

    _initCompleter.complete(_socket!.port);
    return _socket!.port;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;

    _socket?.close();
    _socket = null;

    for (var record in _pendingTransactions.values) {
      record.timer.cancel();
    }
    _pendingTransactions.clear();

    for (var record in _refreshTimer.values) {
      record.cancel();
    }
    _refreshTimer.clear();

    for (var record in _tokenTimer.values) {
      record.timer.cancel();
    }
    _tokenTimer.clear();
  }

  @override
  Future<void> tryAddNodeAddress(InternetAddress ip, int port) async {
    if (_containsNodeAddress(ip, port)) {
      return;
    }

    _sendPing(ip, port);
  }

  @override
  void announcePeer(Uint8List infoHash, int port, {bool impliedPort = false}) {
    if (_disposed) {
      throw DHTException('DHTManager has been disposed');
    }
    if (!_connected) {
      throw DHTException('Not connected to DHT network');
    }
    if (_paused) {
      return Log.fine('DHT is paused, ignoring announce peer message');
    }

    for (DHTNode node in _root.findClosestNodes(NodeId(id: infoHash))) {
      _sendAnnouncePeer(node, infoHash, port, impliedPort);
    }
  }

  @override
  void printDebugInfo() {
    print(JsonEncoder.withIndent('  ').convert({
      'neededInfoHashes': _neededInfoHashes.toList(),
      'infoHashTable': _infoHashTable.map((key, value) => MapEntry(key, value.map((peer) => '${peer.ip.address}:${peer.port}').toList())),
      'selfNode': _selfNode.toString(),
      'nodes': _root.nodes.map((node) => node.toString()).toList(),
    }));
    print('');
  }

  Future<void> _processResponse(Datagram? datagram) async {
    if (datagram == null) {
      Log.fine('Received null datagram');
      return;
    }

    if (_disposed) {
      Log.info('DHTManager has been disposed, ignore datagram: $datagram');
      return;
    }

    if (_paused) {
      Log.fine('DHTManager is paused, ignore datagram: $datagram');
      return;
    }

    Map data;
    try {
      data = bDecode(datagram.data);
    } on Exception catch (e) {
      Log.warning('Received invalid datagram: ${datagram.data}', e);
      return;
    }

    dynamic y = data[keyType];
    if (y is! Uint8List) {
      Log.warning('Received invalid message type: $y, data: $data');
      return;
    }

    DHTMessageType type;
    try {
      type = DHTMessageType.fromBytes(y);
    } on DHTException catch (e) {
      Log.warning('Received invalid message type: $y, data: $data', e);
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
            return _processPingMessage(PingMessage(id: NodeId(id: id))..tid = tid, datagram.address, datagram.port);
          case methodFindNode:
            dynamic target = arguments[keyTarget];
            if (target is! Uint8List) {
              Log.warning('Received invalid target: $target');
              return;
            }

            return _processFindNodeMessage(
                FindNodeMessage(id: NodeId(id: id), target: NodeId(id: target))..tid = tid, datagram.address, datagram.port);
          case methodGetPeers:
            dynamic infoHash = arguments[keyInfoHash];
            if (infoHash is! Uint8List) {
              Log.warning('Received invalid info hash: $infoHash');
              return;
            }

            return _processGetPeersMessage(GetPeersMessage(id: NodeId(id: id), infoHash: infoHash)..tid = tid, datagram.address, datagram.port);
          case methodAnnouncePeer:
            dynamic infoHash = arguments[keyInfoHash];
            dynamic port = arguments[keyPort];
            dynamic token = arguments[keyToken];
            dynamic impliedPort = arguments[keyImpliedPort];

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
                impliedPort: impliedPort == 1,
                token: token,
              )..tid = tid,
              datagram.address,
              datagram.port,
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

        List<DHTNode> nodes = DHTNode.parseCompactList(rawNodes);
        List<Peer> peers = Peer.parseCompactList(rawPeers);

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
        if (error is! Uint8List) {
          Log.warning('Received invalid error message: $error');
          return;
        }

        return _processErrorMessage(ErrorMessage(tid: tid, code: code, message: error.toUTF8));
      default:
        Log.severe('Unknown message type: $type');
    }
  }

  Future<void> _sendPing(InternetAddress ip, int port) async {
    _sendQueryMessage(PingMessage(id: _selfNode.id), ip, port);
  }

  Future<void> _sendFindNode(DHTNode node) async {
    _sendQueryMessage(FindNodeMessage(id: _selfNode.id, target: _selfNode.id), node.ip, node.port);
  }

  Future<void> _sendGetPeers(DHTNode node, Uint8List infoHash) async {
    _sendQueryMessage(GetPeersMessage(id: _selfNode.id, infoHash: infoHash), node.ip, node.port);
  }

  Future<void> _sendAnnouncePeer(DHTNode node, Uint8List infoHash, int port, bool impliedPort) async {
    _sendQueryMessage(
      AnnouncePeerMessage(
        id: _selfNode.id,
        infoHash: infoHash,
        port: port,
        impliedPort: impliedPort,
        token: node.token!,
      ),
      node.ip,
      node.port,
    );
  }

  Future<void> _sendQueryMessage(QueryMessage message, InternetAddress ip, int port) async {
    assert(_socket != null);

    if (!_connected) {
      Log.fine('Not connected to DHT network, ignoring query message: $message');
      return;
    }

    if (_paused) {
      Log.fine('DHT is paused, ignoring query message: $message');
      return;
    }

    Uint8List tid = _generateTransactionId();
    while (_pendingTransactions[tid.toHexString] != null) {
      tid = _generateTransactionId();
    }
    message.tid = tid;

    if (message is! AnnouncePeerMessage) {
      _pendingTransactions[tid.toHexString] = (message: message, timer: Timer(queryTimeout, () => _resendQueryMessageOnce(tid, ip, port)));
    }

    Log.finest('Sending $message to ${ip.address}:$port, tid:$tid');

    _sendSocketWithRetry(message.toUint8List, ip, port);
  }

  void _resendQueryMessageOnce(Uint8List tid, InternetAddress ip, int port) {
    ({QueryMessage message, Timer timer})? record = _pendingTransactions.remove(tid.toHexString);
    if (record == null) {
      return;
    }

    Log.finest('Resending ${record.message} to ${ip.address}:$port, tid: $tid');

    _pendingTransactions[tid.toHexString] = (
      message: record.message,
      timer: Timer(queryTimeout, () {
        Log.finest('Waiting for response timeout, removing node address: ${ip.address}:$port');

        _pendingTransactions.remove(tid.toHexString);
        _removeNodeAddress(ip, port);
      }),
    );

    _sendSocketWithRetry(record.message.toUint8List, ip, port);
  }

  Future<void> _sendResponseMessage(ResponseMessage message, InternetAddress ip, int port) async {
    if (!_connected) {
      Log.fine('Not connected to DHT network, ignoring response message: $message');
      return;
    }

    if (_paused) {
      Log.fine('DHT is paused, ignoring response message: $message');
      return;
    }

    Log.finest('Sending response message to ${ip.address}:$port, message: ${message}');

    _sendSocketWithRetry(message.toUint8List, ip, port);
  }

  Future<void> _sendSocketWithRetry(Uint8List bytes, InternetAddress ip, int port) async {
    await _socketCompleter.future;

    int times = 0;

    while (_socket!.send(bytes, ip, port) == 0) {
      if (times++ >= 3) {
        Log.warning('Failed to send message to ${ip.address}:$port, giving up');
        return;
      }

      await Future.delayed(Duration(milliseconds: 100));
      Log.finest('Failed to send message to ${ip.address}:$port, retrying for $times time');
    }
  }

  Future<void> _processPingMessage(PingMessage pingMessage, InternetAddress ip, int port) async {
    Log.finest('Received ping message from ${ip.address}:$port, id: ${pingMessage.id}');

    tryAddNodeAddress(ip, port);

    await _sendResponseMessage(ResponseMessage(tid: pingMessage.tid, node: _selfNode), ip, port);
  }

  Future<void> _processFindNodeMessage(FindNodeMessage findNodeMessage, InternetAddress ip, int port) async {
    Log.finest('Received find node message from ${ip.address}:$port, id: ${findNodeMessage.id}, target: ${findNodeMessage.target}');

    List<DHTNode> nodes = _root.findClosestNodes(findNodeMessage.target);

    await _sendResponseMessage(ResponseMessage(tid: findNodeMessage.tid, node: _selfNode, nodes: nodes), ip, port);
  }

  Future<void> _processGetPeersMessage(GetPeersMessage getPeersMessage, InternetAddress ip, int port) async {
    Log.finest('Received get peers message from ${ip.address}:$port, id: ${getPeersMessage.id}, info hash: ${getPeersMessage.infoHash}');

    List<Peer>? peers = _infoHashTable[getPeersMessage.infoHash.toHexString];
    List<DHTNode> nodes = _root.findClosestNodes(NodeId(id: getPeersMessage.infoHash));

    Uint8List token = _generateToken(ip, port);
    _tokenTimer[(ip: ip, port: port)] = (token: token, timer: Timer(DHTManager.tokenExpireTime, () => _tokenTimer.remove((ip: ip, port: port))));

    await _sendResponseMessage(ResponseMessage(tid: getPeersMessage.tid, node: _selfNode, nodes: nodes, peers: peers), ip, port);
  }

  Future<void> _processAnnouncePeerMessage(AnnouncePeerMessage announcePeerMessage, InternetAddress ip, int port) async {
    Log.finest(
        'Received announce peer message from ${ip.address}:$port, id: ${announcePeerMessage.id}, info hash: ${announcePeerMessage.infoHash}, token: ${announcePeerMessage.token}');

    Uint8List? exitsToken = _tokenTimer.remove((ip: ip, port: port))?.token;
    if (exitsToken == null || !ListEquality<int>().equals(exitsToken, announcePeerMessage.token)) {
      Log.warning('Received announce peer message with invalid token $exitsToken-${announcePeerMessage.token}, ignoring message.');
      return;
    }

    _tokenTimer[(ip: ip, port: port)] = (token: exitsToken, timer: Timer(DHTManager.tokenExpireTime, () => _tokenTimer.remove((ip: ip, port: port))));

    Peer peer = Peer(ip: ip, port: announcePeerMessage.impliedPort ? port : announcePeerMessage.port);

    (_infoHashTable[announcePeerMessage.infoHash.toHexString] ??= []).add(peer);

    _fireOnNewPeersFoundCallBack(announcePeerMessage.infoHash, [peer]);
  }

  void _processResponseMessage(ResponseMessage response) {
    if (_pendingTransactions[response.tid.toHexString] == null) {
      Log.info('DHT received response with unknown transaction id: ${response.tid}');
      return;
    }

    ({QueryMessage message, Timer timer}) record = _pendingTransactions.remove(response.tid.toHexString)!;
    record.timer.cancel();

    _refreshTimer[response.node]?.cancel();
    _refreshTimer[response.node] = Timer(DHTManager.nodeRefreshPeriod, () => _sendPing(response.node.ip, response.node.port));

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
    Log.warning('DHT received error message: $message');
  }

  void _processPingResponse(PingMessage message, ResponseMessage response) {
    Log.finest('DHT received ping response: $response');

    _addNodeAndRequire(response.node);
  }

  void _processFindNodeResponse(FindNodeMessage message, ResponseMessage response) {
    Log.finest('DHT received find node response: $response');

    if (_root.nodes.lookup(response.node) == null) {
      Log.warning('DHT received find node response but node not found');
      return;
    }

    if (response.nodes == null) {
      Log.warning('DHT received find node response but no nodes found');
      return;
    }

    for (DHTNode node in response.nodes!) {
      if (!node.ip.isLoopback && !node.ip.isLinkLocal) {
        tryAddNodeAddress(node.ip, node.port);
      }
    }
  }

  void _processGetPeersResponse(GetPeersMessage message, ResponseMessage response) {
    Log.finest('DHT received get peers response: $response');

    if (response.nodes == null && response.peers == null) {
      Log.warning('DHT received get peers response but no nodes or peers found');
      return;
    }

    DHTNode? node = _root.nodes.lookup(response.node);
    if (node == null) {
      Log.warning('DHT received find node response but node not found');
      return;
    }

    if (response.token == null) {
      Log.warning('DHT received get peers response but no token found');
    } else {
      node.token = response.token;
    }

    if (response.peers != null && response.peers!.isNotEmpty) {
      Log.info('DHT received ${response.peers!.length} peers from ${response.node}');

      (_infoHashTable[message.infoHash.toHexString] ??= []).addAll(response.peers!);
      _fireOnNewPeersFoundCallBack(message.infoHash, response.peers!);
    }

    if (response.nodes != null) {
      for (DHTNode node in response.nodes!) {
        tryAddNodeAddress(node.ip, node.port);
      }
    }
  }

  bool _addNodeAndRequire(DHTNode node) {
    if (!_addNodeAndSplit(node)) {
      return false;
    }

    for (String infoHash in _neededInfoHashes) {
      _sendGetPeers(node, infoHash.toUint8ListFromHex);
    }
    _sendFindNode(node);
    return true;
  }

  bool _addNodeAndSplit(DHTNode node) {
    assert(node.bucket == null);

    bool added = _root.addNode(node);
    if (!added) {
      Log.finest('DHT failed to add node: $node');
      return false;
    }

    assert(node.bucket != null);
    Log.finest('DHT added node: $node');

    while (_selfNode.bucket!.size >= Bucket.maxBucketSize) {
      Log.fine('DHT bucket is full, splitting bucket: ${_selfNode.bucket.hashCode}');
      _selfNode.bucket!.split();
    }

    return true;
  }

  Uint8List _generateTransactionId() {
    Random random = Random();
    List<int> id = List.generate(CommonConstants.transactionIdLength, (index) => random.nextInt(1 << 8));
    return Uint8List.fromList(id);
  }

  Uint8List _generateToken(InternetAddress ip, int port) {
    List<int> bytes = ip.rawAddress + [port ~/ 256, port % 256] + DateTime.now().microsecondsSinceEpoch.toRadixString(16).codeUnits;
    return Uint8List.fromList(bytes);
  }

  bool _containsNodeAddress(InternetAddress ip, int port) {
    return _root.nodes.any((node) => node.ip.address == ip.address && node.port == port);
  }

  void _removeNodeAddress(InternetAddress ip, int port) {
    List<DHTNode> list = _root.nodes.where((node) => node.ip.address == ip.address && node.port == port).toList();

    for (DHTNode node in list) {
      assert(node.bucket != null);
      _root.removeNode(node);
    }
  }
}

mixin DHTManagerEventDispatcher {
  final Set<void Function(dynamic)> _onConnectInterruptedCallBacks = {};
  final Set<void Function()> _onDisconnectedCallBacks = {};

  final Set<void Function(Uint8List infoHash, List<Peer> peers)> _onNewPeersFoundCallBacks = {};

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
