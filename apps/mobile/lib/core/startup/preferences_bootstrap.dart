import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef PreferencesLoader = Future<SharedPreferences> Function();
typedef PreferencesAppBuilder = Widget Function(SharedPreferences preferences);

/// Paints a native-looking Flutter shell immediately while non-sensitive device
/// preferences load. A broken platform channel becomes a retryable boundary
/// instead of leaving the process on the native splash indefinitely.
class PreferencesBootstrap extends StatefulWidget {
  const PreferencesBootstrap({
    super.key,
    required this.appBuilder,
    this.loader = SharedPreferences.getInstance,
    this.timeout = const Duration(seconds: 8),
  });

  final PreferencesAppBuilder appBuilder;
  final PreferencesLoader loader;
  final Duration timeout;

  @override
  State<PreferencesBootstrap> createState() => _PreferencesBootstrapState();
}

class _PreferencesBootstrapState extends State<PreferencesBootstrap> {
  late Future<SharedPreferences> _preferences;
  Widget? _app;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _preferences = widget.loader().timeout(widget.timeout);
  }

  void _retry() {
    setState(() {
      _app = null;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: _preferences,
      builder: (context, snapshot) {
        final preferences = snapshot.data;
        if (preferences != null) {
          return _app ??= widget.appBuilder(preferences);
        }
        if (snapshot.hasError) {
          return _PreferencesUnavailable(onRetry: _retry);
        }
        return const _PreferencesLoading();
      },
    );
  }
}

class _PreferencesLoading extends StatelessWidget {
  const _PreferencesLoading();

  @override
  Widget build(BuildContext context) {
    final label = switch (_languageCode(context)) {
      'ca' => 'EsferaUp s’està iniciant',
      'es' => 'EsferaUp se está iniciando',
      _ => 'EsferaUp is starting',
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        backgroundColor: Color(0xFF145D9E),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      builder: (context, child) => Semantics(label: label, child: child),
    );
  }
}

class _PreferencesUnavailable extends StatelessWidget {
  const _PreferencesUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = switch (_languageCode(context)) {
      'ca' => (
        title:
            'La configuració del dispositiu no està disponible temporalment.',
        body:
            'No hem obert les dades del compte. Torna-ho a provar per continuar.',
        retry: 'Torna-ho a provar',
      ),
      'es' => (
        title:
            'La configuración del dispositivo no está disponible temporalmente.',
        body:
            'No hemos abierto los datos de la cuenta. Inténtalo de nuevo para continuar.',
        retry: 'Intentar de nuevo',
      ),
      _ => (
        title: 'Device settings are temporarily unavailable.',
        body: 'Your account data has not been opened. Try again to continue.',
        retry: 'Try again',
      ),
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_backup_restore_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    copy.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(copy.body, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(copy.retry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _languageCode(BuildContext context) =>
    View.of(context).platformDispatcher.locale.languageCode;
