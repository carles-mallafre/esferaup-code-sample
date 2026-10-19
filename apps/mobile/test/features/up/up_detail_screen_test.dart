import 'package:esferaup/core/router/app_router.dart';
import 'package:esferaup/features/memories/presentation/screens/memory_detail_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/up_detail_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUpRepository extends Mock implements UpRepository {}

void main() {
  late _MockUpRepository repository;

  setUp(() => repository = _MockUpRepository());

  UpDetail detail({
    List<UpAttachment> attachments = const [],
    bool attachmentsPending = false,
    UpCrisiDetail? crisi,
  }) => UpDetail(
    id: 'up-cold',
    profileId: 'profile-1',
    category: 'escola',
    occurredAt: DateTime(2026, 7, 25, 10),
    mood: UpMood.good,
    note: 'Authoritative note loaded from the API',
    isPinned: false,
    isCrisi: crisi != null,
    crisi: crisi,
    attachments: attachments,
    attachmentsPending: attachmentsPending,
    createdAt: DateTime(2026, 7, 25, 10, 1),
  );

  Widget app({
    double textScale = 1,
    AppFontFamily font = AppFontFamily.lexend,
    bool dark = false,
    Locale locale = const Locale('en'),
  }) => ProviderScope(
    overrides: [upRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      locale: locale,
      theme: dark ? AppTheme.dark(font) : AppTheme.light(font),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const UpDetailScreen(upId: 'up-cold'),
    ),
  );

  testWidgets('pending attachments appear without leaving the detail', (
    tester,
  ) async {
    var reads = 0;
    when(() => repository.getUp('up-cold')).thenAnswer((_) async {
      reads += 1;
      return reads == 1
          ? detail(attachmentsPending: true)
          : detail(
              attachments: const [
                UpAttachment(
                  index: 0,
                  mime: 'application/pdf',
                  sizeBytes: 1024,
                ),
              ],
            );
    });
    await tester.pumpWidget(app(textScale: 2));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Attachments are being checked.'),
      findsOneWidget,
    );
    expect(find.text('Attachment 1'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Attachments are being checked.'), findsNothing);
    expect(find.text('Attachment 1'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving a pending detail stops attachment polling', (
    tester,
  ) async {
    when(
      () => repository.getUp('up-cold'),
    ).thenAnswer((_) async => detail(attachmentsPending: true));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
    verify(() => repository.getUp('up-cold')).called(1);
  });

  for (final font in AppFontFamily.values) {
    for (final dark in [false, true]) {
      testWidgets('pending attachments reflow with $font dark=$dark at 200%', (
        tester,
      ) async {
        when(
          () => repository.getUp('up-cold'),
        ).thenAnswer((_) async => detail(attachmentsPending: true));
        await tester.pumpWidget(app(textScale: 2, font: font, dark: dark));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Attachments are being checked.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('deleting the original clears the memory underneath', (
    tester,
  ) async {
    var deleted = false;
    when(() => repository.getUp('up-cold')).thenAnswer((_) async {
      if (deleted) throw const UnknownError(code: 'NOT_FOUND');
      return detail();
    });
    when(() => repository.deleteUp('up-cold')).thenAnswer((_) async {
      deleted = true;
    });
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const MemoryDetailScreen(upId: 'up-cold'),
        ),
        GoRoute(
          path: Routes.upDetail,
          builder: (context, state) => UpDetailScreen(
            upId: state.pathParameters['upId'],
            onDeleted: () => context.pop(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [upRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          theme: AppTheme.light(AppFontFamily.lexend),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View original UP'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this UP?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('Authoritative note loaded from the API'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(find.byTooltip('Options'), findsNothing);
    expect(find.text('This UP could not be loaded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete says it is recoverable and Undo restores the UP', (
    tester,
  ) async {
    var deleted = false;
    when(() => repository.getUp('up-cold')).thenAnswer((_) async {
      if (deleted) throw const UnknownError(code: 'NOT_FOUND');
      return detail();
    });
    when(() => repository.deleteUp('up-cold')).thenAnswer((_) async {
      deleted = true;
    });
    when(() => repository.restoreUp('up-cold')).thenAnswer((_) async {
      deleted = false;
    });

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This UP will be removed from the family feed. You can recover it '
        'for 7 days from “Recently deleted” in My UPs.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('UP deleted. You can recover it for 7 days.'),
      findsOneWidget,
    );
    final undo = find.widgetWithText(SnackBarAction, 'Undo');
    expect(tester.getSize(undo).height, greaterThanOrEqualTo(44));
    await tester.tap(undo);
    await tester.pumpAndSettle();

    verify(() => repository.restoreUp('up-cold')).called(1);
    expect(find.text('UP restored'), findsOneWidget);
    expect(find.text('Authoritative note loaded from the API'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the delete confirmation with Undo goes away on its own', (
    tester,
  ) async {
    when(() => repository.getUp('up-cold')).thenAnswer((_) async => detail());
    when(() => repository.deleteUp('up-cold')).thenAnswer((_) async {});

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text('UP deleted. You can recover it for 7 days.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();

    expect(
      find.text('UP deleted. You can recover it for 7 days.'),
      findsNothing,
      reason: 'an action makes a SnackBar persist unless told otherwise',
    );
  });

  testWidgets('a failed Undo says the UP could not be restored', (
    tester,
  ) async {
    when(() => repository.getUp('up-cold')).thenAnswer((_) async => detail());
    when(() => repository.deleteUp('up-cold')).thenAnswer((_) async {});
    when(() => repository.restoreUp('up-cold')).thenThrow(const NetworkError());

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();

    expect(
      find.text('This UP could not be restored. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('cold ID hydrates the authoritative UP without route extras', (
    tester,
  ) async {
    when(() => repository.getUp('up-cold')).thenAnswer((_) async => detail());

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Authoritative note loaded from the API'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    verify(() => repository.getUp('up-cold')).called(1);
  });

  testWidgets('network failure stays on the detail route with a retry action', (
    tester,
  ) async {
    when(() => repository.getUp('up-cold')).thenThrow(const NetworkError());

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('edit persists the note and tag then reloads detail', (
    tester,
  ) async {
    var changed = false;
    final saved = UpDetail(
      id: 'up-cold',
      profileId: 'profile-1',
      category: 'escola',
      occurredAt: DateTime(2026, 7, 25),
      isPinned: false,
      isCrisi: false,
      createdAt: DateTime(2026, 7, 25),
      note: 'Updated note',
      tag: 'shared-reading',
      mood: UpMood.good,
    );
    when(
      () => repository.getUp('up-cold'),
    ).thenAnswer((_) async => changed ? saved : detail());
    when(
      () => repository.updateUp(
        upId: 'up-cold',
        category: 'escola',
        mood: UpMood.good,
        note: 'Updated note',
        tag: 'shared-reading',
      ),
    ).thenAnswer((_) async {
      changed = true;
      return saved;
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Updated note');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('up-edit-tag')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('up-edit-tag')),
        matching: find.byType(TextField),
      ),
      'shared-reading',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    expect(find.text('Updated note'), findsOneWidget);
    expect(find.text('shared-reading'), findsOneWidget);
  });

  testWidgets('unsafe attachment grants are rejected before opening', (
    tester,
  ) async {
    when(() => repository.getUp('up-cold')).thenAnswer(
      (_) async => detail(
        attachments: const [
          UpAttachment(index: 0, mime: 'application/pdf', sizeBytes: 1200),
        ],
      ),
    );
    when(
      () => repository.getAttachmentDownloadGrant(
        upId: 'up-cold',
        attachmentIndex: 0,
      ),
    ).thenAnswer(
      (_) async => UpAttachmentDownloadGrant(
        url: Uri.parse('file:///private/unsafe.pdf'),
        mime: 'application/pdf',
        sizeBytes: 1200,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Attachment 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attachment 1'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This attachment cannot be opened safely right now. Try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('attachments name their type in words, not as a MIME string', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    when(() => repository.getUp('up-cold')).thenAnswer(
      (_) async => detail(
        attachments: const [
          UpAttachment(index: 0, mime: 'image/jpeg', sizeBytes: 2048),
          UpAttachment(index: 1, mime: 'application/pdf', sizeBytes: 2048),
          UpAttachment(index: 2, mime: 'text/plain', sizeBytes: 2048),
        ],
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('Image · '), findsOneWidget);
    expect(find.textContaining('PDF · '), findsOneWidget);
    expect(find.textContaining('File · '), findsOneWidget);
    expect(find.textContaining('image/jpeg'), findsNothing);
    expect(find.textContaining('application/pdf'), findsNothing);
  });

  testWidgets('attachment sizes use the decimal mark of the locale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    when(() => repository.getUp('up-cold')).thenAnswer(
      (_) async => detail(
        attachments: const [
          UpAttachment(index: 0, mime: 'image/jpeg', sizeBytes: 10752),
          UpAttachment(index: 1, mime: 'image/png', sizeBytes: 1887437),
        ],
      ),
    );

    await tester.pumpWidget(app(locale: const Locale('es')));
    await tester.pumpAndSettle();

    expect(find.textContaining('10,5 KB'), findsOneWidget);
    expect(find.textContaining('1,8 MB'), findsOneWidget);
    expect(find.textContaining('10.5 KB'), findsNothing);
  });

  testWidgets('a crisis header shows how the child is now', (tester) async {
    when(() => repository.getUp('up-cold')).thenAnswer(
      (_) async => detail(
        crisi: const UpCrisiDetail(
          triggerText: 'Trigger',
          moodAfter: UpMood.sad,
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Sad · School'), findsOneWidget);
    expect(find.text('Good · School'), findsNothing);
  });

  testWidgets('a crisis without a now answer keeps the UP mood', (
    tester,
  ) async {
    when(
      () => repository.getUp('up-cold'),
    ).thenAnswer((_) async => detail(crisi: const UpCrisiDetail(draft: true)));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Good · School'), findsOneWidget);
  });

  testWidgets('detail reflows at 200 percent text scale', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    when(() => repository.getUp('up-cold')).thenAnswer((_) async => detail());

    await tester.pumpWidget(app(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Authoritative note loaded from the API'), findsOneWidget);
  });
}
