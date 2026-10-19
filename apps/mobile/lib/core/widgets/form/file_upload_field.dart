import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/form/dashed_border.dart';
import 'package:flutter/material.dart';

/// `C/FileUpload`: an 88 dp dashed drop zone — round icon chip + title + the
/// accepted-formats hint. Used for the optional certificate/report upload on 08
/// Account Setup (and reused wherever a document upload is offered). The host
/// opens the OS file picker on tap; the Plan 028 safety pipeline runs server-side.
class FileUploadField extends StatelessWidget {
  const FileUploadField({
    super.key,
    required this.title,
    required this.hint,
    this.onTap,
  });

  final String title;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DashedBorder(
          radius: 12,
          color: enabled ? c.primary : c.gray400,
          strokeWidth: 1.5,
          dash: 6,
          gap: 4,
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: c.surfaceCard,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled ? c.primaryLight : c.gray100,
                  ),
                  child: Icon(
                    Icons.file_upload_outlined,
                    size: 20,
                    color: enabled ? c.primary : c.textMuted,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textStrong,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hint,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
