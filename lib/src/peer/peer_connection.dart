import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/peer/peer_meesage.dart';
import 'package:jtorrent/src/util/log_util.dart';

import '../model/peer.dart';

abstract class PeerConnection with PeerConnectionEventDispatcher {
  static const int maxPendingRequests = 6;
  static const Duration maxIdleTime = Duration(minutes: 2);
  static const Duration requestTimeout = Duration(seconds: 20);

  final Peer peer;

  bool connecting = false;
  bool connected = false;
  bool illegal = false;

  DateTime? lastActiveTime;
  bool haveHandshake = false;
  bool peerHaveHandshake = false;
  bool haveSentBitField = false;
  bool peerHaveSentBitField = false;
  int timeoutTimes = 0;

  bool amChoking = true;
  bool amInterested = false;
  bool peerChoking = true;
  bool peerInterested = false;

  final Map<({int pieceIndex, int subPieceIndex}), ({int length, Timer timer})> pendingRequests = {};

  Timer? _keepAliveTimer;
  Timer? _peerKeepAliveTimer;

  PeerConnection({required this.peer});

  Future<void> connect();

  void close({bool illegal = false});

  void sendHandShake(Uint8List infoHash);

  void sendKeepAlive();

  void sendUnChoke();

  void sendInterested();

  bool sendRequest(int pieceIndex, int subPieceIndex, int length);

  void sendCancel(int pieceIndex, int subPieceIndex, int length);

  void sendBitField(Uint8List bitField);

  void sendHaveMessage(int pieceIndex);

  List<({int pieceIndex, int subPieceIndex})> clearPendingRequests() {
    for (var entry in pendingRequests.entries) {
      entry.value.timer.cancel();
      sendCancel(entry.key.pieceIndex, entry.key.subPieceIndex, entry.value.length);
    }

    List<({int pieceIndex, int subPieceIndex})> requests = pendingRequests.keys.toList();
    pendingRequests.clear();
    return requests;
  }

  bool completePendingRequest(int pieceIndex, int subPieceIndex) {
    ({int length, Timer timer})? value = pendingRequests.remove((pieceIndex: pieceIndex, subPieceIndex: subPieceIndex));
    if (value != null) {
      value.timer.cancel();
      return true;
    }
    return false;
  }

  bool cancelPendingRequest(int pieceIndex, int subPieceIndex) {
    ({int length, Timer timer})? value = pendingRequests.remove((pieceIndex: pieceIndex, subPieceIndex: subPieceIndex));
    if (value != null) {
      value.timer.cancel();
      sendCancel(pieceIndex, subPieceIndex, value.length);
      return true;
    }
    return false;
  }

  void resetTimeoutTimes() {
    timeoutTimes = 0;
  }

  void _countDownKeepAliveTimer() {
    _peerKeepAliveTimer?.cancel();
    _peerKeepAliveTimer = Timer(maxIdleTime, () {
      sendKeepAlive();
    });
  }

  void _countDownPeerKeepAliveTimer() {
    _peerKeepAliveTimer?.cancel();
    _peerKeepAliveTimer = Timer(maxIdleTime, () {
      Log.fine('Peer $peer is idle for $maxIdleTime, closing connection');
      close();
    });
  }

  bool _addRequest(int pieceIndex, int subPieceIndex, int length) {
    if (pendingRequests[(subPieceIndex: subPieceIndex, pieceIndex: pieceIndex)] != null) {
      return true;
    }
    if (pendingRequests.length >= PeerConnection.maxPendingRequests) {
      return false;
    }

    pendingRequests[(pieceIndex: pieceIndex, subPieceIndex: subPieceIndex)] = (
      length: length,
      timer: Timer(PeerConnection.requestTimeout, () {
        bool success = pendingRequests.remove((pieceIndex: pieceIndex, subPieceIndex: subPieceIndex)) != null;
        if (success) {
          _fireOnRequestTimeoutCallBack(pieceIndex, subPieceIndex);
        }
      }),
    );

    return true;
  }
}

class TcpPeerConnection extends PeerConnection {
  TcpPeerConnection({required super.peer});

  Socket? _socket;

  /// The buffer for the message from socket
  final List<int> _buffer = [];

  /// Some clients (Deluge for example) send bitfield with missing pieces even if it has all data. Then it sends rest of pieces as have messages.
  /// They are saying this helps against ISP filtering of BitTorrent protocol. It is called lazy bitfield. We combine them together as a single [BitFieldMessage]
  final List<BitFieldMessage> _stackedBitFieldMessages = [];
  final List<HaveMessage> _stackedHaveMessages = [];

  @override
  Future<void> connect() async {
    assert(!connecting && !connected);

    connecting = true;
    _socket?.close();
    _buffer.clear();

    try {
      _socket = await Socket.connect(peer.ip, peer.port);
    } on Exception catch (e) {
      close();
      return _fireOnConnectFailedCallBack(e);
    }

    connected = true;
    _fireOnConnectedCallBack();

    _socket!.listen(
      (data) => _handleNewResponseData(data),
      onError: (Object error, StackTrace stackTrace) {
        close();
        _fireOnConnectInterruptedCallBack(error);
      },
      onDone: () {
        close();
        _fireOnDisconnectedCallBack();
      },
    );

    _countDownKeepAliveTimer();
  }

  @override
  void sendHandShake(Uint8List infoHash) {
    assert(haveHandshake == false);
    assert(_socket != null);

    Log.finest('send handshake to ${peer.ip.address}:${peer.port}');

    _sendMessage(HandshakeMessage.noExtension(infoHash: infoHash));
  }

  @override
  void sendKeepAlive() {
    assert(_socket != null);

    Log.finest('send keep alive to ${peer.ip.address}:${peer.port}');

    _sendMessage(KeepAliveMessage.instance);
  }
  
  @override
  void sendUnChoke() {
    assert(_socket != null);
    assert(amChoking == true);

    Log.finest('send unChoke to ${peer.ip.address}:${peer.port}');

    _sendMessage(UnChokeMessage.instance);
  }

  @override
  void sendInterested() {
    assert(_socket != null);
    assert(amInterested == false);

    Log.finest('send interested to ${peer.ip.address}:${peer.port}');

    _sendMessage(InterestedMessage.instance);
  }

  @override
  bool sendRequest(int pieceIndex, int subPieceIndex, int length) {
    assert(_socket != null);
    assert(peerChoking == false);

    if (!_addRequest(pieceIndex, subPieceIndex, length)) {
      return false;
    }

    Log.finest('send request to ${peer.ip.address}:${peer.port} for piece: $pieceIndex subPieceIndex: $subPieceIndex length: $length');

    _sendMessage(RequestMessage(index: pieceIndex, begin: subPieceIndex * CommonConstants.subPieceLength, length: length));
    return true;
  }

  @override
  void sendCancel(int pieceIndex, int subPieceIndex, int length) {
    assert(_socket != null);

    Log.fine('send cancel to ${peer.ip.address}:${peer.port} for piece: $pieceIndex subPieceIndex: $subPieceIndex length: $length');

    _sendMessage(CancelMessage(index: pieceIndex, begin: subPieceIndex * CommonConstants.subPieceLength, length: length));
  }

  @override
  void sendBitField(Uint8List bitField) {
    assert(_socket != null);
    assert(haveSentBitField == false);

    Log.finest('send bitfield to ${peer.ip.address}:${peer.port} with bitfield: $bitField');

    _sendMessage(BitFieldMessage.fromBitField(bitField));
  }

  @override
  void sendHaveMessage(int pieceIndex) {
    assert(_socket != null);

    Log.finest('send have message to ${peer.ip.address}:${peer.port} for piece: $pieceIndex');

    _sendMessage(HaveMessage(pieceIndex: pieceIndex));
  }

  @override
  void close({bool illegal = false}) {
    connecting = false;
    connected = false;
    this.illegal = illegal;

    _socket?.close();
    _buffer.clear();
  }

  void _sendMessage(PeerMessage message) {
    if (!connected) {
      return;
    }

    assert(_socket != null);
    try {
      _socket!.add(message.toUint8List);
    } on Object catch (e) {
      _fireOnSendMessageFailedCallBack(e);
    }
    
    _countDownKeepAliveTimer();
  }

  void _handleNewResponseData(Uint8List response) {
    super._countDownPeerKeepAliveTimer();

    _buffer.addAll(response);
    if (_buffer.isEmpty) {
      return;
    }

    _handleBuffer();
  }

  void _handleBuffer() {
    if (_isHandshakeMessageHead()) {
      _handleHandshakeMessage();

      if (_buffer.isNotEmpty) {
        _handleBuffer();
      }

      return;
    }

    if (_isOtherMessageHead()) {
      _handleOtherMessage();

      if (_buffer.isNotEmpty) {
        _handleBuffer();
      }
    }

    _sendComposedMessage();
  }

  bool _isHandshakeMessageHead() {
    if (_buffer.length < 68) {
      return false;
    }

    final int pStrlen = _buffer[0];
    if (pStrlen != HandshakeMessage.defaultPStrlen) {
      return false;
    }

    for (int i = 0; i < HandshakeMessage.defaultPStrlen; i++) {
      if (_buffer[i + 1] != HandshakeMessage.defaultPStrCodeUnits[i]) {
        return false;
      }
    }

    return true;
  }

  void _handleHandshakeMessage() {
    List<int> segment = _buffer.sublist(0, 68);
    _buffer.removeRange(0, 68);
    _fireOnHandshakeMessageCallBack(HandshakeMessage.fromBuffer(segment));
  }

  bool _isOtherMessageHead() {
    if (_buffer.length < 4) {
      return false;
    }

    if (_buffer.length == 4 && (_buffer[0] == 0 && _buffer[1] == 0 && _buffer[2] == 0 && _buffer[3] == 0)) {
      return false;
    }

    for (int i = 0; i < 4; i++) {
      if (_buffer[i] >= (2 << 8 - 1)) {
        return false;
      }
    }

    int length = ByteData.view(Uint8List.fromList(_buffer).buffer, 0, 4).getInt32(0, Endian.big);
    if (_buffer.length < 4 + length) {
      return false;
    }

    return true;
  }

  void _handleOtherMessage() {
    int length = ByteData.view(Uint8List.fromList(_buffer).buffer, 0, 4).getInt32(0, Endian.big);

    List<int> segment = _buffer.sublist(0, 4 + length);
    _buffer.removeRange(0, 4 + length);

    if (length == 0) {
      return _fireOnKeepAliveMessageCallBack(KeepAliveMessage.instance);
    }

    int typeId = segment[4];

    switch (typeId) {
      case ChokeMessage.typeId:
        if (length != 1) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid choke message length $length'));
          break;
        } else {
          return _fireOnChokeMessageCallBack(ChokeMessage.instance);
        }
      case UnChokeMessage.typeId:
        if (length != 1) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid uncChoke message length $length'));
          break;
        } else {
          return _fireOnUnChokeMessageCallBack(UnChokeMessage.instance);
        }
      case InterestedMessage.typeId:
        if (length != 1) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid interested message length $length'));
          break;
        } else {
          return _fireOnInterestedMessageCallBack(InterestedMessage.instance);
        }
      case NotInterestedMessage.typeId:
        if (length != 1) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid notInterested message length $length'));
          break;
        } else {
          return _fireOnNotInterestedMessageCallBack(NotInterestedMessage.instance);
        }
      case HaveMessage.typeId:
        if (length != 5) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid have message length $length'));
          break;
        } else {
          _stackedHaveMessages.add(HaveMessage.fromBuffer(segment));
          break;
        }
      case BitFieldMessage.typeId:
        if (length < 1) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid bitField message length $length'));
          break;
        } else {
          _stackedBitFieldMessages.add(BitFieldMessage.fromBuffer(segment));
          break;
        }
      case RequestMessage.typeId:
        if (length != 13) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid request message length $length'));
          break;
        } else {
          return _fireOnRequestMessageCallBack(RequestMessage.fromBuffer(segment));
        }
      case PieceMessage.typeId:
        if (length < 9) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid piece message length $length'));
          break;
        } else {
          return _fireOnPieceMessageCallBack(PieceMessage.fromBuffer(segment));
        }
      case CancelMessage.typeId:
        if (length != 13) {
          _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Invalid cancel message length $length'));
          break;
        } else {
          return _fireOnCancelMessageCallBack(CancelMessage.fromBuffer(segment));
        }
      default:
        _fireOnIllegalMessageCallBack(IllegalMessage(message: 'Unknown message type id: $typeId'));
    }
  }

  void _sendComposedMessage() {
    if (_stackedBitFieldMessages.isEmpty && _stackedHaveMessages.isEmpty) {
      return;
    }

    if (_stackedBitFieldMessages.isEmpty && _stackedHaveMessages.isNotEmpty) {
      _fireOnComposedHaveMessageCallBack(ComposedHaveMessage.composed(_stackedHaveMessages));
    } else if (_stackedBitFieldMessages.isNotEmpty && _stackedHaveMessages.isEmpty) {
      for (BitFieldMessage bitFieldMessage in _stackedBitFieldMessages) {
        _fireOnBitFieldMessageCallBack(bitFieldMessage);
      }
    } else {
      _fireOnBitFieldMessageCallBack(BitFieldMessage.composed(_stackedBitFieldMessages, _stackedHaveMessages));
    }

    _stackedBitFieldMessages.clear();
    _stackedHaveMessages.clear();
  }
}

mixin PeerConnectionEventDispatcher {
  final Set<void Function()> _onConnectedCallBacks = {};
  final Set<void Function(dynamic)> _onConnectFailedCallBacks = {};
  final Set<void Function(dynamic)> _onConnectInterruptedCallBacks = {};
  final Set<void Function()> _onDisconnectedCallBacks = {};
  final Set<void Function(dynamic)> _onSendMessageFailedCallBacks = {};

  final Set<void Function(IllegalMessage)> _onIllegalMessageCallBacks = {};
  final Set<void Function(HandshakeMessage)> _onHandshakeMessageCallBacks = {};
  final Set<void Function(KeepAliveMessage)> _onKeepAliveMessageCallBacks = {};
  final Set<void Function(ChokeMessage)> _onChokeMessageCallBacks = {};
  final Set<void Function(UnChokeMessage)> _onUnChokeMessageCallBacks = {};
  final Set<void Function(InterestedMessage)> _onInterestedMessageCallBacks = {};
  final Set<void Function(NotInterestedMessage)> _onNotInterestedMessageCallBacks = {};
  final Set<void Function(ComposedHaveMessage)> _onComposedHaveMessageCallBacks = {};
  final Set<void Function(BitFieldMessage)> _onBitFieldMessageCallBacks = {};
  final Set<void Function(RequestMessage)> _onRequestMessageCallBacks = {};
  final Set<void Function(PieceMessage)> _onPieceMessageCallBacks = {};
  final Set<void Function(CancelMessage)> _onCancelMessageCallBacks = {};

  final Set<void Function(int pieceIndex, int subPieceIndex)> _onRequestTimeoutCallBacks = {};

  void addOnConnectedCallBack(void Function() callback) => _onConnectedCallBacks.add(callback);

  bool removeOnConnectedCallBack(void Function() callback) => _onConnectedCallBacks.remove(callback);

  void _fireOnConnectedCallBack() {
    for (var callback in _onConnectedCallBacks) {
      Timer.run(() {
        callback();
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

  void addOnIllegalMessageCallBack(void Function(IllegalMessage) callback) => _onIllegalMessageCallBacks.add(callback);

  bool removeOnIllegalMessageCallBack(void Function(IllegalMessage) callback) => _onIllegalMessageCallBacks.remove(callback);

  void _fireOnIllegalMessageCallBack(IllegalMessage message) {
    for (var callback in _onIllegalMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnHandshakeMessageCallBack(void Function(HandshakeMessage) callback) => _onHandshakeMessageCallBacks.add(callback);

  bool removeOnHandshakeMessageCallBack(void Function(HandshakeMessage) callback) => _onHandshakeMessageCallBacks.remove(callback);

  void _fireOnHandshakeMessageCallBack(HandshakeMessage message) {
    for (var callback in _onHandshakeMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnKeepAliveMessageCallBack(void Function(KeepAliveMessage) callback) => _onKeepAliveMessageCallBacks.add(callback);

  bool removeOnKeepAliveMessageCallBack(void Function(KeepAliveMessage) callback) => _onKeepAliveMessageCallBacks.remove(callback);

  void _fireOnKeepAliveMessageCallBack(KeepAliveMessage message) {
    for (var callback in _onKeepAliveMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnChokeMessageCallBack(void Function(ChokeMessage) callback) => _onChokeMessageCallBacks.add(callback);

  bool removeOnChokeMessageCallBack(void Function(ChokeMessage) callback) => _onChokeMessageCallBacks.remove(callback);

  void _fireOnChokeMessageCallBack(ChokeMessage message) {
    for (var callback in _onChokeMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnUnChokeMessageCallBack(void Function(UnChokeMessage) callback) => _onUnChokeMessageCallBacks.add(callback);

  bool removeOnUnChokeMessageCallBack(void Function(UnChokeMessage) callback) => _onUnChokeMessageCallBacks.remove(callback);

  void _fireOnUnChokeMessageCallBack(UnChokeMessage message) {
    for (var callback in _onUnChokeMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnInterestedMessageCallBack(void Function(InterestedMessage) callback) => _onInterestedMessageCallBacks.add(callback);

  bool removeOnInterestedMessageCallBack(void Function(InterestedMessage) callback) => _onInterestedMessageCallBacks.remove(callback);

  void _fireOnInterestedMessageCallBack(InterestedMessage message) {
    for (var callback in _onInterestedMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnNotUnInterestedMessageCallBack(void Function(NotInterestedMessage) callback) => _onNotInterestedMessageCallBacks.add(callback);

  bool removeOnNotUnInterestedMessageCallBack(void Function(NotInterestedMessage) callback) => _onNotInterestedMessageCallBacks.remove(callback);

  void _fireOnNotInterestedMessageCallBack(NotInterestedMessage message) {
    for (var callback in _onNotInterestedMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnComposedHaveMessageCallBack(void Function(ComposedHaveMessage) callback) => _onComposedHaveMessageCallBacks.add(callback);

  bool removeOnComposedHaveMessageCallBack(void Function(ComposedHaveMessage) callback) => _onComposedHaveMessageCallBacks.remove(callback);

  void _fireOnComposedHaveMessageCallBack(ComposedHaveMessage message) {
    for (var callback in _onComposedHaveMessageCallBacks) {
      callback(message);
    }
  }

  void addOnBitFieldMessageCallBack(void Function(BitFieldMessage) callback) => _onBitFieldMessageCallBacks.add(callback);

  bool removeOnBitFieldMessageCallBack(void Function(BitFieldMessage) callback) => _onBitFieldMessageCallBacks.remove(callback);

  void _fireOnBitFieldMessageCallBack(BitFieldMessage message) {
    for (var callback in _onBitFieldMessageCallBacks) {
      callback(message);
    }
  }

  void addOnRequestMessageCallBack(void Function(RequestMessage) callback) => _onRequestMessageCallBacks.add(callback);

  bool removeOnRequestMessageCallBack(void Function(RequestMessage) callback) => _onRequestMessageCallBacks.remove(callback);

  void _fireOnRequestMessageCallBack(RequestMessage message) {
    for (var callback in _onRequestMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnPieceMessageCallBack(void Function(PieceMessage) callback) => _onPieceMessageCallBacks.add(callback);

  bool removeOnPieceMessageCallBack(void Function(PieceMessage) callback) => _onPieceMessageCallBacks.remove(callback);

  void _fireOnPieceMessageCallBack(PieceMessage message) {
    for (var callback in _onPieceMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnCancelMessageCallBack(void Function(CancelMessage) callback) => _onCancelMessageCallBacks.add(callback);

  bool removeOnCancelMessageCallBack(void Function(CancelMessage) callback) => _onCancelMessageCallBacks.remove(callback);

  void _fireOnCancelMessageCallBack(CancelMessage message) {
    for (var callback in _onCancelMessageCallBacks) {
      Timer.run(() {
        callback(message);
      });
    }
  }

  void addOnRequestTimeoutCallBack(void Function(int pieceIndex, int subPieceIndex) callback) => _onRequestTimeoutCallBacks.add(callback);

  bool removeOnRequestTimeoutCallBack(void Function(int pieceIndex, int subPieceIndex) callback) => _onRequestTimeoutCallBacks.remove(callback);

  void _fireOnRequestTimeoutCallBack(int pieceIndex, int subPieceIndex) {
    for (var callback in _onRequestTimeoutCallBacks) {
      Timer.run(() {
        callback(pieceIndex, subPieceIndex);
      });
    }
  }

  void dispose() {
    _onConnectedCallBacks.clear();
    _onConnectFailedCallBacks.clear();
    _onConnectInterruptedCallBacks.clear();
    _onDisconnectedCallBacks.clear();

    _onIllegalMessageCallBacks.clear();
    _onHandshakeMessageCallBacks.clear();
    _onKeepAliveMessageCallBacks.clear();
    _onChokeMessageCallBacks.clear();
    _onUnChokeMessageCallBacks.clear();
    _onInterestedMessageCallBacks.clear();
    _onNotInterestedMessageCallBacks.clear();
    _onComposedHaveMessageCallBacks.clear();
    _onBitFieldMessageCallBacks.clear();
    _onRequestMessageCallBacks.clear();
    _onPieceMessageCallBacks.clear();
    _onCancelMessageCallBacks.clear();

    _onRequestTimeoutCallBacks.clear();
  }
}
