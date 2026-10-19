import 'package:dio/dio.dart';
import 'package:esferaup/core/errors/app_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One refused write. [sequence] makes two identical refusals in a row two
/// distinct events for the listener.
class ProfileWriteBlockNotice {
  const ProfileWriteBlockNotice({
    required this.reason,
    required this.sequence,
    this.profileId,
  });

  final ProfileWriteBlock reason;
  final int sequence;

  /// The profile named in the refused request's path, when there is one.
  final String? profileId;
}

class ProfileWriteBlockController extends Notifier<ProfileWriteBlockNotice?> {
  @override
  ProfileWriteBlockNotice? build() => null;

  void report(ProfileWriteBlock reason, {String? profileId}) {
    state = ProfileWriteBlockNotice(
      reason: reason,
      sequence: (state?.sequence ?? 0) + 1,
      profileId: profileId,
    );
  }
}

/// The last write a profile refused with 423. The app root turns each event
/// into one explanation, so every write surface gets it without its own
/// mapping.
final profileWriteBlockProvider =
    NotifierProvider<ProfileWriteBlockController, ProfileWriteBlockNotice?>(
      ProfileWriteBlockController.new,
    );

class ProfileWriteBlockInterceptor extends Interceptor {
  ProfileWriteBlockInterceptor(this._onBlocked);

  final void Function(ProfileWriteBlock reason, String? profileId) _onBlocked;

  static final RegExp _profileInPath = RegExp(
    r'/profiles/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:/|$)',
    caseSensitive: false,
  );

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 423 &&
        err.requestOptions.method.toUpperCase() != 'GET') {
      final envelope = err.response?.data;
      final error = envelope is Map ? envelope['error'] : null;
      final code = error is Map ? error['code'] : null;
      if (code is String && _codes.contains(code)) {
        _onBlocked(
          profileWriteBlockForCode(code),
          _profileInPath.firstMatch(err.requestOptions.path)?.group(1),
        );
      }
    }
    handler.next(err);
  }

  static const _codes = {
    'PROFILE_MIGRATION_IN_PROGRESS',
    'PROFILE_AWAITING_ADULT_CONSENT',
    'PROFILE_ERASURE_REQUESTED',
  };
}
