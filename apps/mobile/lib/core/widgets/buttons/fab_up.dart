import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// `C/FAB-UP` — the 64 dp navy capture button ("UP", 22px Bold white) that
/// floats bottom-right above the bottom nav and opens the Add-UP flow.
class FabUp extends StatelessWidget {
  const FabUp({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 64,
      height: 64,
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: c.primary,
        foregroundColor: c.actionLabel,
        elevation: 3,
        shape: const CircleBorder(),
        tooltip: AppLocalizations.of(context).fabAddUp,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'UP',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.actionLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
