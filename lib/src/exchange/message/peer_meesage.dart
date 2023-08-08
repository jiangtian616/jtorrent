import 'dart:convert';
import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';

import '../../util/common_util.dart';

abstract interface class PeerMessage {
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
class ComposedHaveMessage extends HaveMessage {
  final List<int> pieceIndexes;

  const ComposedHaveMessage._({required this.pieceIndexes}) : super._(pieceIndex: 0);

  factory ComposedHaveMessage.composed(List<HaveMessage> haveMessages) {
    return ComposedHaveMessage._(pieceIndexes: haveMessages.map((m) => m.pieceIndex).toList());
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

  final bool composed;
  final Uint8List bitField;

  BitFieldMessage({required this.composed, required this.bitField});

  factory BitFieldMessage.fromBoolList(List<bool> pieces) {
    return BitFieldMessage(composed: false, bitField: CommonUtil.boolListToBitmap(pieces));
  }

  factory BitFieldMessage.fromBuffer(List<int> buffer) {
    return BitFieldMessage(composed: false, bitField: Uint8List.fromList(buffer.sublist(5)));
  }

  factory BitFieldMessage.composed(List<BitFieldMessage> bitFieldMessages, List<HaveMessage> haveMessages) {
    List<int> composedBitField = bitFieldMessages.first.bitField;

    for (BitFieldMessage message in bitFieldMessages) {
      for (int i = 0; i < composedBitField.length; i++) {
        composedBitField[i] |= message.bitField[i];
      }
    }
    for (HaveMessage message in haveMessages) {
      composedBitField[message.pieceIndex ~/ 8] |= 1 << (7 - message.pieceIndex % 8);
    }

    return BitFieldMessage(composed: true, bitField: Uint8List.fromList(composedBitField));
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
    return 'BitFieldMessage{composed: $composed, bitField: $bitField}';
  }
}

class RequestMessage implements PeerMessage {
  static const int typeId = 6;

  final int index;
  final int begin;
  final int length;

  const RequestMessage({required this.index, required this.begin, required this.length});

  factory RequestMessage.fromBuffer(List<int> buffer) {
    return RequestMessage(
      index: (buffer[5] << 24) | (buffer[6] << 16) | (buffer[7] << 8) | buffer[8],
      begin: (buffer[9] << 24) | (buffer[10] << 16) | (buffer[11] << 8) | buffer[12],
      length: (buffer[13] << 24) | (buffer[14] << 16) | (buffer[15] << 8) | buffer[16],
    );
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([
        0,
        0,
        0,
        13,
        typeId,
        index ~/ (1 << 24),
        index % (1 << 24) ~/ (1 << 16),
        index % (1 << 16) ~/ (1 << 8),
        index % (1 << 8),
        begin ~/ (1 << 24),
        begin % (1 << 24) ~/ (1 << 16),
        begin % (1 << 16) ~/ (1 << 8),
        begin % (1 << 8),
        length ~/ (1 << 24),
        length % (1 << 24) ~/ (1 << 16),
        length % (1 << 16) ~/ (1 << 8),
        length % (1 << 8),
      ]);

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
      index: (buffer[5] << 24) + (buffer[6] << 16) + (buffer[7] << 8) + buffer[8],
      begin: (buffer[9] << 24) + (buffer[10] << 16) + (buffer[11] << 8) + buffer[12],
      block: Uint8List.fromList(buffer.sublist(13)),
    );
  }

  @override
  Uint8List get toUint8List => Uint8List.fromList([
        (block.length + 9) ~/ (1 << 24),
        (block.length + 9) % (1 << 24) ~/ (1 << 16),
        (block.length + 9) % (1 << 16) ~/ (1 << 8),
        (block.length + 9) % (1 << 8),
        typeId,
        index ~/ (1 << 24),
        index % (1 << 24) ~/ (1 << 16),
        index % (1 << 16) ~/ (1 << 8),
        index % (1 << 8),
        begin ~/ (1 << 24),
        begin % (1 << 24) ~/ (1 << 16),
        begin % (1 << 16) ~/ (1 << 8),
        begin % (1 << 8),
        ...block
      ]);

  @override
  String toString() {
    return 'PieceMessage{index: $index, subIndex: ${begin ~/ CommonConstants.subPieceLength}, block.length: ${block.length}}';
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
