import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/announce/tracker.dart';
import 'package:jtorrent/src/extension/utf8_extension.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';

import '../exception/announce_exception.dart';
import '../model/announce_response.dart';
import '../model/peer.dart';
import 'announce_request_options_provider.dart';

class HttpTracker extends Tracker {
  HttpTracker({required Uri uri, required AnnounceConfigProvider announceConfigProvider})
      : super(uri: uri, announceConfigProvider: announceConfigProvider);

  HttpClient? _httpClient;
  HttpClientRequest? _request;

  bool _closed = false;

  Map<String, dynamic> get _announceRequestOptions => {
        'info_hash': Uri.encodeQueryComponent(String.fromCharCodes(super.announceConfigProvider.infoHash), encoding: latin1),
        'peer_id': Uri.encodeQueryComponent(String.fromCharCodes(super.announceConfigProvider.peerId), encoding: latin1),
        'port': super.announceConfigProvider.localPort,
        if (super.announceConfigProvider.localIp != null) 'localip': super.announceConfigProvider.localIp!.address,
        'uploaded': super.announceConfigProvider.uploaded,
        'downloaded': super.announceConfigProvider.downloaded,
        'left': super.announceConfigProvider.left,
        'compact': super.announceConfigProvider.compact ? 1 : 0,
        'no_peer_id': super.announceConfigProvider.noPeerId ? 1 : 0,
        'numwant': super.announceConfigProvider.numWant,
      };

  @override
  Future<void> close({bool force = false}) async {
    if (_closed) return;
    _closed = true;

    _request?.abort();
    _request = null;
    _httpClient?.close(force: force);
    _httpClient = null;
  }

  @override
  Future<AnnounceResponse> announceOnce(AnnounceEventType type) {
    Map<String, dynamic> options = _announceRequestOptions;

    return _doAnnounce(type, options).then((rawResponse) => _parseResponse(type, options, rawResponse));
  }

  @override
  Future<Uint8List> _doAnnounce(AnnounceEventType type, Map<String, dynamic> options) async {
    String query = options.entries.map((entry) => '${entry.key}=${entry.value}').join('&');
    Uri announceWithQueryParams = super.uri.replace(query: query);

    _httpClient ??= HttpClient();
    _request?.abort();

    _request = await _httpClient!.getUrl(announceWithQueryParams).timeout(super.announceConfigProvider.announceConnectTimeout);
    HttpClientResponse response = await _request!.close().timeout(super.announceConfigProvider.announceReceiveTimeout);

    List<int> rawBody =
        await response.toList().then((segments) => segments.fold<List<int>>([], (previousValue, element) => previousValue..addAll(element)));

    return Uint8List.fromList(rawBody);
  }

  @override
  AnnounceResponse _parseResponse(AnnounceEventType type, Map<String, dynamic> options, Uint8List rawResponse) {
    dynamic response = bDecode(rawResponse);
    _checkResponseValid(response);

    String? failureReason = response['failure reason'] is Uint8List ? (response['failure reason'] as Uint8List).toUTF8 : null;
    if (failureReason != null) {
      return AnnounceResponse.failed(failureReason: failureReason);
    }

    String? warningMessage = response['warning message'] is Uint8List ? (response['warning message'] as Uint8List).toUTF8 : null;
    int? completePeerCount = response['complete'] is int ? response['complete'] : null;
    int? inCompletePeerCount = response['incomplete'] is int ? response['incomplete'] : null;
    int interval = response['interval'] is int ? response['interval'] : throw AnnounceException('Invalid interval: ${response['interval']}');
    int? minInterval = response['min interval'] is int ? response['min interval'] : null;
    Set<Peer> peerSet = options['compact'] == 1
        ? (_parseCompactPeers(response['peers'])..addAll(_parseCompactPeers6(response['peers6'])))
        : _parseUnCompactPeers(response['peers']);

    return AnnounceResponse.success(
      warning: warningMessage,
      completePeerCount: completePeerCount,
      inCompletePeerCount: inCompletePeerCount,
      interval: interval,
      minInterval: minInterval,
      peers: peerSet,
    );
  }

  void _checkResponseValid(dynamic response) {
    if (response is! Map) {
      throw AnnounceException('Invalid tracker response: $response');
    }

    if (response['failure reason'] != null) {
      if (response['failure reason'] is! Uint8List) {
        throw AnnounceException('Invalid failure reason: ${response['failure reason']}');
      }
      return;
    }

    if (response['interval'] == null) {
      throw AnnounceException('Tracker response without interval: $response');
    }
    if (response['peers'] == null) {
      throw AnnounceException('Tracker response without peers: $response');
    }
  }

  Set<Peer> _parseCompactPeers(dynamic peers) {
    if (peers == null) {
      return {};
    }

    if (peers is! Uint8List) {
      throw AnnounceException('Invalid peers: $peers');
    }

    if (peers.length % 6 != 0) {
      throw AnnounceException('Invalid peers: $peers');
    }

    Set<Peer> peerSet = {};
    for (int i = 0; i < peers.length; i += 6) {
      InternetAddress ip = InternetAddress.fromRawAddress(peers.sublist(i, i + 4), type: InternetAddressType.IPv4);
      int port = peers[i + 4] * (2 << 7) + peers[i + 5];
      peerSet.add(Peer(ip: ip, port: port));
    }

    return peerSet;
  }

  Set<Peer> _parseCompactPeers6(dynamic peers6) {
    if (peers6 == null) {
      return {};
    }

    if (peers6 is! Uint8List) {
      throw AnnounceException('Invalid peers6: $peers6');
    }

    if (peers6.length % 18 != 0) {
      throw AnnounceException('Invalid peers6: $peers6');
    }

    Set<Peer> peerSet = {};
    for (int i = 0; i < peers6.length; i += 18) {
      InternetAddress ip = InternetAddress.fromRawAddress(peers6.sublist(i, i + 16), type: InternetAddressType.IPv6);
      int port = peers6[i + 16] * (1 << 8) + peers6[i + 17];
      peerSet.add(Peer(ip: ip, port: port));
    }

    return peerSet;
  }

  Set<Peer> _parseUnCompactPeers(dynamic peers) {
    if (peers == null) {
      return {};
    }

    if (peers is! List) {
      throw AnnounceException('Invalid peers: $peers');
    }

    return peers.map((peer) {
      if (peer is! Map) {
        throw AnnounceException('Invalid peer: $peer');
      }

      String? peerId = peer['peer id'] is Uint8List ? (peer['peer id'] as Uint8List).toUTF8 : null;
      String ip = peer['ip'] is Uint8List ? (peer['ip'] as Uint8List).toUTF8 : throw AnnounceException('Invalid ip: ${peer['ip']}');
      int port = peer['port'] is int ? peer['port'] : throw AnnounceException('Invalid port: ${peer['port']}');

      return Peer(peerId: peerId, ip: InternetAddress(ip), port: port);
    }).toSet();
  }
}
