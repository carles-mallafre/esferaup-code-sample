import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session.g.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Why a session ended — drives the login screen's banner copy.
enum SessionExpiredReason {
  /// Token expired / refresh failed against the server.
  expired,

  /// `tokens_invalidated_at` bumped: password change, admin revoke.
  revoked,

  /// The adult's role changed (a downgrade, or the migració-at-18 flip).
  roleChanged,

  /// A password change whose response was lost: it may have been committed.
  passwordChangeUncertain,

  /// Normal sign-out or never-authenticated.
  unauthenticated;

  /// Reasons the sign-in screen explains instead of the welcome carousel.
  bool get isExplained =>
      this == roleChanged || this == passwordChangeUncertain;
}

/// App-wide auth status. The router's refresh notifier listens to this; the
/// [AuthInterceptor] calls [expire] on a hard logout.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  @override
  AuthStatus build() => AuthStatus.unknown;

  SessionExpiredReason? lastReason;

  void markAuthenticated() {
    lastReason = null;
    state = AuthStatus.authenticated;
  }

  void expire(SessionExpiredReason reason) {
    lastReason = reason;
    state = AuthStatus.unauthenticated;
  }
}
