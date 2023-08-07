import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../constant/common_constants.dart';

class CommonUtil {
  static String generateInfoHashString(Uint8List infoHash) {
    return Uri.encodeQueryComponent(String.fromCharCodes(infoHash), encoding: latin1);
  }

  static Uint8List generateLocalPeerId(Uint8List infoHash) {
    String prefix = CommonConstants.peerIdPrefix;

    Random random = Random(infoHash.hashCode);
    List<int> suffix = List.generate(CommonConstants.peerIdLength - prefix.length, (index) => random.nextInt(2 << 7 - 1));

    return Uint8List.fromList(utf8.encode(prefix) + suffix);
  }

  static Uint8List boolListToBitmap(List<bool> pieces) {
    int length = pieces.length;
    int bitmapLength = (length + 7) ~/ 8;
    Uint8List bitmap = Uint8List(bitmapLength);

    for (int i = 0; i < length; i++) {
      if (pieces[i]) {
        bitmap[i ~/ 8] |= 1 << (7 - i % 8);
      }
    }

    return bitmap;
  }
}
