import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/model/announce_response.dart';
import 'package:jtorrent/src/peer/file/file_manager.dart';
import 'package:jtorrent/src/peer/file/state_file.dart';
import 'package:jtorrent/src/peer/piece/piece_manager.dart';
import 'package:jtorrent/src/util/common_util.dart';
import 'package:jtorrent/src/util/log_util.dart';

import '../announce/announce_manager.dart';
import '../announce/announce_request_options_provider.dart';
import '../model/peer.dart';
import '../model/torrent.dart';
import '../peer/peer_manager.dart';

abstract class TorrentTask {
  TorrentTask._();

  factory TorrentTask.fromTorrent(Torrent torrent, String savePath) {
    return _TorrentTask(torrent: torrent, savePath: savePath);
  }

  /// Start to download
  Future<void> start();

  /// Pause all tasks
  void pause();

  /// Resume all tasks
  void resume();

  TorrentTaskDebugInfo getDebugInfo();
}

class _TorrentTask extends TorrentTask implements AnnounceConfigProvider {
  _TorrentTask({required Torrent torrent, required String savePath})
      : _torrent = torrent,
        _savePath = savePath,
        _localPeerId = CommonUtil.generateLocalPeerId(torrent.infoHash),
        super._();

  final Torrent _torrent;

  final String _savePath;
  late final Uint8List _localPeerId;

  late final StateFile _stateFile;

  late final AnnounceManager _announceManager;
  late final PeerManager _peerManager;
  late final PieceManager _pieceManager;
  late final FileManager _fileManager;

  ServerSocket? _serverSocket;

  @override
  bool compact = true;
  @override
  bool noPeerId = true;
  @override
  int numWant = 200;

  @override
  Duration announceConnectTimeout = Duration(milliseconds: 10000);
  @override
  Duration announceReceiveTimeout = Duration(milliseconds: 30000);

  bool _initialized = false;
  bool _paused = false;
  bool _completed = false;

  final Completer<void> _initCompleter = Completer<void>();

  @override
  Uint8List get infoHash => _torrent.infoHash;

  @override
  InternetAddress? get localIp => _serverSocket!.address;

  @override
  int get localPort => _serverSocket!.port;

  @override
  int get left => _torrent.files.fold(0, (previousValue, element) => previousValue + element.length) - downloaded;

  @override
  int get downloaded => _pieceManager.downloadedBytes;

  @override
  int get uploaded => _stateFile.uploaded;

  @override
  Uint8List get peerId => _localPeerId;

  @override
  Future<void> start() async {
    assert(_paused == false);
    assert(_serverSocket == null);

    if (_initialized) {
      return _initCompleter.future;
    }
    _initialized = true;

    /// todo
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _serverSocket!.listen((data) {});

    _announceManager = AnnounceManager(announceConfigProvider: this);
    _announceManager.addTrackerServers(_torrent.allTrackers);
    _announceManager.addOnNewPeersFoundCallback(_processOnNewPeers);

    _stateFile = await StateFile.find(_savePath, _torrent);
    _pieceManager = PieceManager.fromTorrent(torrent: _torrent, bitField: _stateFile.bitField);
    _fileManager = FileManager.fromTorrent(savePath: _savePath, torrent: _torrent);
    await _fileManager.init();

    _peerManager = PeerManager(
      infoHash: _torrent.infoHash,
      pieceManager: _pieceManager,
      fileManager: _fileManager,
    );
    _peerManager.addOnPieceCompletedCallBack(_processPieceCompleted);
    _peerManager.addOnCompletedCallBack(_processCompleted);

    await _stateFileHashCheck();
    if (_stateFile.status == DownloadStatus.completed) {
      _completed = true;
    } else {
      _announceManager.start();
    }

    Log.info(
        '${_stateFile.infoHash.toHexString}\'s initial status: ${_stateFile.status}, uploaded: ${_stateFile.uploaded}, bitField: ${_stateFile.bitField}');
    _initCompleter.complete();
  }

  @override
  void pause() {
    if (_paused) {
      return;
    }
    _paused = true;

    _peerManager.pause();
  }

  @override
  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;

    _peerManager.resume();
  }

  void _processOnNewPeers(AnnounceSuccessResponse response) {
    for (Peer peer in response.peers) {
      _peerManager.addNewPeer(peer);
    }
  }

  void _processPieceCompleted(Uint8List bitField) {
    _stateFile.updateBitField(bitField);
  }

  void _processCompleted() {
    _stateFile.updateStatus(DownloadStatus.completed);
    _stateFile.flushAll();
  }

  Future<void> _stateFileHashCheck() async {
    if (_stateFile.status == DownloadStatus.completed) {
      return;
    }

    bool needFlush = false;

    for (int i = 0; i < _pieceManager.pieceCount; i++) {
      if (CommonUtil.getValueFromBitmap(_stateFile.bitField, i)) {
        Uint8List bytes = await _fileManager.readPiece(i);
        bool valid = _pieceManager.checkPieceHash(i, bytes);

        if (!valid) {
          Log.warning('Piece $i is invalid, reset bitField');
          CommonUtil.setValueToBitmap(_stateFile.bitField, i, false);
          _pieceManager.resetLocalPiece(i);
          needFlush = true;
        }
      }
    }

    if (needFlush) {
      return await _stateFile.flushAll();
    }

    if (_stateFile.pieceCount == CommonUtil.getBitCountFromBitmap(_stateFile.bitField)) {
      Log.info('All pieces are downloaded, set status to completed');
      _stateFile.updateStatus(DownloadStatus.completed);
    }
  }

  @override
  TorrentTaskDebugInfo getDebugInfo() {
    return TorrentTaskDebugInfo(
      downloadProgress: downloaded / (downloaded + left),
      downloadPieceProgress: '${_pieceManager.downloadedPieceCount} / ${_pieceManager.pieceCount}',
      bitField: _pieceManager.bitField,
      activeConnections: _peerManager.activeConnections.map((c) => c.peer).toList(),
      availableConnections: _peerManager.availableConnections.map((c) => c.peer).toList(),
      pendingPieceRequests: _peerManager.pendingRequests,
    );
  }
}

class TorrentTaskDebugInfo {
  final double downloadProgress;
  final String downloadPieceProgress;
  final Uint8List bitField;
  final List<Peer> activeConnections;
  final List<Peer> availableConnections;
  final Map<Peer, List<({int pieceIndex, int subPieceIndex})>> pendingPieceRequests;

  const TorrentTaskDebugInfo({
    required this.downloadProgress,
    required this.downloadPieceProgress,
    required this.bitField,
    required this.activeConnections,
    required this.availableConnections,
    required this.pendingPieceRequests,
  });

  String format() {
    return JsonEncoder.withIndent('  ').convert(this);
  }

  Map<String, dynamic> toJson() {
    return {
      'downloadProgress': this.downloadProgress,
      'downloadPieceProgress': this.downloadPieceProgress,
      'bitField': this.bitField.toString(),
      'activeConnections': this.activeConnections.map((e) => '${e.ip.address}:${e.port}').toList().toString(),
      'availableConnections': this.availableConnections.map((e) => '${e.ip.address}:${e.port}').toList(),
      'pendingPieceRequests': this
          .pendingPieceRequests
          .map((key, value) => MapEntry('${key.ip.address}:${key.port}', value.map((e) => '${e.pieceIndex}-${e.subPieceIndex}').toString())),
    };
  }
}
