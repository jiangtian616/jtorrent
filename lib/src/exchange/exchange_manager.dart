import 'dart:async';
import 'dart:typed_data';

import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/util/log_util.dart';

import '../model/torrent_exchange_info.dart';
import '../model/peer.dart';
import 'connection/peer_connection.dart';
import 'message/peer_meesage.dart';

class ExchangeManager {
  final Map<Uint8List, TorrentExchangeInfo> _torrentExchangeMap = {};

  void addNewTorrentTask(Torrent torrent, Set<Peer> peers) {
    TorrentExchangeInfo? exchangeStatusInfo = _torrentExchangeMap[torrent.infoHash];

    if (exchangeStatusInfo == null) {
      exchangeStatusInfo = TorrentExchangeInfo(torrent: torrent, peers: peers);
      _torrentExchangeMap[torrent.infoHash] = exchangeStatusInfo;
    } else {
      exchangeStatusInfo.allKnownPeers.addAll(peers);
    }

    for (Peer peer in exchangeStatusInfo.allKnownPeers) {
      Future<PeerConnection> connectionFuture = _openConnection(exchangeStatusInfo, peer);
      Future<void> handshakeFuture = connectionFuture.then((connection) => connection.sendHandShake());
      handshakeFuture.onError((error, stackTrace) => Log.warning('Connection error: $peer'));
    }
  }

  Future<PeerConnection> _openConnection(TorrentExchangeInfo torrentExchangeInfo, Peer peer) async {
    PeerConnection? connection = torrentExchangeInfo.peerConnectionMap[peer];
    if (connection == null) {
      connection = _generatePeerConnection(torrentExchangeInfo, peer);
      torrentExchangeInfo.peerConnectionMap[peer] = connection;
    }

    if (connection.connecting || connection.connected) {
      return connection;
    }

    await connection.connect();
    connection.listen((PeerMessage data) => _onPeerMessage(connection!, data));

    return connection;
  }

  PeerConnection _generatePeerConnection(TorrentExchangeInfo exchangeStatusInfo, Peer peer) {
    /// todo
    return TcpPeerConnection(infoHash: exchangeStatusInfo.torrent.infoHash, peer: peer);
  }

  void _onPeerMessage(PeerConnection connection, PeerMessage message) {
    assert(_torrentExchangeMap[connection.infoHash] != null);
    assert(_torrentExchangeMap[connection.infoHash]!.peerConnectionMap[connection.peer] == connection);

    Log.fine('${connection.peer.ip.address} message: $message');

    if (message is IllegalMessage) {
      connection.closeByIllegal();
    }
  }
}
