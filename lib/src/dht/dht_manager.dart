import 'dart:async';
import 'dart:io';

import 'package:jtorrent/src/dht/dht_message.dart';
import 'package:jtorrent/src/dht/struct/dht_node.dart';
import 'package:jtorrent/src/dht/struct/node_id.dart';
import 'package:jtorrent/src/util/log_util.dart';

import 'struct/bucket.dart';

class DHTManager with DHTManagerEventDispatcher {
  final Bucket _root = Bucket(rangeBegin: NodeId.min, rangeEnd: NodeId.max);

  late final DHTNode _selfNode;

  List<({InternetAddress ip, int port})> discardNodes = [];

  List<DHTNode> badNodes = [];

  bool _initialized = false;
  bool connecting = false;
  bool connected = false;

  RawDatagramSocket? _socket;

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

    _selfNode = DHTNode(id: NodeId.random(), address: _socket!.address, port: _socket!.port);
    _root.addNode(_selfNode);

    connected = true;
    _fireOnConnectedCallBack(_socket!.port);

    _socket!.listen(
      (RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          _processReceiveData(_socket!.receive());
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

  Future<void> tryAddNode(InternetAddress ip, int port) async {
    if (_root.containNodeAddress(ip, port)) {
      return;
    }

    _sendPing(ip, port);
  }

  Future<void> _processReceiveData(Datagram? datagram) async {
    if (datagram == null) {
      return;
    }
  }

  Future<void> _sendPing(InternetAddress ip, int port) async {
    assert(_socket != null);
    
    _socket!.send(PingMessage(tid: tid, selfId: _selfNode.id).toUint8List, ip, port);
  }
}

mixin DHTManagerEventDispatcher {
  final Set<void Function(int)> _onConnectedCallBacks = {};
  final Set<void Function(dynamic)> _onConnectFailedCallBacks = {};
  final Set<void Function(dynamic)> _onConnectInterruptedCallBacks = {};
  final Set<void Function()> _onDisconnectedCallBacks = {};
  final Set<void Function(dynamic)> _onSendMessageFailedCallBacks = {};

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
}
