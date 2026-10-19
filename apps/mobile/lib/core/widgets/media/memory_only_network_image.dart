import 'package:flutter/material.dart';

final class MemoryOnlyNetworkImageSource {
  factory MemoryOnlyNetworkImageSource(Uri url, {int? cacheWidth}) =>
      MemoryOnlyNetworkImageSource._(
        ResizeImage.resizeIfNeeded(
          cacheWidth,
          null,
          NetworkImage(url.toString()),
        ),
      );

  const MemoryOnlyNetworkImageSource._(this.provider);

  final ImageProvider<Object> provider;

  Future<bool> evict() => provider.evict();
}

/// Renders authenticated family media through Flutter's in-process image cache.
///
/// Keep filesystem-backed image-cache packages out of this path: the URL may
/// resolve to child or other private family content.
class MemoryOnlyNetworkImage extends StatelessWidget {
  const MemoryOnlyNetworkImage({
    super.key,
    required this.source,
    required this.placeholder,
    this.error,
    this.fit = BoxFit.cover,
  });

  final MemoryOnlyNetworkImageSource source;
  final Widget placeholder;
  final Widget? error;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image(
    image: source.provider,
    fit: fit,
    gaplessPlayback: true,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (wasSynchronouslyLoaded || frame != null) return child;
      return placeholder;
    },
    errorBuilder: (_, _, _) => error ?? placeholder,
  );
}
