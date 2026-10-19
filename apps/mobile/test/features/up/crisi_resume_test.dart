import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/family/domain/entities/family.dart';
import 'package:esferaup/features/family/domain/entities/profile.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/crisi_screen.dart';
import 'package:esferaup/features/up/presentation/screens/up_detail_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUpRepository extends Mock implements UpRepository {}

UpDetail _draft({bool draft = true}) => UpDetail(
  id: 'up-draft',
  profileId: 'p',
  category: 'emocions',
  occurredAt: DateTime(2026, 6, 15, 14, 10),
  isPinned: false,
  isCrisi: true,
  crisi: UpCrisiDetail(
    triggerText: 'Massa soroll al supermercat',
    durationBucket: 'fifteen_to_30',
    moodAfter: UpMood.sad,
    draft: draft,
  ),
  createdAt: DateTime(2026, 6, 15, 14, 11),
);

Widget _app(
  _MockUpRepository repository,
  Widget home, {
  String locale = 'en',
}) => ProviderScope(
  overrides: [
    upRepositoryProvider.overrideWithValue(repository),
    currentFamilyProvider.overrideWith(
      (ref) => Family(
        id: 'f',
        profiles: [
          Profile(id: 'p', displayName: 'Marc', dob: DateTime(2017, 4, 5)),
        ],
        puntsBalance: 0,
        tier: 'free',
        status: 'active',
      ),
    ),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    theme: AppTheme.light(AppFontFamily.lexend),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  setUpAll(() => registerFallbackValue(UpMood.good));

  testWidgets('resume mode prefills the draft and completes it in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _MockUpRepository();
    when(() => repository.getUp('up-draft')).thenAnswer((_) async => _draft());
    when(
      () => repository.updateCrisi(
        upId: any(named: 'upId'),
        occurredAt: any(named: 'occurredAt'),
        triggerText: any(named: 'triggerText'),
        resolutionText: any(named: 'resolutionText'),
        durationBucket: any(named: 'durationBucket'),
        moodAfter: any(named: 'moodAfter'),
        draft: any(named: 'draft'),
      ),
    ).thenAnswer((_) async => _draft(draft: false));
    var saved = false;

    await tester.pumpWidget(
      _app(
        repository,
        CrisiScreen(resumeUpId: 'up-draft', onSave: () => saved = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Massa soroll al supermercat'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'Hem sortit i ha passat',
    );
    await tester.tap(find.text('Save the crisis'));
    await tester.pumpAndSettle();

    final call = verify(
      () => repository.updateCrisi(
        upId: 'up-draft',
        occurredAt: DateTime(2026, 6, 15, 14, 10),
        triggerText: captureAny(named: 'triggerText'),
        resolutionText: captureAny(named: 'resolutionText'),
        durationBucket: captureAny(named: 'durationBucket'),
        moodAfter: any(named: 'moodAfter'),
        draft: captureAny(named: 'draft'),
      ),
    )..called(1);
    expect(
      call.captured,
      unorderedEquals([
        'Massa soroll al supermercat',
        'Hem sortit i ha passat',
        'fifteen_to_30',
        false,
      ]),
    );
    verifyNever(
      () => repository.createCrisi(
        profileId: any(named: 'profileId'),
        occurredAt: any(named: 'occurredAt'),
      ),
    );
    expect(saved, isTrue);
  });

  testWidgets('resuming a draft saves the moment changed on the form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _MockUpRepository();
    when(() => repository.getUp('up-draft')).thenAnswer((_) async => _draft());
    when(
      () => repository.updateCrisi(
        upId: any(named: 'upId'),
        occurredAt: any(named: 'occurredAt'),
        triggerText: any(named: 'triggerText'),
        resolutionText: any(named: 'resolutionText'),
        durationBucket: any(named: 'durationBucket'),
        moodAfter: any(named: 'moodAfter'),
        draft: any(named: 'draft'),
      ),
    ).thenAnswer((_) async => _draft(draft: false));

    await tester.pumpWidget(
      _app(repository, const CrisiScreen(resumeUpId: 'up-draft')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('15/6/2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('14/6/2026'), findsOneWidget);

    await tester.tap(find.text('Save the crisis'));
    await tester.pumpAndSettle();

    final occurredAt = verify(
      () => repository.updateCrisi(
        upId: 'up-draft',
        occurredAt: captureAny(named: 'occurredAt'),
        triggerText: any(named: 'triggerText'),
        resolutionText: any(named: 'resolutionText'),
        durationBucket: any(named: 'durationBucket'),
        moodAfter: any(named: 'moodAfter'),
        draft: false,
      ),
    ).captured.single;
    expect(occurredAt, DateTime(2026, 6, 14, 14, 10));
  });

  testWidgets('a new crisi without a trigger explains what is missing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _MockUpRepository();

    await tester.pumpWidget(_app(repository, const CrisiScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save the crisis'));
    await tester.pumpAndSettle();

    expect(
      find.text('Briefly describe what happened before saving the crisis.'),
      findsOneWidget,
    );
    verifyNever(
      () => repository.createCrisi(
        profileId: any(named: 'profileId'),
        occurredAt: any(named: 'occurredAt'),
      ),
    );
  });

  testWidgets('the UP detail offers to continue an unfinished crisis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _MockUpRepository();
    when(() => repository.getUp('up-draft')).thenAnswer((_) async => _draft());
    String? resumed;

    await tester.pumpWidget(
      _app(
        repository,
        UpDetailScreen(upId: 'up-draft', onResumeCrisi: (id) => resumed = id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unfinished'), findsOneWidget);
    expect(find.text('What happened'), findsOneWidget);
    expect(find.text('Massa soroll al supermercat'), findsOneWidget);
    await tester.tap(find.text('Continue the crisis'));
    await tester.pumpAndSettle();
    expect(resumed, 'up-draft');
  });

  testWidgets('a finished crisis reads in the app language, without Edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _MockUpRepository();
    when(
      () => repository.getUp('up-draft'),
    ).thenAnswer((_) async => _draft(draft: false));

    for (final (locale, pill) in [
      ('ca', 'Crisi'),
      ('es', 'Crisis'),
      ('en', 'Crisis'),
    ]) {
      await tester.pumpWidget(
        _app(
          repository,
          const UpDetailScreen(upId: 'up-draft'),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(pill), findsOneWidget, reason: locale);
      await tester.pumpWidget(const SizedBox());
    }

    await tester.pumpWidget(
      _app(repository, const UpDetailScreen(upId: 'up-draft'), locale: 'es'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Emociones'), findsOneWidget);
    expect(find.text('Qué ha pasado'), findsOneWidget);
    expect(find.text('Massa soroll al supermercat'), findsOneWidget);
    expect(find.text('Cómo se ha resuelto'), findsOneWidget);
    expect(find.text('Todavía no lo has escrito.'), findsOneWidget);
    expect(find.text('Sin terminar'), findsNothing);
    expect(find.byTooltip('Editar'), findsNothing);
    expect(find.byTooltip('Compartir'), findsOneWidget);
    expect(find.byTooltip('Eliminar'), findsOneWidget);
    expect(find.text('Fijar · Memorias'), findsOneWidget);
  });
}
