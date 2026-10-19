import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Astra C/Tematica: a theme surface around the shared concentric glyph.
class TematicaMark extends StatelessWidget {
  const TematicaMark({super.key, required this.color, this.size = 48});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final surfaces = <Color, Color>{
      c.tematicaAtencio: c.tematicaAtencioSoft,
      c.tematicaLectura: c.tematicaLecturaSoft,
      c.tematicaMates: c.tematicaMatesSoft,
      c.tematicaMindfulness: c.tematicaMindfulnessSoft,
      c.tematicaLlenguatge: c.tematicaLlenguatgeSoft,
      c.tematicaCoordinacio: c.tematicaCoordinacioSoft,
      c.tematicaMemoria: c.tematicaMemoriaSoft,
      c.tematicaCreativitat: c.tematicaCreativitatSoft,
    };
    return ExcludeSemantics(
      child: _disc(
        size,
        surfaces[color] ?? c.primaryLight,
        _disc(
          size * 0.5,
          color,
          _disc(size * 0.32, c.markInner, _disc(size * 0.14, color, null)),
        ),
      ),
    );
  }

  Widget _disc(double diameter, Color color, Widget? child) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: child == null ? null : Center(child: child),
  );
}
