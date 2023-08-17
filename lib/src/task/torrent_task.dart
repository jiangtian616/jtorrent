import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/peer/file/file_manager.dart';
import 'package:jtorrent/src/peer/piece/piece_manager.dart';
import 'package:jtorrent/src/util/common_util.dart';

import '../announce/announce_manager.dart';
import '../announce/announce_request_options_provider.dart';
import '../model/torrent.dart';
import '../peer/peer_manager.dart';

const _MAX_OUT_PEERS = 50;
const _MAX_IN_PEERS = 10;

abstract class TorrentTask {
  TorrentTask._();

  factory TorrentTask.fromTorrent(Torrent torrent, String savePath) {
    return _TorrentTask(torrent: torrent, savePath: savePath);
  }

  /// Start to download
  Future<void> start();

  /// Stop all tasks
  Future<void> stop();

  /// Pause all tasks
  void pause();

  /// Resume all tasks
  void resume();
}

class _TorrentTask extends TorrentTask implements AnnounceConfigProvider {
  _TorrentTask({required Torrent torrent, required String savePath})
      : _torrent = torrent,
        _savePath = savePath,
        _localPeerId = CommonUtil.generateLocalPeerId(torrent.infoHash),
        super._();

  final Torrent _torrent;

  final String _savePath;

  late final AnnounceManager _announceManager;

  late final PeerManager _peerManager;

  late final Uint8List _localPeerId;

  ServerSocket? _serverSocket;

  @override
  bool compact = true;
  @override
  bool noPeerId = true;
  @override
  int numWant = 100;

  @override
  Duration connectTimeout = Duration(milliseconds: 10000);
  @override
  Duration receiveTimeout = Duration(milliseconds: 30000);

  bool _paused = false;

  @override
  Uint8List get infoHash => _torrent.infoHash;

  @override
  InternetAddress? get localIp => _serverSocket!.address;

  @override
  int get localPort => _serverSocket!.port;

  @override
  int get left => throw UnimplementedError();

  @override
  int get downloaded => throw UnimplementedError();

  @override
  int get uploaded => throw UnimplementedError();

  @override
  Uint8List get peerId => _localPeerId;

  @override
  Future<void> start() async {
    assert(_serverSocket == null);

    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _serverSocket!.listen((data) {});

    _announceManager = AnnounceManager(announceConfigProvider: this);
    _announceManager.addTrackerServers(_torrent.allTrackers);

    PieceManager _pieceManager = PieceManager(torrent: _torrent);
    FileManager _fileManager = FileManager(savePath: _savePath);

    _peerManager = PeerManager(
      infoHash: _torrent.infoHash,
      pieceManager: _pieceManager,
      fileManager: _fileManager,
    );

    _pieceManager = PieceManager(
      torrent: _torrent,
      peerManager: _peerManager,
      savePath: _savePath,
    );

    _announceManager.start();
  }

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  Future<void> stop() {
    throw UnimplementedError();
  }
}
