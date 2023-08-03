import 'package:jtorrent/src/model/torrent_file.dart';

/// http://bittorrent.org/beps/bep_0003.html
class Torrent {
  Set<Uri>? _announces;

  /// Single file : name of the file
  /// Multiple files : name of the directory
  String? name;

  final List<TorrentFile> files;
}
