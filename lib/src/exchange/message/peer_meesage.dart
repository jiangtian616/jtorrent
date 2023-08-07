import 'dart:convert';
import 'dart:typed_data';

import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/model/peer.dart';

import '../../util/common_util.dart';

abstract interface class PeerMessage {
  Peer get peer;

  Uint8List get toUint8List;
}

class IllegalMessage implements PeerMessage {
  final String message;

  const IllegalMessage({required this.message});

  @override
  Uint8List get toUint8List => Uint8List(0);

  @override
  String toString() {
    return 'IllegalMessage{message: $message}';
  }
}

class HandshakeMessage implements PeerMessage {
  static const int defaultPStrlen = 19;
  static const String defaultPStr = 'BitTorrent protocol';
  static const List<int> defaultPStrCodeUnits = [66, 105, 116, 84, 111, 114, 114, 101, 110, 116, 32, 112, 114, 111, 116, 111, 99, 111, 108];

  /// Default value is 19
  final int pStrlen;

  /// Default value is 'BitTorrent protocol'
  final String pStr;

  /// 8 reserved bytes
  final Uint8List reserved;

  /// 20 bytes, same as info_hash when announce
  final Uint8List infoHash;

  /// 20 bytes, same as peer_id e when announce
  final Uint8List peerId;

  HandshakeMessage._({
    required this.pStrlen,
    required this.pStr,
    required this.reserved,
    required this.infoHash,
    required this.peerId,
  });

  HandshakeMessage.noExtension({required this.infoHash})
      : pStrlen = defaultPStrlen,
        pStr = defaultPStr,
        reserved = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]),
        peerId = CommonUtil.generateLocalPeerId(infoHash);

  factory HandshakeMessage.fromBuffer(List<int> buffer) {
    return HandshakeMessage._(
      pStrlen: buffer[0],
      pStr: String.fromCharCodes(buffer.sublist(1, 1 + buffer[0])),
      reserved: Uint8List.fromList(buffer.sublist(1 + buffer[0], 1 + buffer[0] + 8)),
      infoHash: Uint8List.fromList(buffer.sublist(1 + buffer[0] + 8, 1 + buffer[0] + 8 + 20)),
      peerId: Uint8List.fromList(buffer.sublist(1 + buffer[0] + 8 + 20, 1 + buffer[0] + 8 + 20 + 20)),
    );
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([pStrlen, ...ascii.encode(pStr), ...reserved, ...infoHash, ...peerId]);

  @override
  String toString() {
    return 'HandshakeMessage{pStrlen: $pStrlen, pStr: $pStr, reserved: $reserved, infoHash: ${infoHash.toHexString}, peerId: ${String.fromCharCodes(peerId)}';
  }
}

class KeepAliveMessage implements PeerMessage {
  const KeepAliveMessage._();

  static const KeepAliveMessage instance = KeepAliveMessage._();

  factory KeepAliveMessage.fromBuffer(List<int> buffer) {
    return instance;
  }

  @override
  Uint8List get toUint8List => Uint8List(0);

  @override
  String toString() {
    return 'KeepAliveMessage{}';
  }
}

class ChokeMessage implements PeerMessage {
  static const int typeId = 0;

  const ChokeMessage._();

  static const ChokeMessage instance = ChokeMessage._();

  factory ChokeMessage.fromBuffer(List<int> buffer) {
    return instance;
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([0, 0, 0, 1, typeId]);

  @override
  String toString() {
    return 'ChokeMessage{}';
  }
}

class UnChokeMessage implements PeerMessage {
  static const int typeId = 1;

  const UnChokeMessage._();

  static const UnChokeMessage instance = UnChokeMessage._();

  factory UnChokeMessage.fromBuffer(List<int> buffer) {
    return instance;
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([0, 0, 0, 1, typeId]);

  @override
  String toString() {
    return 'UnChokeMessage{}';
  }
}

class InterestedMessage implements PeerMessage {
  static const int typeId = 2;

  const InterestedMessage._();

  static const InterestedMessage instance = InterestedMessage._();

  factory InterestedMessage.fromBuffer(List<int> buffer) {
    return instance;
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([0, 0, 0, 1, typeId]);

  @override
  String toString() {
    return 'InterestedMessage{}';
  }
}

class NotInterestedMessage implements PeerMessage {
  static const int typeId = 3;

  const NotInterestedMessage._();

  static const NotInterestedMessage instance = NotInterestedMessage._();

  factory NotInterestedMessage.fromBuffer(List<int> buffer) {
    return instance;
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([0, 0, 0, 1, typeId]);

  @override
  String toString() {
    return 'NotInterestedMessage{}';
  }
}

class HaveMessage implements PeerMessage {
  static const int typeId = 4;
  final int pieceIndex;

  const HaveMessage._({required this.pieceIndex});

  factory HaveMessage.fromBuffer(List<int> buffer) {
    return HaveMessage._(pieceIndex: ByteData.view(Uint8List.fromList(buffer).buffer, 5, 4).getInt32(0));
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([0, 0, 0, 5, typeId, ...(ByteData(4)..setInt32(0, pieceIndex, Endian.big)).buffer.asUint8List()]);

  @override
  String toString() {
    return 'HaveMessage{pieceIndex: $pieceIndex}';
  }
}

/// Peer may send multiple Have messages at once, we stack them together
class StackHaveMessage extends HaveMessage {
  final List<int> pieceIndexes;

  const StackHaveMessage._({required this.pieceIndexes}) : super._(pieceIndex: 0);

  factory StackHaveMessage.fromHaveMessage(List<HaveMessage> haveMessages) {
    return StackHaveMessage._(pieceIndexes: haveMessages.map((m) => m.pieceIndex).toList());
  }

  @override
  Uint8List get toUint8List => throw UnsupportedError('StackHaveMessage cannot be converted to Uint8List');

  @override
  String toString() {
    return 'StackHaveMessage{pieceIndexes: $pieceIndexes}';
  }
}

class BitFieldMessage implements PeerMessage {
  static const int typeId = 5;

  final Uint8List bitField;

  BitFieldMessage({required this.bitField});

  factory BitFieldMessage.fromBoolList(List<bool> pieces) {
    return BitFieldMessage(bitField: CommonUtil.boolListToBitmap(pieces));
  }

  factory BitFieldMessage.fromBuffer(List<int> buffer) {
    return BitFieldMessage(bitField: Uint8List.fromList(buffer.sublist(5)));
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([
        (bitField.length + 1) ~/ (1 << 24),
        (bitField.length + 1) % (1 << 24) ~/ (1 << 16),
        (bitField.length + 1) % (1 << 16) ~/ (1 << 8),
        (bitField.length + 1) % (1 << 8),
        typeId,
        ...bitField
      ]);

  @override
  String toString() {
    return 'BitFieldMessage{bitField: $bitField}';
  }
}

class RequestMessage implements PeerMessage {
  static const int typeId = 6;

  final int index;
  final int begin;
  final int length;

  const RequestMessage._({required this.index, required this.begin, required this.length});

  factory RequestMessage.fromBuffer(List<int> buffer) {
    return RequestMessage._(
      index: buffer[5],
      begin: buffer[6],
      length: buffer[7],
    );
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([0, 0, 0, 4, typeId, index, begin, length]);

  @override
  String toString() {
    return 'RequestMessage{index: $index, begin: $begin, length: $length}';
  }
}

class PieceMessage implements PeerMessage {
  static const int typeId = 7;

  final int index;
  final int begin;
  final Uint8List block;

  const PieceMessage._({required this.index, required this.begin, required this.block});

  factory PieceMessage.fromBuffer(List<int> buffer) {
    return PieceMessage._(
      index: buffer[5],
      begin: buffer[6],
      block: Uint8List.fromList(buffer.sublist(7)),
    );
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([
        (block.length + 3) ~/ (1 << 24),
        (block.length + 3) % (1 << 24) ~/ (1 << 16),
        (block.length + 3) % (1 << 16) ~/ (1 << 8),
        (block.length + 3) % (1 << 8),
        typeId,
        index,
        begin,
        ...block
      ]);

  @override
  String toString() {
    return 'PieceMessage{index: $index, begin: $begin, block: $block}';
  }
}

class CancelMessage implements PeerMessage {
  static const int typeId = 8;

  final int index;
  final int begin;
  final int length;

  const CancelMessage._({required this.index, required this.begin, required this.length});

  factory CancelMessage.fromBuffer(List<int> buffer) {
    return CancelMessage._(
      index: buffer[5],
      begin: buffer[6],
      length: buffer[7],
    );
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([0, 0, 0, 4, typeId, index, begin, length]);

  @override
  String toString() {
    return 'CancelMessage{index: $index, begin: $begin, length: $length}';
  }
}
