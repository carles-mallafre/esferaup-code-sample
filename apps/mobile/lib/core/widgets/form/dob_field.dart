import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// `C/DOBPicker`: a 56 dp tappable row — calendar icon, the formatted date (or a
/// `DD / MM / AAAA` placeholder), and a chevron. Used for the adult DOB on 08
/// and the child DOB on 11. The host owns the value + opens the picker on tap.
class DobField extends StatelessWidget {
  const DobField({
    super.key,
    required this.value,
    this.placeholder = 'DD / MM / AAAA',
    this.onTap,
  });

  /// Pre-formatted `DD / MM / AAAA`, or null to show the placeholder.
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasValue = value != null;
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
              Icon(Icons.calendar_today_outlined, size: 20, color: c.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasValue ? value! : placeholder,
                  style: TextStyle(
                    fontSize: 15,
                    color: hasValue ? c.textStrong : c.textMuted,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: c.gray400),
            ],
          ),
        ),
      ),
    );
  }
}
