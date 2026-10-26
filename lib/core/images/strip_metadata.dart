import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Removes ALL metadata from a photo — above all the GPS position, the date,
/// and the phone's make and model that cameras write into the file (EXIF).
///
/// WHY. Photos on Findora are stored in a public bucket, so anyone holding a
/// photo's link can download the file. The app shows only an APPROXIMATE
/// location for a post (supabase/33_approximate_locations.sql), but a photo
/// taken with the camera app usually carries the EXACT place it was taken, and
/// Android's image picker deliberately copies that GPS data into the smaller
/// copy it makes when we ask for a 1600 px version. Without this step the
/// approximate-location protection could be undone by right-clicking a photo.
///
/// HOW. Decode the pixels, apply the rotation the file only *recorded* (so the
/// picture still looks upright without its orientation tag), and encode a fresh
/// JPEG. Nothing but pixels is carried over — EXIF, XMP, thumbnails and
/// comments are all gone. Transparent PNGs become opaque JPEGs, which is
/// fine for photos.
///
/// Throws a [FormatException] if the bytes aren't an image this can read —
/// callers must then NOT upload the original.
Uint8List stripImageMetadata(Uint8List bytes, {int quality = 85}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Not an image this app can read.');
  }
  final upright = img.bakeOrientation(decoded);
  // The pixels now carry the orientation; start the output with no metadata.
  upright.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(upright, quality: quality));
}

Uint8List _stripInBackground(Uint8List bytes) => stripImageMetadata(bytes);

/// [file] as a metadata-free JPEG, written next to it (the picker's cache
/// file is replaced by the clean copy, never uploaded). Runs off the UI thread
/// since decoding and encoding a 1600 px photo takes a moment. Throws on a
/// file that can't be read as an image.
Future<File> stripPhotoMetadata(File file) async {
  final original = await file.readAsBytes();
  final clean = await compute(_stripInBackground, original);
  final out = File('${file.path}.clean.jpg');
  await out.writeAsBytes(clean, flush: true);
  // The original still has the GPS in it; don't leave it lying in the cache.
  try {
    await file.delete();
  } catch (_) {
    // Best effort: the cache is private to the app and cleared by Android.
  }
  return out;
}
