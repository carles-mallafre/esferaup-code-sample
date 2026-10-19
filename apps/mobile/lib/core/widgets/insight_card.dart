import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// An AI-pattern / insight card: a primary-outlined surface with a spark icon,
/// a title, a short body and an optional action link (`Veure patró →`). Used
/// for "Patró detectat" on Els meus UPs and similar AI Patron surfaces.
///
/// Per the project voice lock, callers must phrase the body as a *hypothetical
/// pattern*, never a diagnostic claim.
class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.auto_awesome_rounded,
    this.actionLabel,
    this.onAction,
    this.outlined = true,
    this.onTap,
  });

  final String title;
  final String body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Outlined (primary border on card surface) is the standalone teaser style;
  /// `outlined: false` is the filled primary-light inline style (UP detail).
  final bool outlined;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: outlined ? c.surfaceCard : c.primaryLight,
            borderRadius: BorderRadius.circular(16),
            border: outlined ? Border.all(color: c.primary, width: 1.5) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: outlined ? c.secondaryLight : c.surfaceCard,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: c.textStrong),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: c.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            color: c.textStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: onAction,
                      behavior: HitTestBehavior.opaque,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              actionLabel!,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: c.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: c.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
