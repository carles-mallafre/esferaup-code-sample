import 'dart:math' as math;

import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// App-wide keyboard behaviour, mounted once above the navigator:
///
/// * A tap (not a scroll) outside the focused text field closes the keyboard.
/// * On iOS, the multiline, number and phone keyboards have no key that closes
///   them, so a «Hecho» bar rides on top of the keyboard while such a field is
///   focused. The bar's height is added to `viewInsets.bottom`, so scaffolds,
///   sheets and scroll-into-view keep content clear of it.
class KeyboardAccessory extends StatefulWidget {
  const KeyboardAccessory({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardAccessory> createState() => _KeyboardAccessoryState();
}

class _KeyboardAccessoryState extends State<KeyboardAccessory> {
  bool _focusedFieldNeedsBar = false;
  Offset? _tapDown;

  late final Map<Type, Action<Intent>> _actions = {
    EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(
      onInvoke: (intent) {
        _tapDown = intent.pointerDownEvent.position;
        return null;
      },
    ),
    EditableTextTapUpOutsideIntent:
        CallbackAction<EditableTextTapUpOutsideIntent>(
          onInvoke: (intent) {
            final down = _tapDown;
            _tapDown = null;
            if (down != null &&
                (intent.pointerUpEvent.position - down).distance < kTouchSlop) {
              intent.focusNode.unfocus();
            }
            return null;
          },
        ),
  };

  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
    _onFocusChange();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    super.dispose();
  }

  // The focused field is inspected after the frame: during a build the primary
  // focus can still belong to a subtree that is being replaced, and looking up
  // the ancestors of a deactivated element throws.
  void _onFocusChange() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final needsBar = _needsBar();
      if (needsBar != _focusedFieldNeedsBar) {
        setState(() => _focusedFieldNeedsBar = needsBar);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  static bool _needsBar() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return false;
    final field = context.findAncestorWidgetOfExactType<EditableText>();
    if (field == null || field.readOnly) return false;
    final type = field.keyboardType;
    if (type.index == TextInputType.number.index ||
        type.index == TextInputType.phone.index) {
      return true;
    }
    final multiline =
        field.maxLines != 1 || type.index == TextInputType.multiline.index;
    final action = field.textInputAction;
    return multiline && (action == null || action == TextInputAction.newline);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final showBar = _focusedFieldNeedsBar && keyboard > 0;
    final barHeight = showBar
        ? KeyboardDoneBar.heightFor(media.textScaler)
        : 0.0;
    return Actions(
      actions: _actions,
      child: Stack(
        children: [
          MediaQuery(
            data: media.copyWith(
              viewInsets: media.viewInsets.copyWith(
                bottom: keyboard + barHeight,
              ),
            ),
            child: widget.child,
          ),
          if (showBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboard,
              height: barHeight,
              child: KeyboardDoneBar(
                onDone: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
        ],
      ),
    );
  }
}

class KeyboardDoneBar extends StatelessWidget {
  const KeyboardDoneBar({super.key, required this.onDone});

  final VoidCallback onDone;

  static double heightFor(TextScaler scaler) =>
      math.max(48, scaler.scale(16) * 1.4 + AppSpacing.s3);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: c.surfaceCard,
      shape: Border(top: BorderSide(color: c.surfaceBorder)),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
          child: Semantics(
            hint: l10n.keyboardDoneHint,
            child: TextButton(
              onPressed: onDone,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 44),
                foregroundColor: c.primary,
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(l10n.keyboardDone, maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}
