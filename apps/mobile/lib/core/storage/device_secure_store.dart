import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Raised when the device keychain/keystore cannot honor a secure operation.
/// Callers must fail closed rather than substitute plaintext persistence.
class SecureStorageUnavailable implements Exception {
  const SecureStorageUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'SecureStorageUnavailable($cause)';
}

/// Namespaced-by-caller key/value boundary for device-only secret material.
abstract interface class DeviceSecureStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

/// The only production boundary that instantiates `FlutterSecureStorage`.
///
/// iOS values remain on this device and are unavailable while it is locked;
/// Android uses encrypted shared preferences. No plaintext fallback exists.
class PlatformDeviceSecureStore implements DeviceSecureStore {
  PlatformDeviceSecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
              synchronizable: false,
            ),
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) =>
      _guard(() => _storage.read(key: key));

  @override
  Future<void> write({required String key, required String value}) =>
      _guard(() => _storage.write(key: key, value: value));

  @override
  Future<void> delete({required String key}) =>
      _guard(() => _storage.delete(key: key));

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on SecureStorageUnavailable {
      rethrow;
    } on Object catch (error) {
      throw SecureStorageUnavailable(error);
    }
  }
}
