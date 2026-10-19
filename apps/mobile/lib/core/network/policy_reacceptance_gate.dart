import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'policy_reacceptance_gate.g.dart';

class PolicyReacceptanceState {
  const PolicyReacceptanceState({
    this.required = false,
    this.requiredVersions = const {},
  });

  final bool required;
  final Map<String, String> requiredVersions;
}

@Riverpod(keepAlive: true)
class PolicyReacceptanceController extends _$PolicyReacceptanceController {
  @override
  PolicyReacceptanceState build() => const PolicyReacceptanceState();

  void requireReacceptance(Map<String, String> requiredVersions) {
    state = PolicyReacceptanceState(
      required: true,
      requiredVersions: Map.unmodifiable(requiredVersions),
    );
  }

  void clear() => state = const PolicyReacceptanceState();
}

class PolicyReacceptanceInterceptor extends Interceptor {
  PolicyReacceptanceInterceptor(this._onRequired);

  final void Function(Map<String, String> requiredVersions) _onRequired;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 403) {
      final envelope = err.response?.data;
      if (envelope is Map && envelope['error'] is Map) {
        final error = envelope['error'] as Map;
        if (error['code'] == 'POLICY_REACCEPT_REQUIRED') {
          _onRequired(_requiredVersions(error['details']));
        }
      }
    }
    handler.next(err);
  }

  Map<String, String> _requiredVersions(Object? details) {
    if (details is! Map) return const {};
    final raw = details['required_versions'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }
}
