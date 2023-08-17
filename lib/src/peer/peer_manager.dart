import 'dart:async';
import 'dart:math';
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

class PeerManager {
  int maxRequestCountPerPeer = 8;

  int get uploadedBytes => _uploadedBytes;

  PeerManager({required Uint8List infoHash, required PieceManager pieceManager, required FileManager fileManager})
      : _infoHash = infoHash,
        _pieceManager = pieceManager,
        _fileManager = fileManager;

  final Uint8List _infoHash;

  final PieceManager _pieceManager;

  final FileManager _fileManager;

  final Map<Peer, PeerConnection> _peerConnectionMap = {};

  int _uploadedBytes = 0;

  void addNewPeer(Peer peer) {
    if (_peerConnectionMap.containsKey(peer)) {
      return;
    }

    PeerConnection connection = _generatePeerConnection(peer);
    _peerConnectionMap[peer] = connection;

    _hookPeerConnection(connection);

    connection.connect();
  }

  void pause() {}

  void resume() {}

  PeerConnection _generatePeerConnection(Peer peer) {
    /// todo
    return TcpPeerConnection(peer: peer);
  }

  void _hookPeerConnection(PeerConnection connection) {
    connection.addOnConnectedCallBack(() => _processConnected(connection));
    connection.addOnConnectFailedCallBack((error) => _processConnectFailed(connection, error));
    connection.addOnConnectInterruptedCallBack((error) => _processConnectInterrupted(connection, error));
    connection.addOnDisconnectedCallBack(() => _processDisconnected(connection));

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
  }

  void _processConnected(PeerConnection connection) {
    assert(connection.haveHandshake == false);

    Log.finest('Connected to ${connection.peer.ip.address}:${connection.peer.port}');

    _sendHandshake(connection);
  }

  void _processConnectFailed(PeerConnection connection, dynamic error) {
    Log.finest('Connect to ${connection.peer.ip.address}:${connection.peer.port} failed, error: $error');

    connection.close();
  }

  void _processConnectInterrupted(PeerConnection connection, dynamic error) {
    Log.finest('Connect to ${connection.peer.ip.address}:${connection.peer.port} interrupted, error: $error');

    connection.close();
  }

  void _processDisconnected(PeerConnection connection) {
    connection.close();
  }

  void _processIllegalMessage(PeerConnection connection, IllegalMessage message) {
    Log.warning('Receive illegal message from ${connection.peer.ip.address}:${connection.peer.port} :${message.message}');
    connection.close(illegal: true);
  }

  void _processHandshakeMessage(PeerConnection connection, HandshakeMessage message) {
    Log.finest('Receive handshake message from ${connection.peer.ip.address}:${connection.peer.port}, info hash: ${message.infoHash.toHexString}');

    if (connection.peerHaveHandshake) {
      Log.info('${connection.peer.ip.address} handshake again');
    }
    connection.peerHaveHandshake = true;

    if (!ListEquality<int>().equals(message.infoHash, _infoHash)) {
      Log.warning(
          'Receive Invalid handshake message from ${connection.peer.ip.address}:${connection.peer.port}, info hash not match:  ${message.infoHash.toHexString} != ${_infoHash.toHexString}');
      return connection.close(illegal: true);
    }

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
    Log.finest('Receive choke message from ${connection.peer.ip.address}:${connection.peer.port}');

    connection.peerChoking = true;
  }

  void _processUnChokeMessage(PeerConnection connection, UnChokeMessage message) {
    Log.finest('Receive unchoke message from ${connection.peer.ip.address}:${connection.peer.port}');

    connection.peerChoking = false;
    _managePieceRequest(connection);
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

    for (int pieceIndex in message.pieceIndexes) {
      if (pieceIndex >= _pieceManager.pieceCount) {
        Log.severe('StackHaveMessage pieceIndex $pieceIndex >= pieces.length ${_pieceManager.pieceCount}');
        continue;
      }
      _pieceManager.updatePeerPiece(connection.peer, pieceIndex, true);
    }
  }

  void _processBitfieldMessage(PeerConnection connection, BitFieldMessage message) {
    Log.finest(
        'Receive bitfield message from ${connection.peer.ip.address}:${connection.peer.port}, composed: ${message.composed}, bitfield: ${message.bitField}');
    
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

    _managePieceRequest(connection);
  }

  void _processRequestMessage(PeerConnection connection, RequestMessage message) {
    Log.finest(
        'Receive request message from ${connection.peer.ip.address}:${connection.peer.port}, index: ${message.index}, begin: ${message.begin}, length: ${message.length}');
  }

  void _processPieceMessage(PeerConnection connection, PieceMessage message) {
    Log.finest(
        'Receive piece message from ${connection.peer.ip.address}:${connection.peer.port}, index: ${message.index}, begin: ${message.begin}, length: ${message.block.length}');

    if (message.index >= _pieceManager.pieceCount) {
      Log.severe('PieceMessage pieceIndex ${message.index} >= pieces.length ${_pieceManager.pieceCount}');
      return connection.close(illegal: true);
    }

    if (message.block.length != CommonConstants.subPieceLength) {
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

    if (_pieceManager.pieceCompleted(message.index)) {
      Log.fine('Piece ${message.index} already downloaded of ${_infoHash.toHexString}');
      return;
    }

    if (_pieceManager.subPieceCompleted(message.index, subPieceIndex)) {
      Log.fine('Sub piece $subPieceIndex of piece ${message.index} already downloaded of ${_infoHash.toHexString}');
      return;
    }

    _fileManager.write(message.index * _pieceManager.pieceLength + message.begin, message.block).then((bool success) {
      if (success) {
        _pieceManager.updateLocalSubPiece(message.index, subPieceIndex, PieceStatus.downloaded);
        _checkAllSubPiecesDownloaded(connection, message.index);
      } else {
        _managePieceRequest(connection);
      }
    });
  }

  Future<void> _checkAllSubPiecesDownloaded(PeerConnection connection, int pieceIndex) async {
    if (!_pieceManager.pieceCompleted(pieceIndex)) {
      return;
    }

    Log.fine('Piece $pieceIndex of ${_infoHash.toHexString} downloaded, start hash check');

    Uint8List bytes;
    try {
      bytes = await _fileManager.read(pieceIndex * _pieceManager.pieceLength, _pieceManager.pieceLength);
    } on Exception catch (e) {
      _pieceManager.resetLocalPieces(pieceIndex);
      return _managePieceRequest(connection);
    }

    bool success = _pieceManager.checkHash(pieceIndex, sha1.convert(bytes).bytes);

    if (success) {
      Log.fine('${_infoHash.toHexString}\'s piece $pieceIndex hash check success');
      _checkAllPiecesDownloaded();

      /// todo: send have message to all peers
    } else {
      Log.severe('${_infoHash.toHexString}\'s piece $pieceIndex hash check failed, delete piece file');
      _pieceManager.resetLocalPieces(pieceIndex);
      _managePieceRequest(connection);
    }
  }

  void _checkAllPiecesDownloaded() {
    if (!_pieceManager.completed) {
      return;
    }

    Log.fine('All pieces of ${_infoHash.toHexString} downloaded, start merge pieces');

    /// todo
  }

  void _processCancelMessage(PeerConnection connection, CancelMessage message) {}

  void _sendHandshake(PeerConnection connection) {
    connection.sendHandShake(_infoHash);
    connection.haveHandshake = true;
  }

  void _managePieceRequest(PeerConnection connection) {
    if (_pieceManager.completed) {
      Log.info('Ignore piece request because all pieces downloaded: ${_infoHash.toHexString}');
      return;
    }

    int? targetPieceIndex = _pieceManager.selectPieceIndexToDownload(connection.peer);
    if (targetPieceIndex == null) {
      Log.fine(
          'Ignore piece request because no piece to request to ${connection.peer.ip.address}:${connection.peer.port} of ${_infoHash.toHexString}');
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

    int? targetSubPieceIndex = _pieceManager.selectSubPieceIndexToDownload(targetPieceIndex);
    if (targetSubPieceIndex == null) {
      Log.fine(
          'Ignore piece request because no sub piece to request to ${connection.peer.ip.address}:${connection.peer.port} of ${_infoHash.toHexString}');
      return;
    }

    _pieceManager.updateLocalSubPiece(targetPieceIndex, targetSubPieceIndex, PieceStatus.downloading);

    connection.sendRequest(targetPieceIndex, targetSubPieceIndex);

    Timer.run(() {
      _managePieceRequest(connection);
    });
  }
}
