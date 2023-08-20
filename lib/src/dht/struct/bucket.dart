import 'dart:io';

import 'package:jtorrent/src/dht/struct/tree_node.dart';
import 'package:jtorrent/src/exception/dht_exception.dart';

import 'dht_node.dart';
import 'node_id.dart';

class Bucket extends TreeNode {
  static const maxBucketSize = 8;

  final Set<DHTNode> _nodes = {};

  final NodeId rangeBegin;

  final NodeId rangeEnd;

  Bucket({required this.rangeBegin, required this.rangeEnd});

  Bucket? get leftBucket => leftChild as Bucket?;

  Bucket? get rightBucket => rightChild as Bucket?;

  bool get isParent {
    if (leftChild == null && rightChild == null) {
      return false;
    }

    assert(leftChild != null && rightChild != null);
    assert(_nodes.isNotEmpty);

    return true;
  }

  bool canAddNode(DHTNode node) {
    assert(node.bucket == null);

    if (node.id < rangeBegin || node.id > rangeEnd) {
      throw DHTException('Node ${node.id} is out of bucket range $rangeBegin - $rangeEnd');
    }

    if (isParent) {
      if (node.id < leftBucket!.rangeEnd) {
        return leftBucket!.canAddNode(node);
      } else {
        return rightBucket!.canAddNode(node);
      }
    } else {
      if (_nodes.length >= maxBucketSize) {
        return false;
      }

      if (_nodes.contains(node)) {
        return false;
      }

      return true;
    }
  }

  bool addNode(DHTNode node) {
    assert(node.bucket == null);

    if (node.id < rangeBegin || node.id > rangeEnd) {
      throw DHTException('Node ${node.id} is out of bucket range $rangeBegin - $rangeEnd');
    }

    if (isParent) {
      bool childAdded;
      if (node.id < leftBucket!.rangeEnd) {
        childAdded = leftBucket!.addNode(node);
      } else {
        childAdded = rightBucket!.addNode(node);
      }

      if (childAdded) {
        _nodes.add(node);
      }

      return childAdded;
    } else {
      if (_nodes.length >= maxBucketSize) {
        return false;
      }

      if (!_nodes.add(node)) {
        return false;
      }

      node.bucket = this;
      return true;
    }
  }

  void split() {
    if (isParent) {
      throw DHTException('Bucket is already splitted');
    }

    NodeId middle = NodeId.middleNodeId(rangeBegin, rangeEnd);

    leftChild = Bucket(rangeBegin: rangeBegin, rangeEnd: middle);
    rightChild = Bucket(rangeBegin: middle, rangeEnd: rangeEnd);

    for (DHTNode node in _nodes) {
      if (node.id < middle) {
        leftBucket!.addNode(node);
      } else {
        rightBucket!.addNode(node);
      }
    }
  }

  bool containNodeAddress(InternetAddress ip, int port) {
    for (DHTNode node in _nodes) {
      if (node.address == ip && node.port == port) {
        return true;
      }
    }

    return false;
  }
}
