import 'dart:typed_data';

import 'package:findora/core/images/strip_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A small JPEG that carries EXIF (here an orientation tag; a real camera file
/// also carries GPS, date and device model in the same block).
Uint8List _jpegWithExif({int width = 40, int height = 20, int orientation = 6}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 30, 30));
  image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

bool _containsAscii(Uint8List bytes, String needle) {
  final pattern = needle.codeUnits;
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  group('stripImageMetadata', () {
    test('the test photo really does carry an EXIF block to begin with', () {
      expect(_containsAscii(_jpegWithExif(), 'Exif'), isTrue);
    });

    test('the result carries no EXIF block at all', () {
      final clean = stripImageMetadata(_jpegWithExif());
      expect(_containsAscii(clean, 'Exif'), isFalse);
      expect(img.decodeJpg(clean)!.exif.isEmpty, isTrue);
    });

    test('the rotation the file only recorded is applied to the pixels first', () {
      // 40x20 tagged "rotate 90°" shows as 20x40; the clean copy has no tag, so
      // the pixels themselves must now be 20x40.
      final clean = img.decodeJpg(stripImageMetadata(_jpegWithExif(orientation: 6)))!;
      expect(clean.width, 20);
      expect(clean.height, 40);
    });

    test('an upright photo keeps its size', () {
      final clean = img.decodeJpg(stripImageMetadata(_jpegWithExif(orientation: 1)))!;
      expect(clean.width, 40);
      expect(clean.height, 20);
    });

    test('a PNG becomes a plain JPEG', () {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));
      final clean = stripImageMetadata(png);
      expect(img.decodeJpg(clean), isNotNull);
    });

    test('bytes that are not an image are refused — never passed through', () {
      expect(() => stripImageMetadata(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
      expect(() => stripImageMetadata(Uint8List(0)), throwsFormatException);
    });
  });
}
