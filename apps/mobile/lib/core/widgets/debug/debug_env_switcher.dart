import 'package:esferaup/core/config/api_environment.dart';
import 'package:esferaup/core/config/env.dart';
import 'package:esferaup/core/network/session.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/feedback/app_snack_bar.dart';
import 'package:esferaup/core/widgets/option_picker_sheet.dart';
import 'package:esferaup/features/auth/presentation/providers/auth_providers.dart';
import 'package:esferaup/features/onboarding/presentation/providers/account_setup_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A debug-only chip (renders nothing in release) that shows the active API
/// backend and lets you switch on the fly. Switching repoints the Dio client and
/// clears the session so you re-authenticate against the new backend.
class DebugEnvSwitcher extends ConsumerWidget {
  const DebugEnvSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();
    final c = context.colors;
    final env = ref.watch(apiEnvironmentProvider);
    return Center(
      child: InkWell(
        onTap: () => _pick(context, ref, env),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.warningLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.warning),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bug_report_outlined, size: 15, color: c.warningInk),
              const SizedBox(width: 6),
              Text(
                'ENV · ${Env.labelFor(env)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.warningInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    AppEnv current,
  ) async {
    final picked = await showOptionPicker<AppEnv>(
      context: context,
      title: 'API environment',
      selected: current,
      options: [
        for (final e in AppEnv.values)
          PickerOption(
            value: e,
            label: Env.labelFor(e),
            sublabel: Env.baseUrlFor(e),
          ),
      ],
    );
    if (picked == null || picked == current) return;
    // New backend → the old tokens + onboarding state are meaningless. Clear them
    // so the router drops to the auth flow and we re-authenticate cleanly.
    await ref.read(sessionTransitionCoordinatorProvider).clear();
    await ref.read(apiEnvironmentProvider.notifier).select(picked);
    ref.read(registrationOnboardingIntentProvider.notifier).reset();
    ref
        .read(sessionControllerProvider.notifier)
        .expire(SessionExpiredReason.unauthenticated);
    if (context.mounted) {
      showInfoSnackBar(context, 'Switched to ${Env.labelFor(picked)}');
    }
  }
}
