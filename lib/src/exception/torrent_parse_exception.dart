class TorrentParseException implements Exception {
  final String message;

  const TorrentParseException(this.message);

  @override
  String toString() => 'TorrentParseException: $message';
}
