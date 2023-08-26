import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/peer/piece/piece_manager.dart';
import 'package:jtorrent/src/util/log_util.dart';

import '../model/peer.dart';
import 'peer_connection.dart';
import 'file/file_manager.dart';
import 'peer_meesage.dart';

class PeerManager with PeerManagerEventDispatcher {
  PeerManager({required this.infoHash, required PieceManager pieceManager, required FileManager fileManager})
      : _pieceManager = pieceManager,
        _fileManager = fileManager {
    _fileManager.addOnWriteSuccessCallback(_processWriteSubPieceSuccess);
    _fileManager.addOnWriteFailedCallback(_processWriteSubPieceFailed);
    _fileManager.addOnCompleteSuccessCallback(_processCompleteSuccess);
    _fileManager.addOnCompleteFailedCallback(_processCompleteFailed);
    _pieceManager.addOnPieceHashCheckSuccessCallback(_processPieceHashCheckSuccess);
    _pieceManager.addOnPieceHashCheckFailedCallback(_processPieceHashCheckFailed);
    _pieceManager.addOnPieceHashReadFailedCallback(_processPieceHashReadFailed);
    _pieceManager.addOnAllPieceCompletedCallback(_processAllPieceCompleted);
  }

  static const int maxTimeoutTimesPerPeer = 2;

  static const int maxOutgoingConnections = 30;
  static const int maxIncomingConnections = 5;

  final Uint8List infoHash;

  final PieceManager _pieceManager;

  final FileManager _fileManager;

  final Map<Peer, PeerConnection> _peerConnectionMap = {};

  bool _paused = false;

  int? DHTPort;

  void addNewPeer(Peer peer) {
    if (_peerConnectionMap.containsKey(peer)) {
      return;
    }

    PeerConnection connection = _generatePeerConnection(peer);
    _peerConnectionMap[peer] = connection;

    _hookPeerConnection(connection);

    connection.connect();
  }

  void addIncomePeer(Socket socket) {
    Peer peer = Peer(ip: socket.remoteAddress, port: socket.remotePort);

    if (_peerConnectionMap.containsKey(peer)) {
      Log.info('Peer ${peer.ip.address}:${peer.port} already connected');
      socket.close();
      return;
    }

    if (activeInComingConnectionsCount >= maxIncomingConnections) {
      Log.info('Incoming connections reach max: $maxIncomingConnections, ignore ${peer.ip.address}:${peer.port}');
      socket.close();
      return;
    }

    PeerConnection connection = _generatePeerConnection(peer);
    _peerConnectionMap[peer] = connection;
    connection.fromClient = true;

    _hookPeerConnection(connection);

    connection.listen(socket);
  }

  void pause() {
    if (_paused) {
      return;
    }
    _paused = true;
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;

    for (PeerConnection connection in availableConnections) {
      _tryRequestPiece(connection);
    }
  }

  Map<Peer, List<({int pieceIndex, int subPieceIndex})>> get pendingRequests => Map.fromEntries(
      _peerConnectionMap.entries.where((e) => e.value.pendingRequests.isNotEmpty).map((e) => MapEntry(e.key, e.value.pendingRequests.keys.toList())));

  List<PeerConnection> get activeConnections => _peerConnectionMap.values.where((element) => element.connected).toList();

  List<PeerConnection> get availableConnections =>
      activeConnections.where((element) => element.peerHaveSentBitField).where((element) => element.peerChoking == false).toList();

  List<PeerConnection> get noTimeoutConnections => availableConnections.where((element) => element.timeoutTimes < maxTimeoutTimesPerPeer).toList();

  int get activeInComingConnectionsCount => activeConnections.where((element) => element.fromClient).length;

  PeerConnection _generatePeerConnection(Peer peer) {
    /// todo
    return TcpPeerConnection(peer: peer);
  }

  void _hookPeerConnection(PeerConnection connection) {
    connection.addOnConnectedCallBack(() => _processConnected(connection));
    connection.addOnConnectFailedCallBack((error) => _processConnectFailed(connection, error));
    connection.addOnConnectInterruptedCallBack((error) => _processConnectInterrupted(connection, error));
    connection.addOnDisconnectedCallBack(() => _processDisconnected(connection));
    connection.addOnSendMessageFailedCallBack((error) => _processSendMessageFailed(connection, error));

    connection.addOnIllegalMessageCallBack((message) => _processIllegalMessage(connection, message));
    connection.addOnHandshakeMessageCallBack((message) => _processHandshakeMessage(connection, message));
    connection.addOnKeepAliveMessageCallBack((message) => _processKeepAliveMessage(connection, message));
    connection.addOnChokeMessageCallBack((message) => _processChokeMessage(connection, message));
    connection.addOnUnChokeMessageCallBack((message) => _processUnChokeMessage(connection, message));
    connection.addOnInterestedMessageCallBack((message) => _processInterestedMessage(connection, message));
    connection.addOnNotUnInterestedMessageCallBack((message) => _processNotInterestedMessage(connection, message));
    connection.addOnComposedHaveMessageCallBack((message) => _processComposedHaveMessage(connection, message));
    connection.addOnBitFieldMessageCallBack((message) => _processBitfieldMessage(connection, message));
    connection.addOnRequestMessageCallBack((message) => _processRequestMessage(connection, message));
    connection.addOnPieceMessageCallBack((message) => _processPieceMessage(connection, message));
    connection.addOnCancelMessageCallBack((message) => _processCancelMessage(connection, message));
    connection.addOnPortMessageCallBack((message) => _processPortMessage(connection, message));

    connection.addOnRequestTimeoutCallBack((int pieceIndex, int subPieceIndex) => _processRequestTimeout(connection, pieceIndex, subPieceIndex));
  }

  void _unHookPeerConnection(PeerConnection connection) {
    connection.removeOnConnectedCallBack(() => _processConnected(connection));
    connection.removeOnConnectFailedCallBack((error) => _processConnectFailed(connection, error));
    connection.removeOnConnectInterruptedCallBack((error) => _processConnectInterrupted(connection, error));
    connection.removeOnDisconnectedCallBack(() => _processDisconnected(connection));

    connection.removeOnIllegalMessageCallBack((message) => _processIllegalMessage(connection, message));
    connection.removeOnHandshakeMessageCallBack((message) => _processHandshakeMessage(connection, message));
    connection.removeOnKeepAliveMessageCallBack((message) => _processKeepAliveMessage(connection, message));
    connection.removeOnChokeMessageCallBack((message) => _processChokeMessage(connection, message));
    connection.removeOnUnChokeMessageCallBack((message) => _processUnChokeMessage(connection, message));
    connection.removeOnInterestedMessageCallBack((message) => _processInterestedMessage(connection, message));
    connection.removeOnNotUnInterestedMessageCallBack((message) => _processNotInterestedMessage(connection, message));
    connection.removeOnComposedHaveMessageCallBack((message) => _processComposedHaveMessage(connection, message));
    connection.removeOnBitFieldMessageCallBack((message) => _processBitfieldMessage(connection, message));
    connection.removeOnRequestMessageCallBack((message) => _processRequestMessage(connection, message));
    connection.removeOnPieceMessageCallBack((message) => _processPieceMessage(connection, message));
    connection.removeOnCancelMessageCallBack((message) => _processCancelMessage(connection, message));
    connection.removeOnPortMessageCallBack((message) => _processPortMessage(connection, message));

    connection.removeOnRequestTimeoutCallBack((int pieceIndex, int subPieceIndex) => _processRequestTimeout(connection, pieceIndex, subPieceIndex));
  }

  void _processConnected(PeerConnection connection) {
    assert(connection.haveHandshake == false);

    Log.finest('Connected to ${connection.peer.ip.address}:${connection.peer.port}');

    _sendHandshake(connection);
  }

  void _processConnectFailed(PeerConnection connection, dynamic error) {
    Log.finest('Connect to ${connection.peer.ip.address}:${connection.peer.port} failed');

    _unHookPeerConnection(connection);
  }

  void _processConnectInterrupted(PeerConnection connection, dynamic error) {
    Log.fine('Connect to ${connection.peer.ip.address}:${connection.peer.port} interrupted, error: $error');

    _resetConnectionPendingRequest(connection);
    _unHookPeerConnection(connection);
    
    _pieceManager.removePeerPieces(connection.peer);
  }

  void _processDisconnected(PeerConnection connection) {
    Log.fine('Disconnected from ${connection.peer.ip.address}:${connection.peer.port}');

    _resetConnectionPendingRequest(connection);
    _unHookPeerConnection(connection);

    _pieceManager.removePeerPieces(connection.peer);
  }

  void _processSendMessageFailed(PeerConnection connection, error) {
    Log.info('Send message to ${connection.peer.ip.address}:${connection.peer.port} failed', error, StackTrace.current);

    connection.close();
    _resetConnectionPendingRequest(connection);
    _unHookPeerConnection(connection);
  }

  void _processIllegalMessage(PeerConnection connection, IllegalMessage message) {
    Log.warning('Receive illegal message from ${connection.peer.ip.address}:${connection.peer.port} :${message.message}');
    connection.close(illegal: true);
  }

  void _processHandshakeMessage(PeerConnection connection, HandshakeMessage message) {
    Log.finest(
        'Receive handshake message from ${connection.peer.ip.address}:${connection.peer.port}, info hash: ${message.infoHash.toHexString}, supportDHT: ${message.supportDHT}, supportExtension: ${message.supportExtension}');

    if (!ListEquality<int>().equals(message.infoHash, infoHash)) {
      Log.warning(
          'Receive Invalid handshake message from ${connection.peer.ip.address}:${connection.peer.port}, info hash not match:  ${message.infoHash.toHexString} != ${infoHash.toHexString}');
      return connection.close(illegal: true);
    }

    if (connection.peerHaveHandshake) {
      Log.info('${connection.peer.ip.address} handshake again');
      return;
    }

    connection.peerHaveHandshake = true;
    connection.supportDHT = message.supportDHT;
    connection.supportExtension = message.supportExtension;

    if (connection.haveHandshake == false) {
      _sendHandshake(connection);
    }
    connection.sendBitField(_pieceManager.bitField);
    connection.haveSentBitField = true;
  }

  void _processKeepAliveMessage(PeerConnection connection, KeepAliveMessage message) {
    Log.finest('Receive keep alive message from ${connection.peer.ip.address}:${connection.peer.port}');

    connection.lastActiveTime = DateTime.now();
  }

  void _processChokeMessage(PeerConnection connection, ChokeMessage message) {
    Log.fine('Receive choke message from ${connection.peer.ip.address}:${connection.peer.port}');

    connection.peerChoking = true;
  }

  void _processUnChokeMessage(PeerConnection connection, UnChokeMessage message) {
    Log.fine('Receive unchoke message from ${connection.peer.ip.address}:${connection.peer.port}');

    connection.peerChoking = false;
    _tryRequestPiece(connection);
  }

  void _processInterestedMessage(PeerConnection connection, InterestedMessage message) {
    Log.finest('Receive interested message from ${connection.peer.ip.address}:${connection.peer.port}');

    connection.peerInterested = true;
  }

  void _processNotInterestedMessage(PeerConnection connection, NotInterestedMessage message) {
    Log.finest('Receive not interested message from ${connection.peer.ip.address}:${connection.peer.port}');

    connection.peerInterested = false;
  }

  void _processComposedHaveMessage(PeerConnection connection, ComposedHaveMessage message) {
    Log.finest('Receive have message from ${connection.peer.ip.address}:${connection.peer.port}, piece indexes: ${message.pieceIndexes}');

    _pieceManager.initPeerPieces(connection.peer);

    for (int pieceIndex in message.pieceIndexes) {
      if (pieceIndex >= _pieceManager.pieceCount) {
        Log.severe('StackHaveMessage pieceIndex $pieceIndex >= pieces.length ${_pieceManager.pieceCount}');
        continue;
      }
      _pieceManager.updatePeerPiece(connection.peer, pieceIndex, true);
    }

    _tryRequestPiece(connection);
  }

  void _processBitfieldMessage(PeerConnection connection, BitFieldMessage message) {
    Log.fine(
        'Receive bitfield message from ${connection.peer.ip.address}:${connection.peer.port}, composed: ${message.composed}, bitfield: ${message.bitField}');

    _pieceManager.initPeerPieces(connection.peer);

    for (int i = 0; i < message.bitField.length; i++) {
      int byte = message.bitField[i];

      if (byte == 0) {
        continue;
      }

      if (byte > (2 << 8 - 1)) {
        Log.warning('BitFieldMessage byte $byte > ${(2 << 8 - 1)}');
      }

      for (int j = 0; j < 8; j++) {
        if ((byte & (1 << (7 - j))) != 0) {
          int pieceIndex = i * 8 + j;
          if (pieceIndex < _pieceManager.pieceCount) {
            _pieceManager.updatePeerPiece(connection.peer, pieceIndex, true);
          }
        }
      }
    }

    connection.peerHaveSentBitField = true;

    if (connection.supportDHT && DHTPort != null) {
      connection.sendPort(DHTPort!);
    }

    _tryRequestPiece(connection);
  }

  void _processRequestMessage(PeerConnection connection, RequestMessage message) {
    Log.info(
        'Receive request message from ${connection.peer.ip.address}:${connection.peer.port}, index: ${message.index}, begin: ${message.begin}, length: ${message.length}');
  }

  void _processPieceMessage(PeerConnection connection, PieceMessage message) {
    Log.finest(
        'Receive piece message from ${connection.peer.ip.address}:${connection.peer.port}, index: ${message.index}, subIndex: ${message.begin ~/ CommonConstants.subPieceLength}, length: ${message.block.length}');

    if (message.index >= _pieceManager.pieceCount) {
      Log.severe('PieceMessage pieceIndex ${message.index} >= pieces.length ${_pieceManager.pieceCount}');
      return connection.close(illegal: true);
    }

    if (message.index < _pieceManager.pieceCount - 1 && message.block.length != CommonConstants.subPieceLength) {
      Log.warning('block length ${message.block.length} != sub piece length ${CommonConstants.subPieceLength}');
      return connection.close(illegal: true);
    }

    if (message.begin % CommonConstants.subPieceLength != 0) {
      Log.warning('begin ${message.begin} is not a multiple of sub piece length ${CommonConstants.subPieceLength}');
      return connection.close(illegal: true);
    }

    int subPieceIndex = message.begin ~/ CommonConstants.subPieceLength;

    if (subPieceIndex >= _pieceManager.subPieceCount) {
      Log.warning('sub piece index $subPieceIndex >= sub piece count ${_pieceManager.subPieceCount}');
      return connection.close(illegal: true);
    }

    connection.completePendingRequest(message.index, subPieceIndex);
    connection.resetTimeoutTimes();

    if (_pieceManager.pieceDownloaded(message.index)) {
      Log.info('${infoHash.toHexString}\'s piece ${message.index} already downloaded');
      return _tryRequestPiece(connection);
    }

    if (_pieceManager.subPieceDownloaded(message.index, subPieceIndex)) {
      Log.info('${infoHash.toHexString}\'s sub piece $subPieceIndex of piece ${message.index} already downloaded');
      return _tryRequestPiece(connection);
    }

    _fileManager.writeSubPiece(message.index, message.begin, message.block);

    Timer.run(() {
      _tryRequestPiece(connection);
    });
  }

  void _processCancelMessage(PeerConnection connection, CancelMessage message) {
    Log.info(
        'Receive cancel message from ${connection.peer.ip.address}:${connection.peer.port}, index: ${message.index}, begin: ${message.begin}, length: ${message.length}');
  }

  void _processPortMessage(PeerConnection connection, PortMessage message) {
    Log.finest('Receive port message from ${connection.peer.ip.address}:${connection.peer.port}, port: ${message.port}');
    _fireOnDHTNodeFoundCallbacks(connection.peer.ip, message.port);
  }

  void _processRequestTimeout(PeerConnection connection, int pieceIndex, int subPieceIndex) {
    Log.finest('Request ${connection.peer.ip.address}:${connection.peer.port} timeout, pieceIndex: $pieceIndex, subPieceIndex: $subPieceIndex');

    _pieceManager.resetLocalSubPiece(pieceIndex, subPieceIndex);

    if (connection.timeoutTimes < maxTimeoutTimesPerPeer) {
      connection.timeoutTimes++;
      _tryRequestPiece(connection);
    } else {
      for (PeerConnection c in noTimeoutConnections) {
        _tryRequestPiece(c);
      }
    }
  }

  Future<void> _processWriteSubPieceSuccess(int pieceIndex, int begin, Uint8List block) async {
    Log.finest('Write sub piece success, pieceIndex: $pieceIndex, subPieceIndex: ${begin ~/ CommonConstants.subPieceLength}');

    _pieceManager.completeSubPiece(pieceIndex, begin ~/ CommonConstants.subPieceLength, () => _fileManager.readPiece(pieceIndex));

    for (PeerConnection connection in activeConnections) {
      bool removed = connection.cancelPendingRequest(pieceIndex, begin ~/ CommonConstants.subPieceLength);
      if (removed) {
        Log.finest(
            'Cancel pending request because downloaded from other peer, pieceIndex: $pieceIndex, subPieceIndex: ${begin ~/ CommonConstants.subPieceLength}');
        _tryRequestPiece(connection);
      }
    }
  }

  void _processWriteSubPieceFailed(int pieceIndex, int begin, Uint8List block, error) {
    Log.severe(
        'Write sub piece failed, pieceIndex: $pieceIndex, subPieceIndex: ${begin ~/ CommonConstants.subPieceLength}', error, StackTrace.current);

    _pieceManager.resetLocalSubPiece(pieceIndex, begin ~/ CommonConstants.subPieceLength);
  }

  void _processPieceHashCheckSuccess(int pieceIndex) {
    Log.fine('${infoHash.toHexString}\'s piece $pieceIndex hash check success');

    // for (PeerConnection connection in activeConnections) {
    //   connection.sendHaveMessage(pieceIndex);
    // }

    _fireOnPieceCompletedCallbacks(_pieceManager.bitField);
  }

  void _processPieceHashCheckFailed(int pieceIndex) {
    Log.severe('${infoHash.toHexString}\'s piece $pieceIndex hash check failed, reset');

    _pieceManager.resetLocalPiece(pieceIndex);
  }

  void _processPieceHashReadFailed(int pieceIndex, error) {
    Log.severe('${infoHash.toHexString}\'s piece $pieceIndex hash read failed', error, StackTrace.current);

    _pieceManager.resetLocalPiece(pieceIndex);
  }

  void _processAllPieceCompleted() {
    Log.info('All pieces of ${infoHash.toHexString} completed');

    for (PeerConnection connection in activeConnections) {
      connection.clearPendingRequests();
    }

    _fileManager.complete();
  }

  void _processCompleteSuccess() {
    Log.info('Complete ${infoHash.toHexString} success');

    _fireOnCompletedCallbacks();
  }

  void _processCompleteFailed(dynamic error) {
    Log.severe('Complete ${infoHash.toHexString} failed', error, StackTrace.current);

    /// todo
  }

  void _sendHandshake(PeerConnection connection) {
    connection.sendHandShake(infoHash, DHTPort != null, false);
    connection.haveHandshake = true;
  }

  void _tryRequestPiece(PeerConnection connection) {
    if (_pieceManager.downloaded) {
      Log.info('Ignore piece request because all pieces downloaded: ${infoHash.toHexString}');
      return;
    }

    if (connection.connected == false) {
      Log.info(
          'Ignore piece request because connection is not connected: ${infoHash.toHexString}, ${connection.peer.ip.address}:${connection.peer.port}');
      return;
    }

    if (connection.peerHaveSentBitField == false) {
      Log.fine(
          'Ignore piece request because peer ${connection.peer.ip.address}:${connection.peer.port} have not sent bit field: ${infoHash.toHexString}');
      return;
    }

    if (_paused) {
      Log.finest('Ignore piece request because has paused: ${infoHash.toHexString}');
      return;
    }

    if (connection.amChoking) {
      connection.sendUnChoke();
      connection.amChoking = false;
    }

    if (connection.amInterested == false) {
      connection.sendInterested();
      connection.amInterested = true;
    }

    if (connection.peerChoking) {
      return;
    }

    ({int pieceIndex, int subPieceIndex, int length})? subPiece = _pieceManager.selectPieceIndexToDownload(connection.peer);
    if (subPiece == null) {
      Log.finest(
          'Ignore piece request because no piece to request to ${connection.peer.ip.address}:${connection.peer.port} of ${infoHash.toHexString}');
      return;
    }

    if (connection.sendRequest(subPiece.pieceIndex, subPiece.subPieceIndex, subPiece.length)) {
      _pieceManager.updateLocalSubPiece(subPiece.pieceIndex, subPiece.subPieceIndex, PieceStatus.downloading);

      Timer.run(() {
        _tryRequestPiece(connection);
      });
    }
  }

  void _resetConnectionPendingRequest(PeerConnection connection) {
    List<({int pieceIndex, int subPieceIndex})> requests = connection.clearPendingRequests();
    for (({int pieceIndex, int subPieceIndex}) request in requests) {
      _pieceManager.resetLocalSubPiece(request.pieceIndex, request.subPieceIndex);
    }
  }
}

mixin PeerManagerEventDispatcher {
  final Set<void Function(InternetAddress ip, int port)> _onDHTNodeFoundCallbacks = {};

  final Set<void Function(Uint8List)> _onPieceCompletedCallbacks = {};
  final Set<void Function()> _onCompletedCallbacks = {};

  void addOnDHTNodeFoundCallback(void Function(InternetAddress ip, int port) callBack) {
    _onDHTNodeFoundCallbacks.add(callBack);
  }

  bool removeOnDHTNodeFoundCallback(void Function(InternetAddress ip, int port) callBack) {
    return _onDHTNodeFoundCallbacks.remove(callBack);
  }

  void _fireOnDHTNodeFoundCallbacks(InternetAddress ip, int port) {
    for (var callBack in _onDHTNodeFoundCallbacks) {
      Timer.run(() {
        callBack(ip, port);
      });
    }
  }

  void addOnPieceCompletedCallback(void Function(Uint8List) callBack) {
    _onPieceCompletedCallbacks.add(callBack);
  }

  bool removeOnPieceCompletedCallback(void Function(Uint8List) callBack) {
    return _onPieceCompletedCallbacks.remove(callBack);
  }

  void _fireOnPieceCompletedCallbacks(Uint8List piece) {
    for (void Function(Uint8List) callBack in _onPieceCompletedCallbacks) {
      Timer.run(() {
        callBack(piece);
      });
    }
  }

  void addOnCompletedCallback(void Function() callBack) {
    _onCompletedCallbacks.add(callBack);
  }

  bool removeOnCompletedCallback(void Function() callBack) {
    return _onCompletedCallbacks.remove(callBack);
  }

  void _fireOnCompletedCallbacks() {
    for (void Function() callBack in _onCompletedCallbacks) {
      Timer.run(() {
        callBack();
      });
    }
  }
}
