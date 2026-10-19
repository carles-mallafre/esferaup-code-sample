import 'package:flutter/foundation.dart';

/// Build-time environment configuration, selected via `--dart-define`.
///
/// `flutter run --dart-define=APP_ENV=staging` (default, api-dev) / `dev`
/// (local API over Tailscale) / `prod`. Android Studio run configurations for
/// each live in `.run/`.
/// `API_BASE_URL` overrides the per-env default in non-release builds (useful
/// for a physical device pointing at a LAN host). Release builds reject it.
enum AppEnv {
  dev,
  staging,
  prod;

  static AppEnv get current {
    const raw = String.fromEnvironment('APP_ENV');
    return fromBuildValue(raw, releaseMode: kReleaseMode);
  }

  static AppEnv fromBuildValue(String raw, {required bool releaseMode}) {
    final value = raw.trim();
    if (value.isEmpty && !releaseMode) return AppEnv.staging;

    final environment = switch (value) {
      'dev' => AppEnv.dev,
      'staging' => AppEnv.staging,
      'prod' => AppEnv.prod,
      _ => null,
    };
    if (environment == null) {
      throw StateError('APP_ENV must be one of dev, staging, or prod.');
    }
    if (releaseMode && environment != AppEnv.prod) {
      throw StateError('Release builds require APP_ENV=prod.');
    }
    return environment;
  }
}

abstract final class Env {
  static AppEnv get env => AppEnv.current;
  static bool get isDev => env == AppEnv.dev;
  static bool get isProd => env == AppEnv.prod;

  /// The dev Mac's **stable Tailscale MagicDNS name** — it never changes with
  /// DHCP/Wi-Fi and reaches the local API from anywhere on the tailnet (the
  /// device just needs the Tailscale app + MagicDNS). Cleartext HTTP to
  /// `*.ts.net` is allow-listed in `ios/Runner/Info-Debug.plist` and the debug
  /// `AndroidManifest.xml`.
  ///
  /// Plain-LAN alternative (same-Wi-Fi, no Tailscale): swap in the Mac's LAN IP,
  /// e.g. `192.168.1.10` (find it with `ipconfig getifaddr en0`).
  static const devHost = 'dev-machine.your-tailnet.ts.net';

  /// API root for [e]. In non-release builds, a compile-time `API_BASE_URL`
  /// dart-define wins (LAN testing on a physical device); otherwise the
  /// per-env default. Release builds reject overrides.
  ///
  /// The authed feature API is mounted under `/api/v1` in `apps/api/main.py`
  /// (`include_router(api_router)` with the `/api` prefix). Only the no-auth
  /// public endpoints live at `/v1/...`. The mobile app talks to the authed API,
  /// so the base is `/api/v1`.
  static String baseUrlFor(AppEnv e) {
    const override = String.fromEnvironment('API_BASE_URL');
    return resolveBaseUrl(e, override: override, releaseMode: kReleaseMode);
  }

  static String resolveBaseUrl(
    AppEnv environment, {
    required String override,
    required bool releaseMode,
  }) {
    if (releaseMode && environment != AppEnv.prod) {
      throw StateError('Release builds require APP_ENV=prod.');
    }
    if (releaseMode && override.isNotEmpty) {
      throw StateError('Release builds cannot override API_BASE_URL.');
    }
    if (override.isNotEmpty) return override;
    return switch (environment) {
      AppEnv.dev => 'http://$devHost:8000/api/v1',
      AppEnv.staging => 'https://api-staging.example.com/api/v1',
      AppEnv.prod => 'https://api.esferaup.com/api/v1',
    };
  }

  /// API root for the build-time environment (the default; runtime debug
  /// switching goes through `apiEnvironmentProvider`).
  static String get apiBaseUrl => baseUrlFor(env);

  /// The public web and share hosts that belong to [e].
  ///
  /// A dev build must open dev links: a QR minted by api-dev prints
  /// `share-staging.example.com`, and a build that only trusts the production host
  /// refuses its own environment's links.
  static String webHostFor(AppEnv e) => switch (e) {
    AppEnv.dev || AppEnv.staging => 'staging.example.com',
    AppEnv.prod => 'esferaup.com',
  };

  static String shareHostFor(AppEnv e) => switch (e) {
    AppEnv.dev || AppEnv.staging => 'share-staging.example.com',
    AppEnv.prod => 'share.esferaup.com',
  };

  /// Base for links the app opens in a browser (help, account, plans).
  static String webBaseUrlFor(AppEnv e) => 'https://${webHostFor(e)}';

  static String get webHost => webHostFor(env);
  static String get shareHost => shareHostFor(env);
  static String get webBaseUrl => webBaseUrlFor(env);

  /// Human label for the env-switcher.
  static String labelFor(AppEnv e) => switch (e) {
    AppEnv.dev => 'Local (Tailscale)',
    AppEnv.staging => 'Dev server (api-dev)',
    AppEnv.prod => 'Production (api)',
  };

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Whole-request limit on the app client: connect, send, wait and retries.
  static const Duration requestDeadline = Duration(seconds: 30);
}
