import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:jtorrent/src/constant/common_constants.dart';

class NodeDistance {
  final Uint8List values;

  NodeDistance(List<int> values)
      : assert(values.length == CommonConstants.nodeIdLength),
        values = Uint8List.fromList(values);

  @override
  int get hashCode => values.hashCode;

  @override
  bool operator ==(other) {
    return other is NodeDistance && ListEquality<int>().equals(values, other.values);
  }

  bool operator >=(other) {
    if (other is! NodeDistance) {
      throw '${other.runtimeType} is not NodeDistance';
    }

    for (var i = 0; i < values.length; i++) {
      if (values[i] > other.values[i]) {
        return true;
      } else if (values[i] < other.values[i]) {
        return false;
      }
    }

    return true;
  }

  bool operator >(other) {
    if (other is! NodeDistance) {
      throw '${other.runtimeType} is not NodeDistance';
    }

    for (var i = 0; i < values.length; i++) {
      if (values[i] > other.values[i]) {
        return true;
      } else if (values[i] < other.values[i]) {
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
}
