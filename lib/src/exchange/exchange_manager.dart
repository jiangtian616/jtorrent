import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:path/path.dart';

import '../model/torrent_exchange_info.dart';
import '../model/peer.dart';
import 'connection/peer_connection.dart';
import 'message/peer_meesage.dart';

class ExchangeManager {
  final String _downloadPath;

  ExchangeManager({required String downloadPath, Map<Uint8List, TorrentExchangeInfo>? initData})
      : _downloadPath = downloadPath,
        _torrentExchangeMap = initData ?? {};

  final Map<Uint8List, TorrentExchangeInfo> _torrentExchangeMap;

  late final List<PeerMessageHandler> _messageHandlers = [
    IllegalPeerMessageHandler(),
    HandshakePeerMessageHandler(exchangeManager: this),
    KeepAlivePeerMessageHandler(),
    ChokePeerMessageHandler(),
    UnChokePeerMessageHandler(exchangeManager: this),
    InterestedPeerMessageHandler(),
    NotInterestedPeerMessageHandler(),
    ComposedHaveMessageHandler(),
    BitFieldPeerMessageHandler(exchangeManager: this),
    RequestPeerMessageHandler(exchangeManager: this),
    PiecePeerMessageHandler(exchangeManager: this),
  ];

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

  Future<PeerConnection> _openConnection(TorrentExchangeInfo torrentExchangeInfo, Peer peer) async {
    PeerConnection? connection = torrentExchangeInfo.peerConnectionMap[peer];
    if (connection == null) {
      connection = _generatePeerConnection(torrentExchangeInfo, peer);
      torrentExchangeInfo.peerConnectionMap[peer] = connection;
    }

    if (connection.connecting || connection.connected) {
      return connection;
    }

    await connection.connect();
    connection.listen((PeerMessage data) => _onPeerMessage(connection!, data));

    return connection;
  }

  PeerConnection _generatePeerConnection(TorrentExchangeInfo torrentExchangeInfo, Peer peer) {
    /// todo
    return TcpPeerConnection(peer: peer, torrentExchangeInfo: torrentExchangeInfo);
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

abstract interface class PeerMessageHandler {
  bool support(PeerMessage peerMessage);

  void handle(PeerConnection connection, PeerMessage peerMessage);
}

class IllegalPeerMessageHandler implements PeerMessageHandler {
  const IllegalPeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is IllegalMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.closeByIllegal();
  }
}

class HandshakePeerMessageHandler implements PeerMessageHandler {
  final ExchangeManager _exchangeManager;

  const HandshakePeerMessageHandler({required ExchangeManager exchangeManager}) : _exchangeManager = exchangeManager;

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is HandshakeMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    if (connection.peerHaveHandshake) {
      Log.info('${connection.peer.ip.address} handshake again');
    }
    connection.peerHaveHandshake = true;

    TorrentExchangeInfo? torrentExchangeInfo = _exchangeManager._torrentExchangeMap[connection.infoHash];
    if (torrentExchangeInfo == null) {
      Log.warning('Ignore handshake and close connection because no torrent: ${connection.infoHash}');
      connection.closeByIllegal();
      return;
    }

    if (connection.haveHandshake == false) {
      _exchangeManager._sendHandshake(connection);
    }

    connection.sendBitField(torrentExchangeInfo.pieces);
    connection.sentBitField = true;
  }
}

class KeepAlivePeerMessageHandler implements PeerMessageHandler {
  const KeepAlivePeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is KeepAliveMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.lastActiveTime = DateTime.now();
  }
}

class ChokePeerMessageHandler implements PeerMessageHandler {
  const ChokePeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is ChokeMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.peerChoking = true;
  }
}

class UnChokePeerMessageHandler implements PeerMessageHandler {
  final ExchangeManager _exchangeManager;

  const UnChokePeerMessageHandler({required ExchangeManager exchangeManager}) : _exchangeManager = exchangeManager;

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is UnChokeMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    Log.finest('Receive ${connection.peer.ip.address}:${connection.peer.port} $peerMessage');

    connection.peerChoking = false;
    _exchangeManager._managePieceRequest(connection);
  }
}

class InterestedPeerMessageHandler implements PeerMessageHandler {
  const InterestedPeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is InterestedMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.peerInterested = true;
  }
}

class NotInterestedPeerMessageHandler implements PeerMessageHandler {
  const NotInterestedPeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is NotInterestedMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.peerInterested = false;
  }
}

class ComposedHaveMessageHandler implements PeerMessageHandler {
  const ComposedHaveMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is ComposedHaveMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    for (int pieceIndex in (peerMessage as ComposedHaveMessage).pieceIndexes) {
      if (pieceIndex >= connection.peerPieces.length) {
        Log.severe('StackHaveMessage pieceIndex $pieceIndex >= pieces.length ${connection.peerPieces.length}');
        continue;
      }
      connection.peerPieces[pieceIndex] = PieceStatus.downloaded;
    }
  }
}

class BitFieldPeerMessageHandler implements PeerMessageHandler {
  final ExchangeManager _exchangeManager;

  const BitFieldPeerMessageHandler({required ExchangeManager exchangeManager}) : _exchangeManager = exchangeManager;

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is BitFieldMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    BitFieldMessage bitFieldMessage = peerMessage as BitFieldMessage;
    for (int i = 0; i < bitFieldMessage.bitField.length; i++) {
      int byte = bitFieldMessage.bitField[i];

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
            connection.peerPieces[pieceIndex] = PieceStatus.downloaded;
          }
        }
      }
    }

    _exchangeManager._managePieceRequest(connection);
  }
}

class RequestPeerMessageHandler implements PeerMessageHandler {
  final ExchangeManager _exchangeManager;

  const RequestPeerMessageHandler({required ExchangeManager exchangeManager}) : _exchangeManager = exchangeManager;

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is RequestMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    Log.fine('Receive ${connection.peer.ip.address}:${connection.peer.port} $peerMessage');
  }
}

class PiecePeerMessageHandler implements PeerMessageHandler {
  final ExchangeManager _exchangeManager;

  const PiecePeerMessageHandler({required ExchangeManager exchangeManager}) : _exchangeManager = exchangeManager;

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is PieceMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    Log.finest('Receive ${connection.peer.ip.address}:${connection.peer.port} $peerMessage');
    PieceMessage pieceMessage = peerMessage as PieceMessage;

    if (pieceMessage.index >= connection.peerPieces.length) {
      Log.severe('PieceMessage pieceIndex ${pieceMessage.index} >= pieces.length ${connection.peerPieces.length}');
      return connection.closeByIllegal();
    }

    TorrentExchangeInfo? torrentExchangeInfo = _exchangeManager._torrentExchangeMap[connection.infoHash];
    if (torrentExchangeInfo == null) {
      Log.warning('TorrentExchangeInfo not found for ${connection.infoHash.toHexString} when save piece: ${pieceMessage.index}}');
      return connection.close();
    }

    if (torrentExchangeInfo.pieces[pieceMessage.index] == PieceStatus.downloaded) {
      Log.info('${connection.infoHash.toHexString}\'s Piece ${pieceMessage.index} already downloaded');
      return;
    }

    if (pieceMessage.block.length != CommonConstants.subPieceLength) {
      Log.warning('block length ${pieceMessage.block.length} != sub piece length ${CommonConstants.subPieceLength}');
      return connection.closeByIllegal();
    }

    if (pieceMessage.begin % CommonConstants.subPieceLength != 0) {
      Log.warning('begin ${pieceMessage.begin} is not a multiple of sub piece length ${CommonConstants.subPieceLength}');
      return connection.closeByIllegal();
    }

    int subPieceIndex = pieceMessage.begin ~/ CommonConstants.subPieceLength;

    if (subPieceIndex >= torrentExchangeInfo.subPieces[pieceMessage.index].length) {
      Log.warning('sub piece index $subPieceIndex >= sub piece count ${torrentExchangeInfo.subPieces[pieceMessage.index].length}');
      return connection.closeByIllegal();
    }

    if (torrentExchangeInfo.subPieces[pieceMessage.index][subPieceIndex] == true) {
      Log.info('${connection.infoHash.toHexString}\'s Piece ${pieceMessage.index} sub piece $subPieceIndex already downloaded');
      return;
    }

    String savePath = _exchangeManager._computePiecePath(torrentExchangeInfo.name, pieceMessage.index);

    _saveSubPiece(savePath, pieceMessage.begin, pieceMessage.block).then((_) {
      Log.fine('save ${connection.infoHash.toHexString}\'s piece ${pieceMessage.index} subPiece $subPieceIndex success');

      torrentExchangeInfo.subPieces[pieceMessage.index][subPieceIndex] = true;
      _checkAllSubPiecesDownloaded(torrentExchangeInfo, pieceMessage.index, savePath);
    }).onError((error, stackTrace) {
      Log.severe('save ${connection.infoHash.toHexString}\'s piece ${pieceMessage.index} subPiece $subPieceIndex failed: $error');

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
}
