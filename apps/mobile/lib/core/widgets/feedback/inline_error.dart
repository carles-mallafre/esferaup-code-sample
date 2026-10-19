import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_radius.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A compact error panel (error-light surface + error-ink text) for inline form
/// submission failures.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: c.errorLight,
        borderRadius: AppRadius.brMd,
      ),
      child: Text(message, style: TextStyle(fontSize: 13, color: c.errorInk)),
    );
  }
}
