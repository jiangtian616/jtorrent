import 'package:logging/logging.dart';

class Log {
  static final Logger _logger = Logger('jtorrent')
    ..level = Level.FINE
    ..onRecord.listen((LogRecord record) {
      print(record);
    });

  set level(Level level) {
    _logger.level = level;
  }

  static void finest(Object? message, [Object? error, StackTrace? stackTrace]) => _logger.log(Level.FINEST, message, error, stackTrace);
  
  static void fine(Object? message, [Object? error, StackTrace? stackTrace]) => _logger.log(Level.FINE, message, error, stackTrace);

  static void info(Object? message, [Object? error, StackTrace? stackTrace]) => _logger.log(Level.INFO, message, error, stackTrace);

  static void warning(Object? message, [Object? error, StackTrace? stackTrace]) => _logger.log(Level.WARNING, message, error, stackTrace);

  static void severe(Object? message, [Object? error, StackTrace? stackTrace]) => _logger.log(Level.SEVERE, message, error, stackTrace);
}
