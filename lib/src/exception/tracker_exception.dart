class TrackerException implements Exception {
  final String message;

  TrackerException(this.message);

  @override
  String toString() => 'TrackerException: $message';
}