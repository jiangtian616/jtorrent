import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/constant/common_constants.dart';
import 'package:path/path.dart';

import '../../model/torrent.dart';

class FileManager with FileManagerEventDispatcher {
  static const int readBufferSize = 1024 * 1024 * 4;

  final String savePath;

  /// Inherit from [Torrent.name]
  final String name;

  /// Inherit from [Torrent.files]
  final List<TorrentFile> _files;

  final int pieceLength;

  String get tempDownloadFilePath => join(savePath, name + CommonConstants.tempDownloadFileSuffix);

  FileManager.fromTorrent({required String savePath, required Torrent torrent})
      : this._(savePath: savePath, name: torrent.name, files: torrent.files, pieceLength: torrent.pieceLength);

  FileManager._({
    required this.savePath,
    required this.name,
    required List<TorrentFile> files,
    required this.pieceLength,
  }) : _files = files;

  late final RandomAccessFile _readFile;
  late final RandomAccessFile _writeFile;

  bool _initialized = false;
  bool _disposed = false;

  final StreamController<({int pieceIndex, int begin, Uint8List block})> _writeSC = StreamController();
  late final StreamSubscription<({int pieceIndex, int begin, Uint8List block})> _writeSS;
  final StreamController<({int pieceIndex, Completer<Uint8List> completer})> _readSC = StreamController();
  late final StreamSubscription<({int pieceIndex, Completer<Uint8List> completer})> _readSS;

  Future<void> init() async {
    assert(!_initialized);
    _initialized = true;

    _writeFile = await File(tempDownloadFilePath).open(mode: FileMode.writeOnlyAppend);
    _readFile = await File(tempDownloadFilePath).open(mode: FileMode.read);
    _writeSS = _writeSC.stream.listen(_doWriteSubPiece);
    _readSS = _readSC.stream.listen(_doReadPiece);
  }

  Future<void> dispose() async {
    assert(_initialized);
    assert(!_disposed);
    _disposed = true;

    await _writeSC.close();
    await _readSC.close();
    await _writeFile.flush();
    await _readFile.close();
    await _writeFile.close();
  }

  Future<void> writeSubPiece(int pieceIndex, int begin, Uint8List block) async {
    assert(_initialized);
    assert(!_disposed);

    _writeSC.sink.add((pieceIndex: pieceIndex, begin: begin, block: block));
  }

  Future<Uint8List> readPiece(int pieceIndex) async {
    assert(_initialized);
    assert(!_disposed);

    Completer<Uint8List> completer = Completer();
    _readSC.sink.add((pieceIndex: pieceIndex, completer: completer));
    return completer.future;
  }

  Future<void> complete() async {
    assert(_initialized);
    assert(!_disposed);

    await _writeSC.close();
    await _writeFile.flush();
    await _writeFile.close();

    assert(_files.isNotEmpty);

    if (_files.length == 1) {
      return _extractSingleFile();
    } else {
      return _extractMultiFile();
    }
  }

  Future<void> _doWriteSubPiece(({int pieceIndex, int begin, Uint8List block}) event) async {
    _writeSS.pause();

    try {
      int beginPos = event.pieceIndex * pieceLength + event.begin;
      int endPos = event.pieceIndex * pieceLength + event.begin + event.block.length;
      // await _writeFile.lock(FileLock.blockingExclusive, beginPos, endPos);
      await _writeFile.setPosition(event.pieceIndex * pieceLength + event.begin);
      await _writeFile.writeFrom(event.block);
      // await _writeFile.unlock(beginPos, endPos);
      _fireOnWriteSuccess(event.pieceIndex, event.begin, event.block);
    } on Exception catch (e) {
      _fireOnWriteFailed(event.pieceIndex, event.begin, event.block, e);
    }

    _writeSS.resume();
  }

  Future<void> _doReadPiece(({int pieceIndex, Completer<Uint8List> completer}) event) async {
    _readSS.pause();

    try {
      int beginPos = event.pieceIndex * pieceLength;
      int endPos = event.pieceIndex * pieceLength + pieceLength;
      // await _readFile.lock(FileLock.blockingShared, beginPos, endPos);
      await _readFile.setPosition(event.pieceIndex * pieceLength);
      Uint8List bytes = await _readFile.read(pieceLength);
      // await _readFile.unlock(beginPos, endPos);
      event.completer.complete(bytes);
    } on Exception catch (e) {
      event.completer.completeError(e, StackTrace.current);
    }

    _readSS.resume();
  }

  Future<void> _extractSingleFile() async {
    try {
      await File(tempDownloadFilePath).copy(join(savePath, name));
      _fireOnCompleteSuccess();
    } on FileSystemException catch (e) {
      _fireOnCompleteFailed(e);
    }
  }

  Future<void> _extractMultiFile() async {
    try {
      await Directory(join(savePath, name)).create(recursive: true);

      Map<int, ({int beginPieceIndex, int beginPiecePosition, int endPieceIndex, int endPiecePosition})> filePieceRangeMap = {};

      List<int> buffer = List.filled(readBufferSize, 0);
      int curBytePosition = 0;
      for (int i = 0; i < _files.length; i++) {
        TorrentFile metadata = _files[i];
        File file = File(join(savePath, name, metadata.path));
        IOSink writeFile = file.openWrite(mode: FileMode.writeOnly);

        int beginBytePosition = curBytePosition;
        int endBytePosition = curBytePosition + metadata.length;

        curBytePosition += metadata.length;

        int readPosition = beginBytePosition;
        while (readPosition < endBytePosition) {
          await _readFile.setPosition(readPosition);
          await _readFile.readInto(buffer);
          if (endBytePosition - readPosition < readBufferSize) {
            writeFile.add(buffer.sublist(0, endBytePosition - readPosition));
          } else {
            writeFile.add(buffer);
          }

          readPosition += readBufferSize;
        }
        await writeFile.flush();
        await writeFile.close();
      }

      _fireOnCompleteSuccess();
    } on FileSystemException catch (e) {
      _fireOnCompleteFailed(e);
    }
  }
}

mixin FileManagerEventDispatcher {
  final Set<void Function(int pieceIndex, int begin, Uint8List block)> _onWriteSuccessCallbacks = {};
  final Set<void Function(int pieceIndex, int begin, Uint8List block, dynamic error)> _onWriteFailedCallbacks = {};
  final Set<void Function()> _onCompleteSuccessCallbacks = {};
  final Set<void Function(dynamic error)> _onCompleteFailedCallbacks = {};

  void addOnWriteSuccessCallback(void Function(int pieceIndex, int begin, Uint8List block) callback) {
    _onWriteSuccessCallbacks.add(callback);
  }

  bool removeOnWriteSuccessCallback(void Function(int pieceIndex, int begin, Uint8List block) callback) {
    return _onWriteSuccessCallbacks.remove(callback);
  }

  void _fireOnWriteSuccess(int pieceIndex, int begin, Uint8List block) {
    for (var callback in _onWriteSuccessCallbacks) {
      Timer.run(() {
        callback(pieceIndex, begin, block);
      });
    }
  }

  void addOnWriteFailedCallback(void Function(int pieceIndex, int begin, Uint8List block, dynamic error) callback) {
    _onWriteFailedCallbacks.add(callback);
  }

  bool removeOnWriteFailedCallback(void Function(int pieceIndex, int begin, Uint8List block, dynamic error) callback) {
    return _onWriteFailedCallbacks.remove(callback);
  }

  void _fireOnWriteFailed(int pieceIndex, int begin, Uint8List block, dynamic error) {
    for (var callback in _onWriteFailedCallbacks) {
      Timer.run(() {
        callback(pieceIndex, begin, block, error);
      });
    }
  }

  void addOnCompleteSuccessCallback(void Function() callback) {
    _onCompleteSuccessCallbacks.add(callback);
  }

  bool removeOnCompleteSuccessCallback(void Function() callback) {
    return _onCompleteSuccessCallbacks.remove(callback);
  }

  void _fireOnCompleteSuccess() {
    for (var callback in _onCompleteSuccessCallbacks) {
      Timer.run(() {
        callback();
      });
    }
  }

  void addOnCompleteFailedCallback(void Function(dynamic error) callback) {
    _onCompleteFailedCallbacks.add(callback);
  }

  bool removeOnCompleteFailedCallback(void Function(dynamic error) callback) {
    return _onCompleteFailedCallbacks.remove(callback);
  }

  void _fireOnCompleteFailed(dynamic error) {
    for (var callback in _onCompleteFailedCallbacks) {
      Timer.run(() {
        callback(error);
      });
    }
  }
}
