import 'dart:typed_data';

extension Uint8ListExtension on Uint8List {
  String get toHexString => map((char) => char.toRadixString(16)).map((char) => char.length == 2 ? char : '0$char').toList().join();
}
