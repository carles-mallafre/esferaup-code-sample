/// Which adult of the family wrote or added a piece of content.
///
/// `firstName` is null when the family knows no name for them (the app then says
/// "an adult of the family"); `former` marks an adult who erased their account and
/// left the family. Only adults of the same family receive it.
class ContentAuthor {
  const ContentAuthor({
    this.firstName,
    this.isSelf = false,
    this.former = false,
  });

  final String? firstName;
  final bool isSelf;
  final bool former;

  /// The API's `author` object; an older API that only sends `former_author` still
  /// names an adult who left.
  static ContentAuthor? fromJson(Object? author, {Object? formerAuthor}) =>
      switch (author) {
        final Map<String, dynamic> value => ContentAuthor(
          firstName: _name(value['first_name']),
          isSelf: value['is_self'] == true,
          former: value['former'] == true,
        ),
        _ => switch (formerAuthor) {
          final Map<String, dynamic> value => ContentAuthor(
            firstName: _name(value['first_name']),
            former: true,
          ),
          _ => null,
        },
      };

  static String? _name(Object? raw) => switch (raw) {
    final String name when name.trim().isNotEmpty => name.trim(),
    _ => null,
  };
}
