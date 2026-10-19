import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements UpRepository {}

void main() {
  for (final expired in [true, false]) {
    testWidgets('invalid grant does not renew (expired=$expired)', (
      tester,
    ) async {
      final repository = _Repository();
      var requests = 0;
      when(
        () => repository.getAttachmentDownloadGrant(
          upId: 'up-photo',
          attachmentIndex: 0,
        ),
      ).thenAnswer((_) async {
        requests += 1;
        return UpAttachmentDownloadGrant(
          url: Uri.parse(
            expired ? 'https://media.example.test/photo' : 'file:///photo',
          ),
          mime: 'image/png',
          sizeBytes: 1024,
          expiresAt: DateTime.now().add(Duration(seconds: expired ? -1 : 60)),
        );
      });
      final container = ProviderContainer(
        overrides: [upRepositoryProvider.overrideWithValue(repository)],
      );
      final provider = upAttachmentDownloadGrantProvider('up-photo', 0);
      container.listen(provider, (_, _) {});
      try {
        await container.read(provider.future);
        await tester.pump(const Duration(minutes: 2));
        expect(requests, 1);
      } finally {
        container.dispose();
      }
    });
  }

  testWidgets('visible photo renews its short-lived grant before expiry', (
    tester,
  ) async {
    final repository = _Repository();
    var requests = 0;
    when(
      () => repository.getAttachmentDownloadGrant(
        upId: 'up-photo',
        attachmentIndex: 0,
      ),
    ).thenAnswer((_) async {
      requests += 1;
      return UpAttachmentDownloadGrant(
        url: Uri.parse('https://media.example.test/photo?attempt=$requests'),
        mime: 'image/png',
        sizeBytes: 1024,
        expiresAt: DateTime.now().add(const Duration(seconds: 60)),
      );
    });
    final container = ProviderContainer(
      overrides: [upRepositoryProvider.overrideWithValue(repository)],
    );
    final provider = upAttachmentDownloadGrantProvider('up-photo', 0);
    final subscription = container.listen(provider, (_, _) {});
    try {
      await container.read(provider.future);
      await tester.pump(const Duration(seconds: 56));
      await tester.pump();
      expect(requests, 2);
      expect(container.read(provider).requireValue.url.query, 'attempt=2');
      subscription.close();
      await tester.pump();
      await tester.pump(const Duration(minutes: 2));
      expect(requests, 2);
    } finally {
      container.dispose();
    }
  });

  testWidgets('failed renewal stays failed without a retry loop', (
    tester,
  ) async {
    final repository = _Repository();
    var requests = 0;
    when(
      () => repository.getAttachmentDownloadGrant(
        upId: 'up-photo',
        attachmentIndex: 0,
      ),
    ).thenAnswer((_) async {
      requests += 1;
      if (requests > 1) throw StateError('access withdrawn');
      return UpAttachmentDownloadGrant(
        url: Uri.parse('https://media.example.test/photo'),
        mime: 'image/png',
        sizeBytes: 1024,
        expiresAt: DateTime.now().add(const Duration(seconds: 60)),
      );
    });
    final container = ProviderContainer(
      overrides: [upRepositoryProvider.overrideWithValue(repository)],
    );
    final provider = upAttachmentDownloadGrantProvider('up-photo', 0);
    container.listen(provider, (_, _) {});
    try {
      await container.read(provider.future);
      await tester.pump(const Duration(seconds: 56));
      await tester.pump();
      expect(container.read(provider).hasError, isTrue);
      await tester.pump(const Duration(minutes: 2));
      expect(requests, 2);
    } finally {
      container.dispose();
    }
  });
}
