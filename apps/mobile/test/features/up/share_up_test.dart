import 'dart:io';
import 'package:esferaup/core/upload/sensitive_download_transport.dart';
import 'package:esferaup/core/upload/upload_providers.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/sharing/share_up.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Repo extends Mock implements UpRepository {}

class _Download extends Mock implements SensitiveDownloadTransport {}

void main() {
  testWidgets(
    'share downloads only the displayed ready photo and retains it for recipient',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'esfera-share-test',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final repo = _Repo(), download = _Download();
      final uri = Uri.parse('https://media.example.test/clean-photo');
      when(
        () => repo.getAttachmentDownloadGrant(upId: 'up1', attachmentIndex: 1),
      ).thenAnswer(
        (_) async => UpAttachmentDownloadGrant(
          url: uri,
          mime: 'image/jpeg',
          sizeBytes: 3,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      when(
        () => download.downloadToTemp(uri, extension: 'jpg', maxBytes: 3),
      ).thenAnswer((_) async => file);
      final calls = <MethodCall>[];
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return 'dev.fluttercommunity.plus/share/unavailable';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final detail = UpDetail(
        id: 'up1',
        profileId: 'p1',
        category: 'casa',
        occurredAt: DateTime(2026, 9, 1),
        isPinned: false,
        isCrisi: false,
        createdAt: DateTime(2026, 9, 1),
        note: 'Shared moment',
        attachments: const [
          UpAttachment(index: 1, mime: 'image/jpeg', sizeBytes: 3),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            upRepositoryProvider.overrideWithValue(repo),
            sensitiveDownloadTransportProvider.overrideWithValue(download),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => shareUp(context, ref, detail),
                  child: const Text('Share'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      expect(calls.single.method, 'shareFiles');
      expect((calls.single.arguments as Map)['paths'], [file.path]);
      expect(
        (calls.single.arguments as Map)['text'],
        contains('Shared moment'),
      );
      expect(file.existsSync(), isTrue);
    },
  );
}
