import 'dart:io';

import 'package:jtorrent/src/model/torrent.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    test('Test parse torrent', () async {
      var result = Torrent.fromFileSync(File('/Users/jtmonster/IdeaProjects/jtorrent/test/sample.torrent'));
      assert(result.announces.fold(0, (previousValue, element) => previousValue + element.length) == 137);
      assert(result.files.length == 1);
      assert(result.files.first.length == 2352463340);
    });
  });
}
