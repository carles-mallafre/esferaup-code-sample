// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_refresher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$tokenRefresherHash() => r'bdd193e67a75b0165f9f2c754cd34b1106e17378';

/// Overridden in the auth feature's provider wiring. Throws until then so a
/// 401 before auth is set up fails loudly rather than silently.
///
/// Copied from [tokenRefresher].
@ProviderFor(tokenRefresher)
final tokenRefresherProvider = Provider<TokenRefresher>.internal(
  tokenRefresher,
  name: r'tokenRefresherProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$tokenRefresherHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TokenRefresherRef = ProviderRef<TokenRefresher>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
