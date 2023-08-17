import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/peer/piece/piece_provider.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:path/path.dart';

import '../model/torrent_exchange_info.dart';
import '../model/peer.dart';
import 'peer_connection.dart';
import 'file/file_manager.dart';
import 'peer_meesage.dart';

class PeerManager {
  PeerManager({required Uint8List infoHash, required PieceProvider pieceProvider, required FileManager fileManager})
      : _infoHash = infoHash,
        _pieceProvider = pieceProvider,
        _fileManager = fileManager;

  final Uint8List _infoHash;

  final PieceProvider _pieceProvider;

  final FileManager _fileManager;

  final Map<Peer, PeerConnection> _peerConnectionMap = {};

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
  
  void resume(){}

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

  void _processConnected(PeerConnection connection) {}

  void _processConnectFailed(PeerConnection connection, dynamic error) {}

  void _processConnectInterrupted(PeerConnection connection, dynamic error) {}

  void _processDisconnected(PeerConnection connection) {}

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

    if (_infoHash != message.infoHash) {
      Log.warning(
          'Receive Invalid handshake message from ${connection.peer.ip.address}:${connection.peer.port}, info hash not match:  ${message.infoHash.toHexString} != ${_infoHash.toHexString}');
      return connection.close(illegal: true);
    }

    if (connection.haveHandshake == false) {
      _sendHandshake(connection);
    }

    connection.sendBitField(_pieceProvider.pieces);
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
      if (pieceIndex >= connection.peerPieces.length) {
        Log.severe('StackHaveMessage pieceIndex $pieceIndex >= pieces.length ${connection.peerPieces.length}');
        continue;
      }
      connection.peerPieces[pieceIndex] = true;
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
          if (pieceIndex < connection.peerPieces.length) {
            connection.peerPieces[pieceIndex] = true;
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

    if (message.index >= connection.peerPieces.length) {
      Log.severe('PieceMessage pieceIndex ${message.index} >= pieces.length ${connection.peerPieces.length}');
      return connection.close(illegal: true);
    }

    TorrentExchangeInfo? torrentExchangeInfo = _torrentExchangeMap[connection.infoHash];
    if (torrentExchangeInfo == null) {
      Log.warning('TorrentExchangeInfo not found for ${connection.infoHash.toHexString} when save piece: ${pieceMessage.index}}');
      return connection.close();
    }

    if (torrentExchangeInfo.pieces[message.index] == PieceStatus.downloaded) {
      Log.info('${connection.infoHash.toHexString}\'s Piece ${message.index} already downloaded');
      return;
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

    if (subPieceIndex >= torrentExchangeInfo.subPieces[message.index].length) {
      Log.warning('sub piece index $subPieceIndex >= sub piece count ${torrentExchangeInfo.subPieces[message.index].length}');
      return connection.close(illegal: true);
    }

    if (torrentExchangeInfo.subPieces[message.index][subPieceIndex] == true) {
      Log.info('${connection.infoHash.toHexString}\'s Piece ${message.index} sub piece $subPieceIndex already downloaded');
      return;
    }

    String savePath = _computePiecePath(torrentExchangeInfo.name, message.index);

    _saveSubPiece(savePath, message.begin, message.block).then((_) {
      Log.fine('save ${connection.infoHash.toHexString}\'s piece ${message.index} subPiece $subPieceIndex success');

      torrentExchangeInfo.subPieces[message.index][subPieceIndex] = true;
      _checkAllSubPiecesDownloaded(torrentExchangeInfo, message.index, savePath);
    }).onError((error, stackTrace) {
      Log.severe('save ${connection.infoHash.toHexString}\'s piece ${message.index} subPiece $subPieceIndex failed: $error');

      /// todo: send request message again
    });
  }

  Future<void> _saveSubPiece(String savePath, int position, Uint8List block) async {
    File pieceFile = File(savePath);
    RandomAccessFile f = await pieceFile.open(mode: FileMode.writeOnlyAppend);

    try {
      await f.setPosition(position);
      await f.writeFrom(block);
    } on Exception catch (e) {
      await f.close();
      rethrow;
    }
  }

  Future<void> _checkAllSubPiecesDownloaded(TorrentExchangeInfo torrentExchangeInfo, int pieceIndex, String savePath) async {
    if (torrentExchangeInfo.subPieces[pieceIndex].any((subPiece) => subPiece == false)) {
      return;
    }

    Log.fine('${torrentExchangeInfo.infoHash.toHexString}\'s piece $pieceIndex download success, try check hash');

    File pieceFile = File(savePath);
    RandomAccessFile f = await pieceFile.open(mode: FileMode.read);

    try {
      List<int> bytes = Uint8List(torrentExchangeInfo.pieceLength);
      await f.readInto(bytes);
      List<int> hash = sha1.convert(bytes).bytes;

      if (ListEquality<int>().equals(hash, torrentExchangeInfo.pieceSha1s[pieceIndex])) {
        Log.fine('${torrentExchangeInfo.infoHash.toHexString}\'s piece $pieceIndex hash check success');

        torrentExchangeInfo.pieces[pieceIndex] = PieceStatus.downloaded;
        await f.flush();

        _checkAllPiecesDownloaded(torrentExchangeInfo);

        /// todo: send have message to all peers
      } else {
        Log.severe('${torrentExchangeInfo.infoHash.toHexString}\'s piece $pieceIndex hash check failed');

        torrentExchangeInfo.subPieces[pieceIndex].fillRange(0, torrentExchangeInfo.subPieces[pieceIndex].length, false);
        await f.truncate(0);
      }
    } on Exception catch (e) {
      await f.close();
    }
  }

  void _checkAllPiecesDownloaded(TorrentExchangeInfo torrentExchangeInfo) {
    if (!torrentExchangeInfo.allPiecesDownloaded) {
      return;
    }

    Log.fine('${torrentExchangeInfo.infoHash.toHexString} download success');
  }

  void _processCancelMessage(PeerConnection connection, CancelMessage message) {}

  void addNewTorrentTask(Torrent torrent, Set<Peer> peers) {
    TorrentExchangeInfo? exchangeStatusInfo = _torrentExchangeMap[torrent.infoHash];

    if (exchangeStatusInfo == null) {
      exchangeStatusInfo = TorrentExchangeInfo.fromTorrent(torrent: torrent, peers: peers);
      _torrentExchangeMap[torrent.infoHash] = exchangeStatusInfo;
    } else {
      exchangeStatusInfo.allKnownPeers.addAll(peers);
    }

    for (Peer peer in exchangeStatusInfo.allKnownPeers) {
      /// todo ipv6 peers
      Future<PeerConnection> connectionFuture = _openConnection(exchangeStatusInfo, peer);
      Future<void> handshakeFuture = connectionFuture.then((connection) => _sendHandshake(connection));
      handshakeFuture.onError((error, stackTrace) => Log.finest('Connection error: ${peer.ip.address}:${peer.port}'));
    }
  }

  Future<PeerConnection> _openConnection(Peer peer) async {
    PeerConnection? connection = torrentExchangeInfo.peerConnectionMap[peer];
    if (connection == null) {
      connection = _generatePeerConnection(peer);
      torrentExchangeInfo.peerConnectionMap[peer] = connection;
    }

    if (connection.connecting || connection.connected) {
      return connection;
    }

    await connection.connect();
    connection.listen((PeerMessage data) => _onPeerMessage(connection!, data));

    return connection;
  }

  PeerConnection _generatePeerConnection(Peer peer) {
    /// todo
    return TcpPeerConnection(peer: peer);
  }

  void _sendHandshake(PeerConnection connection) {
    connection.sendHandShake();
    connection.haveHandshake = true;
  }

  void _managePieceRequest(PeerConnection connection) {
    if (connection.torrentExchangeInfo.allPiecesDownloaded) {
      Log.info('Ignore request because all pieces downloaded: ${connection.infoHash}');
      return;
    }

    List<int> targetPieceIndexes = _computePieceIndexesToDownload(connection);
    if (targetPieceIndexes.isEmpty) {
      Log.fine('Ignore request because no piece to request: ${connection.infoHash.toHexString}');
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

    /// compute again in case of update during previous operation
    targetPieceIndexes = _computePieceIndexesToDownload(connection);
    if (targetPieceIndexes.isEmpty) {
      Log.fine('Ignore request because no piece to request: ${connection.infoHash}');
      return;
    }

    List<int> selectedPieceIndexes = _selectPieceIndexes(connection.torrentExchangeInfo, targetPieceIndexes);

    for (int pieceIndex in selectedPieceIndexes) {
      connection.torrentExchangeInfo.pieces[pieceIndex] = PieceStatus.downloading;

      File pieceFile = File(_computePiecePath(connection.torrentExchangeInfo.name, pieceIndex));
      pieceFile.createSync(recursive: true, exclusive: false);

      for (int subPieceIndex = 0; subPieceIndex < connection.torrentExchangeInfo.subPieces[subPieceIndex].length; subPieceIndex++) {
        if (connection.torrentExchangeInfo.subPieces[pieceIndex][subPieceIndex] == false) {
          connection.sendRequest(pieceIndex, subPieceIndex);
        }
      }
    }
  }

  List<int> _computePieceIndexesToDownload(PeerConnection connection) {
    List<int> targetPieceIndexes = [];
    for (int i = 0; i < connection.peerPieces.length; i++) {
      if (connection.peerPieces[i] != PieceStatus.downloaded) {
        continue;
      }

      if (connection.torrentExchangeInfo.pieces[i] != PieceStatus.notDownloaded) {
        continue;
      }

      targetPieceIndexes.add(i);
    }
    return targetPieceIndexes;
  }

  List<int> _selectPieceIndexes(TorrentExchangeInfo torrentExchangeInfo, List<int> targetPieceIndexes) {
    /// todo
    return targetPieceIndexes.sublist(0, 1);
  }

  String _computePiecePath(String name, int pieceIndex) {
    return join(_downloadPath, '$name${CommonConstants.tempDirectorySuffix}', 'pieces', '$pieceIndex');
  }

  void _onPeerMessage(PeerConnection connection, PeerMessage message) {
    assert(_torrentExchangeMap[connection.infoHash] != null);
    assert(_torrentExchangeMap[connection.infoHash]!.peerConnectionMap[connection.peer] == connection);

    for (PeerMessageHandler handler in _messageHandlers) {
      if (handler.support(message)) {
        return handler.handle(connection, message);
      }
    }
  }
}
