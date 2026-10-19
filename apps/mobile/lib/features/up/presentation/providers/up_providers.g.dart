// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'up_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$upRemoteDataSourceHash() =>
    r'873e681c8a27a564e1c92deaf1dda522e3f207e4';

/// See also [upRemoteDataSource].
@ProviderFor(upRemoteDataSource)
final upRemoteDataSourceProvider = Provider<UpRemoteDataSource>.internal(
  upRemoteDataSource,
  name: r'upRemoteDataSourceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$upRemoteDataSourceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpRemoteDataSourceRef = ProviderRef<UpRemoteDataSource>;
String _$upRepositoryHash() => r'0200d2645eafc4ec3c9cd43870e84152cb18cce0';

/// See also [upRepository].
@ProviderFor(upRepository)
final upRepositoryProvider = Provider<UpRepository>.internal(
  upRepository,
  name: r'upRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$upRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpRepositoryRef = ProviderRef<UpRepository>;
String _$upAttachmentPickerHash() =>
    r'91e468baa567a910d2813654c2c4b8cd07143f41';

/// See also [upAttachmentPicker].
@ProviderFor(upAttachmentPicker)
final upAttachmentPickerProvider = Provider<UpAttachmentPicker>.internal(
  upAttachmentPicker,
  name: r'upAttachmentPickerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$upAttachmentPickerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpAttachmentPickerRef = ProviderRef<UpAttachmentPicker>;
String _$upAttachmentDownloadGrantHash() =>
    r'feab32ccf62d77d4dcf038ece68c9c865138037f';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [upAttachmentDownloadGrant].
@ProviderFor(upAttachmentDownloadGrant)
const upAttachmentDownloadGrantProvider = UpAttachmentDownloadGrantFamily();

/// See also [upAttachmentDownloadGrant].
class UpAttachmentDownloadGrantFamily
    extends Family<AsyncValue<UpAttachmentDownloadGrant>> {
  /// See also [upAttachmentDownloadGrant].
  const UpAttachmentDownloadGrantFamily();

  /// See also [upAttachmentDownloadGrant].
  UpAttachmentDownloadGrantProvider call(String upId, int attachmentIndex) {
    return UpAttachmentDownloadGrantProvider(upId, attachmentIndex);
  }

  @override
  UpAttachmentDownloadGrantProvider getProviderOverride(
    covariant UpAttachmentDownloadGrantProvider provider,
  ) {
    return call(provider.upId, provider.attachmentIndex);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'upAttachmentDownloadGrantProvider';
}

/// See also [upAttachmentDownloadGrant].
class UpAttachmentDownloadGrantProvider
    extends AutoDisposeFutureProvider<UpAttachmentDownloadGrant> {
  /// See also [upAttachmentDownloadGrant].
  UpAttachmentDownloadGrantProvider(String upId, int attachmentIndex)
    : this._internal(
        (ref) => upAttachmentDownloadGrant(
          ref as UpAttachmentDownloadGrantRef,
          upId,
          attachmentIndex,
        ),
        from: upAttachmentDownloadGrantProvider,
        name: r'upAttachmentDownloadGrantProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$upAttachmentDownloadGrantHash,
        dependencies: UpAttachmentDownloadGrantFamily._dependencies,
        allTransitiveDependencies:
            UpAttachmentDownloadGrantFamily._allTransitiveDependencies,
        upId: upId,
        attachmentIndex: attachmentIndex,
      );

  UpAttachmentDownloadGrantProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.upId,
    required this.attachmentIndex,
  }) : super.internal();

  final String upId;
  final int attachmentIndex;

  @override
  Override overrideWith(
    FutureOr<UpAttachmentDownloadGrant> Function(
      UpAttachmentDownloadGrantRef provider,
    )
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UpAttachmentDownloadGrantProvider._internal(
        (ref) => create(ref as UpAttachmentDownloadGrantRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        upId: upId,
        attachmentIndex: attachmentIndex,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<UpAttachmentDownloadGrant> createElement() {
    return _UpAttachmentDownloadGrantProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UpAttachmentDownloadGrantProvider &&
        other.upId == upId &&
        other.attachmentIndex == attachmentIndex;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, upId.hashCode);
    hash = _SystemHash.combine(hash, attachmentIndex.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UpAttachmentDownloadGrantRef
    on AutoDisposeFutureProviderRef<UpAttachmentDownloadGrant> {
  /// The parameter `upId` of this provider.
  String get upId;

  /// The parameter `attachmentIndex` of this provider.
  int get attachmentIndex;
}

class _UpAttachmentDownloadGrantProviderElement
    extends AutoDisposeFutureProviderElement<UpAttachmentDownloadGrant>
    with UpAttachmentDownloadGrantRef {
  _UpAttachmentDownloadGrantProviderElement(super.provider);

  @override
  String get upId => (origin as UpAttachmentDownloadGrantProvider).upId;
  @override
  int get attachmentIndex =>
      (origin as UpAttachmentDownloadGrantProvider).attachmentIndex;
}

String _$deletedUpsHash() => r'971e3669ae3e6c2acdd2692e83ef67f4b8562420';

/// See also [deletedUps].
@ProviderFor(deletedUps)
const deletedUpsProvider = DeletedUpsFamily();

/// See also [deletedUps].
class DeletedUpsFamily extends Family<AsyncValue<List<DeletedUp>>> {
  /// See also [deletedUps].
  const DeletedUpsFamily();

  /// See also [deletedUps].
  DeletedUpsProvider call(String profileId) {
    return DeletedUpsProvider(profileId);
  }

  @override
  DeletedUpsProvider getProviderOverride(
    covariant DeletedUpsProvider provider,
  ) {
    return call(provider.profileId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'deletedUpsProvider';
}

/// See also [deletedUps].
class DeletedUpsProvider extends AutoDisposeFutureProvider<List<DeletedUp>> {
  /// See also [deletedUps].
  DeletedUpsProvider(String profileId)
    : this._internal(
        (ref) => deletedUps(ref as DeletedUpsRef, profileId),
        from: deletedUpsProvider,
        name: r'deletedUpsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$deletedUpsHash,
        dependencies: DeletedUpsFamily._dependencies,
        allTransitiveDependencies: DeletedUpsFamily._allTransitiveDependencies,
        profileId: profileId,
      );

  DeletedUpsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.profileId,
  }) : super.internal();

  final String profileId;

  @override
  Override overrideWith(
    FutureOr<List<DeletedUp>> Function(DeletedUpsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: DeletedUpsProvider._internal(
        (ref) => create(ref as DeletedUpsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        profileId: profileId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<DeletedUp>> createElement() {
    return _DeletedUpsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is DeletedUpsProvider && other.profileId == profileId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, profileId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin DeletedUpsRef on AutoDisposeFutureProviderRef<List<DeletedUp>> {
  /// The parameter `profileId` of this provider.
  String get profileId;
}

class _DeletedUpsProviderElement
    extends AutoDisposeFutureProviderElement<List<DeletedUp>>
    with DeletedUpsRef {
  _DeletedUpsProviderElement(super.provider);

  @override
  String get profileId => (origin as DeletedUpsProvider).profileId;
}

String _$upDetailControllerHash() =>
    r'94497737afa5d513c65f72ba98fd86a5f4646453';

abstract class _$UpDetailController
    extends BuildlessAutoDisposeAsyncNotifier<UpDetail> {
  late final String upId;

  FutureOr<UpDetail> build(String upId);
}

/// See also [UpDetailController].
@ProviderFor(UpDetailController)
const upDetailControllerProvider = UpDetailControllerFamily();

/// See also [UpDetailController].
class UpDetailControllerFamily extends Family<AsyncValue<UpDetail>> {
  /// See also [UpDetailController].
  const UpDetailControllerFamily();

  /// See also [UpDetailController].
  UpDetailControllerProvider call(String upId) {
    return UpDetailControllerProvider(upId);
  }

  @override
  UpDetailControllerProvider getProviderOverride(
    covariant UpDetailControllerProvider provider,
  ) {
    return call(provider.upId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'upDetailControllerProvider';
}

/// See also [UpDetailController].
class UpDetailControllerProvider
    extends AutoDisposeAsyncNotifierProviderImpl<UpDetailController, UpDetail> {
  /// See also [UpDetailController].
  UpDetailControllerProvider(String upId)
    : this._internal(
        () => UpDetailController()..upId = upId,
        from: upDetailControllerProvider,
        name: r'upDetailControllerProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$upDetailControllerHash,
        dependencies: UpDetailControllerFamily._dependencies,
        allTransitiveDependencies:
            UpDetailControllerFamily._allTransitiveDependencies,
        upId: upId,
      );

  UpDetailControllerProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.upId,
  }) : super.internal();

  final String upId;

  @override
  FutureOr<UpDetail> runNotifierBuild(covariant UpDetailController notifier) {
    return notifier.build(upId);
  }

  @override
  Override overrideWith(UpDetailController Function() create) {
    return ProviderOverride(
      origin: this,
      override: UpDetailControllerProvider._internal(
        () => create()..upId = upId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        upId: upId,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<UpDetailController, UpDetail>
  createElement() {
    return _UpDetailControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UpDetailControllerProvider && other.upId == upId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, upId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UpDetailControllerRef on AutoDisposeAsyncNotifierProviderRef<UpDetail> {
  /// The parameter `upId` of this provider.
  String get upId;
}

class _UpDetailControllerProviderElement
    extends
        AutoDisposeAsyncNotifierProviderElement<UpDetailController, UpDetail>
    with UpDetailControllerRef {
  _UpDetailControllerProviderElement(super.provider);

  @override
  String get upId => (origin as UpDetailControllerProvider).upId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
