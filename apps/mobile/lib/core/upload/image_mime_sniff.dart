import 'dart:io';

/// The image type its first bytes declare, or null when they are not one of
/// the formats the app uploads.
///
/// The picked file's name is not enough: on Android, image_picker re-encodes a
/// resized PNG without transparency as JPEG and keeps the `.png` name, and the
/// upload pipeline quarantines a body whose bytes do not match its MIME type.
String? sniffImageMime(List<int> head) {
  bool at(int offset, List<int> bytes) {
    if (head.length < offset + bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (head[offset + i] != bytes[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
      at(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  if (at(4, const [0x66, 0x74, 0x79, 0x70]) && head.length >= 12) {
    final brand = String.fromCharCodes(head.sublist(8, 12));
    if (const {
      'heic',
      'heix',
      'hevc',
      'heim',
      'heis',
      'mif1',
      'msf1',
    }.contains(brand)) {
      return 'image/heic';
    }
  }
  return null;
}

/// [sniffImageMime] of a file on disk (reads only its first bytes).
Future<String?> sniffImageFileMime(File file) async {
  final raf = await file.open();
  try {
    return sniffImageMime(await raf.read(16));
  } finally {
    await raf.close();
  }
}
