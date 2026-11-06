/// `user/item/file.jpg` -> `user/item/thumb_file.jpg`: where a photo's
/// thumbnail lives in the bucket, next to the original. Always a JPEG,
/// whatever the original was.
///
/// Keep in step with `thumbPathFor` in
/// supabase/functions/make-thumbnails/index.ts, which creates the file — the
/// app uses this name to delete the thumbnail together with its photo.
String thumbnailPathFor(String storagePath) {
  final slash = storagePath.lastIndexOf('/');
  final dir = slash == -1 ? '' : storagePath.substring(0, slash + 1);
  final file = storagePath.substring(slash + 1).replaceFirst(RegExp(r'\.[^.]+$'), '');
  return '${dir}thumb_$file.jpg';
}
