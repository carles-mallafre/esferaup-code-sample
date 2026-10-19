import 'package:esferaup/core/widgets/media/memory_only_network_image.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves a short-lived authenticated grant without exposing object keys to
/// the widget tree. Non-image, unsafe, expired, and failed grants stay on the
/// caller-provided placeholder.
class AuthenticatedUpImage extends ConsumerWidget {
  const AuthenticatedUpImage({
    super.key,
    required this.upId,
    required this.placeholder,
    this.attachmentIndex = 0,
    this.fit = BoxFit.cover,
    this.cacheWidth = 1000,
  });

  final String upId;
  final int attachmentIndex;
  final BoxFit fit;
  final int cacheWidth;
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(upAttachmentDownloadGrantProvider(upId, attachmentIndex))
      .when(
        loading: () => placeholder,
        error: (_, _) => placeholder,
        data: (grant) {
          final imageMime =
              grant.mime == 'image/jpeg' ||
              grant.mime == 'image/png' ||
              grant.mime == 'image/webp';
          final fresh = grant.expiresAt.isAfter(
            DateTime.now().add(const Duration(seconds: 2)),
          );
          if (!grant.isSafeHttp || !fresh || !imageMime) return placeholder;
          return MemoryOnlyNetworkImage(
            source: MemoryOnlyNetworkImageSource(
              grant.url,
              cacheWidth: cacheWidth,
            ),
            fit: fit,
            placeholder: placeholder,
          );
        },
      );
}
