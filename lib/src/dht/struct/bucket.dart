import 'package:jtorrent/src/dht/struct/node.dart';
import 'package:jtorrent/src/dht/struct/tree_node.dart';
import 'package:jtorrent/src/exception/dht_exception.dart';

import 'node_id.dart';

class Bucket<T extends AbstractNode> extends TreeNode {
  static const int maxBucketSize = 8;

  final Set<T> _nodes = {};

  final NodeId rangeBegin;

  final NodeId rangeEnd;

  int get size => _nodes.length;

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

  bool canAddNode(T node) {
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

  bool addNode(T node) {
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

    if (middle == rangeBegin || middle == rangeEnd) {
      throw DHTException('Bucket is too small to split');
    }

    leftChild = Bucket(rangeBegin: rangeBegin, rangeEnd: middle);
    rightChild = Bucket(rangeBegin: middle, rangeEnd: rangeEnd);

    for (T node in _nodes) {
      if (node.id < middle) {
        leftBucket!.addNode(node);
      } else {
        rightBucket!.addNode(node);
      }
    }
  }

  bool contains(bool Function(T node) test) {
    return _nodes.any(test);
  }

  bool containsNode(T node) {
    return _nodes.contains(node);
  }

  T? getNode(T node) {
    return _nodes.lookup(node);
  }
}
