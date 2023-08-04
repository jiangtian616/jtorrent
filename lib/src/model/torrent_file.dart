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
