import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/exchange/message/peer_meesage.dart';

import '../../model/peer.dart';
import '../../model/torrent_exchange_info.dart';
import '../message/peer_message_raw_handler.dart';

abstract class PeerConnection {
  final Peer peer;
  final TorrentExchangeInfo torrentExchangeInfo;

  bool connecting;
  bool connected;
  bool illegal;
  bool handshaked;
  DateTime? lastActiveTime;

  bool amChoking;
  bool amInterested;
  bool peerChoking;
  bool peerInterested;

  final List<PieceStatus> pieces;

  PeerConnection({
    required this.peer,
    required this.torrentExchangeInfo,
    this.connecting = false,
    this.connected = false,
    this.illegal = false,
    this.handshaked = false,
    this.lastActiveTime,
    this.amChoking = true,
    this.amInterested = false,
    this.peerChoking = true,
    this.peerInterested = false,
  }) : pieces = List.filled(torrentExchangeInfo.torrent.pieceSha1s.length, PieceStatus.notDownloaded);

  Uint8List get infoHash => torrentExchangeInfo.torrent.infoHash;

  Future<void> connect() {
    assert(!connecting && !connected);
    connecting = true;
    return doConnect();
  }

  Future<void> doConnect();

  StreamSubscription<PeerMessage> listen(void Function(PeerMessage data) onPeerMessage);

  Future sendHandShake();

  void closeByIllegal() {
    assert(connecting && connected);

    connecting = false;
    connected = false;
    illegal = true;
    doCloseByIllegal();
  }

  void doCloseByIllegal();
}

class TcpPeerConnection extends PeerConnection {
  TcpPeerConnection({
    required super.peer,
    required super.torrentExchangeInfo,
    super.amChoking = true,
    super.amInterested = false,
    super.peerChoking = true,
    super.peerInterested = false,
  }) {
    _messageHandler = TcpPeerMessageRawHandler(infoHash: infoHash);
  }

  Socket? _socket;

  late final TcpPeerMessageRawHandler _messageHandler;

  @override
  Future<void> doConnect() async {
    try {
      _socket?.close();
      _messageHandler.reset();

      _socket = await Socket.connect(peer.ip, peer.port);
      connected = true;

      _socket!.listen((Uint8List data) => _messageHandler.handleNewResponseData(data));

      _socket!.done.then((_) {
        connecting = false;
        connected = false;
      });
    } on Exception catch (e) {
      connecting = false;
      rethrow;
    }
  }

  @override
  StreamSubscription<PeerMessage> listen(void Function(PeerMessage data) onPeerMessage) {
    assert(connected);

    return _messageHandler.listen(onPeerMessage);
  }

  @override
  Future sendHandShake() {
    assert(connected);
    assert(_socket != null);

    _socket!.add(HandshakeMessage.noExtension(infoHash: infoHash).toUint8List);
    return _socket!.flush();
  }

  @override
  void doCloseByIllegal() {
    _socket?.close();
    _messageHandler.reset();
  }
}
