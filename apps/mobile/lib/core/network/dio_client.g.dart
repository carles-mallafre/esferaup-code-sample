// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dio_client.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$secureTokenStoreHash() => r'ab4cfac2d7b85777ef8d39df71884cbd39aee5a8';

/// See also [secureTokenStore].
@ProviderFor(secureTokenStore)
final secureTokenStoreProvider = Provider<SecureTokenStore>.internal(
  secureTokenStore,
  name: r'secureTokenStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$secureTokenStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SecureTokenStoreRef = ProviderRef<SecureTokenStore>;
String _$sessionTerminatorHash() => r'bf98fb34b94ba13a82f26c3c0982f4cc44684fd3';

/// Core fallback used outside the application root (background/unit harnesses).
/// The production container overrides this with the full artifact coordinator.
///
/// Copied from [sessionTerminator].
@ProviderFor(sessionTerminator)
final sessionTerminatorProvider = Provider<SessionTerminator>.internal(
  sessionTerminator,
  name: r'sessionTerminatorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sessionTerminatorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SessionTerminatorRef = ProviderRef<SessionTerminator>;
String _$etagCacheInterceptorHash() =>
    r'ab6665da6f41fec288bbf73ddc2bce1d0c574840';

/// See also [etagCacheInterceptor].
@ProviderFor(etagCacheInterceptor)
final etagCacheInterceptorProvider = Provider<ETagCacheInterceptor>.internal(
  etagCacheInterceptor,
  name: r'etagCacheInterceptorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$etagCacheInterceptorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EtagCacheInterceptorRef = ProviderRef<ETagCacheInterceptor>;
String _$dioHash() => r'4854929ef522ca46db15dd2707715a9f8985942b';

/// The app's single Dio. Interceptor order:
/// RequestDeadline → Auth → CorrelationId → Idempotency → PolicyReacceptance → ProfileWriteBlock
/// → Retry → ETagCache → (debug) NetworkLog.
/// The logger runs last so it traces the fully-decorated request + the final
/// outcome. Background isolates use [backgroundDio] instead.
///
/// Copied from [dio].
@ProviderFor(dio)
final dioProvider = Provider<Dio>.internal(
  dio,
  name: r'dioProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$dioHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DioRef = ProviderRef<Dio>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
