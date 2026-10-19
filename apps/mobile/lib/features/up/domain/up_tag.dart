bool validUpTag(String value) {
  final tag = value.trim();
  return tag.isEmpty ||
      (tag.runes.length <= 60 &&
          RegExp(
            r"^[\p{L}\p{N}][\p{L}\p{N}'’·-]*$",
            unicode: true,
          ).hasMatch(tag));
}
