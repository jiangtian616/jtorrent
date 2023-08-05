import 'package:jtorrent/src/model/peer.dart';

/// Correspond to tracker reply when we ask for torrent file info
class AnnounceResponse {
  final bool success;

  final Uri tracker;

  final String? failureReason;

  final AnnounceSuccessResponse? result;

  AnnounceResponse.success({
    required this.tracker,
    String? warning,
    int? completePeerCount,
    int? inCompletePeerCount,
    required int interval,
    int? minInterval,
    required Set<Peer> peers,
  })  : success = true,
        failureReason = null,
        result = AnnounceSuccessResponse(
          warning: warning,
          completePeerCount: completePeerCount,
          inCompletePeerCount: inCompletePeerCount,
          interval: interval,
          minInterval: minInterval,
          peers: peers,
        );

  AnnounceResponse.failed({required this.tracker, required this.failureReason})
      : success = false,
        result = null;

  @override
  String toString() {
    return 'TrackerResponse{success: $success, failureReason: $failureReason, result: $result}';
  }
}

class AnnounceSuccessResponse {
  /// Readable warning message
  final String? warning;

  /// Number of peers who have downloaded the whole file
  final int? completePeerCount;

  /// Number of peers who have not downloaded the whole file
  final int? inCompletePeerCount;

  /// Interval in seconds that the client should wait between sending regular requests to the tracker
  final int interval;

  /// Minimum announce interval. Clients must not reannounce more frequently than this if present.
  final int? minInterval;

  /// peer info
  final Set<Peer> peers;

  AnnounceSuccessResponse({
    this.warning,
    this.completePeerCount,
    this.inCompletePeerCount,
    required this.interval,
    this.minInterval,
    required this.peers,
  });

  @override
  String toString() {
    return 'TrackerSuccessResponse{warning: $warning, completePeerCount: $completePeerCount, inCompletePeerCount: $inCompletePeerCount, interval: $interval, minInterval: $minInterval, peers: $peers}';
  }
}
