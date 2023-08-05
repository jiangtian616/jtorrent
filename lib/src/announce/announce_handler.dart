import 'dart:typed_data';

import 'package:jtorrent/src/announce/announce_task.dart';

import '../model/announce_request_options.dart';
import '../model/announce_response.dart';

abstract class AnnounceHandler {
  const AnnounceHandler();

  /// Check if this tracker handler support the tracker server
  bool support(Uri tracker);

  /// Send a tracker request to target tracker server to get torrent information
  Future<AnnounceResponse> announce(AnnounceTask task, AnnounceRequestOptions requestOptions, Uri tracker) {
    assert(support(tracker));

    Future<Uint8List> responseFuture = doAnnounce(task, requestOptions, tracker);

    return responseFuture.then((rawResponse) => parseResponse(task, requestOptions, tracker, rawResponse));
  }

  Future<Uint8List> doAnnounce(AnnounceTask task, AnnounceRequestOptions requestOptions, Uri tracker);

  AnnounceResponse parseResponse(AnnounceTask task, AnnounceRequestOptions requestOptions, Uri tracker, Uint8List rawResponse);
}
