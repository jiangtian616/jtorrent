import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/exchange/message/peer_meesage.dart';
import 'package:jtorrent/src/util/log_util.dart';

import '../../model/peer.dart';
import '../../model/torrent_exchange_info.dart';
import '../message/peer_message_raw_handler.dart';

abstract class PeerConnection {
  final Peer peer;
  final TorrentExchangeInfo torrentExchangeInfo;

  bool connecting;
  bool connected;

  DateTime? lastActiveTime;
  bool illegal;
  bool haveHandshake;
  bool peerHaveHandshake;
  bool sentBitField;

  bool amChoking;
  bool amInterested;
  bool peerChoking;
  bool peerInterested;

  /// Record each piece's status of peer
  final List<PieceStatus> peerPieces;

  PeerConnection({
    required this.peer,
    required this.torrentExchangeInfo,
    this.connecting = false,
    this.connected = false,
    this.lastActiveTime,
    this.illegal = false,
    this.haveHandshake = false,
    this.peerHaveHandshake = false,
    this.sentBitField = false,
    this.amChoking = true,
    this.amInterested = false,
    this.peerChoking = true,
    this.peerInterested = false,
  }) : peerPieces = List.generate(torrentExchangeInfo.pieceSha1s.length, (index) => PieceStatus.notDownloaded);

  Uint8List get infoHash => torrentExchangeInfo.infoHash;

  Future<void> connect() {
    assert(!connecting && !connected);
    connecting = true;
    return doConnect();
  }

  Future<void> doConnect();

  StreamSubscription<PeerMessage> listen(void Function(PeerMessage data) onPeerMessage);

  void sendHandShake();

  void sendUnChoke();

  void sendRequest(int pieceIndex, int subPieceIndex);

  void sendInterested();

  void sendBitField(List<PieceStatus> pieces);

  void closeByIllegal() {
    assert(connecting && connected);

    connecting = false;
    connected = false;
    illegal = true;
    doClose();
  }

  void close() {
    assert(connecting && connected);

    connecting = false;
    connected = false;
    doClose();
  }

  void doClose();
}

class TcpPeerConnection extends PeerConnection {
  TcpPeerConnection({
    required super.peer,
    required super.torrentExchangeInfo,
    super.amChoking,
    super.amInterested,
    super.peerChoking,
    super.peerInterested,
  }) {
    _messageHandler = TcpPeerMessageRawHandler(infoHash: infoHash, peer: peer);
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

      _socket!.listen(
        (Uint8List data) => _messageHandler.handleNewResponseData(data),
        onError: (Object error, StackTrace stackTrace) {
          Log.fine('socket error while listen: $error');
          closeByIllegal();
        },
      );

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
  void sendHandShake() {
    assert(connected);
    assert(haveHandshake == false);
    assert(_socket != null);

    Log.finest('send handshake to ${peer.ip.address}:${peer.port}');
    _socket!.add(HandshakeMessage.noExtension(infoHash: infoHash).toUint8List);
  }

  @override
  void sendUnChoke() {
    assert(connected);
    assert(_socket != null);
    assert(amChoking == true);

    Log.finest('send unChoke to ${peer.ip.address}:${peer.port}');
    _socket!.add(UnChokeMessage.instance.toUint8List);
  }

  @override
  void sendRequest(int pieceIndex, int subPieceIndex) {
    assert(connected);
    assert(_socket != null);
    assert(peerChoking == false);

    Log.finest(
        'send request to ${peer.ip.address}:${peer.port} for piece $pieceIndex subPiece $subPieceIndex length: ${CommonConstants.subPieceLength}');
    _socket!.add(
        RequestMessage(index: pieceIndex, begin: subPieceIndex * CommonConstants.subPieceLength, length: CommonConstants.subPieceLength).toUint8List);
  }

  @override
  void sendInterested() {
    assert(connected);
    assert(_socket != null);
    assert(amInterested == false);

    Log.finest('send interested to ${peer.ip.address}:${peer.port}');
    _socket!.add(InterestedMessage.instance.toUint8List);
  }

  @override
  void sendBitField(List<PieceStatus> pieces) {
    assert(connected);
    assert(_socket != null);
    assert(sentBitField == false);

    Log.finest('send bitfield to ${peer.ip.address}:${peer.port}');
    List<bool> boolList = pieces.map((piece) => piece == PieceStatus.downloaded).toList();
    _socket!.add(BitFieldMessage.fromBoolList(boolList).toUint8List);
  }

  @override
  void doClose() {
    _socket?.close();
    _messageHandler.reset();
  }
}
