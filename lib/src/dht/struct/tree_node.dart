class TreeNode {
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

    _leftChild = node;
  }
}
