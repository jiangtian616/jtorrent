import 'dart:convert';
import 'dart:typed_data';

extension UTF8Extesion on Uint8List {
  String get toUTF8 => utf8.decode(this);
}
