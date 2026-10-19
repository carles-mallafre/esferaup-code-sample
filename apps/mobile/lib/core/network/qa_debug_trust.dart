import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A local QA stack's test CA (base64 of its PEM), passed only to debug builds
/// with `--dart-define=QA_EXTRA_CA_PEM_B64=…` so a physical Android device can
/// reach the stack's HTTPS storage (Android does not let Dart trust user CAs).
const _qaExtraCaPemB64 = String.fromEnvironment('QA_EXTRA_CA_PEM_B64');

/// The overrides to install, or null: release and profile builds never trust
/// an extra CA, and a debug build trusts one only when it was given.
HttpOverrides? qaDebugTrustOverrides({
  String pemBase64 = _qaExtraCaPemB64,
  bool debugMode = kDebugMode,
}) {
  if (!debugMode || pemBase64.isEmpty) return null;
  return _QaExtraCaOverrides(base64.decode(pemBase64));
}

class _QaExtraCaOverrides extends HttpOverrides {
  _QaExtraCaOverrides(this._pem);

  final List<int> _pem;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final trusted = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(_pem);
    return super.createHttpClient(context ?? trusted);
  }
}
