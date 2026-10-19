import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One selectable row in an [showOptionPicker].
class PickerOption<T> {
  const PickerOption({required this.value, required this.label, this.sublabel});
  final T value;
  final String label;
  final String? sublabel;
}

/// A modal bottom sheet that lets the user pick one of [options]. Returns the
/// chosen value (or null if dismissed). Used for the typography / language
/// pickers on 08 Account Setup and throughout Configuració.
Future<T?> showOptionPicker<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
  required T selected,
}) {
  final c = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: c.surfaceCard,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s5,
                    0,
                    AppSpacing.s5,
                    AppSpacing.s2,
                  ),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: c.textStrong,
                    ),
                  ),
                ),
                for (final option in options)
                  _OptionRow<T>(
                    option: option,
                    isSelected: option.value == selected,
                    onTap: () => Navigator.of(context).pop(option.value),
                  ),
                const SizedBox(height: AppSpacing.s2),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final PickerOption<T> option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s5,
          vertical: AppSpacing.s4,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: c.textStrong,
                    ),
                  ),
                  if (option.sublabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.sublabel!,
                      style: TextStyle(fontSize: 13, color: c.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check, size: 20, color: c.primary),
          ],
        ),
      ),
    );
  }
}
