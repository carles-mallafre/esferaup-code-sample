import 'dart:async';

import 'package:esferaup/core/storage/device_secure_store.dart';

export 'package:esferaup/core/storage/device_secure_store.dart'
    show DeviceSecureStore, SecureStorageUnavailable;

/// The authenticated session token pair + access-token expiry.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiry,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiry;

  bool expiresWithin(Duration buffer) =>
      DateTime.now().toUtc().add(buffer).isAfter(accessExpiry);
}

/// A token pair bound to the in-process authenticated-session generation.
///
/// Network refreshes carry this generation across the await boundary and may
/// publish their result only while it is still current. Logout and explicit
/// session replacement advance the generation before touching secure storage,
/// so a stale response cannot resurrect credentials.
class TokenPairSnapshot {
  const TokenPairSnapshot({required this.pair, required this.generation});

  final TokenPair pair;
  final int generation;
}

/// Fail-closed secure storage for the token pair. iOS Keychain is
/// `unlocked_this_device_only` (no iCloud backup); Android EncryptedSharedPrefs.
/// Tokens are NEVER mirrored to plain SharedPreferences.
class SecureTokenStore {
  SecureTokenStore([DeviceSecureStore? storage])
    : _storage = storage ?? PlatformDeviceSecureStore();

  final DeviceSecureStore _storage;
  Future<void> _operationTail = Future<void>.value();
  int _sessionGeneration = 0;
  bool _sessionReadsBlocked = false;

  static const _kAccess = 'auth.access';
  static const _kRefresh = 'auth.refresh';
  static const _kExpiry = 'auth.access_expiry';
  static const _kActiveSlot = 'auth.active_slot';
  static const _slotA = 'a';
  static const _slotB = 'b';
  static const _loggedOut = 'none';

  /// Probes the keychain at startup. Throws [SecureStorageUnavailable] if the
  /// platform store can't be read — the caller must block the app.
  Future<void> ensureAvailable() async {
    try {
      await read();
    } on SecureStorageUnavailable {
      rethrow;
    } catch (e) {
      throw SecureStorageUnavailable(e);
    }
  }

  Future<TokenPair?> read() async => (await readSnapshot())?.pair;

  Future<TokenPairSnapshot?> readSnapshot() {
    final requestedGeneration = _sessionGeneration;
    return _serialized(() async {
      if (_sessionReadsBlocked || requestedGeneration != _sessionGeneration) {
        return null;
      }
      final pair = await _read();
      if (pair == null ||
          _sessionReadsBlocked ||
          requestedGeneration != _sessionGeneration) {
        return null;
      }
      return TokenPairSnapshot(pair: pair, generation: requestedGeneration);
    });
  }

  bool isGenerationCurrent(int generation) => generation == _sessionGeneration;

  /// Invalidates every in-flight refresh before an explicit login or tenant
  /// replacement starts and hides the old pair from in-process readers. The
  /// caller must subsequently publish or clear with the returned generation.
  int beginSessionTransition() {
    _sessionReadsBlocked = true;
    return ++_sessionGeneration;
  }

  Future<TokenPair?> _read() async {
    try {
      final active = await _storage.read(key: _kActiveSlot);
      if (active == _loggedOut) return null;
      if (active == _slotA || active == _slotB) {
        return await _readCompleteSlot(active!);
      }
      if (active != null) {
        throw StateError('Invalid secure-session slot marker');
      }

      final legacy = await _readLegacy();
      if (legacy == null) return null;
      // One-time migration from the original three-key layout. The inactive
      // slot is completed and verified before the single active pointer flips.
      await _commit(legacy, currentSlot: null);
      return legacy;
    } on SecureStorageUnavailable {
      rethrow;
    } catch (e) {
      throw SecureStorageUnavailable(e);
    }
  }

  Future<void> write(TokenPair pair) {
    final generation = ++_sessionGeneration;
    _sessionReadsBlocked = true;
    return _serialized(() async {
      await _write(pair);
      if (generation == _sessionGeneration) _sessionReadsBlocked = false;
    });
  }

  /// Publishes a rotated pair only if no login, session switch, or logout has
  /// superseded the session that initiated the network refresh.
  Future<bool> writeIfCurrent(TokenPair pair, {required int generation}) =>
      _serialized(() async {
        if (generation != _sessionGeneration) return false;
        await _write(pair);
        final current = generation == _sessionGeneration;
        if (current) _sessionReadsBlocked = false;
        return current;
      });

  /// Removes the persisted pair without advancing an already-reserved
  /// transition generation. Used to fail closed when replacement cleanup or
  /// target-session readiness cannot complete.
  Future<bool> clearStorageIfCurrent({required int generation}) =>
      _serialized(() async {
        if (generation != _sessionGeneration) return false;
        await _clear();
        final current = generation == _sessionGeneration;
        if (current) _sessionReadsBlocked = false;
        return current;
      });

  Future<void> _write(TokenPair pair) async {
    try {
      if (pair.accessToken.isEmpty || pair.refreshToken.isEmpty) {
        throw ArgumentError('Session tokens cannot be empty');
      }
      final current = await _storage.read(key: _kActiveSlot);
      if (current != null &&
          current != _slotA &&
          current != _slotB &&
          current != _loggedOut) {
        throw StateError('Invalid secure-session slot marker');
      }
      await _commit(
        pair,
        currentSlot: current == _slotA || current == _slotB ? current : null,
      );
    } on SecureStorageUnavailable {
      rethrow;
    } catch (e) {
      throw SecureStorageUnavailable(e);
    }
  }

  Future<void> clear() {
    final generation = ++_sessionGeneration;
    _sessionReadsBlocked = true;
    return _serialized(() async {
      await _clear();
      if (generation == _sessionGeneration) _sessionReadsBlocked = false;
    });
  }

  /// Invalidates and removes the current local session while returning the
  /// refresh token in memory for a best-effort bare-client server revocation.
  Future<TokenPair?> takeAndClear() {
    final generation = ++_sessionGeneration;
    _sessionReadsBlocked = true;
    return _serialized(() async {
      final pair = await _read();
      await _clear();
      if (generation == _sessionGeneration) _sessionReadsBlocked = false;
      return pair;
    });
  }

  /// Clears only the session that initiated a failed refresh. A late failure
  /// must never erase credentials from a newer login or tenant switch.
  Future<bool> clearIfCurrent({required int generation}) {
    if (generation != _sessionGeneration) return Future.value(false);
    final clearGeneration = ++_sessionGeneration;
    _sessionReadsBlocked = true;
    return _serialized(() async {
      await _clear();
      if (clearGeneration == _sessionGeneration) _sessionReadsBlocked = false;
      return true;
    });
  }

  Future<void> _clear() async {
    try {
      // The tombstone is the atomic logout point. If cleanup is interrupted,
      // subsequent reads remain unauthenticated rather than reviving a stale
      // legacy/slot credential set.
      await _storage.write(key: _kActiveSlot, value: _loggedOut);
      for (final key in [
        _kAccess,
        _kRefresh,
        _kExpiry,
        ..._slotKeys(_slotA),
        ..._slotKeys(_slotB),
      ]) {
        await _storage.delete(key: key);
      }
      await _storage.delete(key: _kActiveSlot);
    } on SecureStorageUnavailable {
      rethrow;
    } catch (e) {
      throw SecureStorageUnavailable(e);
    }
  }

  Future<void> _commit(TokenPair pair, {required String? currentSlot}) async {
    final next = currentSlot == _slotA ? _slotB : _slotA;
    final keys = _slotKeys(next);
    await _storage.write(key: keys[0], value: pair.accessToken);
    await _storage.write(key: keys[1], value: pair.refreshToken);
    await _storage.write(
      key: keys[2],
      value: pair.accessExpiry.toUtc().toIso8601String(),
    );

    final staged = await _readCompleteSlot(next);
    if (!_samePair(staged, pair)) {
      throw StateError('Secure-session staging verification failed');
    }

    // A single key write publishes the fully staged replacement. Readers see
    // either the complete old pair or the complete new pair, never a mixture.
    await _storage.write(key: _kActiveSlot, value: next);
    if (await _storage.read(key: _kActiveSlot) != next) {
      throw StateError('Secure-session slot activation failed');
    }

    // Legacy credentials become unreachable at the pointer flip. Remove them
    // only afterward so a crash before activation still leaves a valid session.
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpiry);
    await _deleteSlot(next == _slotA ? _slotB : _slotA);
  }

  Future<void> _deleteSlot(String slot) async {
    for (final key in _slotKeys(slot)) {
      await _storage.delete(key: key);
    }
  }

  Future<TokenPair?> _readLegacy() async {
    final values = await Future.wait([
      _storage.read(key: _kAccess),
      _storage.read(key: _kRefresh),
      _storage.read(key: _kExpiry),
    ]);
    if (values.every((value) => value == null)) return null;
    return _parseCompletePair(values, source: 'legacy');
  }

  Future<TokenPair> _readCompleteSlot(String slot) async {
    final keys = _slotKeys(slot);
    final values = await Future.wait([
      _storage.read(key: keys[0]),
      _storage.read(key: keys[1]),
      _storage.read(key: keys[2]),
    ]);
    return _parseCompletePair(values, source: 'active slot');
  }

  TokenPair _parseCompletePair(List<String?> values, {required String source}) {
    final access = values[0];
    final refresh = values[1];
    final expiryRaw = values[2];
    final expiry = DateTime.tryParse(expiryRaw ?? '');
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty ||
        expiry == null) {
      throw StateError('Incomplete or corrupt $source session');
    }
    return TokenPair(
      accessToken: access,
      refreshToken: refresh,
      accessExpiry: expiry,
    );
  }

  static List<String> _slotKeys(String slot) => [
    'auth.$slot.access',
    'auth.$slot.refresh',
    'auth.$slot.access_expiry',
  ];

  static bool _samePair(TokenPair left, TokenPair right) =>
      left.accessToken == right.accessToken &&
      left.refreshToken == right.refreshToken &&
      left.accessExpiry.toUtc() == right.accessExpiry.toUtc();

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
