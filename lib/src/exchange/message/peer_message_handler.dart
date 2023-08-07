import 'package:jtorrent/src/exchange/message/peer_meesage.dart';
import 'package:jtorrent/src/util/log_util.dart';

import '../../model/torrent_exchange_info.dart';
import '../connection/peer_connection.dart';

abstract interface class PeerMessageHandler {
  bool support(PeerMessage peerMessage);

  void handle(PeerConnection connection, PeerMessage peerMessage);
}

class IllegalPeerMessageHandler implements PeerMessageHandler {
  const IllegalPeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is IllegalMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.closeByIllegal();
  }
}

class HandshakePeerMessageHandler implements PeerMessageHandler {
  const HandshakePeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is HandshakeMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    if (connection.handshaked) {
      Log.info('${connection.peer.ip.address} handshake again');
    }
    connection.handshaked = true;
  }
}

class KeepAlivePeerMessageHandler implements PeerMessageHandler {
  const KeepAlivePeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is KeepAliveMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.lastActiveTime = DateTime.now();
  }
}

class ChokePeerMessageHandler implements PeerMessageHandler {
  const ChokePeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is ChokeMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.peerChoking = true;
  }
}

class UnChokePeerMessageHandler implements PeerMessageHandler {
  const UnChokePeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is UnChokeMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.peerChoking = false;
  }
}

class InterestedPeerMessageHandler implements PeerMessageHandler {
  const InterestedPeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is InterestedMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.peerInterested = true;
  }
}

class NotInterestedPeerMessageHandler implements PeerMessageHandler {
  const NotInterestedPeerMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is NotInterestedMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    connection.peerInterested = false;
  }
}

class StackHaveMessageHandler implements PeerMessageHandler {
  const StackHaveMessageHandler();

  @override
  bool support(PeerMessage peerMessage) {
    return peerMessage is StackHaveMessage;
  }

  @override
  void handle(PeerConnection connection, PeerMessage peerMessage) {
    assert(support(peerMessage));

    for (int pieceIndex in (peerMessage as StackHaveMessage).pieceIndexes) {
      if (pieceIndex >= connection.pieces.length) {
        Log.severe('StackHaveMessage pieceIndex $pieceIndex >= pieces.length ${connection.pieces.length}');
        continue;
      }
      connection.pieces[pieceIndex] = PieceStatus.downloaded;
    }
  }
}
