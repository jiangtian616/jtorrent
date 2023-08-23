import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:jtorrent/src/extension/uint8_list_extension.dart';

import '../../constant/common_constants.dart';
import 'node_distance.dart';

class NodeId {
  final List<int> id;

  NodeId({required List<int> id})
      : assert(id.length == CommonConstants.nodeIdLength),
        assert(id.every((element) => element >= 0 && element <= 256)),
        id = List.unmodifiable(id);

  static NodeId random() {
    Random random = Random();
    List<int> id = List.generate(CommonConstants.nodeIdLength, (index) => random.nextInt(1 << 8));
    return NodeId(id: id);
  }

  static NodeId min = NodeId(id: List.generate(CommonConstants.nodeIdLength, (index) => 0));
  static NodeId max = NodeId(id: [256] + List.generate(CommonConstants.nodeIdLength - 1, (index) => 0));

  NodeDistance distanceWith(NodeId other) {
    return NodeDistance(xor(other));
  }

  List<int> xor(NodeId other) {
    Uint8List result = Uint8List(CommonConstants.nodeIdLength);
    for (var i = 0; i < CommonConstants.nodeIdLength; i++) {
      result[i] = id[i] ^ other.id[i];
    }
    return result;
  }

  @override
  int get hashCode => id.toHexString.hashCode;

  @override
  bool operator ==(other) {
    return other is NodeId && ListEquality<int>().equals(id, other.id);
  }

  bool operator >=(other) {
    if (other is! NodeId) {
      throw '${other.runtimeType} is not NodeId';
    }

    for (var i = 0; i < id.length; i++) {
      if (id[i] > other.id[i]) {
        return true;
      } else if (id[i] < other.id[i]) {
        return false;
      }
    }

    return true;
  }

  bool operator >(other) {
    if (other is! NodeId) {
      throw '${other.runtimeType} is not NodeId';
    }

    for (var i = 0; i < id.length; i++) {
      if (id[i] > other.id[i]) {
        return true;
      } else if (id[i] < other.id[i]) {
        return false;
      }
    }

    return false;
  }

  bool operator <=(other) {
    return !(this > other);
  }

  bool operator <(other) {
    return !(this >= other);
  }

  static NodeId middleNodeId(NodeId a, NodeId b) {
    if (a == b) {
      return NodeId(id: a.id);
    }

    if (a > b) {
      return middleNodeId(b, a);
    }

    List<int> result = List.generate(CommonConstants.nodeIdLength, (index) => 0);

    for (var i = 0; i < CommonConstants.nodeIdLength; i++) {
      result[i] = a.id[i] + b.id[i];
    }

    bool addHighBit = false;
    for (var i = 0; i < CommonConstants.nodeIdLength; i++) {
      if (addHighBit) {
        result[i] += (1 << 8);
      }

      addHighBit = (result[i] & 1) == 1;

      result[i] >>= 1;
    }

    return NodeId(id: result);
  }

  @override
  String toString() {
    return id.toHexString;
  }
}
