import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_status.g.dart';

/// Whether the device has any network interface up. Says nothing about the
/// API being reachable: use it only as a hint to retry a failed load.
@Riverpod(keepAlive: true)
Stream<bool> networkAvailable(Ref ref) => Connectivity().onConnectivityChanged
    .map((results) => results.any((r) => r != ConnectivityResult.none));
