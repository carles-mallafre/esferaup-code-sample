import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:flutter/material.dart';

/// A static mood face avatar — a soft-tinted circle with the mood's expression
/// icon. Used on UP feed cards and detail headers (the interactive picker is
/// [MoodSelector]).
class MoodFace extends StatelessWidget {
  const MoodFace({super.key, required this.mood, this.size = 48});

  final UpMood mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mood.color.withValues(alpha: 0.18),
      ),
      child: Icon(mood.icon, size: size * 0.62, color: mood.color),
    );
  }
}
