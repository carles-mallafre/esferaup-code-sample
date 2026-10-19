// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sessionControllerHash() => r'4f430d350d3bbf091862e2a0fe973775043c7ae2';

/// App-wide auth status. The router's refresh notifier listens to this; the
/// [AuthInterceptor] calls [expire] on a hard logout.
///
/// Copied from [SessionController].
@ProviderFor(SessionController)
final sessionControllerProvider =
    NotifierProvider<SessionController, AuthStatus>.internal(
      SessionController.new,
      name: r'sessionControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$sessionControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SessionController = Notifier<AuthStatus>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
