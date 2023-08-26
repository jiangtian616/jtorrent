import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:jtorrent/src/model/peer.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/peer/piece/piece.dart';
import 'package:jtorrent/src/util/common_util.dart';
import 'package:sortedmap/sortedmap.dart';

class PieceManager with PieceManagerEventDispatcher {
  final Uint8List infoHash;

  final int pieceLength;

  final int pieceCount;

  final Map<Peer, List<bool>> _peerPieces = {};

  final List<Piece> _localPieces;

  final SortedMap<int, int> _piece2PeerCount = SortedMap(Ordering.byValue());

  PieceManager.fromTorrent({required Torrent torrent, Uint8List? bitField})
      : this._(
          infoHash: torrent.infoHash,
          totalBytes: torrent.totalBytes,
          pieceLength: torrent.pieceLength,
          pieceSha1s: torrent.pieceSha1s,
          bitField: bitField,
        );

  PieceManager._({
    required this.infoHash,
    required int totalBytes,
    required this.pieceLength,
    required List<Uint8List> pieceSha1s,
    Uint8List? bitField,
  })  : pieceCount = pieceSha1s.length,
        _localPieces = List.generate(
          pieceSha1s.length,
          (index) => Piece(
            pieceLength: index < pieceSha1s.length - 1 ? pieceLength : totalBytes - (pieceSha1s.length - 1) * pieceLength,
            pieceHash: pieceSha1s[index],
            completed: bitField == null ? false : CommonUtil.getValueFromBitmap(bitField, index),
          ),
        ) {
    for (int i = 0; i < pieceCount; i++) {
      _piece2PeerCount[i] = 0;
    }
  }

  int get subPieceCount => _localPieces.first.subPiecesCount;

  Uint8List get bitField => CommonUtil.boolListToBitmap(_localPieces.map((piece) => piece.downloaded).toList());

  bool get downloaded => _localPieces.every((piece) => piece.downloaded);

  bool pieceDownloaded(int pieceIndex) => _localPieces[pieceIndex].downloaded;

  bool subPieceDownloaded(int pieceIndex, int subPieceIndex) => _localPieces[pieceIndex].subPieces[subPieceIndex] == PieceStatus.downloaded;

  int get downloadedPieceCount => _localPieces.where((piece) => piece.completed).length;

  int get downloadedBytes =>
      _localPieces.where((piece) => piece.completed).fold<int>(0, (previousValue, element) => previousValue + element.pieceLength);

  void initPeerPieces(Peer peer) {
    _peerPieces[peer] ??= List.filled(pieceCount, false);

    for (int pieceIndex = 0; pieceIndex < _peerPieces[peer]!.length; pieceIndex++) {
      if (_peerPieces[peer]![pieceIndex]) {
        _piece2PeerCount.update(pieceIndex, (value) => value + 1);
      }
    }
  }

  void updatePeerPiece(Peer peer, int pieceIndex, bool isDownloaded) {
    assert(pieceIndex >= 0 && pieceIndex < pieceCount);
    assert(_peerPieces[peer] != null);

    _peerPieces[peer]![pieceIndex] = isDownloaded;
    _piece2PeerCount.update(pieceIndex, (value) => value + 1);
  }

  void removePeerPieces(Peer peer) {
    List<bool>? bitField = _peerPieces.remove(peer);

    if (bitField != null) {
      for (int pieceIndex = 0; pieceIndex < bitField.length; pieceIndex++) {
        if (bitField[pieceIndex]) {
          _piece2PeerCount.update(pieceIndex, (value) => value - 1);
        }
      }
    }
  }

  void resetLocalSubPiece(int index, int subPieceIndex) {
    assert(index >= 0 && index < pieceCount);
    assert(subPieceIndex >= 0 && subPieceIndex < subPieceCount);

    if (_localPieces[index].subPieces[subPieceIndex] == PieceStatus.downloading) {
      _localPieces[index].updateSubPiece(subPieceIndex, PieceStatus.none);
    }
  }

  void resetLocalPiece(int index, [bool force = false]) {
    assert(index >= 0 && index < pieceCount);
    if (force || _localPieces[index].completed == false) {
      _localPieces[index].completed = false;
      _localPieces[index].resetSubPieces();
    }
  }

  void updateLocalSubPiece(int index, int subPieceIndex, PieceStatus status) {
    assert(index >= 0 && index < pieceCount);
    assert(subPieceIndex >= 0 && subPieceIndex < subPieceCount);

    _localPieces[index].updateSubPiece(subPieceIndex, status);
  }

  ({int pieceIndex, int subPieceIndex, int length})? selectPieceIndexToDownload(Peer peer) {
    assert(_peerPieces[peer] != null);

    /// find a sub piece that is not being downloaded with rarest first strategy
    for (int pieceIndex in _piece2PeerCount.keys) {
      if (!_peerPieces[peer]![pieceIndex]) {
        continue;
      }
      if (_localPieces[pieceIndex].completed) {
        continue;
      }

      for (int subPieceIndex = 0; subPieceIndex < _localPieces[pieceIndex].subPiecesCount; subPieceIndex++) {
        if (_localPieces[pieceIndex].subPieces[subPieceIndex] == PieceStatus.none) {
          return (pieceIndex: pieceIndex, subPieceIndex: subPieceIndex, length: _localPieces[pieceIndex].subPieceLength(subPieceIndex));
        }
      }
    }

    /// Endgame mode: find a sub piece that is being downloaded
    for (int pieceIndex in _piece2PeerCount.keys) {
      if (!_peerPieces[peer]![pieceIndex]) {
        continue;
      }
      if (_localPieces[pieceIndex].completed) {
        continue;
      }

      for (int subPieceIndex = 0; subPieceIndex < _localPieces[pieceIndex].subPiecesCount; subPieceIndex++) {
        if (_localPieces[pieceIndex].subPieces[subPieceIndex] == PieceStatus.downloading) {
          return (pieceIndex: pieceIndex, subPieceIndex: subPieceIndex, length: _localPieces[pieceIndex].subPieceLength(subPieceIndex));
        }
      }
    }

    return null;
  }

  Future<void> completeSubPiece(int pieceIndex, int subPieceIndex, Future<Uint8List> Function() hashGetter) async {
    assert(pieceIndex >= 0 && pieceIndex < pieceCount);
    assert(subPieceIndex >= 0 && subPieceIndex < subPieceCount);

    updateLocalSubPiece(pieceIndex, subPieceIndex, PieceStatus.downloaded);

    if (!pieceDownloaded(pieceIndex)) {
      return;
    }

    Uint8List bytes;
    try {
      bytes = await hashGetter.call();
    } on Exception catch (e) {
      return _fireOnPieceHashReadFailedCallbacks(pieceIndex, e);
    }

    if (checkPieceHash(pieceIndex, bytes)) {
      _fireOnPieceHashCheckSuccessCallbacks(pieceIndex);

      completePiece(pieceIndex);
    } else {
      _fireOnPieceHashCheckFailedCallbacks(pieceIndex);
    }
  }

  Future<void> completePiece(int pieceIndex) async {
    assert(pieceIndex >= 0 && pieceIndex < pieceCount);
    assert(_localPieces[pieceIndex].downloaded);

    if (!_localPieces[pieceIndex].complete()) {
      return;
    }

    if (downloaded) {
      _fireOnAllPieceCompletedCallbacks();
    }
  }

  bool checkPieceHash(int pieceIndex, Uint8List bytes) {
    assert(pieceIndex >= 0 && pieceIndex < pieceCount);

    return _localPieces[pieceIndex].checkHash(bytes);
  }
}

enum PieceStatus { none, downloading, downloaded }

mixin PieceManagerEventDispatcher {
  final Set<void Function(int pieceIndex)> _onPieceHashCheckSuccessCallbacks = {};
  final Set<void Function(int pieceIndex)> _onPieceHashCheckFailedCallbacks = {};
  final Set<void Function(int pieceIndex, dynamic error)> _onPieceHashReadFailedCallbacks = {};

  final Set<void Function()> _onAllPieceCompletedCallbacks = {};

  void addOnPieceHashCheckSuccessCallback(void Function(int pieceIndex) callback) {
    _onPieceHashCheckSuccessCallbacks.add(callback);
  }

  bool removeOnPieceHashCheckSuccessCallback(void Function(int pieceIndex) callback) {
    return _onPieceHashCheckSuccessCallbacks.remove(callback);
  }

  void _fireOnPieceHashCheckSuccessCallbacks(int pieceIndex) {
    for (var callback in _onPieceHashCheckSuccessCallbacks) {
      Timer.run(() {
        callback.call(pieceIndex);
      });
    }
  }

  void addOnPieceHashCheckFailedCallback(void Function(int pieceIndex) callback) {
    _onPieceHashCheckFailedCallbacks.add(callback);
  }

  bool removeOnPieceHashCheckFailedCallback(void Function(int pieceIndex) callback) {
    return _onPieceHashCheckFailedCallbacks.remove(callback);
  }

  void _fireOnPieceHashCheckFailedCallbacks(int pieceIndex) {
    for (var callback in _onPieceHashCheckFailedCallbacks) {
      Timer.run(() {
        callback.call(pieceIndex);
      });
    }
  }

  void addOnPieceHashReadFailedCallback(void Function(int pieceIndex, dynamic error) callback) {
    _onPieceHashReadFailedCallbacks.add(callback);
  }

  bool removeOnPieceHashReadFailedCallback(void Function(int pieceIndex, dynamic error) callback) {
    return _onPieceHashReadFailedCallbacks.remove(callback);
  }

  void _fireOnPieceHashReadFailedCallbacks(int pieceIndex, dynamic error) {
    for (var callback in _onPieceHashReadFailedCallbacks) {
      Timer.run(() {
        callback.call(pieceIndex, error);
      });
    }
  }

  void addOnAllPieceCompletedCallback(void Function() callback) {
    _onAllPieceCompletedCallbacks.add(callback);
  }

  bool removeOnAllPieceCompletedCallback(void Function() callback) {
    return _onAllPieceCompletedCallbacks.remove(callback);
  }

  void _fireOnAllPieceCompletedCallbacks() {
    for (var callback in _onAllPieceCompletedCallbacks) {
      Timer.run(() {
        callback.call();
      });
    }
  }
}
