import "utils.dart";

sealed class Node(this.path, this.type) {
  final String? type;
  final List<String> path;
  late final String name = _name;

  String get _name => "_${path.name}";
}

//---

final class Group(super.path, super.type) extends Node {
  final Map<String, Node> children = {};
}

//---

final class Token(super.path, String super.type, this.rawValue) extends Node {
  final dynamic rawValue;

  dynamic resolvedValue;
}
