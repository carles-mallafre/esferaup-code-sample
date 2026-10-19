import 'dart:async';

import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// Snackbar helpers that use the inverse-surface theme (legible in both modes).
/// Errors get a leading error-coloured icon so they read as errors without an
/// unreadable red-on-red pill.
///
/// A snack bar belongs to the screen's Scaffold, which a modal bottom sheet
/// covers. Called from inside a sheet, these helpers draw the same message
/// above the sheet instead, so it is never out of sight.
void showErrorSnackBar(BuildContext context, String message) {
  _show(context, message, leadingIcon: Icons.error_outline);
}

void showInfoSnackBar(BuildContext context, String message) {
  _show(context, message);
}

void _show(BuildContext context, String message, {IconData? leadingIcon}) {
  final c = context.colors;
  final content = Row(
    children: [
      if (leadingIcon != null) ...[
        Icon(leadingIcon, size: 20, color: c.error),
        const SizedBox(width: 10),
      ],
      Expanded(child: Text(message)),
    ],
  );
  if (ModalRoute.of(context) is ModalBottomSheetRoute) {
    _showAboveSheet(context, content);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: content));
}

OverlayEntry? _aboveSheet;

void _showAboveSheet(BuildContext context, Widget content) {
  final overlay = Overlay.of(context, rootOverlay: true);
  if (_aboveSheet?.mounted ?? false) _aboveSheet!.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AboveSheetMessage(
      content: content,
      onDone: () {
        if (_aboveSheet == entry) _aboveSheet = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _aboveSheet = entry;
  overlay.insert(entry);
}

class _AboveSheetMessage extends StatefulWidget {
  const _AboveSheetMessage({required this.content, required this.onDone});

  final Widget content;
  final VoidCallback onDone;

  @override
  State<_AboveSheetMessage> createState() => _AboveSheetMessageState();
}

class _AboveSheetMessageState extends State<_AboveSheetMessage> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), widget.onDone);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snack = theme.snackBarTheme;
    final media = MediaQuery.of(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: media.viewInsets.bottom + media.viewPadding.bottom + 16,
      child: Semantics(
        container: true,
        liveRegion: true,
        onDismiss: widget.onDone,
        child: GestureDetector(
          onTap: widget.onDone,
          child: Material(
            elevation: 6,
            color: snack.backgroundColor ?? theme.colorScheme.inverseSurface,
            shape:
                snack.shape ??
                const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: DefaultTextStyle.merge(
                style:
                    snack.contentTextStyle ??
                    TextStyle(color: theme.colorScheme.onInverseSurface),
                child: widget.content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
