import 'dart:async';

class SerialRunner<R> {
  final StreamController<({FutureOr<R> Function() operation, Completer<R> completer})> _controller =
      StreamController<({FutureOr<R> Function() operation, Completer<R> completer})>();

  late final StreamSubscription<({FutureOr<R> Function() operation, Completer<R> completer})> _subscription;

  SerialRunner() {
    _subscription = _controller.stream.listen((({FutureOr<R> Function() operation, Completer<R> completer}) record) async {
      _subscription.pause();
      R result = await record.operation.call();
      record.completer.complete(result);
      _subscription.resume();
    });
  }

  Future<R> run(FutureOr<R> Function() operation) async {
    Completer<R> completer = Completer<R>();
    _controller.sink.add((operation: operation, completer: completer));
    return completer.future;
  }

  void dispose() {
    _subscription.cancel();
    _controller.close();
  }
}
