import 'bucket.dart';
import 'node_id.dart';

abstract class AbstractNode {
  final NodeId id;

  Bucket? bucket;

  AbstractNode({required this.id});

  @override
  String toString() {
    return 'AbstractNode{id: $id, bucket: $bucket}';
  }

  @override
  bool operator ==(Object other) => other is AbstractNode && id == other.id;

  @override
  int get hashCode => id.hashCode;

  int value4Index(int index) {
    assert(index >= 0 && index < id.id.length * 8);
    return id.id[index ~/ 8] & (1 << (7 - index % 8));
  }
}
