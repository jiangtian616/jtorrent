import 'dart:async';
import 'dart:typed_data';

import 'package:jtorrent/src/exchange/exchange_manager.dart';
import 'package:jtorrent/src/exchange/message/peer_meesage.dart';

import '../../model/peer.dart';
import '../connection/peer_connection.dart';

abstract interface class PeerMessageRawHandler {
  Peer get peer;

  Uint8List get infoHash;

  void handleNewResponseData(Uint8List response);

  StreamSubscription<PeerMessage> listen(void Function(PeerMessage data) onPeerMessage);

  void reset();

  void close();
}

class TcpPeerMessageRawHandler implements PeerMessageRawHandler {
  /// Inherit from [PeerConnection]
  final Uint8List _infoHash;

  /// Inherit from [PeerConnection]
  final Peer _peer;

  TcpPeerMessageRawHandler({required Uint8List infoHash, required Peer peer})
      : _infoHash = infoHash,
        _peer = peer;

  /// The buffer for the message from socket
  final List<int> _buffer = [];

  /// Some clients (Deluge for example) send bitfield with missing pieces even if it has all data. Then it sends rest of pieces as have messages.
  /// They are saying this helps against ISP filtering of BitTorrent protocol. It is called lazy bitfield. We combine them together as a single [BitFieldMessage]
  final List<BitFieldMessage> _stackedBitFieldMessages = [];
  final List<HaveMessage> _stackedHaveMessages = [];

  /// Add message to this to notify [ExchangeManager]
  final StreamController<PeerMessage> _peerMessageStreamController = StreamController();

  final List<StreamSubscription<PeerMessage>> _subscriptions = [];

  @override
  Uint8List get infoHash => _infoHash;

  @override
  Peer get peer => _peer;

  @override
  void handleNewResponseData(Uint8List response) {
    _buffer.addAll(response);
    if (_buffer.isEmpty) {
      return;
    }

    _handleBuffer();
  }

  @override
  StreamSubscription<PeerMessage> listen(void Function(PeerMessage data) onPeerMessage) {
    StreamSubscription<PeerMessage> subscription = _peerMessageStreamController.stream.listen(onPeerMessage);
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  void reset() {
    _buffer.clear();

    for (StreamSubscription<PeerMessage> value in _subscriptions) {
      value.cancel();
    }
    _subscriptions.clear();
  }

  @override
  void close() {
    reset();
    _peerMessageStreamController.close();
  }

  void _handleBuffer() {
    if (_isHandshakeMessageHead()) {
      _handleHandshakeMessage();

      if (_buffer.isNotEmpty) {
        _handleBuffer();
      }

      return;
    }

    if (_isOtherMessageHead()) {
      _handleOtherMessage();

      if (_buffer.isNotEmpty) {
        _handleBuffer();
      }
    }

    _sendComposedMessage();
  }

  bool _isHandshakeMessageHead() {
    if (_buffer.length < 68) {
      return false;
    }

    final int pStrlen = _buffer[0];
    if (pStrlen != HandshakeMessage.defaultPStrlen) {
      return false;
    }

    for (int i = 0; i < HandshakeMessage.defaultPStrlen; i++) {
      if (_buffer[i + 1] != HandshakeMessage.defaultPStrCodeUnits[i]) {
        return false;
      }
    }

    return true;
  }

  void _handleHandshakeMessage() {
    if (_isInvalidHandshakeMessage()) {
      return _peerMessageStreamController.sink.add(IllegalMessage(message: 'Invalid handshake message'));
    }

    List<int> segment = _buffer.sublist(0, 68);
    _buffer.removeRange(0, 68);
    _peerMessageStreamController.sink.add(HandshakeMessage.fromBuffer(segment));
  }

  bool _isInvalidHandshakeMessage() {
    for (int i = 0; i < 20; i++) {
      if (_buffer[i + 28] != infoHash[i]) {
        return true;
      }
    }

    return false;
  }

  bool _isOtherMessageHead() {
    if (_buffer.length < 4) {
      return false;
    }

    if (_buffer.length == 4 && (_buffer[0] == 0 && _buffer[1] == 0 && _buffer[2] == 0 && _buffer[3] == 0)) {
      return false;
    }

    for (int i = 0; i < 4; i++) {
      if (_buffer[i] >= (2 << 8 - 1)) {
        return false;
      }
    }

    int length = ByteData.view(Uint8List.fromList(_buffer).buffer, 0, 4).getInt32(0, Endian.big);
    if (_buffer.length < 4 + length) {
      return false;
    }

    return true;
  }

  void _handleOtherMessage() {
    int length = ByteData.view(Uint8List.fromList(_buffer).buffer, 0, 4).getInt32(0, Endian.big);

    List<int> segment = _buffer.sublist(0, 4 + length);
    _buffer.removeRange(0, 4 + length);

    if (length == 0) {
      return _peerMessageStreamController.sink.add(KeepAliveMessage.instance);
    }

    int typeId = segment[4];

    PeerMessage? peerMessage;
    switch (typeId) {
      case ChokeMessage.typeId:
        if (length != 1) {
          peerMessage = IllegalMessage(message: 'Invalid choke message length $length');
        } else {
          peerMessage = ChokeMessage.instance;
        }
        break;
      case UnChokeMessage.typeId:
        if (length != 1) {
          peerMessage = IllegalMessage(message: 'Invalid unChoke message length $length');
        } else {
          peerMessage = UnChokeMessage.instance;
        }
        break;
      case InterestedMessage.typeId:
        if (length != 1) {
          peerMessage = IllegalMessage(message: 'Invalid interested message length $length');
        } else {
          peerMessage = InterestedMessage.instance;
        }
        break;
      case NotInterestedMessage.typeId:
        if (length != 1) {
          peerMessage = IllegalMessage(message: 'Invalid notInterested message length $length');
        } else {
          peerMessage = NotInterestedMessage.instance;
        }
        break;
      case HaveMessage.typeId:
        if (length != 5) {
          peerMessage = IllegalMessage(message: 'Invalid have message length $length');
        } else {
          _stackedHaveMessages.add(HaveMessage.fromBuffer(segment));
        }
        break;
      case BitFieldMessage.typeId:
        if (length < 1) {
          peerMessage = IllegalMessage(message: 'Invalid bitField message length $length');
        } else {
          _stackedBitFieldMessages.add(BitFieldMessage.fromBuffer(segment));
        }
        break;
      case RequestMessage.typeId:
        if (length != 13) {
          peerMessage = IllegalMessage(message: 'Invalid request message length $length');
        } else {
          peerMessage = RequestMessage.fromBuffer(segment);
        }
        break;
      case PieceMessage.typeId:
        if (length < 9) {
          peerMessage = IllegalMessage(message: 'Invalid piece message length $length');
        } else {
          peerMessage = PieceMessage.fromBuffer(segment);
        }
        break;
      case CancelMessage.typeId:
        if (length != 13) {
          peerMessage = IllegalMessage(message: 'Invalid cancel message length $length');
        } else {
          peerMessage = CancelMessage.fromBuffer(segment);
        }
        break;
      default:
        peerMessage = IllegalMessage(message: 'Unknown message type id: $typeId');
    }

    if (peerMessage != null) {
      _peerMessageStreamController.sink.add(peerMessage);
    }
  }

  void _sendComposedMessage() {
    if (_stackedBitFieldMessages.isEmpty && _stackedHaveMessages.isEmpty) {
      return;
    }

    if (_stackedBitFieldMessages.isEmpty && _stackedHaveMessages.isNotEmpty) {
      _peerMessageStreamController.sink.add(ComposedHaveMessage.composed(_stackedHaveMessages));
    } else if (_stackedBitFieldMessages.isNotEmpty && _stackedHaveMessages.isEmpty) {
      for (BitFieldMessage bitFieldMessage in _stackedBitFieldMessages) {
        _peerMessageStreamController.sink.add(bitFieldMessage);
      }
    } else {
      _peerMessageStreamController.sink.add(BitFieldMessage.composed(_stackedBitFieldMessages, _stackedHaveMessages));
    }

    _stackedBitFieldMessages.clear();
    _stackedHaveMessages.clear();
  }
}
