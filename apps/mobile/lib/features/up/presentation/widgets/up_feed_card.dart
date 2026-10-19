import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/widgets/mood_face.dart';
import 'package:esferaup/features/up/presentation/widgets/authenticated_up_image.dart';
import 'package:flutter/material.dart';

/// A single UP in a feed/list: the mood face, a `date · time · category` meta
/// line (category in its esfera colour) and the note preview. Shared by Els
/// meus UPs, the Inici feed and the Esferes UPs tab.
class UpFeedCard extends StatelessWidget {
  const UpFeedCard({
    super.key,
    required this.mood,
    required this.date,
    required this.time,
    required this.category,
    required this.categoryColor,
    required this.note,
    this.leadingIcon,
    this.hasAttachment = false,
    this.upId,
    this.coverImageIndex,
    this.isCrisis = false,
    this.authorLine,
    this.onTap,
  });

  final UpMood mood;
  final String date;
  final String time;
  final String category;
  final Color categoryColor;
  final String note;
  final IconData? leadingIcon;
  final bool hasAttachment;
  final String? upId;
  final int? coverImageIndex;
  final bool isCrisis;

  /// «Escrito por Laia»: one subtle line when another adult wrote it.
  final String? authorLine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: ['$date · $time · $category · $note', ?authorLine].join(' · '),
      excludeSemantics: true,
      child: Material(
        color: isCrisis ? c.errorLight : c.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isCrisis ? c.error : c.surfaceBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leadingIcon == null)
                  MoodFace(mood: mood, size: 48)
                else
                  ExcludeSemantics(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: c.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(leadingIcon, color: c.primary),
                    ),
                  ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            '$date · $time',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.textStrong,
                            ),
                          ),
                          Text(
                            category,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: categoryColor,
                            ),
                          ),
                          if (hasAttachment)
                            ExcludeSemantics(
                              child: Icon(
                                Icons.attachment_rounded,
                                size: 18,
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          color: c.textStrong,
                        ),
                      ),
                      if (authorLine != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          authorLine!,
                          style: TextStyle(fontSize: 13, color: c.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (upId != null && coverImageIndex != null) ...[
                  const SizedBox(width: AppSpacing.s3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.square(
                      dimension: 72,
                      child: AuthenticatedUpImage(
                        upId: upId!,
                        attachmentIndex: coverImageIndex!,
                        cacheWidth: 216,
                        placeholder: ColoredBox(
                          color: c.primaryLight,
                          child: Icon(Icons.image_outlined, color: c.textMuted),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
