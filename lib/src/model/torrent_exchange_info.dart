import 'package:jtorrent/src/model/peer.dart';
import 'package:jtorrent/src/model/torrent.dart';

import '../exchange/connection/peer_connection.dart';

class TorrentExchangeInfo {
  final Torrent torrent;

  final Set<Peer> allKnownPeers;

  final List<PieceStatus> pieces;

  final Map<Peer, PeerConnection> peerConnectionMap = {};

  TorrentExchangeInfo({required this.torrent, required Set<Peer> peers})
      : allKnownPeers = Set.from(peers),
        pieces = List.filled(torrent.pieceSha1s.length, PieceStatus.notDownloaded);
}

enum PieceStatus { notDownloaded, downloading, downloaded }
