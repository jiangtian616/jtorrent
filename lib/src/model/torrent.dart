import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/exception/torrent_parse_exception.dart';
import 'package:jtorrent/src/model/torrent_file.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';
import 'package:path/path.dart';

/// http://bittorrent.org/beps/bep_0003.html
class Torrent {
  /// Tracker addresses
  final List<List<Uri>> announces;

  /// Size of each piece in bytes
  final int pieceLength;

  /// SHA1 hashes of all pieces
  final List<Uint8List> pieceSha1s;

  List<String> get pieceSha1sInHex => pieceSha1s.map((charCodes) => charCodes.map((char) => char.toRadixString(16)).map((char) => char.length == 2 ? char : '0$char').toList().join()).toList();

  /// File content described in torrent file
  final List<TorrentFile> files;

  /// The creation time of the torrent, in standard UNIX epoch format
  final DateTime? createTime;

  /// Free-form textual comments of the author
  final String? comment;

  /// Free-form name and version of the program used to create the .torrent
  final String? createdBy;

  const Torrent({
    required this.announces,
    required this.pieceLength,
    required this.pieceSha1s,
    required this.files,
    this.createTime,
    this.comment,
    this.createdBy,
  });

  static Future<Torrent> fromFile(File file) {
    return file.readAsBytes().then((uint8list) => fromUint8List(uint8list));
  }

  static Torrent fromFileSync(File file) {
    return fromUint8List(file.readAsBytesSync());
  }

  static Torrent fromUint8List(Uint8List uint8list) {
    dynamic content = bDecode(uint8list);

    _checkContentValid(content);

    return Torrent(
      announces: _parseAnnounces(content['announce'], content['announce-list']),
      pieceLength: _parsePieceLength(content['info']['piece length']),
      pieceSha1s: _parsePieceSha1s(content['info']['pieces']),
      files: _parseFiles(content['info']['name'], content['info']['length'], content['info']['files']),
      createTime: _parseCreateTime(content['creation date']),
      comment: _parseComment(content['comment']),
      createdBy: _parseCreateBy(content['created by']),
    );
  }

  static void _checkContentValid(dynamic content) {
    if (content is! Map) {
      throw TorrentParseException('Torrent content is not a Map, but a ${content.runtimeType}');
    }

    if (!content.containsKey('info')) {
      throw TorrentParseException('Torrent content is invalid, [info] is missing');
    }

    if (!content['info'].containsKey('name')) {
      throw TorrentParseException('Torrent content is invalid, [info.name] is missing');
    }
    if (!content['info'].containsKey('piece length')) {
      throw TorrentParseException('Torrent content is invalid, [info.piece length] is missing');
    }
    if (!content['info'].containsKey('pieces')) {
      throw TorrentParseException('Torrent content is invalid, [info.pieces] is missing');
    }
    if ((content['info']['files'] is! List || (content['info']['files'] as List).isEmpty) && !content['info'].containsKey('length')) {
      throw TorrentParseException('Torrent content is invalid, [info.files] and [info.length] is missing');
    }
  }

  static List<List<Uri>> _parseAnnounces(dynamic announce, dynamic announceList) {
    List<List<Uri>> announces = [];

    /// If the "announce-list" key is present, we will ignore the "announce" key and only use the URLs in "announce-list"
    if (announceList is List && announceList.isNotEmpty) {
      for (dynamic announceTier in announceList) {
        if (announceTier is List && announceTier.isNotEmpty && announceTier.first is Uint8List) {
          try {
            announces.add(announceTier.map((a) => Uri.parse(utf8.decode(a))).toList());
          } catch (e) {
            throw TorrentParseException('Torrent content is invalid, [announceList] is invalid, announceTier: $announceTier');
          }
        }
      }
      return announces;
    }

    if (announce is Uint8List) {
      try {
        announces.add([Uri.parse(utf8.decode(announce))]);
      } catch (e) {
        throw TorrentParseException('Torrent content is invalid, [announce] is not a valid URI, announce: $announce');
      }
    }
    return announces;
  }

  static int _parsePieceLength(dynamic pieceLength) {
    if (pieceLength is! int) {
      throw TorrentParseException('Torrent content is invalid, [pieceLength] is not a int, pieceLength: $pieceLength is a ${pieceLength.runtimeType}');
    }

    return pieceLength;
  }

  static List<Uint8List> _parsePieceSha1s(dynamic pieces) {
    if (pieces is! Uint8List) {
      throw TorrentParseException('Torrent content is invalid, [pieces] is not a Uint8List, pieces: $pieces is a ${pieces.runtimeType}');
    }

    if (pieces.length % 20 != 0) {
      throw TorrentParseException('Torrent content is invalid, [pieces] is not a valid SHA1 list, length ${pieces.length} is not a multiple of 20');
    }

    List<Uint8List> pieceSha1s = [];
    for (int i = 0; i < pieces.length; i += 20) {
      pieceSha1s.add(pieces.sublist(i, i + 20));
    }

    return pieceSha1s;
  }

  static List<TorrentFile> _parseFiles(dynamic name, dynamic length, dynamic files) {
    String _name = _parseName(name);
    int? _length = _parseLength(length);

    /// Single file mode
    if (files is! List || files.isEmpty) {
      return [TorrentFile(path: _name, length: _length!)];
    }

    /// Multiple file mode
    List<TorrentFile> torrentFiles = [];
    for (dynamic file in files) {
      if (file is! Map) {
        throw TorrentParseException('Torrent content is invalid, [files.file] is not a Map, file: $file is a ${file.runtimeType}');
      }

      if (!file.containsKey('path')) {
        throw TorrentParseException('Torrent content is invalid, [files.path] is missing');
      }
      if (!file.containsKey('length')) {
        throw TorrentParseException('Torrent content is invalid, [files.length] is missing');
      }

      torrentFiles.add(
        TorrentFile(
          path: join(_name, _parsePath(file['path'])),
          length: _parseFileLength(file['length']),
        ),
      );
    }

    return torrentFiles;
  }

  static String _parseName(dynamic name) {
    if (name is! Uint8List) {
      throw TorrentParseException('Torrent content is invalid, [name] is not a String, name: $name is a ${name.runtimeType}');
    }

    try {
      return utf8.decode(name);
    } catch (e) {
      throw TorrentParseException('Torrent content is invalid, [name] is invalid, name: $name');
    }
  }

  static int? _parseLength(dynamic length) {
    if (length is! int) {
      return null;
    }

    return length;
  }

  static String _parsePath(dynamic path) {
    if (path is! Uint8List) {
      throw TorrentParseException('Torrent content is invalid, [path] is not a String, path: $path is a ${path.runtimeType}');
    }

    try {
      return utf8.decode(path);
    } catch (e) {
      throw TorrentParseException('Torrent content is invalid, [path] is invalid, path: $path');
    }
  }

  static int _parseFileLength(dynamic length) {
    if (length is! int) {
      throw TorrentParseException('Torrent content is invalid, [files.file.length] is not a int, length: $length is a ${length.runtimeType}');
    }

    return length;
  }

  static DateTime? _parseCreateTime(dynamic timeStamp) {
    if (timeStamp is! int) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timeStamp * 1000);
  }

  static String? _parseComment(dynamic comment) {
    if (comment is! Uint8List) {
      return null;
    }

    try {
      return utf8.decode(comment);
    } catch (e) {
      throw TorrentParseException('Torrent content is invalid, [comment] is invalid, comment: $comment');
    }
  }

  static String? _parseCreateBy(dynamic createBy) {
    if (createBy is! Uint8List) {
      return null;
    }

    try {
      return utf8.decode(createBy);
    } catch (e) {
      throw TorrentParseException('Torrent content is invalid, [createBy] is invalid, comment: $createBy');
    }
  }

  @override
  String toString() {
    return 'Torrent{announces: $announces, pieceLength: $pieceLength, pieceSha1sInHex: $pieceSha1sInHex, files: $files, createTime: $createTime, comment: $comment, createdBy: $createdBy}';
  }
}
