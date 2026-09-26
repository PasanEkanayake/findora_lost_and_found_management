import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shown wherever an item has no photo (photos are optional when posting):
/// the Findora mark on a neutral tile. Purely a display fallback — it is
/// never uploaded or stored, so it can't pollute AI matching with a fake
/// "photo" that every photo-less post would then appear to share.
///
/// Fills whatever bounded space it's given; the logo scales to fit. The
/// "No photo" caption only appears when there's room for it.
class ItemPhotoPlaceholder extends StatelessWidget {
  const ItemPhotoPlaceholder({super.key, this.showLabel = false});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0;
        final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 120.0;
        final side = math.min(width, height);
        final logoSize = side * 0.5;
        final labelFits = showLabel && side >= 160;

        return Semantics(
          label: 'No photo',
          image: true,
          child: Container(
            color: theme.colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: 0.85,
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                  ),
                ),
                if (labelFits) ...[
                  const SizedBox(height: 10),
                  Text(
                    'No photo',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One item photo from a URL, or [ItemPhotoPlaceholder] when there is no
/// URL (an item posted without a photo) or the image can't be loaded.
class ItemPhoto extends StatelessWidget {
  const ItemPhoto({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.showLabel = false,
  });

  final String? url;
  final BoxFit fit;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) {
      return ItemPhotoPlaceholder(showLabel: showLabel);
    }

    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      placeholder: (context, url) => Container(color: surface),
      errorWidget: (context, url, error) => ItemPhotoPlaceholder(showLabel: showLabel),
    );
  }
}
