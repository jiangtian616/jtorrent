import 'package:jtorrent/src/dht/struct/node.dart';
import 'package:jtorrent/src/dht/struct/tree_node.dart';
import 'package:jtorrent/src/exception/dht_exception.dart';

import 'node_id.dart';

class Bucket<T extends AbstractNode> extends TreeNode {
  static const int maxBucketSize = 8;

  final Set<T> _nodes = {};

  final NodeId rangeBegin;

  final NodeId rangeEnd;

  Set<T> get nodes => Set.unmodifiable(_nodes);

  int get size => _nodes.length;

  Bucket({required this.rangeBegin, required this.rangeEnd});

  Bucket<T>? get leftBucket => leftChild as Bucket<T>?;

  Bucket<T>? get rightBucket => rightChild as Bucket<T>?;

  Bucket<T>? get parentBucket => parent as Bucket<T>?;

  bool get isParent {
    if (leftChild == null && rightChild == null) {
      return false;
    }

    assert(leftChild != null && rightChild != null);
    assert(_nodes.isNotEmpty);

    return true;
  }

  bool addNode(T node) {
    if (node.id < rangeBegin || node.id >= rangeEnd) {
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

  Bucket<T> findBucketToLocate(T node) {
    assert(node.bucket == null);

    if (node.id < rangeBegin || node.id >= rangeEnd) {
      throw DHTException('Node ${node.id} is out of bucket range $rangeBegin - $rangeEnd');
    }

    T? existNode = getNode(node);
    if (existNode != null) {
      return existNode.bucket as Bucket<T>;
    }

    if (isParent) {
      if (node.id < leftBucket!.rangeEnd) {
        return leftBucket!.findBucketToLocate(node);
      } else {
        return rightBucket!.findBucketToLocate(node);
      }
    } else {
      return this;
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

    leftChild = Bucket<T>(rangeBegin: rangeBegin, rangeEnd: middle);
    rightChild = Bucket<T>(rangeBegin: middle, rangeEnd: rangeEnd);

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

  void removeNode(T node) {
    if (!_nodes.remove(node)) {
      return;
    }

    if (isParent) {
      if (node.id < leftBucket!.rangeEnd) {
        return leftBucket!.removeNode(node);
      } else {
        return rightBucket!.removeNode(node);
      }
    }

    node.bucket = null;
  }

  void removeNodeWhere(bool Function(T node) test) {
    for (T node in _nodes.where(test).toList()) {
      assert(node.bucket != null);

      removeNode(node);
    }
  }

  T? getNode(T node) {
    return _nodes.lookup(node);
  }

  void clear() {
    _nodes.clear();
  }
}
