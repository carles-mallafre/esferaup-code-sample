import 'package:esferaup/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:esferaup/core/config/env.dart';
import 'package:esferaup/core/network/session.dart';
import 'package:esferaup/core/network/policy_reacceptance_gate.dart';
import 'package:esferaup/core/startup/app_startup.dart';
import 'package:esferaup/core/startup/storage_blocked_screen.dart';
import 'package:esferaup/features/activa/domain/entities/activa_catalogue.dart';
import 'package:esferaup/features/activa/presentation/providers/activa_providers.dart';
import 'package:esferaup/features/activa/presentation/screens/activa_screen.dart';
import 'package:esferaup/features/activa/presentation/screens/activa_recommendation_handoff_screen.dart';
import 'package:esferaup/features/activa/presentation/screens/assigned_exercise_hydration_screen.dart';
import 'package:esferaup/features/activa/presentation/screens/exercise_detail_screen.dart';
import 'package:esferaup/features/activa/presentation/screens/exercise_link_screen.dart';
import 'package:esferaup/features/activa/presentation/screens/plan_catalog_screen.dart';
import 'package:esferaup/features/activa/presentation/screens/plan_detail_screen.dart';
import 'package:esferaup/features/activa/presentation/screens/replacement_fascicle_screen.dart';
import 'package:esferaup/features/arxiu/domain/arxiu_entities.dart';
import 'package:esferaup/features/arxiu/presentation/screens/arxiu_document_screen.dart';
import 'package:esferaup/features/arxiu/presentation/screens/arxiu_screen.dart';
import 'package:esferaup/features/subscription/presentation/screens/points_screen.dart';
import 'package:esferaup/features/arxiu/presentation/screens/arxiu_section_screen.dart';
import 'package:esferaup/features/feed/domain/entities/feed_entities.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/family/presentation/widgets/retry_failed_family_on_open.dart';
import 'package:esferaup/features/family/presentation/screens/family_invite_screen.dart';
import 'package:esferaup/features/family/presentation/screens/profile_access_history_screen.dart';
import 'package:esferaup/features/family/presentation/screens/profile_access_screen.dart';
import 'package:esferaup/features/family/presentation/screens/profiles_management_screen.dart';
import 'package:esferaup/features/threesixty/domain/threesixty_entities.dart';
import 'package:esferaup/features/threesixty/presentation/actions/open_place_material_exercise.dart';
import 'package:esferaup/features/threesixty/presentation/screens/category_suggestion_screen.dart';
import 'package:esferaup/features/threesixty/presentation/screens/conversa_inbox_screen.dart';
import 'package:esferaup/features/threesixty/presentation/screens/conversa_screen.dart';
import 'package:esferaup/features/auth/presentation/providers/auth_providers.dart';
import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:esferaup/features/auth/presentation/screens/join_pending_screen.dart';
import 'package:esferaup/features/auth/presentation/screens/login_screen.dart';
import 'package:esferaup/features/esferes/presentation/screens/esfera_detail_screen.dart';
import 'package:esferaup/features/esferes/presentation/screens/esferes_screen.dart';
import 'package:esferaup/features/home/presentation/screens/inici_screen.dart';
import 'package:esferaup/features/legal/legal_content.dart';
import 'package:esferaup/features/legal/presentation/screens/legal_document_screen.dart';
import 'package:esferaup/features/legal/presentation/screens/legal_reaccept_screen.dart';
import 'package:esferaup/features/legal/presentation/widgets/privacy_sheet.dart';
import 'package:esferaup/features/main/presentation/screens/main_shell.dart';
import 'package:esferaup/features/memories/presentation/screens/memories_screen.dart';
import 'package:esferaup/features/memories/presentation/screens/memory_detail_screen.dart';
import 'package:esferaup/features/adult_consent/presentation/screens/adult_consent_screen.dart';
import 'package:esferaup/features/adult_consent/presentation/screens/data_rights_screen.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_screen.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_status_screen.dart';
import 'package:esferaup/features/migration/presentation/providers/migration_providers.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_acknowledgement_screen.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_existing_account_screen.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_existing_choice_screen.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_existing_done_screen.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_existing_sign_in_screen.dart';
import 'package:esferaup/features/migration/presentation/screens/migration_destination_screen.dart';
import 'package:esferaup/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:esferaup/features/notifications/domain/deep_link_target.dart';
import 'package:esferaup/features/notifications/presentation/providers/deep_link_providers.dart';
import 'package:esferaup/features/notifications/presentation/providers/push_notification_controller.dart';
import 'package:esferaup/features/notifications/presentation/screens/public_link_handoff_screen.dart';
import 'package:esferaup/features/onboarding/presentation/screens/account_setup_pas1_screen.dart';
import 'package:esferaup/features/onboarding/presentation/screens/account_setup_pas2_screen.dart';
import 'package:esferaup/features/onboarding/presentation/screens/child_form_screen.dart';
import 'package:esferaup/features/onboarding/presentation/providers/account_setup_providers.dart';
import 'package:esferaup/features/onboarding/presentation/screens/first_point_screen.dart';
import 'package:esferaup/features/onboarding/presentation/screens/get_started_screen.dart';
import 'package:esferaup/features/onboarding/presentation/screens/profile_created_screen.dart';
import 'package:esferaup/features/onboarding/presentation/screens/sign_up_screen.dart';
import 'package:esferaup/features/onboarding/presentation/screens/welcome_carousel_screen.dart';
import 'package:esferaup/features/onboarding/presentation/widgets/profile_access_sheets.dart';
import 'package:esferaup/features/settings/presentation/screens/accessibility_settings_screen.dart';
import 'package:esferaup/features/settings/presentation/screens/account_screen.dart';
import 'package:esferaup/features/settings/presentation/screens/privacy_screen.dart';
import 'package:esferaup/features/settings/presentation/screens/reminder_settings_screen.dart';
import 'package:esferaup/features/settings/presentation/screens/settings_screen.dart';
import 'package:esferaup/features/professional_sharing/presentation/screens/patrons_screen.dart';
import 'package:esferaup/features/professional_sharing/presentation/screens/patro_detail_screen.dart';
import 'package:esferaup/features/professional_sharing/presentation/screens/professional_shares_screen.dart';
import 'package:esferaup/features/settings/presentation/providers/settings_providers.dart';
import 'package:esferaup/features/settings/presentation/providers/export_delivery_providers.dart';
import 'package:esferaup/features/settings/presentation/screens/erasure_recovery_screen.dart';
import 'package:esferaup/features/settings/presentation/screens/export_delivery_screen.dart';
import 'package:esferaup/features/esfera_plans/presentation/screens/esfera_plans_screen.dart';
import 'package:esferaup/features/subscription/presentation/screens/subscription_management_screen.dart';
import 'package:esferaup/features/splash/presentation/screens/splash_screen.dart';
import 'package:esferaup/features/summaries/presentation/screens/summaries_screen.dart';
import 'package:esferaup/features/summaries/presentation/screens/weekly_summary_screen.dart';
import 'package:esferaup/features/threesixty/presentation/screens/observations_screen.dart';
import 'package:esferaup/features/threesixty/presentation/screens/permissions_overview_screen.dart';
import 'package:esferaup/features/threesixty/presentation/screens/place_detail_screen.dart';
import 'package:esferaup/features/threesixty/presentation/screens/three_sixty_screen.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_saved_screen.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_screen.dart';
import 'package:esferaup/features/up/presentation/screens/crisi_screen.dart';
import 'package:esferaup/features/up/presentation/screens/my_ups_screen.dart';
import 'package:esferaup/features/up/presentation/screens/recently_deleted_ups_screen.dart';
import 'package:esferaup/features/up/presentation/screens/up_detail_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:esferaup/features/home/presentation/screens/reminder_setup_screen.dart';
import 'package:esferaup/features/family/presentation/screens/profile_detail_screen.dart';
import 'package:esferaup/features/settings/presentation/widgets/change_password_sheet.dart';
import 'package:esferaup/features/support/presentation/help_contact_screen.dart';
import 'package:esferaup/features/dev_tools/dev_menu_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const storageBlocked = '/storage-blocked';
  static const welcome = '/onboarding/welcome';
  static const getStarted = '/onboarding/get-started';
  static const register = '/onboarding/register';

  /// «Unirme a una familia»: registration with a family code.
  static const registerJoin = '/onboarding/join';

  /// A provisional account waiting for (or turned away by) a family.
  static const joinPending = '/join/pending';
  static const firstPoint = '/onboarding/first-point';
  static const accountSetup = '/onboarding/account-setup';
  static const accountSetupChildren = '/onboarding/account-setup/children';
  static const childForm = '/onboarding/account-setup/child';
  static const profileCreated = '/onboarding/account-setup/created';
  static const accountSetupReminder = '/onboarding/account-setup/reminder';
  static const reminderSetup = '/reminder-setup';
  static const login = '/auth/login';
  static const forgotPassword = '/auth/forgot-password';
  static const familyInvite = '/family/invite';
  static const privacyPolicy = '/legal/privacy';
  static const termsOfUse = '/legal/terms';
  static const legalReaccept = '/legal/reaccept';
  static const inici = '/main/inici';
  static const activa = '/main/activa';
  static const esferes = '/main/esferes';
  static const threeSixty = '/main/360';
  static const addUp = '/up/add';
  static const addUpSaved = '/up/saved';
  static const crisi = '/up/crisi';
  static String crisiResumeFor(String upId) =>
      '/up/crisi?resume=${Uri.encodeQueryComponent(upId)}';
  static const myUps = '/up/mine';
  static const deletedUps = '/up/deleted';
  static const upDetail = '/ups/:upId';
  static const esferaDetail = '/esferes/:category';
  static const memories = '/memories';
  static const patrons = '/memories/patrons';
  static const patronDetail = '/memories/patrons/:patternId';
  static const memoryDetail = '/memories/:upId';

  static String patronDetailFor(String patternId) =>
      '/memories/patrons/$patternId';
  static const summaries = '/summaries';
  static const points = '/points';
  static const summaryDetail = '/summaries/:period/:reference';
  static const notifications = '/notifications';
  static const notificationLink = '/n/:notificationId';
  static const publicObservationLink = '/o/:token';
  static const publicDocumentLink = '/d/:token';
  static const activaExerciseLink = '/e/:code';
  static const activaRecommendation = '/activa/recommendation';
  static const activaReplacementFascicle =
      '/activa/profiles/:profileId/enrolments/:enrolmentId/fascicles/:fascicleId/replacement';
  static const settings = '/settings';
  static const accessibility = '/settings/accessibility';
  static const account = '/settings/account';
  static const privacy = '/settings/privacy';
  static const notificationSettings = '/settings/notifications';
  static const reminder = '/settings/reminder';
  static const help = '/settings/help';
  static const devMenu = '/settings/dev';
  static const professionalShares = '/settings/professional-shares';
  static const profiles = '/settings/profiles';

  /// Child-profile form reachable after onboarding; the onboarding form route
  /// is bounced by the funnel redirect once the family has profiles.
  static const profileNew = '/settings/profiles/new';
  static const profileDetail = '/settings/profiles/:profileId';
  static const profileAccess = '/settings/profiles/:profileId/access';
  static const profileAccessHistory =
      '/settings/profiles/:profileId/access-history';
  static const erasureRecovery = '/privacy/erasure-recovery';
  static const exportDelivery = '/privacy/export';
  static const subscription = '/settings/subscription';
  static const esferaPlans = '/settings/esfera-plans';
  static const arxiu = '/arxiu';
  static const arxiuSection = '/arxiu/seccio';
  static const arxiuDocument = '/arxiu/documents/:documentId';
  static const activaCatalog = '/activa/catalog';
  static const activaPlan = '/activa/plan';
  static const activaExercise = '/activa/exercise';
  static const activaAssignedExercise =
      '/activa/profiles/:profileId/enrolments/:enrolmentId/fascicles/:fascicleId/exercises/:exerciseId';
  static const migration = '/migration';
  static const migrationAcknowledge = '/migration/acknowledge';
  // The handoff link's email already has an account (ADR-026 addendum).
  static const migrationExistingAccount = '/migration/existing';
  static const migrationExistingSignIn = '/migration/existing/sign-in';
  static const migrationExistingChoice = '/migration/existing/choice';
  static const migrationExistingDone = '/migration/existing/done';
  static const profileMigration = '/settings/profiles/:profileId/migration';
  static const profileMigrationDestination =
      '/settings/profiles/:profileId/migration/destination';
  static const profileMigrationStatus =
      '/settings/profiles/:profileId/migration/status';
  static const adultConsent = '/adult-consent';
  static const adultConsentRights = '/adult-consent/rights';
  static const placeDetail = '/360/place';
  static const categorySuggestion = '/360/category-suggestion';
  static const conversa = '/360/conversa';
  static const conversaInbox = '/360/converses';
  static const observations = '/360/observations';
  static const permissions = '/360/permissions';

  static String upDetailFor(String upId) => '/ups/${Uri.encodeComponent(upId)}';
  static String addUpSavedFor(String upId) =>
      Uri(path: addUpSaved, queryParameters: {'upId': upId}).toString();
  static String esferaDetailFor(String category) =>
      '/esferes/${Uri.encodeComponent(category)}';

  /// The Esferes hub with one of its sub-tabs selected (`esferes`, `ups`,
  /// `memories`, `summaries`); the tab is a query parameter so the shell branch
  /// and the bottom nav stay in place.
  static String esferesTabFor(String tab) => '$esferes?tab=$tab';
  static String memoryDetailFor(String upId) =>
      '/memories/${Uri.encodeComponent(upId)}';
  static String arxiuDocumentFor(String documentId) =>
      '/arxiu/documents/${Uri.encodeComponent(documentId)}';
  static String summaryDetailFor(String period, String reference) =>
      '/summaries/${Uri.encodeComponent(period)}/${Uri.encodeComponent(reference)}';
  static String profileDetailFor(String profileId) =>
      '/settings/profiles/${Uri.encodeComponent(profileId)}';
  static String profileAccessFor(String profileId) =>
      '/settings/profiles/${Uri.encodeComponent(profileId)}/access';
  static String profileAccessHistoryFor(String profileId) =>
      '/settings/profiles/${Uri.encodeComponent(profileId)}/access-history';
  static String profileMigrationFor(String profileId) =>
      '/settings/profiles/${Uri.encodeComponent(profileId)}/migration';
  static String profileMigrationStatusFor(String profileId) =>
      '/settings/profiles/${Uri.encodeComponent(profileId)}/migration/status';
  static String profileMigrationDestinationFor(String profileId) =>
      '/settings/profiles/${Uri.encodeComponent(profileId)}/migration/destination';
}

/// The app's single [GoRouter]. It does NOT `ref.watch` (that would rebuild the
/// router and crash on a duplicate GlobalKey); a [_RouterRefresh] listens to
/// startup + session and notifies, and the redirect `ref.read`s state at
/// decision time.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final startup = ref.read(appStartupProvider);
      final erasureRecovery = ref.read(
        pendingErasureRecoveryControllerProvider,
      );
      final exportDelivery = ref.read(pendingExportDeliveryProvider);
      final loc = state.matchedLocation;
      final pending = ref.read(pendingDeepLinkProvider);

      // Public bearer-token pages intentionally stay on their isolated Astro
      // origins. Their native route is only a hand-off and does not require an
      // account or access to secure storage.
      if (pending != null &&
          (pending.kind == DeepLinkKind.publicObservation ||
              pending.kind == DeepLinkKind.publicDocument) &&
          loc != pending.appPath) {
        return pending.appPath;
      }
      if (loc.startsWith('/o/') || loc.startsWith('/d/')) return null;

      // Fail-closed (§7.1): keychain unavailable → the app refuses to operate.
      if (startup.hasError ||
          erasureRecovery.hasError ||
          exportDelivery.hasError) {
        return loc == Routes.storageBlocked ? null : Routes.storageBlocked;
      }
      // While the session is being restored, hold on Splash.
      if (!startup.hasValue || exportDelivery.isLoading) {
        return loc == Routes.splash ? null : Routes.splash;
      }

      final authed =
          ref.read(sessionControllerProvider) == AuthStatus.authenticated;
      if (!authed) {
        if (erasureRecovery.valueOrNull != null) {
          final justCancelled =
              loc == Routes.login &&
              state.uri.queryParameters['erasure'] == 'cancelled';
          return loc == Routes.erasureRecovery || justCancelled
              ? null
              : Routes.erasureRecovery;
        }
        if (pending?.kind == DeepLinkKind.activaExercise ||
            pending?.kind == DeepLinkKind.activaRecommendation) {
          final canAuthenticate =
              loc == Routes.login ||
              loc == Routes.register ||
              loc == Routes.forgotPassword;
          return canAuthenticate ? null : Routes.login;
        }
        if (pending?.kind == DeepLinkKind.familyInvite) {
          final canAuthenticate =
              loc == Routes.login ||
              loc == Routes.register ||
              loc.startsWith('/legal');
          return canAuthenticate ? null : Routes.login;
        }
        if (pending?.kind == DeepLinkKind.migration ||
            pending?.kind == DeepLinkKind.adultConsent) {
          final canAuthenticate =
              loc == Routes.login ||
              loc == Routes.register ||
              loc == Routes.forgotPassword ||
              loc.startsWith('/legal') ||
              (pending?.kind == DeepLinkKind.migration &&
                  loc.startsWith(Routes.migrationExistingAccount));
          return canAuthenticate ? null : Routes.login;
        }
        if (pending?.kind == DeepLinkKind.gdprExport) {
          final canAuthenticate =
              loc == Routes.login ||
              loc == Routes.register ||
              loc == Routes.forgotPassword;
          return canAuthenticate ? null : Routes.login;
        }
        // Unauthenticated: the onboarding funnel + login are allowed; anything
        // else lands on the Welcome carousel, or on sign-in when the session
        // ended for a reason the adult must be told.
        final inAuthFlow =
            loc.startsWith('/onboarding') ||
            loc.startsWith('/auth') ||
            loc.startsWith('/legal');
        if (inAuthFlow) return null;
        final endReason = ref
            .read(sessionControllerProvider.notifier)
            .lastReason;
        return endReason?.isExplained ?? false ? Routes.login : Routes.welcome;
      }
      final policyReaccept = ref.read(policyReacceptanceControllerProvider);
      if (policyReaccept.required) {
        final canReview =
            loc == Routes.legalReaccept ||
            loc == Routes.privacyPolicy ||
            loc == Routes.termsOfUse;
        return canReview ? null : Routes.legalReaccept;
      }
      if (pending?.kind == DeepLinkKind.familyInvite) {
        // Stays put once there: the registration funnel below would otherwise
        // send a just-registered account back to First Point, and around again.
        return loc == Routes.familyInvite ? null : Routes.familyInvite;
      }
      if (pending?.kind == DeepLinkKind.migration) {
        return loc == Routes.migrationAcknowledge ||
                loc.startsWith(Routes.migrationExistingAccount)
            ? null
            : Routes.migrationAcknowledge;
      }
      if (pending?.kind == DeepLinkKind.adultConsent) {
        // The rights explainer is part of the same decision, so it may sit on
        // top of the consent page without the link being dropped.
        return loc == Routes.adultConsent || loc == Routes.adultConsentRights
            ? null
            : Routes.adultConsent;
      }
      if (pending?.kind == DeepLinkKind.gdprExport &&
          loc != Routes.exportDelivery) {
        return Routes.exportDelivery;
      }
      if (loc == Routes.exportDelivery) return null;
      final familyState = ref.read(currentFamilyProvider);
      // Registered with a family code and not accepted yet: the account has no
      // family, so it can only wait, send another code or create its own.
      if (_isProvisionalAccount(familyState.error)) {
        return loc == Routes.joinPending || loc.startsWith('/legal')
            ? null
            : Routes.joinPending;
      }
      final registrationIntent = ref.read(registrationOnboardingIntentProvider);
      final signupBonus = ref
          .read(registrationOnboardingIntentProvider.notifier)
          .signupBonus;
      if (!familyState.hasValue) {
        // Entry screens wait for a family reload (e.g. after sign-in or legal
        // re-acceptance) so a profile-less account goes straight to setup
        // instead of flashing Inici first.
        final onEntryRoute =
            loc == Routes.splash ||
            loc == Routes.login ||
            loc == Routes.legalReaccept;
        if (!familyState.hasError || (familyState.isLoading && onEntryRoute)) {
          return loc == Routes.splash ? null : Routes.splash;
        }
      }
      final profiles = familyState.valueOrNull?.profiles;
      const setupRoutes = {
        Routes.accountSetup,
        Routes.accountSetupChildren,
        Routes.childForm,
        Routes.profileCreated,
        Routes.accountSetupReminder,
      };
      // Only the family's owner sets it up; an adult invited into the family
      // (one account = one family, ADR-025) adds no profiles to it.
      final isFamilyOwner = familyState.valueOrNull?.isFamilyOwner ?? true;
      if (profiles != null &&
          profiles.isEmpty &&
          !registrationIntent &&
          isFamilyOwner) {
        return setupRoutes.contains(loc) ? null : Routes.accountSetup;
      }
      if (registrationIntent) {
        const registrationFunnel = {Routes.firstPoint, ...setupRoutes};
        if (loc == Routes.firstPoint && signupBonus?.showCelebration != true) {
          return Routes.accountSetup;
        }
        if (registrationFunnel.contains(loc)) return null;
        return signupBonus?.showCelebration == true
            ? Routes.firstPoint
            : Routes.accountSetup;
      }
      if (pending?.kind == DeepLinkKind.activaExercise &&
          loc != pending!.appPath) {
        return pending.appPath;
      }
      if (pending?.kind == DeepLinkKind.activaRecommendation &&
          loc != pending!.appPath) {
        return pending.appPath;
      }
      // Onboarded: leave splash / login / onboarding behind, land on Inici.
      if (loc == Routes.splash ||
          loc == Routes.login ||
          loc == Routes.legalReaccept ||
          loc == Routes.joinPending ||
          loc.startsWith('/onboarding')) {
        return Routes.inici;
      }
      if (pending?.kind == DeepLinkKind.notification &&
          loc != pending!.appPath) {
        return pending.appPath;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.storageBlocked,
        builder: (context, state) => StorageBlockedScreen(
          error:
              ref.watch(appStartupProvider).error ??
              ref.watch(pendingErasureRecoveryControllerProvider).error ??
              ref.watch(pendingExportDeliveryProvider).error,
          onRetry: () {
            ref.invalidate(pendingErasureRecoveryControllerProvider);
            ref.invalidate(pendingExportDeliveryProvider);
            ref.invalidate(appStartupProvider);
          },
        ),
      ),
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => WelcomeCarouselScreen(
          onFinish: () => context.go(Routes.getStarted),
        ),
      ),
      GoRoute(
        path: Routes.getStarted,
        builder: (context, state) => GetStartedScreen(
          onCreateAccount: () => context.push(Routes.register),
          onJoinFamily: () => context.push(Routes.registerJoin),
          onSignIn: () => context.go(Routes.login),
          onDemo: () => context.go(Routes.welcome),
        ),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) {
          return SignUpScreen(
            onBack: () => context.canPop()
                ? context.pop()
                : context.go(Routes.getStarted),
            onSignIn: () => context.go(Routes.login),
            onExistingAccount: (email) {
              ref.read(existingAccountHandoffProvider.notifier).prefill(email);
              context.push(Routes.migrationExistingAccount);
            },
            onPrivacy: () => showPrivacySheet(
              context,
              onReadPolicy: () => context.push(Routes.privacyPolicy),
            ),
            onLegal: (which) => context.push(
              which == 'terms' ? Routes.termsOfUse : Routes.privacyPolicy,
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.registerJoin,
        builder: (context, state) => SignUpScreen(
          joinFamily: true,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.getStarted),
          onSignIn: () => context.go(Routes.login),
          onPrivacy: () => showPrivacySheet(
            context,
            onReadPolicy: () => context.push(Routes.privacyPolicy),
          ),
          onLegal: (which) => context.push(
            which == 'terms' ? Routes.termsOfUse : Routes.privacyPolicy,
          ),
        ),
      ),
      GoRoute(
        path: Routes.joinPending,
        builder: (context, state) => const JoinPendingScreen(),
      ),
      GoRoute(
        path: Routes.firstPoint,
        builder: (context, state) {
          final signupBonus = ref
              .read(registrationOnboardingIntentProvider.notifier)
              .signupBonus;
          if (signupBonus?.showCelebration != true) {
            return const SizedBox.shrink();
          }
          return FirstPointScreen(
            awarded: signupBonus!.points,
            onContinue: () => context.go(Routes.accountSetup),
          );
        },
      ),
      GoRoute(
        path: Routes.accountSetup,
        builder: (context, state) {
          final signupBonus = ref
              .read(registrationOnboardingIntentProvider.notifier)
              .signupBonus;
          return AccountSetupPas1Screen(
            onBack: signupBonus?.showCelebration == true
                ? () => context.canPop()
                      ? context.pop()
                      : context.go(Routes.firstPoint)
                : null,
            onContinue: () => context.go(Routes.accountSetupChildren),
          );
        },
      ),
      GoRoute(
        path: Routes.accountSetupChildren,
        builder: (context, state) => AccountSetupPas2Screen(
          onBack: () => context.go(Routes.accountSetup),
          onAddChild: () => context.push(Routes.childForm),
          // With children → celebrate at N2; an empty skip finishes the funnel.
          onFinish: () => context.go(
            ref.read(accountSetupControllerProvider).children.isEmpty
                ? Routes.accountSetupReminder
                : Routes.profileCreated,
          ),
        ),
      ),
      GoRoute(
        path: Routes.childForm,
        builder: (context, state) => ChildFormScreen(
          onBack: () => context.pop(),
          onSaved: () => context.pop(),
        ),
      ),
      GoRoute(
        path: Routes.profileCreated,
        builder: (context, state) {
          final children = ref.read(accountSetupControllerProvider).children;

          return ProfileCreatedScreen(
            childName: children.isEmpty ? '' : children.last.name,
            onGoToApp: () => context.go(Routes.accountSetupReminder),
            onAddAnother: () => context.go(Routes.accountSetupChildren),
            onShare: () async {
              try {
                final family = await ref.read(currentFamilyProvider.future);
                final profileId = children.isEmpty ? null : children.last.id;
                if (profileId == null) throw StateError('Missing profile id');
                if (!context.mounted) return;
                await showProfileInviteSheet(
                  context: context,
                  familyId: family.id,
                  profileId: profileId,
                );
              } on Object {
                if (!context.mounted) return;
                final l10n = AppLocalizations.of(context);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(l10n.profileCreatedInviteUnavailable),
                    ),
                  );
              }
            },
            onConnect: () => showCentreConnectSheet(
              context: context,
              onOpenThreeSixty: () {
                ref
                    .read(registrationOnboardingIntentProvider.notifier)
                    .complete();
                ref.invalidate(currentFamilyProvider);
                context.go(Routes.threeSixty);
              },
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.accountSetupReminder,
        builder: (context, state) => ReminderSetupScreen(
          stepLabel: AppLocalizations.of(context).setupStep3Eyebrow,
          onBack: () => context.go(
            ref.read(accountSetupControllerProvider).children.isEmpty
                ? Routes.accountSetupChildren
                : Routes.profileCreated,
          ),
          onFinished: () {
            ref.read(registrationOnboardingIntentProvider.notifier).complete();
            ref.invalidate(currentFamilyProvider);
            context.go(Routes.inici);
          },
        ),
      ),
      GoRoute(
        path: Routes.reminderSetup,
        builder: (context, state) => ReminderSetupScreen(
          onBack: () => context.pop(),
          onFinished: () =>
              context.canPop() ? context.pop() : context.go(Routes.inici),
        ),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => LoginScreen(
          erasureCancelled: state.uri.queryParameters['erasure'] == 'cancelled',
          sessionEndReason: ref
              .read(sessionControllerProvider.notifier)
              .lastReason,
          invitePending:
              ref.read(pendingDeepLinkProvider)?.kind ==
              DeepLinkKind.familyInvite,
          onForgotPassword: () => context.push(Routes.forgotPassword),
          onRegister: () => context.go(Routes.register),
        ),
      ),
      GoRoute(
        path: Routes.erasureRecovery,
        builder: (context, state) => ErasureRecoveryScreen(
          onCancelled: () => context.go('${Routes.login}?erasure=cancelled'),
          onLogin: () => context.go(Routes.login),
        ),
      ),
      GoRoute(
        path: Routes.familyInvite,
        builder: (context, state) {
          final router = GoRouter.of(context);
          return FamilyInviteScreen(
            onContinue: () => context.go(Routes.inici),
            onClose: () => context.go(Routes.inici),
            // The screen is gone once the session ends; the router is not.
            onCreateAccount: () => router.go(Routes.register),
          );
        },
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => ForgotPasswordScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.login),
          onBackToLogin: () =>
              context.canPop() ? context.pop() : context.go(Routes.login),
        ),
      ),
      GoRoute(
        path: Routes.privacyPolicy,
        builder: (context, state) => LegalDocumentScreen(
          kind: LegalKind.privacy,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.welcome),
        ),
      ),
      GoRoute(
        path: Routes.termsOfUse,
        builder: (context, state) => LegalDocumentScreen(
          kind: LegalKind.terms,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.welcome),
        ),
      ),
      GoRoute(
        path: Routes.legalReaccept,
        builder: (context, state) => LegalReacceptScreen(
          onPrivacy: () => context.push(Routes.privacyPolicy),
          onTerms: () => context.push(Routes.termsOfUse),
        ),
      ),
      GoRoute(
        path: Routes.addUp,
        builder: (context, state) => AddUpScreen(
          onClose: () =>
              context.canPop() ? context.pop() : context.go(Routes.inici),
          onSaved: (upId, esfera) => context.pushReplacement(
            Routes.addUpSavedFor(upId),
            extra: AddUpSavedArgs(upId: upId, esfera: esfera),
          ),
          onCrisi: () => context.push(Routes.crisi),
        ),
      ),
      GoRoute(
        path: Routes.addUpSaved,
        builder: (context, state) {
          final args = state.extra as AddUpSavedArgs?;
          final upId = state.uri.queryParameters['upId'] ?? args?.upId;
          return AddUpSavedScreen(
            upId: upId,
            esfera: args?.esfera,
            onBack: () => context.go(Routes.inici),
            onAddAnother: () => context.pushReplacement(Routes.addUp),
            onViewUp: upId == null
                ? null
                : () => context.pushReplacement(Routes.upDetailFor(upId)),
            onActivateReminder: () => context.push(Routes.reminderSetup),
            onReminderLater: () =>
                ref.read(pushPreferencesProvider).markDismissed(DateTime.now()),
          );
        },
      ),
      GoRoute(
        path: Routes.crisi,
        builder: (context, state) => CrisiScreen(
          resumeUpId: state.uri.queryParameters['resume'],
          onBack: () => context.pop(),
          onSave: () => context.pop(),
          onFinishLater: () => context.pop(),
        ),
      ),
      GoRoute(
        path: Routes.myUps,
        builder: (context, state) => MyUpsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.inici),
          onOpenUp: (item) => item.isDraft
              ? context.push(Routes.crisiResumeFor(item.entityId))
              : context.push(Routes.upDetailFor(item.entityId), extra: item),
          onOpenDocument: (documentId) =>
              context.push(Routes.arxiuDocumentFor(documentId)),
        ),
      ),
      GoRoute(
        path: Routes.deletedUps,
        builder: (context, state) => RecentlyDeletedUpsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.myUps),
        ),
      ),
      GoRoute(
        path: Routes.upDetail,
        builder: (context, state) => UpDetailScreen(
          upId: state.pathParameters['upId'],
          item: state.extra is FeedItem ? state.extra as FeedItem : null,
          childName: '',
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.myUps),
          onDeleted: () =>
              context.canPop() ? context.pop() : context.go(Routes.myUps),
          onResumeCrisi: (upId) =>
              context.pushReplacement(Routes.crisiResumeFor(upId)),
        ),
      ),
      GoRoute(
        path: Routes.esferaDetail,
        builder: (context, state) => EsferaDetailScreen(
          category: state.pathParameters['category'] ?? '',
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.esferes),
          onOpenUp: (item) =>
              context.push(Routes.upDetailFor(item.entityId), extra: item),
        ),
      ),
      GoRoute(
        path: Routes.memories,
        builder: (context, state) => MemoriesScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.esferes),
          onOpenMemory: (item) =>
              context.push(Routes.memoryDetailFor(item.entityId), extra: item),
          onOpenPatterns: () => context.push(Routes.patrons),
        ),
      ),
      GoRoute(
        path: Routes.patrons,
        builder: (context, state) => PatronsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.memories),
          onOpenPattern: (patternId) =>
              context.push(Routes.patronDetailFor(patternId)),
        ),
      ),
      GoRoute(
        path: Routes.patronDetail,
        builder: (context, state) => PatroDetailScreen(
          patternId: state.pathParameters['patternId'] ?? '',
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.patrons),
          onOpenUp: (upId) => context.push(Routes.upDetailFor(upId)),
        ),
      ),
      GoRoute(
        path: Routes.memoryDetail,
        builder: (context, state) => MemoryDetailScreen(
          upId: state.pathParameters['upId'],
          item: state.extra is FeedItem ? state.extra as FeedItem : null,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.memories),
          onDeleted: () =>
              context.canPop() ? context.pop() : context.go(Routes.memories),
        ),
      ),
      GoRoute(
        path: Routes.points,
        builder: (context, state) => PointsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.inici),
        ),
      ),
      GoRoute(
        path: Routes.summaries,
        builder: (context, state) => SummariesScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.esferes),
          onOpenSummary: (period, reference) =>
              context.push(Routes.summaryDetailFor(period, reference)),
        ),
      ),
      GoRoute(
        path: Routes.summaryDetail,
        builder: (context, state) => WeeklySummaryScreen(
          period: state.pathParameters['period'] ?? 'month',
          reference: state.pathParameters['reference'],
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.summaries),
        ),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (context, state) => NotificationsScreen(
          onSettings: () => context.push(Routes.notificationSettings),
          onReminder: () => context.push(Routes.reminder),
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.inici),
          onOpenActiva: () => context.go(Routes.activa),
          onOpenActivaPlan: (planId) => context.go(
            '${Routes.activaPlan}?id=${Uri.encodeComponent(planId)}',
          ),
          onOpenCategorySuggestion:
              ({required request, required place, required childName}) =>
                  context.push(
                    Routes.categorySuggestion,
                    extra: CategorySuggestionRouteTarget(
                      request: request,
                      place: place,
                      childName: childName,
                    ),
                  ),
          onOpenPlace: (place) =>
              context.push(Routes.placeDetail, extra: place),
          onOpenPlaceMaterials: (place) =>
              context.push('${Routes.placeDetail}?tab=materials', extra: place),
          onOpenUp: (upId) => context.push(Routes.upDetailFor(upId)),
          onOpenCrisiDraft: (upId) => context.push(Routes.crisiResumeFor(upId)),
          onOpenDocument: (documentId) =>
              context.push(Routes.arxiuDocumentFor(documentId)),
          onOpenConversa: (placeId) =>
              context.push(Routes.conversa, extra: placeId),
          onOpenProfiles: () => context.push(Routes.profiles),
          onOpenSettings: () => context.push(Routes.settings),
          onOpenInici: () => context.go(Routes.inici),
          onOpenSubscription: () => context.push(Routes.subscription),
          onOpenEsferaPlans: () => context.push(Routes.esferaPlans),
          onOpenArxiu: () => context.push(Routes.arxiu),
          onOpenAddUp: () => context.push(Routes.addUp),
          onOpenActivaReplacement:
              ({
                required profileId,
                required enrolmentId,
                required fascicleId,
                required planId,
                required content,
              }) => context.push(
                '/activa/profiles/${Uri.encodeComponent(profileId)}/enrolments/'
                '${Uri.encodeComponent(enrolmentId)}/fascicles/'
                '${Uri.encodeComponent(fascicleId)}/replacement?planId='
                '${Uri.encodeComponent(planId)}',
                extra: content,
              ),
        ),
      ),
      GoRoute(
        path: Routes.notificationLink,
        builder: (context, state) {
          final notificationId = state.pathParameters['notificationId'] ?? '';
          final target = DeepLinkTarget.notification(notificationId);
          return NotificationsScreen(
            onSettings: () => context.push(Routes.notificationSettings),
            onReminder: () => context.push(Routes.reminder),
            initialNotificationId: target?.token,
            onBack: () async {
              if (target != null) {
                await ref
                    .read(pendingDeepLinkProvider.notifier)
                    .consumeDurably(target);
              }
              if (context.mounted) context.go(Routes.inici);
            },
            onOpenActiva: () => context.go(Routes.activa),
            onOpenActivaPlan: (planId) => context.go(
              '${Routes.activaPlan}?id=${Uri.encodeComponent(planId)}',
            ),
            onOpenCategorySuggestion:
                ({required request, required place, required childName}) =>
                    context.push(
                      Routes.categorySuggestion,
                      extra: CategorySuggestionRouteTarget(
                        request: request,
                        place: place,
                        childName: childName,
                      ),
                    ),
            onOpenPlace: (place) =>
                context.push(Routes.placeDetail, extra: place),
            onOpenPlaceMaterials: (place) => context.push(
              '${Routes.placeDetail}?tab=materials',
              extra: place,
            ),
            onOpenUp: (upId) => context.push(Routes.upDetailFor(upId)),
            onOpenCrisiDraft: (upId) =>
                context.push(Routes.crisiResumeFor(upId)),
            onOpenDocument: (documentId) =>
                context.push(Routes.arxiuDocumentFor(documentId)),
            onOpenConversa: (placeId) =>
                context.push(Routes.conversa, extra: placeId),
            onOpenProfiles: () => context.push(Routes.profiles),
            onOpenSettings: () => context.push(Routes.settings),
            onOpenInici: () => context.go(Routes.inici),
            onOpenSubscription: () => context.push(Routes.subscription),
            onOpenEsferaPlans: () => context.push(Routes.esferaPlans),
            onOpenArxiu: () => context.push(Routes.arxiu),
            onOpenAddUp: () => context.push(Routes.addUp),
            onOpenActivaReplacement:
                ({
                  required profileId,
                  required enrolmentId,
                  required fascicleId,
                  required planId,
                  required content,
                }) => context.push(
                  '/activa/profiles/${Uri.encodeComponent(profileId)}/enrolments/'
                  '${Uri.encodeComponent(enrolmentId)}/fascicles/'
                  '${Uri.encodeComponent(fascicleId)}/replacement?planId='
                  '${Uri.encodeComponent(planId)}',
                  extra: content,
                ),
          );
        },
      ),
      GoRoute(
        path: Routes.publicObservationLink,
        builder: (context, state) =>
            _publicHandoff(ref, state, host: Env.webHost, route: 'o'),
      ),
      GoRoute(
        path: Routes.publicDocumentLink,
        builder: (context, state) =>
            _publicHandoff(ref, state, host: Env.shareHost, route: 'd'),
      ),
      GoRoute(
        path: Routes.activaExerciseLink,
        builder: (context, state) {
          final target = DeepLinkTarget.exercise(
            state.pathParameters['code'] ?? '',
          );
          return ActivaExerciseLinkScreen(target: target);
        },
      ),
      GoRoute(
        path: Routes.activaRecommendation,
        builder: (context, state) {
          final pending = ref.read(pendingDeepLinkProvider);
          final target = pending?.kind == DeepLinkKind.activaRecommendation
              ? pending
              : null;
          void consume() {
            if (target != null) {
              ref.read(pendingDeepLinkProvider.notifier).consume(target);
            }
          }

          return ActivaRecommendationHandoffScreen(
            target: target,
            onResolved: consume,
            onBack: () {
              consume();
              context.go(Routes.activa);
            },
            onOpenPlan: (planId) {
              consume();
              context.go(
                '${Routes.activaPlan}?id=${Uri.encodeComponent(planId)}',
              );
            },
          );
        },
      ),
      GoRoute(
        path: Routes.activaReplacementFascicle,
        builder: (context, state) => ReplacementFascicleScreen(
          profileId: state.pathParameters['profileId'] ?? '',
          enrolmentId: state.pathParameters['enrolmentId'] ?? '',
          fascicleId: state.pathParameters['fascicleId'] ?? '',
          planId: state.uri.queryParameters['planId'] ?? '',
          initialContent: state.extra is ActivaAssignedFascicleContent
              ? state.extra as ActivaAssignedFascicleContent
              : null,
          onBack: () => context.canPop()
              ? context.pop()
              : context.go(Routes.notifications),
          onOpenExercise: (args) =>
              context.push(Routes.activaExercise, extra: args),
        ),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => RetryFailedFamilyOnOpen(
          child: SettingsScreen(
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.inici),
            onNotifications: () => context.push(Routes.notifications),
            onNotificationPreferences: () =>
                context.push(Routes.notificationSettings),
            onArxiu: () => context.push(Routes.arxiu),
            onPoints: () => context.push(Routes.points),
            onSubscription: () => context.push(Routes.subscription),
            onEsferaPlans: () => context.push(Routes.esferaPlans),
            onProfiles: () => context.push(Routes.profiles),
            onProfileAccess: (profileId) =>
                context.push(Routes.profileAccessFor(profileId)),
            onHelp: () => context.push(Routes.help),
            onDevMenu: () => context.push(Routes.devMenu),
            onAccount: (profileId) =>
                context.push(Routes.profileDetailFor(profileId)),
            onAccountOnly: () => context.push(Routes.account),
            onProfessionalShares: () => context.push(Routes.professionalShares),
            onExportStatus: () => context.push(Routes.exportDelivery),
            onAccessibility: () => context.push(Routes.accessibility),
            onPrivacy: () => context.push(Routes.privacy),
            onReminder: () => context.push(Routes.reminder),
          ),
        ),
      ),
      GoRoute(
        path: Routes.notificationSettings,
        builder: (context, state) => NotificationSettingsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
          onReminder: () => context.push(Routes.reminder),
        ),
      ),
      GoRoute(
        path: Routes.reminder,
        builder: (context, state) => ReminderSettingsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
        ),
      ),
      GoRoute(
        path: Routes.privacy,
        builder: (context, state) => PrivacyScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
          onReadPolicy: () => context.push(Routes.privacyPolicy),
          onProfessionalShares: () => context.push(Routes.professionalShares),
          onExportStatus: () => context.push(Routes.exportDelivery),
          onPermissions: () => context.go(Routes.threeSixty),
        ),
      ),
      GoRoute(
        path: Routes.accessibility,
        builder: (context, state) => AccessibilitySettingsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
        ),
      ),
      GoRoute(
        path: Routes.account,
        builder: (context, state) => AccountScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
          onChangePassword: () => showChangePasswordSheet(context),
          onPrivacy: () => context.push(Routes.privacy),
        ),
      ),
      GoRoute(
        path: Routes.professionalShares,
        builder: (context, state) => ProfessionalSharesScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
        ),
      ),
      GoRoute(
        path: Routes.exportDelivery,
        builder: (context, state) {
          final pending = ref.read(pendingDeepLinkProvider);
          final target = pending?.kind == DeepLinkKind.gdprExport
              ? pending
              : null;
          return ExportDeliveryScreen(
            initialJobId: target?.token,
            onJobAdopted: target == null
                ? null
                : () => ref
                      .read(pendingDeepLinkProvider.notifier)
                      .consume(target),
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.settings),
          );
        },
      ),
      GoRoute(
        path: Routes.profiles,
        builder: (context, state) => ProfilesManagementScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
          onOpenProfile: (profileId) =>
              context.push(Routes.profileDetailFor(profileId)),
          onAddProfile: () => context.push(Routes.profileNew),
        ),
      ),
      GoRoute(
        path: Routes.profileNew,
        builder: (context, state) => ChildFormScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.profiles),
          onSaved: () =>
              context.canPop() ? context.pop() : context.go(Routes.profiles),
        ),
      ),
      if (kDebugMode)
        GoRoute(
          path: Routes.devMenu,
          builder: (context, state) => DevMenuScreen(
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.settings),
          ),
        ),
      GoRoute(
        path: Routes.help,
        builder: (context, state) => HelpContactScreen(
          appVersion: ref.read(appVersionProvider).valueOrNull,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
        ),
      ),
      GoRoute(
        path: Routes.profileDetail,
        builder: (context, state) {
          final profileId = state.pathParameters['profileId']!;
          return ProfileDetailScreen(
            profileId: profileId,
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.settings),
            onOpenAccess: () =>
                context.push(Routes.profileAccessFor(profileId)),
            onChangePassword: () => showChangePasswordSheet(context),
            onPrivacy: () => context.push(Routes.privacy),
          );
        },
      ),
      GoRoute(
        path: Routes.profileAccess,
        builder: (context, state) {
          final profileId = state.pathParameters['profileId'] ?? '';
          return ProfileAccessScreen(
            profileId: profileId,
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.profiles),
            onOpenHistory: () =>
                context.push(Routes.profileAccessHistoryFor(profileId)),
            onStartMigration: () =>
                context.push(Routes.profileMigrationFor(profileId)),
            onOpenMigrationStatus: () =>
                context.push(Routes.profileMigrationStatusFor(profileId)),
          );
        },
      ),
      GoRoute(
        path: Routes.profileAccessHistory,
        builder: (context, state) => ProfileAccessHistoryScreen(
          profileId: state.pathParameters['profileId'] ?? '',
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.profiles),
        ),
      ),
      GoRoute(
        path: Routes.subscription,
        builder: (context, state) => SubscriptionManagementScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
        ),
      ),
      GoRoute(
        path: Routes.esferaPlans,
        builder: (context, state) => EsferaPlansScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
        ),
      ),
      GoRoute(
        path: Routes.arxiu,
        builder: (context, state) => RetryFailedFamilyOnOpen(
          child: ArxiuScreen(
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.inici),
            onOpenSection: (section, owner) => context.push(
              Routes.arxiuSection,
              extra: (section: section, owner: owner),
            ),
            onOpenDocument: (document) => context.push(
              Routes.arxiuDocumentFor(document.id),
              extra: document,
            ),
          ),
        ),
      ),
      GoRoute(
        path: Routes.arxiuSection,
        builder: (context, state) => ArxiuSectionScreen(
          section: state.extra is ({String section, String owner})
              ? (state.extra as ({String section, String owner})).section
              : state.extra as String? ?? 'escola',
          initialOwner: state.extra is ({String section, String owner})
              ? (state.extra as ({String section, String owner})).owner
              : 'all',
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.arxiu),
          onOpenDocument: (doc) =>
              context.push(Routes.arxiuDocumentFor(doc.id), extra: doc),
        ),
      ),
      GoRoute(
        path: Routes.arxiuDocument,
        builder: (context, state) => ArxiuDocumentScreen(
          documentId: state.pathParameters['documentId'],
          document: state.extra is ArxiuDocument
              ? state.extra as ArxiuDocument
              : null,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.arxiu),
        ),
      ),
      GoRoute(
        path: Routes.profileMigration,
        builder: (context, state) {
          final profileId = state.pathParameters['profileId'] ?? '';
          final profile = ref
              .read(currentFamilyProvider)
              .valueOrNull
              ?.profiles
              .where((item) => item.id == profileId)
              .firstOrNull;
          return MigrationScreen(
            childName: profile?.displayName ?? '',
            onBack: () => context.canPop()
                ? context.pop()
                : context.go(Routes.profileAccessFor(profileId)),
            onPostpone: () => context.go(Routes.profileAccessFor(profileId)),
            onTransfer: () =>
                context.push(Routes.profileMigrationDestinationFor(profileId)),
          );
        },
      ),
      GoRoute(
        path: Routes.profileMigrationDestination,
        builder: (context, state) {
          final profileId = state.pathParameters['profileId'] ?? '';
          final profile = ref
              .read(currentFamilyProvider)
              .valueOrNull
              ?.profiles
              .where((item) => item.id == profileId)
              .firstOrNull;
          return MigrationDestinationScreen(
            profileId: profileId,
            childName: profile?.displayName ?? '',
            onBack: () => context.canPop()
                ? context.pop()
                : context.go(Routes.profileMigrationFor(profileId)),
            onDone: () => context.go(Routes.profileAccessFor(profileId)),
          );
        },
      ),
      GoRoute(
        path: Routes.profileMigrationStatus,
        builder: (context, state) {
          final profileId = state.pathParameters['profileId'] ?? '';
          return MigrationStatusScreen(
            profileId: profileId,
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.inici),
          );
        },
      ),
      GoRoute(
        path: Routes.adultConsent,
        builder: (context, state) => AdultConsentScreen(
          onLeave: () => context.go(Routes.inici),
          onOpenRights: () => context.push(Routes.adultConsentRights),
          onSignOut: () async {
            await ref.read(authRepositoryProvider).logout();
            ref
                .read(sessionControllerProvider.notifier)
                .expire(SessionExpiredReason.unauthenticated);
          },
        ),
      ),
      GoRoute(
        path: Routes.adultConsentRights,
        builder: (context, state) => DataRightsScreen(
          onBack: () => context.canPop()
              ? context.pop()
              : context.go(Routes.adultConsent),
        ),
      ),
      GoRoute(
        path: Routes.migrationAcknowledge,
        builder: (context, state) => MigrationAcknowledgementScreen(
          onContinue: () => context.go(Routes.inici),
          onDiscard: () => context.go(Routes.inici),
          onExistingAccount: () =>
              context.push(Routes.migrationExistingAccount),
        ),
      ),
      GoRoute(
        path: Routes.migrationExistingAccount,
        builder: (context, state) => MigrationExistingAccountScreen(
          onSignIn: () => context.push(Routes.migrationExistingSignIn),
          onDiscard: () => _discardMigrationLink(ref, context),
        ),
      ),
      GoRoute(
        path: Routes.migrationExistingSignIn,
        builder: (context, state) => MigrationExistingSignInScreen(
          onSignedIn: () => context.push(Routes.migrationExistingChoice),
          onBack: () => context.canPop()
              ? context.pop()
              : context.go(Routes.migrationExistingAccount),
        ),
      ),
      GoRoute(
        path: Routes.migrationExistingChoice,
        builder: (context, state) => MigrationExistingChoiceScreen(
          onConfirmed: () => context.go(Routes.migrationExistingDone),
          onSignInAgain: () => context.canPop()
              ? context.pop()
              : context.go(Routes.migrationExistingSignIn),
          onDiscard: () => _discardMigrationLink(ref, context),
        ),
      ),
      GoRoute(
        path: Routes.migrationExistingDone,
        builder: (context, state) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _discardMigrationLink(ref, context);
          },
          child: MigrationExistingDoneScreen(
            onContinue: () => _discardMigrationLink(ref, context),
          ),
        ),
      ),
      GoRoute(
        path: Routes.migration,
        builder: (context, state) => MigrationScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.inici),
          onPostpone: () =>
              context.canPop() ? context.pop() : context.go(Routes.inici),
        ),
      ),
      GoRoute(
        path: Routes.placeDetail,
        builder: (context, state) => PlaceDetailScreen(
          place: state.extra is ConnectedPlace
              ? state.extra as ConnectedPlace
              : null,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.threeSixty),
          onOpenConversa: (placeId) =>
              context.push(Routes.conversa, extra: placeId),
          onOpenMaterialExercise: (profileId, handoff) async {
            final args =
                await resolvePinnedPlaceMaterialExerciseWhileProfileCurrent(
                  repository: ref.read(activaRepositoryProvider),
                  profileId: profileId,
                  locale: Localizations.localeOf(context).languageCode,
                  handoff: handoff,
                  currentProfileId: () => ref.read(currentProfileProvider)?.id,
                );
            ref.invalidate(activaProgressProvider(profileId, handoff.planId));
            ref.invalidate(activaEnrolmentsProvider(profileId));
            if (args == null) return;
            final enrolmentId = args.enrolmentId;
            if (enrolmentId != null) {
              ref.invalidate(
                activaAssignmentOverviewProvider(profileId, enrolmentId),
              );
            }
            if (!context.mounted ||
                ref.read(currentProfileProvider)?.id != profileId) {
              return;
            }
            await context.push(Routes.activaExercise, extra: args);
          },
          initialTabIndex: state.uri.queryParameters['tab'] == 'materials'
              ? 2
              : 0,
        ),
      ),
      GoRoute(
        path: Routes.categorySuggestion,
        redirect: (context, state) =>
            state.extra is CategorySuggestionRouteTarget
            ? null
            : Routes.threeSixty,
        builder: (context, state) {
          final target = state.extra! as CategorySuggestionRouteTarget;
          return CategorySuggestionScreen(
            request: target.request,
            place: target.place,
            childName: target.childName,
          );
        },
      ),
      GoRoute(
        path: Routes.conversa,
        builder: (context, state) => ConversaScreen(
          placeId: state.extra as String? ?? '',
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.threeSixty),
        ),
      ),
      GoRoute(
        path: Routes.conversaInbox,
        builder: (context, state) => ConversaInboxScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.threeSixty),
          onOpenThread: (placeId) =>
              context.push(Routes.conversa, extra: placeId),
        ),
      ),
      GoRoute(
        path: Routes.observations,
        builder: (context, state) => ObservationsScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.threeSixty),
        ),
      ),
      GoRoute(
        path: Routes.permissions,
        builder: (context, state) => PermissionsOverviewScreen(
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.threeSixty),
          onOpenPlace: (place) =>
              context.push(Routes.placeDetail, extra: place),
        ),
      ),
      GoRoute(
        path: Routes.activaCatalog,
        builder: (context, state) => PlanCatalogScreen(
          autofocusSearch: state.uri.queryParameters['search'] == '1',
          initialTematicaId: state.uri.queryParameters['tematica'],
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.activa),
          onOpenPlan: (planId) => context.push(
            '${Routes.activaPlan}?id=${Uri.encodeComponent(planId)}',
          ),
        ),
      ),
      GoRoute(
        path: Routes.activaPlan,
        builder: (context, state) => PlanDetailScreen(
          planId: state.uri.queryParameters['id'],
          lookupGate: state.uri.queryParameters['lookup'],
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.activa),
          onOpenThreeSixty: () => context.go(Routes.threeSixty),
        ),
      ),
      GoRoute(
        path: Routes.activaExercise,
        builder: (context, state) => ExerciseDetailScreen(
          args: state.extra is ExerciseArgs
              ? state.extra! as ExerciseArgs
              : null,
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.activa),
        ),
      ),
      GoRoute(
        path: Routes.activaAssignedExercise,
        builder: (context, state) {
          final warmArgs = state.extra is ExerciseArgs
              ? state.extra! as ExerciseArgs
              : null;
          if (warmArgs != null) {
            return ExerciseDetailScreen(
              args: warmArgs,
              onBack: () =>
                  context.canPop() ? context.pop() : context.go(Routes.activa),
            );
          }
          return AssignedExerciseHydrationScreen(
            profileId: state.pathParameters['profileId'] ?? '',
            enrolmentId: state.pathParameters['enrolmentId'] ?? '',
            fascicleId: state.pathParameters['fascicleId'] ?? '',
            exerciseId: state.pathParameters['exerciseId'] ?? '',
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.activa),
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.inici,
                builder: (context, state) => const IniciScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.activa,
                builder: (context, state) => const ActivaScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.esferes,
                builder: (context, state) => EsferesScreen(
                  initialTab: EsferesTab.fromKey(
                    state.uri.queryParameters['tab'],
                  ),
                  onTabChanged: (tab) =>
                      context.replace(Routes.esferesTabFor(tab.name)),
                  onOpenEsfera: (category) =>
                      context.push(Routes.esferaDetailFor(category)),
                  onOpenUp: (item) => context.push(
                    Routes.upDetailFor(item.entityId),
                    extra: item,
                  ),
                  onOpenDocument: (documentId) =>
                      context.push(Routes.arxiuDocumentFor(documentId)),
                  onOpenMemory: (item) => context.push(
                    Routes.memoryDetailFor(item.entityId),
                    extra: item,
                  ),
                  onOpenPatterns: () => context.push(Routes.patrons),
                  onOpenSummary: (period, reference) =>
                      context.push(Routes.summaryDetailFor(period, reference)),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.threeSixty,
                builder: (context, state) => ThreeSixtyScreen(
                  onOpenPlace: (place) =>
                      context.push(Routes.placeDetail, extra: place),
                  onOpenMessages: () => context.push(Routes.conversaInbox),
                  onOpenObservations: () => context.push(Routes.observations),
                  onOpenPermissions: () => context.push(Routes.permissions),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

bool _isProvisionalAccount(Object? error) =>
    error is AppError && error.code == 'ACCOUNT_PROVISIONAL';

/// Bridges Riverpod → GoRouter: fires `notifyListeners` when startup completes
/// or the auth status changes, so the redirect re-runs.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(appStartupProvider, (_, _) => _refresh());
    ref.listen(sessionControllerProvider, (_, _) => _refresh());
    ref.listen(registrationOnboardingIntentProvider, (_, _) => _refresh());
    ref.listen(currentFamilyProvider, (_, _) => _refresh());
    ref.listen(policyReacceptanceControllerProvider, (_, _) => _refresh());
    ref.listen(pendingDeepLinkProvider, (_, _) => _refresh());
    ref.listen(pendingErasureRecoveryControllerProvider, (_, _) => _refresh());
    ref.listen(pendingExportDeliveryProvider, (_, _) => _refresh());
  }

  bool _pending = false;

  /// GoRouter re-parses its last *reported* location on refresh, and a pop is
  /// only reported at the end of the frame that rebuilds the navigator. An
  /// immediate refresh (e.g. a family reload right after saving a form) would
  /// restore the page that was just popped, so refresh one frame later.
  void _refresh() {
    if (_pending) return;
    _pending = true;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      scheduler.addPostFrameCallback((_) {
        _pending = false;
        notifyListeners();
      });
      scheduler.scheduleFrame();
    });
    scheduler.scheduleFrame();
  }
}

/// Leaves the existing-account handoff: drops the link and what was signed in
/// for it, then home when signed in, or sign-in otherwise.
void _discardMigrationLink(Ref ref, BuildContext context) {
  final pending = ref.read(pendingDeepLinkProvider);
  if (pending?.kind == DeepLinkKind.migration) {
    ref.read(pendingDeepLinkProvider.notifier).consume(pending!);
  }
  ref.read(existingAccountHandoffProvider.notifier).reset();
  final authed =
      ref.read(sessionControllerProvider) == AuthStatus.authenticated;
  context.go(authed ? Routes.inici : Routes.login);
}

Widget _publicHandoff(
  Ref ref,
  GoRouterState state, {
  required String host,
  required String route,
}) {
  final token = state.pathParameters['token'] ?? '';
  final target = DeepLinkTarget.parse(
    Uri.https(host, '/$route/$token', state.uri.queryParameters),
  );
  if (target == null) {
    return const _InvalidPublicLinkScreen();
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(pendingDeepLinkProvider.notifier).consume(target);
  });
  return PublicLinkHandoffScreen(target: target);
}

class _InvalidPublicLinkScreen extends StatelessWidget {
  const _InvalidPublicLinkScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context).publicLinkInvalid,
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
