import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/model/torrent_exchange_info.dart';
import 'package:jtorrent/src/peer/piece/piece_provider.dart';

class PieceManager implements PieceProvider {
  final Torrent _torrent;

  PieceManager({required Torrent torrent}) : _torrent = torrent;

  List<PieceStatus> _pieces = [];

  @override
  List<bool> get pieces => _pieces.map((piece) => piece == PieceStatus.downloaded).toList();
}
