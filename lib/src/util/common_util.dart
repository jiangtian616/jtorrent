import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../constant/common_constants.dart';

class CommonUtil {
  static String generateLocalPeerId(Uint8List infoHash) {
    String prefix = '-JT${CommonConstants.version}-';

    Random random = Random(infoHash.hashCode);
    String suffix = utf8.decode(List.generate(CommonConstants.peerIdLength - prefix.length, (index) => random.nextInt(1 << 7)));

    return '$prefix$suffix';
  }
}
