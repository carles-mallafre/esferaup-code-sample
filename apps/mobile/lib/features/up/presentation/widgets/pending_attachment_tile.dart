import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/features/up/data/up_attachment_picker.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class PendingAttachmentTile extends StatelessWidget {
  const PendingAttachmentTile({
    super.key,
    required this.attachment,
    this.onRemove,
  });

  final PickedUpAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: c.surfaceCard,
        border: Border.all(color: c.surfaceBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
              dimension: 40,
              child: attachment.isImage
                  ? Image.file(
                      attachment.file,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image_outlined),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textStrong, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).addUpRemoveAttachment,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}
