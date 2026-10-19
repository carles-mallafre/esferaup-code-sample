import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A tappable video preview: a deep-blue brand panel with decorative circles, a
/// centred white play button and a duration pill (bottom-right). Used on
/// exercise detail and any "watch the intro" surface. [aspectRatio] defaults to
/// 16:10.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({
    super.key,
    required this.duration,
    this.onTap,
    this.aspectRatio = 16 / 10,
  });

  final String duration;
  final VoidCallback? onTap;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = AppLocalizations.of(context).commonPlayVideo;
    return Semantics(
      button: onTap != null,
      label: duration.isEmpty ? label : '$label · $duration',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Container(
                color: c.surfaceFeature,
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -20,
                      child: _circle(
                        160,
                        c.brandOceanBlue.withValues(alpha: 0.5),
                      ),
                    ),
                    Positioned(
                      right: -50,
                      bottom: -70,
                      child: _circle(
                        180,
                        c.brandSkyBlue.withValues(alpha: 0.35),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: c.mediaControl,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 38,
                          color: c.mediaGlyph,
                        ),
                      ),
                    ),
                    if (duration.isNotEmpty)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            duration,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circle(double d, Color color) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}
