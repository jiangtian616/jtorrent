import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:path/path.dart';

import '../model/torrent_exchange_info.dart';
import '../model/peer.dart';
import 'connection/peer_connection.dart';
import 'message/peer_meesage.dart';

class ExchangeManager {
  final String _pieceDownloadPath;

  ExchangeManager({required String downloadPath}) : _pieceDownloadPath = downloadPath;

  final Map<Uint8List, TorrentExchangeInfo> _torrentExchangeMap = {};

  late final List<PeerMessageHandler> _messageHandlers = [
    IllegalPeerMessageHandler(),
    HandshakePeerMessageHandler(),
    KeepAlivePeerMessageHandler(),
    ChokePeerMessageHandler(),
    UnChokePeerMessageHandler(exchangeManager: this),
    InterestedPeerMessageHandler(),
    NotInterestedPeerMessageHandler(),
    StackHaveMessageHandler(),
    BitFieldPeerMessageHandler(exchangeManager: this),
    RequestPeerMessageHandler(exchangeManager: this),
    PiecePeerMessageHandler(exchangeManager: this),
  ];

  void addNewTorrentTask(Torrent torrent, Set<Peer> peers) {
    TorrentExchangeInfo? exchangeStatusInfo = _torrentExchangeMap[torrent.infoHash];

    if (exchangeStatusInfo == null) {
      exchangeStatusInfo = TorrentExchangeInfo(torrent: torrent, peers: peers);
      _torrentExchangeMap[torrent.infoHash] = exchangeStatusInfo;
    } else {
      exchangeStatusInfo.allKnownPeers.addAll(peers);
    }

    for (Peer peer in exchangeStatusInfo.allKnownPeers) {
      Future<PeerConnection> connectionFuture = _openConnection(exchangeStatusInfo, peer);
      Future<void> handshakeFuture = connectionFuture.then((connection) => connection.sendHandShake());
      handshakeFuture.onError((error, stackTrace) => Log.info('Connection error: $peer'));
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

  void _tryRequestPiece(PeerConnection connection) {
    if (connection.torrentExchangeInfo.allPiecesDownloaded) {
      Log.info('Ignore request because all pieces downloaded: ${connection.infoHash}');
      return;
    }

    List<int> targetPieceIndexes = _computePieceIndexesToDownload(connection);
    if (targetPieceIndexes.isEmpty) {
      Log.fine('Ignore request because no piece to request: ${connection.infoHash}');
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

    for (int index in selectedPieceIndexes) {
      connection.torrentExchangeInfo.pieces[index] = PieceStatus.downloading;
      connection.sendRequest(index);
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

  void _onPeerMessage(PeerConnection connection, PeerMessage message) {
    assert(_torrentExchangeMap[connection.infoHash] != null);
    assert(_torrentExchangeMap[connection.infoHash]!.peerConnectionMap[connection.peer] == connection);

    Log.fine('Receive ${connection.peer.ip.address}:${connection.peer.port} $message');

    for (PeerMessageHandler handler in _messageHandlers) {
      if (handler.support(message)) {
        handler.handle(connection, message);
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
  const HandshakePeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is HandshakeMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    if (connection.handshaked) {
      Log.info('${connection.peer.ip.address} handshake again');
    }
    connection.handshaked = true;
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

    connection.peerChoking = false;
    _exchangeManager._tryRequestPiece(connection);
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

class StackHaveMessageHandler implements PeerMessageHandler {
  const StackHaveMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is StackHaveMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    for (int pieceIndex in (peerMessage as StackHaveMessage).pieceIndexes) {
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
        if ((byte & (1 << j)) != 0) {
          int pieceIndex = i * 8 + j;
          if (pieceIndex < connection.peerPieces.length) {
            connection.peerPieces[pieceIndex] = PieceStatus.downloaded;
          }
        }
      }
    }

    _exchangeManager._tryRequestPiece(connection);
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

    PieceMessage pieceMessage = peerMessage as PieceMessage;
    if (pieceMessage.index >= connection.peerPieces.length) {
      Log.severe('PieceMessage pieceIndex ${pieceMessage.index} >= pieces.length ${connection.peerPieces.length}');
      return;
    }

    TorrentExchangeInfo? torrentExchangeInfo = _exchangeManager._torrentExchangeMap[connection.infoHash];
    if (torrentExchangeInfo == null) {
      Log.warning('TorrentExchangeInfo not found for ${connection.infoHash} when save piece: ${pieceMessage.index}}');
      return;
    }

    if (torrentExchangeInfo.pieces[pieceMessage.index] == PieceStatus.downloaded) {
      Log.info('${connection.infoHash}\'s Piece ${pieceMessage.index} already downloaded');
      return;
    }

    if (pieceMessage.begin != 0) {
      Log.warning('begin is not 0, not support');
      return;
    }

    if (pieceMessage.block.length != connection.torrentExchangeInfo.torrent.pieceLength) {
      Log.warning(
          '${connection.infoHash}\'s block length ${pieceMessage.block.length} != piece length ${connection.torrentExchangeInfo.torrent.pieceLength}');
      return;
    }

    File pieceFile = File(join(_exchangeManager._pieceDownloadPath, torrentExchangeInfo.torrent.name, 'pieces', '${pieceMessage.index}'));
    Future<File> writeFuture = pieceFile.writeAsBytes(pieceMessage.block);

    writeFuture.then((_) {
      Log.fine('save ${connection.infoHash}\'s piece ${pieceMessage.index} success');
      torrentExchangeInfo.pieces[pieceMessage.index] = PieceStatus.downloaded;

      /// todo: send have message to all peers
    }).onError((error, stackTrace) {
      Log.severe('save ${connection.infoHash}\'s piece ${pieceMessage.index} failed: $error');

      /// todo: send request message again
    });
  }
}
