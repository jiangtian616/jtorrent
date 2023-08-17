import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:jtorrent/src/util/log_util.dart';
import 'package:path/path.dart';

import '../../model/torrent.dart';

class FileManager {
  final String savePath;

  /// Inherit from [Torrent.name]
  final String name;

  /// Inherit from [Torrent.files]
  final List<TorrentFile> _files;

  String get tempDownloadFilePath => join(savePath, name + CommonConstants.tempDownloadFileSuffix);

  FileManager.fromTorrent({required String savePath, required Torrent torrent})
      : this._(savePath: savePath, name: torrent.name, files: torrent.files);

  FileManager._({required this.savePath, required this.name, required List<TorrentFile> files}) : _files = files;

  late final RandomAccessFile _readFile;
  late final RandomAccessFile _writeFile;

  bool _initialized = false;
  bool _disposed = false;

  Future<void> init() async {
    assert(!_initialized);
    _initialized = true;
    
    _writeFile = await File(tempDownloadFilePath).open(mode: FileMode.writeOnlyAppend);
    _readFile = await File(tempDownloadFilePath).open(mode: FileMode.read);
  }

  Future<void> dispose() async {
    assert(_initialized);
    assert(!_disposed);
    _disposed = true;

    await _writeFile.flush();
    await _readFile.close();
    await _writeFile.close();
  }

  Future<bool> write(int position, Uint8List block) async {
    assert(_initialized);
    assert(!_disposed);

    try {
      await _writeFile.setPosition(position);
      await _writeFile.writeFrom(block);
    } on Exception catch (e) {
      Log.severe('Write file $savePath failed', e);
      return false;
    }

    return true;
  }

  Future<Uint8List> read(int position, int size) async {
    assert(_initialized);
    assert(!_disposed);

    try {
      await _readFile.setPosition(position);
      return await _readFile.read(size);
    } on Exception catch (e) {
      Log.severe('Read file $savePath failed', e);
      rethrow;
    }
  }
}
