import 'package:jtorrent/src/model/peer.dart';

class TorrentAnnounceInfo {
  /// Tracker server this announce info comes from
  final Uri tracker;

  /// Number of peers who have downloaded the whole file
  final int? completePeerCount;

  /// Number of peers who have not downloaded the whole file
  final int? incompletePeerCount;

  /// peer info
  final Set<Peer> peers;

  const TorrentAnnounceInfo({required this.tracker, this.completePeerCount, this.incompletePeerCount, required this.peers});

  @override
  String toString() {
    return 'TorrentAnnounceInfo{tracker: $tracker, completePeerCount: $completePeerCount, incompletePeerCount: $incompletePeerCount, peers: $peers}';
  }
}
