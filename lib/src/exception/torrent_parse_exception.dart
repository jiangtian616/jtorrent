class TorrentParseException implements Exception {
  final String message;

  TorrentParseException(this.message);

  @override
  String toString() => 'TorrentParseException: $message';
}
