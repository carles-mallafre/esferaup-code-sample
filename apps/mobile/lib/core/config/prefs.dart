import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synchronous access to [SharedPreferences]. Overridden in `main()` with the
/// instance loaded during the gated startup sequence so providers can read it
/// without an async hop.
final prefsProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('prefsProvider must be overridden in main()'),
);
