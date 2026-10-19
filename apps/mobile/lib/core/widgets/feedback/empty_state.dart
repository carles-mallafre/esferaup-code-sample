import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/widgets/brand_mark.dart';
import 'package:flutter/material.dart';

/// 150×150 illustration mark mirroring `C/EmptyStateMark` — filled concentric
/// brand rings (the EsferaMark) around a centred glyph. (`NoWifi` offline
/// variant: pass `Icons.wifi_off`.)
class EmptyStateMark extends StatelessWidget {
  const EmptyStateMark({super.key, this.icon, this.size = 150});

  /// Centre glyph. When null, the resting EsferaMark dot is shown (the neutral
  /// empty state); pass an icon for offline / permission / not-found states.
  final IconData? icon;

  /// Outer diameter; inner rings scale proportionally.
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: BrandMark(
        size: size,
        center: icon == null
            ? null
            : Icon(icon, size: size * 0.267, color: c.markCentre),
      ),
    );
  }
}

/// Full empty/error state: mark + title + message + optional CTA. Used for
/// `§18.28` global states (Estat buit / Sense connexió / Permís denegat).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.action,
    this.scrollable = false,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Widget? action;

  /// Stay centred while there is room and scroll instead of overflowing when
  /// there is not — which is what a tab body does at 200% text scale.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (!scrollable) return body;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Always draggable, so a pull-to-refresh around it still works.
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: body,
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyStateMark(icon: icon),
            const SizedBox(height: AppSpacing.s6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: c.textMuted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s6),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
