class DHTException implements Exception {
  final String message;

  const DHTException(this.message);

  @override
  String toString() => 'DHTException: $message';
}
