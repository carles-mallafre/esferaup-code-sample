import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/utils/content_author.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The author on their own: «Laia», «Tú», «Marta · ya no está en la familia», or
/// «Una persona adulta de la familia» when no name is known.
String contentAuthorName(AppLocalizations l10n, ContentAuthor author) =>
    switch (author) {
      ContentAuthor(former: true, firstName: final String name) =>
        l10n.formerAuthorNamed(name),
      ContentAuthor(former: true) => l10n.formerAuthorUnknown,
      ContentAuthor(isSelf: true) => l10n.authorSelf,
      ContentAuthor(firstName: final String name) => name,
      _ => l10n.authorAdult,
    };

/// «Escrito por Laia» (or «Añadido por …» for a document), «Escrito por ti», …
String contentAuthorLine(
  AppLocalizations l10n,
  ContentAuthor author, {
  bool added = false,
}) {
  final who = switch (author) {
    ContentAuthor(former: true, firstName: final String name) =>
      l10n.formerAuthorNamed(name),
    ContentAuthor(former: true) => l10n.authorWhoFormerAdult,
    ContentAuthor(isSelf: true) => l10n.authorWhoSelf,
    ContentAuthor(firstName: final String name) => name,
    _ => l10n.authorWhoAdult,
  };
  return added ? l10n.authorAddedBy(who) : l10n.authorWrittenBy(who);
}

/// Small muted line naming who wrote a UP, comment or message.
class ContentAuthorLine extends StatelessWidget {
  const ContentAuthorLine({
    super.key,
    required this.author,
    this.nameOnly = false,
    this.added = false,
    this.color,
  });

  final ContentAuthor author;

  /// Just the name (above a comment or message), not «Escrito por …».
  final bool nameOnly;
  final bool added;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = nameOnly
        ? contentAuthorName(l10n, author)
        : contentAuthorLine(l10n, author, added: added);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color ?? context.colors.textMuted,
        ),
      ),
    );
  }
}
