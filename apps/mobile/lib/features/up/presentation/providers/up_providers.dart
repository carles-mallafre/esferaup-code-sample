import 'dart:async';

import 'package:esferaup/core/config/prefs.dart';
import 'package:esferaup/core/network/dio_client.dart';
import 'package:esferaup/core/upload/upload_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:esferaup/features/up/data/up_attachment_picker.dart';
import 'package:esferaup/features/up/data/up_audio_capture.dart';
import 'package:esferaup/features/up/data/datasources/up_remote_datasource.dart';
import 'package:esferaup/features/up/data/repositories/up_repository_impl.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'up_providers.g.dart';

@Riverpod(keepAlive: true)
UpRemoteDataSource upRemoteDataSource(Ref ref) =>
    UpRemoteDataSource(ref.watch(dioProvider));

@Riverpod(keepAlive: true)
UpRepository upRepository(Ref ref) =>
    UpRepositoryImpl(ref.watch(upRemoteDataSourceProvider));

@Riverpod(keepAlive: true)
UpAttachmentPicker upAttachmentPicker(Ref ref) =>
    NativeUpAttachmentPicker(ref.watch(sensitiveTempFileStoreProvider));

final upAudioPermissionGatewayProvider = Provider<UpAudioPermissionGateway>(
  (ref) => NativeUpAudioPermissionGateway(() => ref.read(prefsProvider)),
);

final upAudioRecorderBackendProvider = Provider<UpAudioRecorderBackend>(
  (ref) =>
      NativeUpAudioRecorderBackend(ref.watch(sensitiveTempFileStoreProvider)),
);

final upAudioCaptureControllerProvider =
    ChangeNotifierProvider<UpAudioCaptureController>((ref) {
      return UpAudioCaptureController(
        permission: ref.watch(upAudioPermissionGatewayProvider),
        recorder: ref.watch(upAudioRecorderBackendProvider),
      );
    });

@riverpod
class UpDetailController extends _$UpDetailController {
  int _attempt = 0;
  Timer? _timer;

  @override
  Future<UpDetail> build(String upId) async {
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      _timer?.cancel();
    });
    final detail = await ref.watch(upRepositoryProvider).getUp(upId);
    if (!disposed && detail.attachmentsPending && _attempt < 30) {
      final delay = _attempt < 10
          ? const Duration(seconds: 3)
          : const Duration(seconds: 30);
      _attempt += 1;
      _timer = Timer(delay, ref.invalidateSelf);
    }
    return detail;
  }

  void refresh() {
    _attempt = 0;
    ref.invalidateSelf();
  }

  Future<void> setPinned(bool pinned) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final result = await ref
        .read(upRepositoryProvider)
        .setPinned(upId: upId, pinned: pinned);
    state = AsyncData(current.copyWith(isPinned: result));
  }
}

@riverpod
Future<UpAttachmentDownloadGrant> upAttachmentDownloadGrant(
  Ref ref,
  String upId,
  int attachmentIndex,
) async {
  var disposed = false;
  Timer? timer;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });
  final grant = await ref
      .watch(upRepositoryProvider)
      .getAttachmentDownloadGrant(upId: upId, attachmentIndex: attachmentIndex);
  final refreshAfter =
      grant.expiresAt.difference(DateTime.now()) - const Duration(seconds: 5);
  if (!disposed && grant.isSafeHttp && refreshAfter > Duration.zero) {
    timer = Timer(refreshAfter, ref.invalidateSelf);
  }
  return grant;
}

@riverpod
Future<List<DeletedUp>> deletedUps(Ref ref, String profileId) =>
    ref.watch(upRepositoryProvider).listDeletedUps(profileId);
