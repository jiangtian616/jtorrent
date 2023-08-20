import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:path/path.dart';

/// 1 byte for status
/// 8 bytes for uploaded
/// x bytes for bitfield
class StateFile {
  final Uint8List infoHash;

  final int pieceCount;

  late DownloadStatus _status;

  DownloadStatus get status => _status;

  late int _uploaded;

  int get uploaded => _uploaded;

  late Uint8List _bitField;

  Uint8List get bitField => _bitField;

  late final RandomAccessFile _writeFile;
  final StreamController<({Future<void> Function() operation, Completer<void> completer})> _writeSC = StreamController();
  late final StreamSubscription<({Future<void> Function() operation, Completer<void> completer})> _writeSS;

  static Future<StateFile> find(String directoryPath, Torrent torrent) async {
    StateFile stateFile = StateFile._(infoHash: torrent.infoHash, pieceCount: torrent.pieceSha1s.length);
    await stateFile._init(directoryPath: directoryPath);
    return stateFile;
  }

  StateFile._({required this.infoHash, required this.pieceCount});

  Future<void> _init({required String directoryPath}) async {
    File file = File(join(directoryPath, '${infoHash.toHexString}${CommonConstants.stateFileSuffix}'));
    bool exists = await file.exists();

    _writeFile = await file.open(mode: FileMode.writeOnlyAppend);
    _writeSS = _writeSC.stream.listen((value) => _operate(value.operation, value.completer));

    int bitFieldLength = (pieceCount / 8).ceil();

    if (exists) {
      Uint8List bytes = await file.readAsBytes();

      assert(bytes.length == 9 + bitFieldLength);

      _status = DownloadStatus.values[bytes[0]];
      _uploaded = bytes.buffer.asByteData().getUint64(1);
      _bitField = bytes.sublist(9, 9 + bitFieldLength);
    } else {
      _status = DownloadStatus.downloading;
      _uploaded = 0;
      _bitField = Uint8List(bitFieldLength);
      await flushAll();
    }
  }

  Future<void> updateStatus(DownloadStatus status) {
    _status = status;

    Completer<void> completer = Completer();
    _writeSC.sink.add((operation: _flushStatus, completer: completer));
    return completer.future;
  }

  Future<void> updateUploaded(int uploaded) {
    _uploaded = uploaded;

    Completer<void> completer = Completer();
    _writeSC.sink.add((operation: _flushUploaded, completer: completer));
    return completer.future;
  }

  Future<void> updateBitField(Uint8List bitField) {
    _bitField = bitField;

    Completer<void> completer = Completer();
    _writeSC.sink.add((operation: _flushBitfield, completer: completer));
    return completer.future;
  }

  Future<void> flushAll() async {
    Completer<void> completer = Completer();
    _writeSC.sink.add((operation: _flushAll, completer: completer));
    return completer.future;
  }

  Future<void> _flushStatus() async {
    await _writeFile.setPosition(0);
    await _writeFile.writeByte(_status.index);
  }

  Future<void> _flushUploaded() async {
    await _writeFile.setPosition(1);
    ByteData byteData = ByteData(8);
    byteData.setInt64(0, _uploaded);
    await _writeFile.writeFrom(byteData.buffer.asUint8List());
  }

  Future<void> _flushBitfield() async {
    await _writeFile.setPosition(9);
    await _writeFile.writeFrom(_bitField);
  }

  Future<void> _flushAll() async {
    await _writeFile.setPosition(0);

    await _writeFile.writeByte(_status.index);

    ByteData byteData = ByteData(8);
    byteData.setInt64(0, _uploaded);
    await _writeFile.writeFrom(byteData.buffer.asUint8List());

    await _writeFile.writeFrom(_bitField);
  }

  Future<void> _operate(Future<void> Function() operation, Completer<void> completer) async {
    _writeSS.pause();

    try {
      await operation.call();
    } on FileSystemException catch (e) {
      Log.severe('Flush state file operation failed', e);
      completer.completeError(e, StackTrace.current);
    }

    _writeSS.resume();
    completer.complete();
  }
}

enum DownloadStatus { paused, downloading, completed }
