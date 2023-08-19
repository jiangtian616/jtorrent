import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/model/peer.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/peer/piece/piece.dart';

class PieceManager {
  int get pieceLength => _localPieces.first.pieceLength;

  int get pieceCount => _localPieces.length;

  int get subPieceCount => _localPieces.first.subPiecesCount;

  List<bool> get bitField => _localPieces.map((piece) => piece.completed).toList();

  bool get completed => _localPieces.every((piece) => piece.completed);

  bool pieceCompleted(int pieceIndex) => _localPieces[pieceIndex].completed;

  bool subPieceCompleted(int pieceIndex, int subPieceIndex) => _localPieces[pieceIndex].subPieces[subPieceIndex] == PieceStatus.downloaded;

  PieceManager.fromTorrent(Torrent torrent) : this._(pieceLength: torrent.pieceLength, pieceSha1s: torrent.pieceSha1s);

  PieceManager._({required int pieceLength, required List<Uint8List> pieceSha1s})
      : _localPieces = List.generate(
          pieceSha1s.length,
          (index) => Piece(
            pieceLength: pieceLength,
            pieceHash: pieceSha1s[index],
            subPieceLength: CommonConstants.subPieceLength,
          ),
        );

  final Map<Peer, List<bool>> _peerPieces = {};

  final List<Piece> _localPieces;


  void updatePeerPiece(Peer peer, int pieceIndex, bool isDownloaded) {
    assert(pieceIndex >= 0 && pieceIndex < pieceCount);

    if (_peerPieces[peer] == null) {
      _peerPieces[peer] = List.filled(pieceCount, false);
    }
    _peerPieces[peer]![pieceIndex] = isDownloaded;
  }

  void resetLocalPieces(int index) {
    _localPieces[index] = Piece(
      pieceLength: pieceLength,
      pieceHash: _localPieces[index].pieceHash,
      subPieceLength: CommonConstants.subPieceLength,
    );
  }

  void updateLocalSubPiece(int index, int subPieceIndex, PieceStatus status) {
    assert(index >= 0 && index < pieceCount);
    assert(subPieceIndex >= 0 && subPieceIndex < subPieceCount);

    _localPieces[index].updateSubPiece(subPieceIndex, status);
  }
  
  void resetLocalSubPieces(int index, int subPieceIndex) {
    assert(index >= 0 && index < pieceCount);
    assert(subPieceIndex >= 0 && subPieceIndex < subPieceCount);

    if (_localPieces[index].subPieces[subPieceIndex] == PieceStatus.downloading) {
      _localPieces[index].updateSubPiece(subPieceIndex, PieceStatus.none);
    }
  }

  int? selectPieceIndexToDownload(Peer peer) {
    assert(_peerPieces[peer] != null);

    /// todo
    for (int i = 0; i < _peerPieces[peer]!.length; i++) {
      if (_peerPieces[peer]![i] && !_localPieces[i].completed && _localPieces[i].subPieces.any((subPiece) => subPiece == PieceStatus.none)) {
        return i;
      }
    }

    return null;
  }

  int? selectSubPieceIndexToDownload(int pieceIndex) {
    assert(pieceIndex >= 0 && pieceIndex < pieceCount);

    /// todo
    for (int i = 0; i < _localPieces[pieceIndex].subPiecesCount; i++) {
      if (_localPieces[pieceIndex].subPieces[i] == PieceStatus.none) {
        return i;
      }
    }

    return null;
  }

  bool checkHash(int pieceIndex, List<int> hash) {
    assert(pieceIndex >= 0 && pieceIndex < pieceCount);
    assert(_localPieces[pieceIndex].completed);

    return _localPieces[pieceIndex].checkHash(hash);
  }
}

enum PieceStatus { none, downloading, downloaded }
