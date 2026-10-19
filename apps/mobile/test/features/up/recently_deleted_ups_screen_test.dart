import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/family/domain/entities/profile.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/feed/domain/repositories/feed_repository.dart';
import 'package:esferaup/features/feed/presentation/providers/feed_providers.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/recently_deleted_ups_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUpRepository extends Mock implements UpRepository {}

class _MockFeedRepository extends Mock implements FeedRepository {}

DeletedUp _up(
  String id, {
  int daysLeft = 7,
  String note = 'Built a tower',
  UpRestoreBlock? restoreBlock,
}) => DeletedUp(
  id: id,
  profileId: 'p1',
  category: 'escola',
  occurredAt: DateTime(2026, 7, 25, 10),
  deletedAt: DateTime(2026, 7, 26, 9),
  daysLeft: daysLeft,
  mood: UpMood.good,
  preview: note,
  restoreBlock: restoreBlock,
);

void main() {
  late _MockUpRepository repository;

  setUp(() => repository = _MockUpRepository());

  Future<void> open(
    WidgetTester tester, {
    double textScale = 1,
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWithValue(
            const Profile(id: 'p1', displayName: 'Marc', role: 'admin'),
          ),
          upRepositoryProvider.overrideWithValue(repository),
          feedRepositoryProvider.overrideWithValue(_MockFeedRepository()),
        ],
        child: MaterialApp(
          locale: locale,
          theme: AppTheme.light(AppFontFamily.lexend),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const RecentlyDeletedUpsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists deleted UPs with the days left and restores one', (
    tester,
  ) async {
    var restored = false;
    when(() => repository.listDeletedUps('p1')).thenAnswer(
      (_) async => restored
          ? [_up('b', daysLeft: 1, note: 'Second note')]
          : [_up('a'), _up('b', daysLeft: 1, note: 'Second note')],
    );
    when(() => repository.restoreUp('a')).thenAnswer((_) async {
      restored = true;
    });

    await open(tester);

    expect(find.text('Recently deleted'), findsOneWidget);
    expect(
      find.text(
        'Deleted UPs are kept here for 7 days. After that they are removed for good.',
      ),
      findsOneWidget,
    );
    expect(find.text('7 days left'), findsOneWidget);
    expect(find.text('1 day left'), findsOneWidget);
    expect(find.text('Built a tower'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore-a')));
    await tester.pumpAndSettle();

    verify(() => repository.restoreUp('a')).called(1);
    expect(find.text('UP restored'), findsOneWidget);
    expect(find.text('Built a tower'), findsNothing);
    expect(find.text('Second note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says so when nothing was deleted recently', (tester) async {
    when(() => repository.listDeletedUps('p1')).thenAnswer((_) async => []);

    await open(tester);

    expect(find.text('There are no recently deleted UPs.'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);
  });

  testWidgets('a failed load explains itself and retries', (tester) async {
    var calls = 0;
    when(() => repository.listDeletedUps('p1')).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw const NetworkError();
      return [_up('a')];
    });

    await open(tester);

    expect(
      find.text('Couldn’t load the deleted UPs. Check your connection.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Built a tower'), findsOneWidget);
  });

  testWidgets('a restore after the window says it can no longer be recovered', (
    tester,
  ) async {
    var expired = false;
    when(
      () => repository.listDeletedUps('p1'),
    ).thenAnswer((_) async => expired ? [] : [_up('a', daysLeft: 1)]);
    when(() => repository.restoreUp('a')).thenAnswer((_) async {
      expired = true;
      throw const UnknownError(code: 'UP_RESTORE_WINDOW_EXPIRED');
    });

    await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore-a')));
    await tester.pumpAndSettle();

    expect(find.text('This UP can no longer be recovered.'), findsOneWidget);
    expect(find.text('There are no recently deleted UPs.'), findsOneWidget);
  });

  testWidgets('any other restore failure keeps the row and asks to retry', (
    tester,
  ) async {
    when(
      () => repository.listDeletedUps('p1'),
    ).thenAnswer((_) async => [_up('a')]);
    when(() => repository.restoreUp('a')).thenThrow(const NetworkError());

    await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore-a')));
    await tester.pumpAndSettle();

    expect(
      find.text('This UP could not be restored. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Built a tower'), findsOneWidget);
  });

  for (final (block, message) in const [
    (
      UpRestoreBlock.consentRevoked,
      'It can’t be recovered: consent to keep UPs for this profile was withdrawn.',
    ),
    (
      UpRestoreBlock.profileMigrating,
      'It can’t be recovered right now: the profile is being handed over and is closed to changes.',
    ),
    (
      UpRestoreBlock.awaitingAdultConsent,
      'It can’t be recovered: the person in this profile is now an adult and hasn’t yet decided what happens with their data.',
    ),
    (
      UpRestoreBlock.erasureRequested,
      'It can’t be recovered: the person in this profile asked for their data to be erased.',
    ),
  ]) {
    testWidgets('a UP that cannot be restored (${block.wire}) is still listed, '
        'with the reason and no restore action', (tester) async {
      when(
        () => repository.listDeletedUps('p1'),
      ).thenAnswer((_) async => [_up('a', restoreBlock: block), _up('b')]);

      await open(tester);

      expect(find.text('Built a tower'), findsNWidgets(2));
      expect(find.text(message), findsOneWidget);
      expect(find.byKey(const ValueKey('restore-a')), findsNothing);
      expect(find.byKey(const ValueKey('restore-b')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a restore refused because consent was withdrawn says so and '
      'reloads the list', (tester) async {
    var refused = false;
    when(() => repository.listDeletedUps('p1')).thenAnswer(
      (_) async => [
        _up('a', restoreBlock: refused ? UpRestoreBlock.consentRevoked : null),
      ],
    );
    when(() => repository.restoreUp('a')).thenAnswer((_) async {
      refused = true;
      throw const UnknownError(code: 'CONSENT_NOT_FOUND');
    });

    await open(tester, locale: const Locale('ca'));
    await tester.tap(find.byKey(const ValueKey('restore-a')));
    await tester.pumpAndSettle();

    // Once in the snackbar, once on the reloaded row.
    expect(
      find.text(
        'No es pot recuperar: s’ha retirat el consentiment per desar UPs d’aquest perfil.',
      ),
      findsNWidgets(2),
    );
    expect(find.byKey(const ValueKey('restore-a')), findsNothing);
    expect(find.byKey(const ValueKey('restore-blocked-a')), findsOneWidget);
  });

  testWidgets('the reason fits at 200% text in Spanish', (tester) async {
    when(() => repository.listDeletedUps('p1')).thenAnswer(
      (_) async => [
        _up('a', restoreBlock: UpRestoreBlock.awaitingAdultConsent),
      ],
    );

    await open(tester, textScale: 2, locale: const Locale('es'));

    expect(tester.takeException(), isNull);
    expect(
      find.text(
        'No se puede recuperar: la persona de este perfil ya es adulta y todavía no ha decidido qué se hace con sus datos.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('restore is labelled, 44pt tall and fits at 200% text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    when(
      () => repository.listDeletedUps('p1'),
    ).thenAnswer((_) async => [_up('a'), _up('b', daysLeft: 1)]);

    await open(tester, textScale: 2, locale: const Locale('ca'));

    expect(tester.takeException(), isNull);
    expect(find.text('Queden 7 dies'), findsOneWidget);
    expect(find.text('Queda 1 dia'), findsOneWidget);
    final button = find.byKey(const ValueKey('restore-a'));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
    expect(
      find.bySemanticsLabel(RegExp(r'^Recupera l’UP del ')),
      findsNWidgets(2),
    );
    handle.dispose();
  });
}
