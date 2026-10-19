import 'package:flutter/material.dart';

/// The five moods on Add UP (§18 "Com et sents?"). Face colour is fixed per mood
/// (green / red / blue / amber / purple from the live Figma).
enum UpMood {
  good(Icons.sentiment_satisfied_rounded, Color(0xFF22C55E)),
  great(Icons.sentiment_very_satisfied_rounded, Color(0xFFEF4444)),
  sad(Icons.sentiment_dissatisfied_rounded, Color(0xFF3B82F6)),
  angry(Icons.sentiment_very_dissatisfied_rounded, Color(0xFFF59E0B)),
  excited(Icons.sentiment_neutral_rounded, Color(0xFFA855F7));

  const UpMood(this.icon, this.color);

  final IconData icon;
  final Color color;
}
