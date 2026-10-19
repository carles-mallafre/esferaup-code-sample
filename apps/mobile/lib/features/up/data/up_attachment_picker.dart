import 'dart:io';

import 'package:esferaup/core/upload/image_mime_sniff.dart';
import 'package:esferaup/core/upload/sensitive_temp_file_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

enum UpAttachmentPickSource { camera, gallery, pdf }

class PickedUpAttachment {
  const PickedUpAttachment({
    required this.file,
    required this.mime,
    required this.displayName,
  });

  final File file;
  final String mime;
  final String displayName;

  bool get isImage => mime.startsWith('image/');
  bool get isAudio => mime.startsWith('audio/');
  String get uploadContext => isImage
      ? 'up_image'
      : isAudio
      ? 'up_audio'
      : 'up_document';
}

abstract interface class UpAttachmentPicker {
  Future<PickedUpAttachment?> pick(UpAttachmentPickSource source);
}

class NativeUpAttachmentPicker implements UpAttachmentPicker {
  NativeUpAttachmentPicker(this._tempFiles, {ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final SensitiveTempFileStore _tempFiles;
  final ImagePicker _imagePicker;

  @override
  Future<PickedUpAttachment?> pick(UpAttachmentPickSource source) async {
    final selected = switch (source) {
      UpAttachmentPickSource.camera => await _pickImage(ImageSource.camera),
      UpAttachmentPickSource.gallery => await _pickImage(ImageSource.gallery),
      UpAttachmentPickSource.pdf => await _pickPdf(),
    };
    if (selected == null) return null;
    final size = await selected.file.length();
    final maxBytes = selected.isImage ? 25 * 1024 * 1024 : 50 * 1024 * 1024;
    if (size > maxBytes) throw const FileSystemException('File too large');
    final copied = await _tempFiles.copyFrom(
      selected.file,
      extension: _extensionForMime(selected.mime),
    );
    return PickedUpAttachment(
      file: copied,
      mime: selected.mime,
      displayName: selected.displayName,
    );
  }

  Future<PickedUpAttachment?> _pickImage(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 2048,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    final mime =
        await sniffImageFileMime(File(picked.path)) ??
        picked.mimeType ??
        _imageMimeFromExtension(p.extension(picked.path));
    if (!_allowedImageMimes.contains(mime)) {
      throw const FormatException('Unsupported image format');
    }
    return PickedUpAttachment(
      file: File(picked.path),
      mime: mime,
      displayName: picked.name,
    );
  }

  Future<PickedUpAttachment?> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: false,
    );
    final files = result?.files;
    final picked = files == null || files.isEmpty ? null : files.single;
    if (picked == null) return null;
    final path = picked.path;
    if (path == null) {
      throw const FileSystemException('Selected PDF is not locally readable');
    }
    return PickedUpAttachment(
      file: File(path),
      mime: 'application/pdf',
      displayName: picked.name,
    );
  }

  static const _allowedImageMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
  };

  static String _imageMimeFromExtension(String extension) =>
      switch (extension.toLowerCase()) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.heic' || '.heif' => 'image/heic',
        _ => 'application/octet-stream',
      };

  static String _extensionForMime(String mime) => switch (mime) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'application/pdf' => 'pdf',
    'audio/mp4' => 'm4a',
    _ => throw const FormatException('Unsupported file format'),
  };
}
