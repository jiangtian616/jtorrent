import 'dart:convert';
import 'dart:typed_data';

extension Uint8ListExtension on Uint8List {
  String get toUTF8 => utf8.decode(this);

  String get toHexString => map((char) => char.toRadixString(16)).map((char) => char.length == 2 ? char : '0$char').toList().join();
}

extension StringExtension on String {
  Uint8List get toUint8ListFromHex => Uint8List.fromList(
        List.generate(length ~/ 2, (index) => int.parse(substring(index * 2, index * 2 + 2), radix: 16)),
      );
}
