import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class SensitiveTempSessionChanged implements Exception {
  const SensitiveTempSessionChanged();
}

/// App-owned cache for sensitive bytes that native pickers expose via temporary
/// or scoped-storage paths. Paths are never persisted. The entire directory is
/// removed on logout/erasure and stale remnants are reaped on next use.
class SensitiveTempFileStore {
  SensitiveTempFileStore({Future<Directory> Function()? tempDirectory})
    : _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _tempDirectory;
  Future<void> _operationTail = Future<void>.value();
  int _generation = 0;
  bool _writesEnabled = true;

  void beginSession() {
    _generation++;
    _writesEnabled = true;
  }

  Future<Directory> _root({required bool create}) async {
    final base = await _tempDirectory();
    final root = Directory(p.join(base.path, 'esferaup_sensitive'));
    if (create) await root.create(recursive: true);
    return root;
  }

  Future<File> copyFrom(File source, {required String extension}) {
    final expectedGeneration = _generation;
    if (!_writesEnabled) {
      return Future<File>.error(const SensitiveTempSessionChanged());
    }
    final safeExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    if (safeExtension.isEmpty) {
      return Future<File>.error(
        const FormatException('A safe extension is required.'),
      );
    }
    return _serialized(() async {
      _assertWritable(expectedGeneration);
      await _cleanupStale();
      final root = await _root(create: true);
      final destination = File(
        p.join(root.path, '${_uuid.v4()}.$safeExtension'),
      );
      try {
        await source.openRead().pipe(destination.openWrite());
        _assertWritable(expectedGeneration);
        return destination;
      } on Object {
        try {
          if (await destination.exists()) await destination.delete();
        } on FileSystemException {
          // A later session cleanup retries without exposing the path.
        }
        rethrow;
      }
    });
  }

  Future<File> allocate({required String extension}) {
    final expectedGeneration = _generation;
    if (!_writesEnabled) {
      return Future<File>.error(const SensitiveTempSessionChanged());
    }
    final safeExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    if (safeExtension.isEmpty) {
      return Future<File>.error(
        const FormatException('A safe extension is required.'),
      );
    }
    return _serialized(() async {
      _assertWritable(expectedGeneration);
      await _cleanupStale();
      final root = await _root(create: true);
      final destination = File(
        p.join(root.path, '${_uuid.v4()}.$safeExtension'),
      );
      _assertWritable(expectedGeneration);
      return destination;
    });
  }

  Future<void> delete(File file) => _serialized(() async {
    final root = await _root(create: false);
    if (!await root.exists()) return;
    final canonicalRoot = p.canonicalize(root.path);
    final canonicalFile = p.canonicalize(file.path);
    if (!p.isWithin(canonicalRoot, canonicalFile)) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort: cleanupAll/cleanupStale retries later. Never log the path.
    }
  });

  Future<void> cleanupStale({Duration maxAge = const Duration(hours: 24)}) =>
      _serialized(() => _cleanupStale(maxAge: maxAge));

  Future<void> _cleanupStale({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final root = await _root(create: false);
    if (!await root.exists()) return;
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File) continue;
      try {
        final modified = await entry.lastModified();
        if (modified.isBefore(cutoff)) await entry.delete();
      } on FileSystemException {
        // A concurrent upload may hold the file. The next sweep retries.
      }
    }
  }

  Future<void> cleanupAll() {
    _generation++;
    _writesEnabled = false;
    return _serialized(() async {
      final root = await _root(create: false);
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } on FileSystemException {
        // These bytes are plaintext picker copies. Unlike an encrypted cache,
        // key destruction cannot make a failed unlink harmless, so session
        // replacement must fail closed and retry before publishing tokens.
        if (await root.exists()) rethrow;
      }
      if (await root.exists()) {
        throw StateError('Sensitive temporary storage could not be cleared');
      }
    });
  }

  void _assertWritable(int expectedGeneration) {
    if (!_writesEnabled || expectedGeneration != _generation) {
      throw const SensitiveTempSessionChanged();
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
