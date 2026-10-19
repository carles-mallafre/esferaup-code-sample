import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The one mapping from an UP category wire key to its Figma colour.
///
/// Six of the eight land exactly on an astra semantic token, so they also get
/// the reviewed dark twin for free. `nutricio` (#F97316) and `descans`
/// (#94A3B8) have no token in the astra collection, so they stay literal in
/// both modes — as they already are on the Esferes grid.
Color upCategoryColor(AppColors c, String category) => switch (category) {
  'escola' => c.tematicaLectura,
  'emocions' => c.tematicaAtencio,
  'casa' => c.tematicaMates,
  'salut' => c.error,
  'esport' => c.tematicaMindfulness,
  'activa' => c.primary,
  'nutricio' => const Color(0xFFF97316),
  'descans' => const Color(0xFF94A3B8),
  _ => c.primary,
};
