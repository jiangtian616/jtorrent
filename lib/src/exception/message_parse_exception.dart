class MessageParseException implements Exception {
  final String message;

  MessageParseException(this.message);

  @override
  String toString() => 'MessageParseException: $message';
}
