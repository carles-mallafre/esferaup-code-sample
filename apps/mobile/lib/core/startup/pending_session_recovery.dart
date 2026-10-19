import 'package:esferaup/core/network/secure_token_store.dart';

enum PendingSessionRecoveryResult { none, recovered, transportPending }

typedef PendingSessionRecovery =
    Future<PendingSessionRecoveryResult> Function(TokenPair sourcePair);

/// Keeps a receipt-bound source session unpublished until the same workspace
/// switch can be replayed or authoritatively rejected by the server.
class PendingSessionRecoveryUnavailable implements Exception {
  const PendingSessionRecoveryUnavailable();
}
