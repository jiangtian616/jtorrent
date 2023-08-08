import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/model/peer.dart';
import 'package:jtorrent/src/model/torrent.dart';

import '../exchange/connection/peer_connection.dart';

class TorrentExchangeInfo {
  /// Inherited from [Torrent]
  final Uint8List infoHash;

  /// Inherited from [Torrent]
  final int pieceLength;

  /// Inherited from [Torrent]
  final String name;

  /// Inherited from [Torrent]
  final List<TorrentFile> files;

  /// Inherited from [Torrent]
  final List<Uint8List> pieceSha1s;

  /// All known peers
  final Set<Peer> allKnownPeers;

  /// Record each piece's status of self
  final List<PieceStatus> pieces;

  /// Record each piece's sub-piece of self
  final List<List<bool>> subPieces;

  bool get allPiecesDownloaded => pieces.every((PieceStatus status) => status == PieceStatus.downloaded);

  final Map<Peer, PeerConnection> peerConnectionMap;

  TorrentExchangeInfo({
    required this.infoHash,
    required this.pieceLength,
    required this.name,
    required this.files,
    required this.pieceSha1s,
    required this.allKnownPeers,
    required this.pieces,
    required this.subPieces,
    required this.peerConnectionMap,
  });

  TorrentExchangeInfo.fromTorrent({required Torrent torrent, required Set<Peer> peers})
      : infoHash = torrent.infoHash,
        pieceLength = torrent.pieceLength,
        name = torrent.name,
        files = torrent.files,
        pieceSha1s = torrent.pieceSha1s,
        allKnownPeers = Set.from(peers),
        pieces = List.generate(torrent.pieceSha1s.length, (index) => PieceStatus.notDownloaded),
        subPieces = List.generate(
          torrent.pieceSha1s.length,
          (index) => List.generate(torrent.pieceLength ~/ CommonConstants.subPieceLength, (index) => false),
        ),
        peerConnectionMap = {};
}

enum PieceStatus { notDownloaded, downloading, downloaded }
