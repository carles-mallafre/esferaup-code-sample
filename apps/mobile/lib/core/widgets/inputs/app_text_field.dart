import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_radius.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:esferaup/l10n/app_localizations.dart';

/// Mirrors `C/Input/*`: height ~56, radius 14, 16px horizontal padding, card
/// fill, 2px primary focus ring. Optional label above + inline error text
/// (bind to a `ValidationError.field`).
///
/// Screen readers name the field by its caption: [label], else
/// [semanticLabel], else [hint]. The caption text itself is not read again.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.semanticLabel,
    this.hint,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.prefixIcon,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.maxLines = 1,
    this.autocorrect = true,
    this.clearable = false,
    this.scrollPadding = const EdgeInsets.all(20),
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;

  /// Names the field for screen readers when its visible caption is drawn
  /// outside it (a `FieldLabel` or a section heading above the field).
  final String? semanticLabel;

  final String? hint;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final IconData? prefixIcon;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;

  /// Off for proper nouns: iOS rewrites "Molins" to "Molina" and the search
  /// then finds nothing.
  final bool autocorrect;

  /// Offers an X while the field has text. Needs [controller], and clearing
  /// reports an empty value through [onChanged].
  final bool clearable;

  /// Room kept clear around the field when it scrolls into view; a larger
  /// bottom keeps the button that follows above the keyboard.
  final EdgeInsets scrollPadding;

  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscure;
  FocusNode? _ownFocusNode;
  TextEditingController? _ownController;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  // The decorator only exposes the hint while the field is empty, so a field
  // named by its hint alone would turn nameless once the adult types.
  Widget _named(Widget field) {
    final caption = widget.label ?? widget.semanticLabel;
    if (caption != null) return Semantics(label: caption, child: field);
    final hint = widget.hint;
    if (hint == null) return field;
    return ValueListenableBuilder(
      valueListenable: _controller,
      builder: (context, value, child) =>
          Semantics(label: value.text.isEmpty ? null : hint, child: child),
      child: field,
    );
  }

  Widget? _clearButton(AppColors c) {
    final controller = widget.controller;
    if (!widget.clearable || controller == null) return null;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) => value.text.isEmpty
          ? const SizedBox.shrink()
          : IconButton(
              onPressed: () {
                controller.clear();
                widget.onChanged?.call('');
              },
              icon: Icon(Icons.close_rounded, color: c.textMuted),
              tooltip: AppLocalizations.of(context).inputClear,
            ),
    );
  }

  // Return's «next» must land on the following field, not on the field's own
  // trailing button.
  Widget? _suffix(AppColors c) {
    final button = widget.obscure
        ? IconButton(
            onPressed: () => setState(() => _obscured = !_obscured),
            icon: Icon(
              _obscured ? Icons.visibility_off : Icons.visibility,
              color: c.textMuted,
            ),
            tooltip: _obscured
                ? AppLocalizations.of(context).inputShowPassword
                : AppLocalizations.of(context).inputHidePassword,
          )
        : _clearButton(c);
    return button == null ? null : ExcludeFocusTraversal(child: button);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = widget.errorText != null;
    return Column(
      // A field sizes to itself: inside a dialog a stretching column turns one
      // input into a full-height box.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? _focusNode.requestFocus : null,
              child: Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textStrong,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
        ],
        _named(
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            obscureText: _obscured,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autocorrect: widget.autocorrect,
            // On Android, suggestions off adds the visible-password variation,
            // which turns an email keyboard into a filter field.
            enableSuggestions:
                widget.autocorrect ||
                widget.keyboardType == TextInputType.emailAddress,
            autofillHints: widget.autofillHints,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            inputFormatters: widget.inputFormatters,
            scrollPadding: widget.scrollPadding,
            style: TextStyle(fontSize: 16, color: c.textStrong),
            decoration: InputDecoration(
              hintText: widget.hint,
              filled: true,
              fillColor: c.surfaceCard,
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(widget.prefixIcon, color: c.textMuted),
              suffixIcon: _suffix(c),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s4,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.brLg,
                borderSide: BorderSide(color: c.surfaceBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.brLg,
                borderSide: BorderSide(
                  color: hasError ? c.error : c.surfaceBorder,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.brLg,
                borderSide: BorderSide(
                  color: hasError ? c.error : c.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.s1),
          Text(
            widget.errorText!,
            style: TextStyle(fontSize: 13, color: c.error),
          ),
        ],
      ],
    );
  }
}
