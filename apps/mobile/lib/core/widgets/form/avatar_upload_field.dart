import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/form/dashed_border.dart';
import 'package:flutter/material.dart';

/// `C/AvatarUpload`: a 96 dp dashed-circle photo slot with a camera glyph and a
/// caption below. Used on 08 Account Setup (adult) and 11 Child Profile Form.
/// Shows [image] once picked; the host opens the picker on tap.
class AvatarUploadField extends StatelessWidget {
  const AvatarUploadField({
    super.key,
    required this.caption,
    this.image,
    this.onTap,
  });

  final String caption;
  final ImageProvider? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: enabled,
          enabled: enabled,
          label: caption,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: DashedBorder(
              radius: 48,
              color: enabled ? c.primary : c.gray400,
              strokeWidth: 1.5,
              dash: 4,
              gap: 4,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled ? c.primaryLight : c.gray100,
                  image: image == null
                      ? null
                      : DecorationImage(image: image!, fit: BoxFit.cover),
                ),
                child: image != null
                    ? null
                    : Icon(
                        Icons.photo_camera_outlined,
                        size: 30,
                        color: enabled ? c.primary : c.textMuted,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(caption, style: TextStyle(fontSize: 12, color: c.textMuted)),
      ],
    );
  }
}
