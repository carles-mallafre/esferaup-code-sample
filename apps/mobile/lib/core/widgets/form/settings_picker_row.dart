import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// `C/SettingsRow/Picker`: a 56 dp row with a label on the left and the current
/// value + chevron on the right. Used for the typography / language pickers on
/// 08 Account Setup and throughout Configuració.
class SettingsPickerRow extends StatelessWidget {
  const SettingsPickerRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.textStrong,
                  ),
                ),
              ),
              Text(value, style: TextStyle(fontSize: 14, color: c.textMuted)),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 16, color: c.gray400),
            ],
          ),
        ),
      ),
    );
  }
}
