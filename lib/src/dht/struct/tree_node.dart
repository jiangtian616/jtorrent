class TreeNode {
  int _layer = 0;

  int get layer => _layer;
  
  TreeNode? _leftChild;

  TreeNode? _rightChild;

  TreeNode? parent;

  TreeNode? get leftChild => _leftChild;

  TreeNode? get rightChild => _rightChild;

  set rightChild(TreeNode? node) {
    _rightChild?.parent = null;

    if (node?.parent != null) {
      if (node!.parent!.leftChild == node) {
        node.parent!.leftChild = null;
      }
      if (node.parent!.rightChild == node) {
        node.parent!.rightChild = null;
      }
    }

    node?.parent = this;
    node?._layer = _layer + 1;

    _rightChild = node;
  }

  set leftChild(TreeNode? node) {
    _leftChild?.parent = null;

    if (node?.parent != null) {
      if (node!.parent!.leftChild == node) {
        node.parent!.leftChild = null;
      }
      if (node.parent!.rightChild == node) {
        node.parent!.rightChild = null;
      }
    }

    node?.parent = this;
    node?._layer = _layer + 1;

    _leftChild = node;
  }
}
