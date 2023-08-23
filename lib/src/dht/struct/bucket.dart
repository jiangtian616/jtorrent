import 'package:jtorrent/src/dht/struct/node.dart';
import 'package:jtorrent/src/dht/struct/node_id.dart';
import 'package:jtorrent/src/dht/struct/tree_node.dart';
import 'package:jtorrent/src/exception/dht_exception.dart';

class Bucket<T extends AbstractNode> extends TreeNode {
  static const int maxBucketSize = 8;

  final Set<T> _nodes = {};

  Set<T> get nodes => Set.unmodifiable(_nodes);

  int get size => _nodes.length;

  Bucket<T>? get _leftBucket => leftChild as Bucket<T>?;

  Bucket<T>? get _rightBucket => rightChild as Bucket<T>?;

  Bucket<T>? get _parentBucket => parent as Bucket<T>?;

  bool get isParent {
    if (leftChild == null && rightChild == null) {
      return false;
    }

    assert(leftChild != null && rightChild != null);
    assert(_nodes.isNotEmpty);

    return true;
  }

  bool addNode(T node) {
    assert(parent == null);

    if (_nodes.contains(node)) {
      return false;
    }

    Bucket<T> bucket = _findBucketToLocate(node.id);
    if (bucket.size >= maxBucketSize) {
      return false;
    }

    while (bucket != this) {
      bucket._nodes.add(node);

      assert(bucket._parentBucket != null);
      bucket = bucket._parentBucket!;
    }

    bucket._nodes.add(node);
    node.bucket = bucket;

    return true;
  }

  bool removeNode(T node) {
    assert(parent == null);

    if (nodes.contains(node) == false) {
      return false;
    }

    Bucket<T> bucket = this;
    while (bucket.isParent) {
      assert(bucket.nodes.contains(node));

      bucket._nodes.remove(node);

      if (node.value4Index(bucket.layer) == 0) {
        bucket = bucket._leftBucket!;
      } else {
        bucket = bucket._rightBucket!;
      }
    }

    node.bucket = null;
    return true;
  }

  void split() {
    if (isParent) {
      throw DHTException('Bucket is already splitted');
    }

    leftChild = Bucket<T>();
    rightChild = Bucket<T>();

    for (T node in _nodes) {
      if (node.value4Index(layer) == 0) {
        _leftBucket!._nodes.add(node);
        node.bucket = _leftBucket!;
      } else {
        _rightBucket!._nodes.add(node);
        node.bucket = _rightBucket!;
      }
    }
  }

  List<T> findClosestNodes(NodeId nodeId) {
    assert(parent == null);

    Bucket<T> bucket = _findBucketToLocate(nodeId);
    if (bucket == this) {
      return List.unmodifiable(_nodes);
    }

    while (bucket._parentBucket != null && bucket._parentBucket!.size < Bucket.maxBucketSize) {
      bucket = bucket._parentBucket!;
    }

    if (bucket._parentBucket == null) {
      return List.unmodifiable(bucket.nodes);
    }

    List<T> result = [];
    result.addAll(bucket.nodes);

    List<T> appendNodes = [];
    if (bucket._parentBucket!._leftBucket == bucket) {
      appendNodes = bucket._parentBucket!._rightBucket!.nodes.toList();
    } else {
      appendNodes = bucket._parentBucket!._leftBucket!.nodes.toList();
    }

    appendNodes.sort((a, b) => a.id.distanceWith(nodeId).compareTo(b.id.distanceWith(nodeId)));
    result.addAll(appendNodes.sublist(0, Bucket.maxBucketSize - result.length));

    return result;
  }

  Bucket<T> _findBucketToLocate(NodeId nodeId) {
    Bucket<T> bucket = this;
    int index = 0;
    while (bucket.isParent) {
      if (nodeId.value4Index(index) == 0) {
        bucket = bucket._leftBucket!;
      } else {
        bucket = bucket._rightBucket!;
      }
      index++;
    }

    return bucket;
  }
}
