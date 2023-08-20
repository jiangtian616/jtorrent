import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:jtorrent/src/exception/torrent_parse_exception.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';
import 'package:jtorrent/src/extension/utf8_extension.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';

/// http://bittorrent.org/beps/bep_0003.html
class Torrent {
  /// Tracker addresses
  final List<List<Uri>> trackers;

  List<Uri> get allTrackers => trackers.expand((t) => t).toList().toList();

  /// Size of each piece in bytes, usually 2^18 = 256KB
  final int pieceLength;

  /// The "info hash" of the torrent, 20-bytes
  final Uint8List infoHash;

  /// The creation time of the torrent, in standard UNIX epoch format
  final DateTime? createTime;

  /// Free-form textual comments of the author
  final String? comment;

  /// Free-form name and version of the program used to create the .torrent
  final String? createdBy;

  /// File name(single file) or directory name(multiple files)
  final String name;

  /// File content described in torrent file
  final List<TorrentFile> files;

  /// SHA1 hashes of all pieces
  final List<Uint8List> pieceSha1s;

  List<String> get pieceSha1sInHex => pieceSha1s
      .map((charCodes) => charCodes.map((char) => char.toRadixString(16)).map((char) => char.length == 2 ? char : '0$char').toList().join())
      .toList();

  int get totalBytes => files.map((file) => file.length).reduce((value, element) => value + element);

  const Torrent({
    required this.trackers,
    required this.pieceLength,
    required this.infoHash,
    this.createTime,
    this.comment,
    this.createdBy,
    required this.name,
    required this.files,
    required this.pieceSha1s,
  });

  static Future<Torrent> fromFile(File file) {
    /// todo: isolate
    return file.readAsBytes().then((uint8list) => fromUint8List(uint8list));
  }

  static Torrent fromFileSync(File file) {
    return fromUint8List(file.readAsBytesSync());
  }

  static Torrent fromUint8List(Uint8List uint8list) {
    dynamic content = bDecode(uint8list);

    _checkContentValid(content);

    return Torrent(
      trackers: _parseAnnounces(content['announce'], content['announce-list']),
      pieceLength: _parsePieceLength(content['info']['piece length']),
      pieceSha1s: _parsePieceSha1s(content['info']['pieces']),
      name: _parseName(content['info']['name']),
      files: _parseFiles(content['info']['length'], content['info']['files']),
      infoHash: _parseInfoHash(content['info']),
      createTime: _parseCreateTime(content['creation date']),
      comment: _parseComment(content['comment']),
      createdBy: _parseCreateBy(content['created by']),
    );
  }

  static void _checkContentValid(dynamic content) {
    if (content is! Map) {
      throw TorrentParseException('Torrent content is not a Map, but a ${content.runtimeType}');
    }

    if (content['info'] is! Map) {
      throw TorrentParseException('Torrent content is invalid, [info] is not a Map, but a ${content['info'].runtimeType}');
    }

    if (content['info']['name'] == null) {
      throw TorrentParseException('Torrent content is invalid, [info.name] is missing');
    }
    if (content['info']['piece length'] == null) {
      throw TorrentParseException('Torrent content is invalid, [info.piece length] is missing');
    }
    if (content['info']['pieces'] == null) {
      throw TorrentParseException('Torrent content is invalid, [info.pieces] is missing');
    }
    if ((content['info']['files'] is! List || (content['info']['files'] as List).isEmpty) && content['info']['length'] == null) {
      throw TorrentParseException('Torrent content is invalid, [info.files] and [info.length] is missing');
    }
  }

  static List<List<Uri>> _parseAnnounces(dynamic announce, dynamic announceList) {
    List<List<Uri>> trackers = [];

    /// If the "announce-list" key is present, we will ignore the "announce" key and only use the URLs in "announce-list"
    if (announceList is List && announceList.isNotEmpty) {
      for (dynamic announceTier in announceList) {
        if (announceTier is List && announceTier.isNotEmpty) {
          List<Uri> trackerTiers = [];
          for (dynamic announce in announceTier) {
            if (announce is Uint8List) {
              try {
                trackerTiers.add(Uri.parse(announce.toUTF8));
              } catch (e) {
                throw TorrentParseException('Torrent content is invalid, [announce] is invalid, announce: $announce');
              }
            }
          }
          trackers.add(trackerTiers);
        }
      }
      return trackers;
    }

    if (announce is Uint8List) {
      try {
        trackers.add([Uri.parse(announce.toUTF8)]);
      } catch (e) {
        throw TorrentParseException('Torrent content is invalid, [announce] is not a valid URI, announce: $announce');
      }
    }
    return trackers;
  }

  static int _parsePieceLength(dynamic pieceLength) {
    if (pieceLength is! int) {
      throw TorrentParseException(
          'Torrent content is invalid, [pieceLength] is not a int, pieceLength: $pieceLength is a ${pieceLength.runtimeType}');
    }

    if (pieceLength & 1 == 1) {
      throw TorrentParseException('Torrent content is invalid, [pieceLength] is not a power of 2, pieceLength: $pieceLength');
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

  static List<TorrentFile> _parseFiles(dynamic length, dynamic files) {
    int? _length = _parseLength(length);

    /// Single file mode
    if (files is! List || files.isEmpty) {
      return [TorrentFile(path: '', length: _length!)];
    }

    /// Multiple file mode
    List<TorrentFile> torrentFiles = [];
    for (dynamic file in files) {
      if (file is! Map) {
        throw TorrentParseException('Torrent content is invalid, [files.file] is not a Map, file: $file is a ${file.runtimeType}');
      }

      if (file['path'] == null) {
        throw TorrentParseException('Torrent content is invalid, [files.path] is missing');
      }
      if (file['length'] == null) {
        throw TorrentParseException('Torrent content is invalid, [files.length] is missing');
      }

      torrentFiles.add(
        TorrentFile(
          path: _parsePath(file['path']),
          length: _parseFileLength(file['length']),
        ),
      );
    }

    return torrentFiles;
  }

  static Uint8List _parseInfoHash(Map info) {
    return Uint8List.fromList(sha1.convert(bEncode(info)).bytes);
  }

  static String _parseName(dynamic name) {
    if (name is! Uint8List) {
      throw TorrentParseException('Torrent content is invalid, [name] is not a Uint8List, name: $name is a ${name.runtimeType}');
    }

    return name.toUTF8;
  }

  static int? _parseLength(dynamic length) {
    if (length is! int) {
      return null;
    }

    return length;
  }

  static String _parsePath(dynamic path) {
    if (path is! Uint8List) {
      throw TorrentParseException('Torrent content is invalid, [path] is not a Uint8List, path: $path is a ${path.runtimeType}');
    }

    return path.toUTF8;
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

    return comment.toUTF8;
  }

  static String? _parseCreateBy(dynamic createBy) {
    if (createBy is! Uint8List) {
      return null;
    }

    return createBy.toUTF8;
  }

  @override
  String toString() {
    return 'Torrent{announces: $trackers, pieceLength: $pieceLength, infoHash: ${infoHash.toHexString}, createTime: $createTime, comment: $comment, createdBy: $createdBy, files: $files, pieceSha1s: $pieceSha1sInHex}';
  }
}

/// File content described in torrent file
class TorrentFile {
  /// File relative path, the last of which is the actual file name
  final String path;

  /// The length of the file in bytes
  final int length;

  const TorrentFile({required this.path, required this.length});

  @override
  String toString() {
    return 'TorrentFile{path: $path, length: $length}';
  }
}
