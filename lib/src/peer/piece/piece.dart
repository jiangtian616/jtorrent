import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:jtorrent/src/peer/piece/piece_manager.dart';

class Piece {
  final Uint8List pieceHash;

  final int pieceLength;

  final List<PieceStatus> subPieces;

  int get subPiecesCount => subPieces.length;

  bool get completed => subPieces.every((element) => element == PieceStatus.downloaded);

  Piece({
    required this.pieceHash,
    required this.pieceLength,
    required int subPieceLength,
  })  : assert(pieceLength % subPieceLength == 0),
        subPieces = List.generate(pieceLength ~/ subPieceLength, (index) => PieceStatus.notDownloaded);

  void updateSubPiece(int subPieceIndex, PieceStatus status) {
    assert(subPieceIndex >= 0 && subPieceIndex < subPiecesCount);

    subPieces[subPieceIndex] = status;
  }

  bool checkHash(List<int> hash) {
    assert(completed);

    return ListEquality<int>().equals(hash, pieceHash);
  }
}
