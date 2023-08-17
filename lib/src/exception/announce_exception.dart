class AnnounceException implements Exception {
  final String message;

  const AnnounceException(this.message);

  @override
  String toString() => 'TrackerException: $message';
}
