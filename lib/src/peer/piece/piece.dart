import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/peer/piece/piece_manager.dart';

class Piece {
  final Uint8List pieceHash;

  final int pieceLength;

  final List<PieceStatus> subPieces;

  int get subPiecesCount => subPieces.length;

  int subPieceLength(int subPieceIndex) =>
      subPieceIndex < subPiecesCount - 1 ? CommonConstants.subPieceLength : pieceLength - (subPiecesCount - 1) * CommonConstants.subPieceLength;

  bool get downloaded => subPieces.every((subPiece) => subPiece == PieceStatus.downloaded);

  bool completed = false;

  Piece({required this.pieceHash, required this.pieceLength, required bool completed})
      : completed = completed ? true : false,
        subPieces =
            List.generate((pieceLength / CommonConstants.subPieceLength).ceil(), (index) => completed ? PieceStatus.downloaded : PieceStatus.none);

  void updateSubPiece(int subPieceIndex, PieceStatus status) {
    assert(subPieceIndex >= 0 && subPieceIndex < subPiecesCount);

    subPieces[subPieceIndex] = status;
  }

  void resetSubPieces() {
    subPieces.fillRange(0, subPiecesCount, PieceStatus.none);
  }

  bool checkHash(List<int> bytes) {
    assert(downloaded);

    return ListEquality<int>().equals(sha1.convert(bytes).bytes, pieceHash);
  }

  bool complete() {
    assert(downloaded);
    bool oldValue = completed;
    completed = true;
    return oldValue == false;
  }
}
