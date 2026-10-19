import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The small SemiBold caption above a form field ("El teu nom", "Idioma", …).
/// fs13 / w600 / gray-700, matching the labels on 08 Account Setup (§18.3).
/// With [focusNode], tapping the label focuses its text field. That field
/// carries the caption as its own name (`AppTextField.semanticLabel`), so the
/// label is then hidden from screen readers rather than read twice.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.focusNode});

  final String text;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.colors.gray700,
      ),
    );
    final node = focusNode;
    if (node == null) return label;
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: node.requestFocus,
        child: label,
      ),
    );
  }
}
