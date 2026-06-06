extension XString on String {
  String get name {
    if (isEmpty) {
      return "";
    }

    final chunks = split(_splitPattern).where((chunk) => chunk.isNotEmpty).toList();

    if (chunks.isEmpty) {
      return "";
    }

    return chunks.first.toLowerCase() + chunks.skip(1).map((chunk) => chunk[0].toUpperCase() + chunk.substring(1)).join();
  }

  static final _splitPattern = RegExp(r"[-_\s]+|(?=[A-Z])");
}

//---

extension XStringIterable on Iterable<String> {
  String get name => join("-").name;
}
