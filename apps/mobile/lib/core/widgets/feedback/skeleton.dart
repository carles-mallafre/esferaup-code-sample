import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The sweep phase shared by every [Skeleton] inside one [SkeletonLoader], so a
/// screenful of placeholders runs off a single controller instead of one each.
class _SkeletonPhase extends InheritedWidget {
  const _SkeletonPhase({required this.phase, required super.child});

  /// Runs 0 → 1 across one sweep. Null while motion is off.
  final Animation<double>? phase;

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonPhase>()?.phase;

  @override
  bool updateShouldNotify(_SkeletonPhase oldWidget) => phase != oldWidget.phase;
}

/// Wraps the placeholder for one pending region: drives the shimmer and gives
/// the region a single "loading" announcement instead of a dozen empty boxes.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, required this.child, this.announce = true});

  final Widget child;

  /// False for a second placeholder on a screen that already announces one —
  /// a screen reader should hear "loading" once, not per block.
  final bool announce;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// The band crosses in the first two thirds; the rest of the period is a rest
  /// beat, which is what keeps a whole screen of blocks from reading as strobe.
  late final CurvedAnimation _sweep = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.66, curve: Curves.easeInOut),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduce != _reduceMotion) setState(() => _reduceMotion = reduce);
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The blocks are bare containers, so they carry no semantics of their own:
    // nothing has to be excluded, and real labels kept beside them (a stat's
    // name, a section header) stay readable.
    final region = _SkeletonPhase(
      phase: _reduceMotion ? null : _sweep,
      child: widget.child,
    );
    if (!widget.announce) return region;
    return Semantics(
      container: true,
      liveRegion: true,
      label: AppLocalizations.of(context).commonLoading,
      child: region,
    );
  }
}

/// One placeholder block. Outside a [SkeletonLoader] it is a plain flat block,
/// which is also what a reduced-motion reader gets.
class Skeleton extends StatelessWidget {
  /// A block of a fixed size: an avatar slot, a button, a QR square.
  const Skeleton({
    super.key,
    required this.height,
    this.width,
    this.widthFactor,
    this.radius = 8,
  }) : fontSize = null;

  const Skeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = size,
      widthFactor = null,
      fontSize = null;

  /// A stand-in for one line of text at [fontSize]. It grows with the text
  /// scale, so the page does not jump when the real words land at 200%.
  const Skeleton.text({super.key, required this.fontSize, this.widthFactor = 1})
    : width = null,
      height = 0,
      radius = 6;

  final double height;
  final double? width;

  /// Share of the available width, for a line inside a column of unknown width.
  final double? widthFactor;
  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = c.gray200;
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? c.gray300
        : c.gray100;
    final size = fontSize == null
        ? height
        : MediaQuery.textScalerOf(context).scale(fontSize!) * 0.8;
    final phase = _SkeletonPhase.of(context);

    Widget block = phase == null
        ? _box(
            size,
            BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(radius),
            ),
          )
        : AnimatedBuilder(
            animation: phase,
            builder: (context, _) {
              // The band is 1.8 wide in alignment units, so it has fully left
              // the block at ±1.9: the cycle starts and ends on the same flat
              // block and the loop has no seam to see.
              final dx = -2 + 4 * phase.value;
              return _box(
                size,
                BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment(dx - 0.9, -1),
                    end: Alignment(dx + 0.9, 1),
                    colors: [base, highlight, base],
                  ),
                ),
              );
            },
          );
    if (widthFactor != null) {
      block = FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: block,
      );
    }
    return block;
  }

  Widget _box(double size, BoxDecoration decoration) =>
      Container(width: width, height: size, decoration: decoration);
}

/// The card chrome a skeleton row sits in — same fill, border and radius as the
/// real cards, so only the text inside it changes when the data lands.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: child,
    );
  }
}
