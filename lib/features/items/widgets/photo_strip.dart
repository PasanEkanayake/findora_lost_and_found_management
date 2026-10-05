import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// One thumbnail in a [PhotoStrip]: either a photo that's already saved on
/// the server ([PhotoStripItem.remote], carrying its `item_images.id` so
/// it can be removed later) or one the person just picked and hasn't
/// uploaded yet ([PhotoStripItem.local]).
class PhotoStripItem {
  const PhotoStripItem.remote({required this.imageId, required this.url}) : file = null;
  const PhotoStripItem.local(File this.file)
      : imageId = null,
        url = null;

  final String? imageId;
  final String? url;
  final File? file;

  bool get isRemote => file == null;
}

/// Horizontal row of photo thumbnails with an "add" tile at the end. Used by
/// both the post form and the edit form.
///
/// [onReplace] is optional: when given, tapping a thumbnail calls it (the
/// screens use that to offer "change photo"), and each thumbnail shows a
/// small swap badge as a hint that it's tappable.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRemove,
    this.onReplace,
  });

  final List<PhotoStripItem> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int>? onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: onReplace == null ? null : () => onReplace!(i),
                      child: Container(
                        width: 96,
                        height: 96,
                        // Fills whatever space BoxFit.contain leaves empty
                        // around a non-square photo, so a portrait or
                        // landscape shot doesn't look like it has a stray
                        // gap next to it.
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: items[i].isRemote
                            ? CachedNetworkImage(
                                imageUrl: items[i].url!,
                                fit: BoxFit.contain,
                                errorWidget: (context, url, error) => Icon(
                                  Icons.broken_image_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Image.file(items[i].file!, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  if (onReplace != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: IgnorePointer(
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                          child: const Icon(Icons.swap_horiz, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Semantics(
                      label: 'Remove photo',
                      button: true,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        behavior: HitTestBehavior.opaque,
                        // Padding widens the actual tap target well beyond
                        // the visible circle — full 48dp isn't achievable
                        // without overlapping the next thumbnail (only
                        // 12px separates them).
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.5),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              child: Icon(Icons.add_a_photo_outlined, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks camera or gallery, then picks. Null if the person backs out of
/// either step.
Future<File?> pickPhotoWithSheet(BuildContext context, ImagePicker picker) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final picked = await picker.pickImage(source: source, imageQuality: 85);
  return picked == null ? null : File(picked.path);
}
