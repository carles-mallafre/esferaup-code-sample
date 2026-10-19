// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_environment.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$apiEnvironmentHash() => r'2b8ceaf64a9f10d64b6edc5ec8616c45e90a095b';

/// The active API environment. Defaults to the build-time [AppEnv.current]; in
/// **debug** builds the debug env switcher can persist an override to repoint the
/// app at another backend. Release builds ignore any override (a prod build can
/// never be pointed at dev). The override is stored per build-time environment,
/// so picking another run configuration starts on that configuration's backend.
///
/// Copied from [ApiEnvironment].
@ProviderFor(ApiEnvironment)
final apiEnvironmentProvider =
    NotifierProvider<ApiEnvironment, AppEnv>.internal(
      ApiEnvironment.new,
      name: r'apiEnvironmentProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$apiEnvironmentHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ApiEnvironment = Notifier<AppEnv>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
