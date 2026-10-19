import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/core/widgets/chips/app_chip.dart';
import 'package:esferaup/features/family/domain/entities/family.dart';
import 'package:esferaup/features/family/domain/entities/profile.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/up/domain/entities/up_save_result.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/crisi_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUpRepository extends Mock implements UpRepository {}

const _saveFailed =
    'No se ha podido guardar. Tus notas se mantienen en pantalla — vuelve a '
    'intentarlo.';

Future<(_MockUpRepository, List<String>)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _MockUpRepository();
  final events = <String>[];
  final container = ProviderContainer(
    overrides: [
      upRepositoryProvider.overrideWithValue(repository),
      currentFamilyProvider.overrideWith(
        (ref) => Family(
          id: 'f',
          profiles: [
            Profile(
              id: 'nen',
              displayName: 'Prova Nen',
              dob: DateTime(2017, 4, 5),
            ),
            Profile(
              id: 'nena',
              displayName: 'Prova Nena QA',
              dob: DateTime(2019, 4, 5),
            ),
          ],
          puntsBalance: 0,
          tier: 'free',
          status: 'active',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(currentFamilyProvider.future);
  container.read(selectedProfileProvider.notifier).select('nena');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('es'),
        theme: AppTheme.light(AppFontFamily.lexend),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CrisiScreen(
          onSave: () => events.add('saved'),
          onFinishLater: () => events.add('later'),
          onBack: () => events.add('back'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, events);
}

void _stubCreate(_MockUpRepository repository, {Object? error}) {
  final call = when(
    () => repository.createCrisi(
      profileId: any(named: 'profileId'),
      occurredAt: any(named: 'occurredAt'),
      triggerText: any(named: 'triggerText'),
      resolutionText: any(named: 'resolutionText'),
      durationBucket: any(named: 'durationBucket'),
      moodAfter: any(named: 'moodAfter'),
      draft: any(named: 'draft'),
    ),
  );
  if (error != null) {
    call.thenAnswer((_) => Future.error(error));
  } else {
    call.thenAnswer(
      (_) async => const UpSaveResult(
        id: 'up-1',
        puntsAwarded: 5,
        dailyCapReached: false,
      ),
    );
  }
}

bool _selected(WidgetTester tester, String label) =>
    tester.widget<AppChip>(find.widgetWithText(AppChip, label)).selected;

void main() {
  setUpAll(() {
    registerFallbackValue(UpMood.good);
    registerFallbackValue(DateTime(2026));
  });

  testWidgets('the crisis form shows its five calm steps and defaults', (
    tester,
  ) async {
    await _pump(tester);
    for (final text in [
      'Crisis emocional',
      'Sin prisa.',
      'Anota lo que recuerdes. Puedes terminar más tarde.',
      'Toca para cambiar el momento',
      'Ej.: Le he dicho que no íbamos al parque…',
      '< 5 min',
      '5–15 min',
      '15–30 min',
      '> 30 min',
      'Música y abrazo · 5 min de calma',
      'Terminar más tarde',
      'Guarda la crisis',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    for (final (n, title) in [
      (1, '¿Cuándo ha pasado?'),
      (2, '¿Qué lo ha desencadenado?'),
      (3, '¿Cuánto ha durado?'),
      (4, '¿Cómo se ha resuelto?'),
      (5, '¿Cómo está ahora?'),
    ]) {
      expect(
        find.text('$n · $title', findRichText: true),
        findsOneWidget,
        reason: title,
      );
    }
    expect(find.textContaining('Hoy · '), findsOneWidget);
    expect(_selected(tester, '5–15 min'), isTrue);
    expect(find.text('Prova Nena QA'), findsNothing);
    expect(find.text('Prova Nen'), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.maxLines, 3);
    }
  });

  testWidgets('a complete crisis needs a trigger and saves to the profile', (
    tester,
  ) async {
    final (repository, events) = await _pump(tester);
    _stubCreate(repository);
    const required =
        'Explica brevemente qué ha pasado antes de guardar la crisis.';

    for (final blank in ['', '    ']) {
      await tester.enterText(find.byType(TextField).first, blank);
      await tester.tap(find.text('Guarda la crisis'));
      await tester.pump();
      expect(find.text(required), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }
    verifyNever(
      () => repository.createCrisi(
        profileId: any(named: 'profileId'),
        occurredAt: any(named: 'occurredAt'),
        triggerText: any(named: 'triggerText'),
        resolutionText: any(named: 'resolutionText'),
        durationBucket: any(named: 'durationBucket'),
        moodAfter: any(named: 'moodAfter'),
        draft: any(named: 'draft'),
      ),
    );

    await tester.enterText(
      find.byType(TextField).first,
      'Prova QA: no quería salir del parque',
    );
    await tester.tap(find.text('15–30 min'));
    await tester.enterText(find.byType(TextField).last, 'Abrazo y música');
    await tester.tap(find.bySemanticsLabel('Triste'));
    await tester.tap(find.text('Guarda la crisis'));
    await tester.pumpAndSettle();

    verify(
      () => repository.createCrisi(
        profileId: 'nena',
        occurredAt: any(named: 'occurredAt'),
        triggerText: 'Prova QA: no quería salir del parque',
        resolutionText: 'Abrazo y música',
        durationBucket: 'fifteen_to_30',
        moodAfter: UpMood.sad,
        draft: false,
      ),
    ).called(1);
    expect(events, ['saved']);
  });

  testWidgets('finish later keeps an unfinished draft without a trigger', (
    tester,
  ) async {
    final (repository, events) = await _pump(tester);
    _stubCreate(repository);
    await tester.tap(find.text('< 5 min'));
    await tester.tap(find.text('Terminar más tarde'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Guardado como borrador. Termínalo cuando estés a punto.'),
      findsOneWidget,
    );
    verify(
      () => repository.createCrisi(
        profileId: 'nena',
        occurredAt: any(named: 'occurredAt'),
        triggerText: '',
        resolutionText: '',
        durationBucket: 'lt5',
        moodAfter: UpMood.good,
        draft: true,
      ),
    ).called(1);
    expect(events, ['later']);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed save keeps what was written', (tester) async {
    final (repository, events) = await _pump(tester);
    for (final error in <AppError>[
      const NetworkError(),
      const ValidationError(code: 'VALIDATION_ERROR', field: 'trigger_text'),
    ]) {
      _stubCreate(repository, error: error);
      await tester.enterText(find.byType(TextField).first, 'Ruido en el súper');
      await tester.tap(find.text('Guarda la crisis'));
      await tester.pump();
      await tester.pump();
      expect(find.text(_saveFailed), findsOneWidget);
      expect(find.text('Ruido en el súper'), findsOneWidget);
      expect(events, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Atrás'));
    expect(events, ['back']);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
