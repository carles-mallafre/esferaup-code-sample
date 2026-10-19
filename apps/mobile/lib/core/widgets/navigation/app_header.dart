import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Back app-bar mirroring `C/Header-Back`: h56, leading chevron, title 17 Bold,
/// optional trailing actions. Usable as `Scaffold.appBar`.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    this.title,
    this.onBack,
    this.actions = const [],
    this.showBack = true,
    this.centerTitle = false,
    this.leadingIcon = Icons.chevron_left,
  });

  final String? title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool showBack;

  /// Centre the title between the leading button and the actions (iOS-style nav
  /// bar). Left-aligned by default.
  final bool centerTitle;

  /// The leading glyph — chevron for back, `Icons.close` for modal screens.
  final IconData leadingIcon;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleStyle = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: c.textStrong,
    );
    final leading = showBack
        ? IconButton(
            onPressed: onBack ?? () => Navigator.maybePop(context),
            icon: Icon(leadingIcon),
            color: c.textStrong,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          )
        : const SizedBox(width: 12);

    // Centre-title screens use a Stack so the title stays optically centred
    // regardless of leading/action widths; the controls sit on top.
    final Widget content = centerTitle
        ? Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Text(
                  title ?? '',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              Row(children: [leading, const Spacer(), ...actions]),
            ],
          )
        : Row(
            children: [
              leading,
              Expanded(
                child: Text(
                  title ?? '',
                  style: titleStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...actions,
            ],
          );

    // Edge-to-edge (Android 15+): the app draws behind the status bar, so the
    // header must inset itself below it. The Scaffold sizes the app-bar slot to
    // this widget's real (SafeArea-grown) height, so the body still starts
    // below the header.
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: content,
        ),
      ),
    );
  }
}
