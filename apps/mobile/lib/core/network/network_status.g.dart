// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_status.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$networkAvailableHash() => r'f24614868da2022bae939f62fd4d4103aa67b1d9';

/// Whether the device has any network interface up. Says nothing about the
/// API being reachable: use it only as a hint to retry a failed load.
///
/// Copied from [networkAvailable].
@ProviderFor(networkAvailable)
final networkAvailableProvider = StreamProvider<bool>.internal(
  networkAvailable,
  name: r'networkAvailableProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$networkAvailableHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NetworkAvailableRef = StreamProviderRef<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
