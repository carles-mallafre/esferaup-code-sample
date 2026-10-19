// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_startup.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$noSessionCleanupHash() => r'3a671da3ddfaf9090832e483b7b12176a1215489';

/// Application-root override removes tenant artifacts when secure storage has
/// no authenticated session. The no-op fallback keeps isolated test harnesses
/// independent from feature-layer providers.
///
/// Copied from [noSessionCleanup].
@ProviderFor(noSessionCleanup)
final noSessionCleanupProvider = Provider<NoSessionCleanup>.internal(
  noSessionCleanup,
  name: r'noSessionCleanupProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$noSessionCleanupHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NoSessionCleanupRef = ProviderRef<NoSessionCleanup>;
String _$pendingSessionRecoveryHash() =>
    r'ecb73052c98ec5047f86d623b171fbea19347b2f';

/// Feature-layer override replays a persisted tenant-switch receipt before the
/// old source session becomes visible after a process restart.
///
/// Copied from [pendingSessionRecovery].
@ProviderFor(pendingSessionRecovery)
final pendingSessionRecoveryProvider =
    Provider<PendingSessionRecovery>.internal(
      pendingSessionRecovery,
      name: r'pendingSessionRecoveryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pendingSessionRecoveryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PendingSessionRecoveryRef = ProviderRef<PendingSessionRecovery>;
String _$authenticatedSessionStartupHash() =>
    r'3053b952533a9c8339cbcdc3b296f18edbe7741c';

/// Application-root hook resumes account-bound workers only after startup has
/// recovered any pending tenant replacement and re-read the authoritative pair.
///
/// Copied from [authenticatedSessionStartup].
@ProviderFor(authenticatedSessionStartup)
final authenticatedSessionStartupProvider =
    Provider<AuthenticatedSessionStartup>.internal(
      authenticatedSessionStartup,
      name: r'authenticatedSessionStartupProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$authenticatedSessionStartupHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuthenticatedSessionStartupRef =
    ProviderRef<AuthenticatedSessionStartup>;
String _$appStartupHash() => r'7d2326856a5e52bbb516cb36a4fe85298575d2e7';

/// Gated startup sequence (§8). Restores the session from fail-closed secure
/// storage and seeds [SessionController]; the router shows the Splash while this
/// resolves. Force-update / remote-flags steps are layered in as those features
/// land.
///
/// Copied from [AppStartup].
@ProviderFor(AppStartup)
final appStartupProvider = AsyncNotifierProvider<AppStartup, void>.internal(
  AppStartup.new,
  name: r'appStartupProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appStartupHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$AppStartup = AsyncNotifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
