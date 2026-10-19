import 'package:esferaup/core/network/secure_token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'token_refresher.g.dart';

/// Port: refreshes the token pair against `POST /v1/auth/refresh`. Implemented
/// by the auth feature (`AuthRepositoryImpl`) and wired via an override of
/// [tokenRefresherProvider]. Keeping the port in `core/` lets the Dio client
/// depend on it without `core` importing `features/auth` (dependency rule).
abstract interface class TokenRefresher {
  /// Returns the new pair, or throws if the server rejects the refresh. The
  /// caller owns generation-checked persistence after the network await.
  Future<TokenPair> refresh(String refreshToken);
}

/// Overridden in the auth feature's provider wiring. Throws until then so a
/// 401 before auth is set up fails loudly rather than silently.
@Riverpod(keepAlive: true)
TokenRefresher tokenRefresher(Ref ref) => throw UnimplementedError(
  'tokenRefresherProvider must be overridden by the auth feature',
);
