import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jtorrent/src/exception/tracker_exception.dart';
import 'package:jtorrent/src/extension/utf8_extension.dart';
import 'package:jtorrent/src/model/announce_response.dart';
import 'package:jtorrent/src/announce/announce_task.dart';
import 'package:jtorrent/src/announce/announce_handler.dart';
import 'package:jtorrent/src/util/common_util.dart';
import 'package:jtorrent_bencoding/jtorrent_bencoding.dart';

import '../model/peer.dart';
import '../model/announce_request_options.dart';

class HttpAnnounceHandler extends AnnounceHandler {
  const HttpAnnounceHandler();

  @override
  bool support(Uri tracker) {
    return tracker.scheme == 'http' || tracker.scheme == 'https';
  }

  @override
  Future<Uint8List> doAnnounce(AnnounceTask task, AnnounceRequestOptions requestOptions, Uri tracker) {
    String query = _generateQueryParameters(task, requestOptions);
    Uri announceWithQueryParams = tracker.replace(query: query);

    Future<HttpClientRequest> requestFuture = HttpClient().getUrl(announceWithQueryParams).timeout(task.connectTimeOut);
    Future<HttpClientResponse> responseFuture = requestFuture.then((req) => req.close()).timeout(task.receiveTimeOut);
    Future<List<List<int>>> rawSegmentBodyFuture = responseFuture.then((resp) => resp.toList());
    Future<List<int>> rawBodyFuture =
        rawSegmentBodyFuture.then((segments) => segments.fold<List<int>>([], (previousValue, element) => previousValue..addAll(element)));

    return rawBodyFuture.then((rawBody) => Uint8List.fromList(rawBody));
  }

  @override
  AnnounceResponse parseResponse(AnnounceTask task, AnnounceRequestOptions requestOptions, Uri tracker, Uint8List rawResponse) {
    dynamic response = bDecode(rawResponse);
    _checkResponseValid(response);

    String? failureReason = response['failure reason'] is Uint8List ? (response['failure reason'] as Uint8List).toUTF8 : null;
    if (failureReason != null) {
      return AnnounceResponse.failed(tracker: tracker, failureReason: failureReason);
    }

    String? warningMessage = response['warning message'] is Uint8List ? (response['warning message'] as Uint8List).toUTF8 : null;
    int? completePeerCount = response['complete'] is int ? response['complete'] : null;
    int? inCompletePeerCount = response['incomplete'] is int ? response['incomplete'] : null;
    int interval = response['interval'] is int ? response['interval'] : throw TrackerException('Invalid interval: ${response['interval']}');
    int? minInterval = response['min interval'] is int ? response['min interval'] : null;
    Set<Peer> peerSet = requestOptions.compact
        ? (_parseCompactPeers(response['peers'])..addAll(_parseCompactPeers6(response['peers6'])))
        : _parseUnCompactPeers(response['peers']);

    return AnnounceResponse.success(
      tracker: tracker,
      warning: warningMessage,
      completePeerCount: completePeerCount,
      inCompletePeerCount: inCompletePeerCount,
      interval: interval,
      minInterval: minInterval,
      peers: peerSet,
    );
  }

  Set<Peer> _parseCompactPeers(dynamic peers) {
    if (peers == null) {
      return {};
    }

    if (peers is! Uint8List) {
      throw TrackerException('Invalid peers: $peers');
    }

    if (peers.length % 6 != 0) {
      throw TrackerException('Invalid peers: $peers');
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
      throw TrackerException('Invalid peers6: $peers6');
    }

    if (peers6.length % 18 != 0) {
      throw TrackerException('Invalid peers6: $peers6');
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
      throw TrackerException('Invalid peers: $peers');
    }

    return peers.map((peer) {
      if (peer is! Map) {
        throw TrackerException('Invalid peer: $peer');
      }

      String? peerId = peer['peer id'] is Uint8List ? (peer['peer id'] as Uint8List).toUTF8 : null;
      String ip = peer['ip'] is Uint8List ? (peer['ip'] as Uint8List).toUTF8 : throw TrackerException('Invalid ip: ${peer['ip']}');
      int port = peer['port'] is int ? peer['port'] : throw TrackerException('Invalid port: ${peer['port']}');

      return Peer(peerId: peerId, ip: InternetAddress(ip), port: port);
    }).toSet();
  }

  String _generateQueryParameters(AnnounceTask task, AnnounceRequestOptions requestOptions) {
    Map<String, dynamic> queryParametersMap = {
      'info_hash': Uri.encodeQueryComponent(String.fromCharCodes(task.infoHash), encoding: latin1),
      'peer_id': Uri.encodeQueryComponent(String.fromCharCodes(CommonUtil.generateLocalPeerId(task.infoHash)), encoding: latin1),
      'port': requestOptions.localPort,
      if (requestOptions.localIp != null) 'localip': requestOptions.localIp!.address,
      'uploaded': requestOptions.uploaded,
      'downloaded': requestOptions.downloaded,
      'left': requestOptions.left,
      'compact': requestOptions.compact ? 1 : 0,
      'no_peer_id': requestOptions.noPeerId ? 1 : 0,
      'numwant': requestOptions.numWant,
      'event': requestOptions.type.name,
    };

    return queryParametersMap.entries.map((entry) => '${entry.key}=${entry.value}').join('&');
  }

  void _checkResponseValid(dynamic response) {
    if (response is! Map) {
      throw TrackerException('Invalid tracker response: $response');
    }

    if (response['failure reason'] != null) {
      if (response['failure reason'] is! Uint8List) {
        throw TrackerException('Invalid failure reason: ${response['failure reason']}');
      }
      return;
    }

    if (response['interval'] == null) {
      throw TrackerException('Tracker response without interval: $response');
    }
    if (response['peers'] == null) {
      throw TrackerException('Tracker response without peers: $response');
    }
  }
}
