import 'package:esferaup/core/upload/upload_providers.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareUp(
  BuildContext context,
  WidgetRef ref,
  UpDetail detail,
) async {
  final l = AppLocalizations.of(context);
  final text =
      '${upCategoryLabel(l, detail.category)} · ${MaterialLocalizations.of(context).formatMediumDate(detail.occurredAt)}\n${detail.note ?? ''}';
  final photo = detail.attachments.where((a) => a.isImage).firstOrNull;
  final files = <XFile>[];
  final downloads = ref.read(sensitiveDownloadTransportProvider);
  if (photo != null) {
    final grant = await ref
        .read(upRepositoryProvider)
        .getAttachmentDownloadGrant(
          upId: detail.id,
          attachmentIndex: photo.index,
        );
    final extension = switch (grant.mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final file = await downloads.downloadToTemp(
      grant.url,
      extension: extension,
      maxBytes: grant.sizeBytes,
    );
    files.add(XFile(file.path, mimeType: grant.mime));
  }
  if (!context.mounted) return;
  final box = context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero) & box.size;
  if (files.isEmpty) {
    await Share.share(text, sharePositionOrigin: origin);
  } else {
    await Share.shareXFiles(files, text: text, sharePositionOrigin: origin);
  }
}
