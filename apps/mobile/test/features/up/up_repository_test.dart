import 'package:dio/dio.dart';
import 'package:esferaup/features/up/data/datasources/up_remote_datasource.dart';
import 'package:esferaup/features/up/data/repositories/up_repository_impl.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/domain/up_tag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  test('tags accept accents and hyphens but reject phrases', () {
    expect(validUpTag('matemàtiques'), isTrue);
    expect(validUpTag('difficult-sleep'), isTrue);
    expect(validUpTag('two words'), isFalse);
    expect(validUpTag('#tag'), isFalse);
    expect(validUpTag('a' * 61), isFalse);
  });
  late _MockDio dio;
  late UpRepositoryImpl repo;

  Response<Map<String, dynamic>> resp(Map<String, dynamic> data) => Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: 201,
    data: data,
  );

  setUp(() {
    dio = _MockDio();
    repo = UpRepositoryImpl(UpRemoteDataSource(dio));
  });

  test('listDeletedUps parses the recoverable UPs of a profile', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/ups/deleted',
        queryParameters: {'profile_id': 'p1'},
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => resp({
        'items': [
          {
            'id': 'up-1',
            'profile_id': 'p1',
            'category': 'casa',
            'occurred_at': '2026-06-15T10:30:00Z',
            'mood': 'love',
            'is_crisi': false,
            'preview': 'Built a tower',
            'has_attachment': true,
            'deleted_at': '2026-06-16T08:00:00Z',
            'restore_until': '2026-06-23T08:00:00Z',
            'days_left': 6,
          },
          {
            'id': 'up-2',
            'profile_id': 'p1',
            'category': 'casa',
            'occurred_at': '2026-06-15T10:30:00Z',
            'deleted_at': '2026-06-16T08:00:00Z',
            'restore_until': '2026-06-23T08:00:00Z',
            'days_left': 6,
            'restore_blocked_reason': 'consent_revoked',
          },
          {
            'id': 'up-3',
            'profile_id': 'p1',
            'category': 'casa',
            'occurred_at': '2026-06-15T10:30:00Z',
            'deleted_at': '2026-06-16T08:00:00Z',
            'restore_until': '2026-06-23T08:00:00Z',
            'days_left': 6,
            'restore_blocked_reason': 'a_reason_added_later',
          },
        ],
      }),
    );

    final items = await repo.listDeletedUps('p1');

    expect(items, hasLength(3));
    expect(items.first.id, 'up-1');
    expect(items.first.daysLeft, 6);
    expect(items.first.mood, UpMood.great);
    expect(items.first.preview, 'Built a tower');
    expect(items.first.hasAttachment, isTrue);
    expect(items.first.restoreBlock, isNull);
    expect(items[1].restoreBlock, UpRestoreBlock.consentRevoked);
    // A reason this build does not know keeps the restore action; the server
    // still refuses and explains.
    expect(items[2].restoreBlock, isNull);
  });

  test('restoreUp posts with an Idempotency-Key', () async {
    when(
      () => dio.post<Map<String, dynamic>>(
        '/ups/up-1/restore',
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async =>
          resp({'id': 'up-1', 'profile_id': 'p1', 'was_already': false}),
    );

    await repo.restoreUp('up-1');

    final options =
        verify(
              () => dio.post<Map<String, dynamic>>(
                '/ups/up-1/restore',
                options: captureAny(named: 'options'),
              ),
            ).captured.single
            as Options;
    expect(options.headers?['Idempotency-Key'], isNotEmpty);
  });

  test('createUp maps mood/category to the wire vocabulary + sends an '
      'Idempotency-Key + parses punts', () async {
    when(
      () => dio.post<Map<String, dynamic>>(
        '/profiles/p1/ups',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => resp({
        'id': 'up-1',
        'punts_awarded': 5,
        'daily_cap_reached': false,
        'esfera_counts': {'emocions': 3},
      }),
    );

    final result = await repo.createUp(
      profileId: 'p1',
      category: 'emocions',
      occurredAt: DateTime.utc(2026, 6, 15, 10, 30),
      mood: UpMood.great,
      note: '  Primer dia de casal!  ',
      tag: '  lectura-compartida  ',
      attachmentUploadKeys: const ['upload-image', 'upload-pdf'],
    );
    expect(result.id, 'up-1');
    expect(result.puntsAwarded, 5);
    expect(result.dailyCapReached, isFalse);

    final captured = verify(
      () => dio.post<Map<String, dynamic>>(
        '/profiles/p1/ups',
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    final data = captured[0] as Map<String, dynamic>;
    expect(data['category'], 'emocions');
    expect(data['mood'], 'love'); // UpMood.great → wire 'love'
    expect(data['note'], 'Primer dia de casal!'); // trimmed
    expect(data['tag'], 'lectura-compartida');
    expect(data['occurred_at'], '2026-06-15T10:30:00.000Z');
    expect(data['attachments'], const [
      {'upload_key': 'upload-image'},
      {'upload_key': 'upload-pdf'},
    ]);
    final options = captured[1] as Options;
    expect(options.headers?['Idempotency-Key'], isNotEmpty);
  });

  test('createCrisi maps duration bucket + mood_after + draft', () async {
    when(
      () => dio.post<Map<String, dynamic>>(
        '/profiles/p1/crisis',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => resp({'id': 'c-1', 'up_id': 'up-9', 'punts_awarded': 0}),
    );

    await repo.createCrisi(
      profileId: 'p1',
      occurredAt: DateTime.utc(2026, 6, 15, 14, 10),
      triggerText: 'canvi de rutina',
      resolutionText: '',
      durationBucket: 'five_to_15',
      moodAfter: UpMood.good,
      draft: true,
    );

    final data =
        verify(
              () => dio.post<Map<String, dynamic>>(
                '/profiles/p1/crisis',
                data: captureAny(named: 'data'),
                options: any(named: 'options'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(data['trigger_text'], 'canvi de rutina');
    expect(data.containsKey('resolution_text'), isFalse); // empty → omitted
    expect(data['duration_bucket'], 'five_to_15');
    expect(data['mood_after'], 'happy'); // UpMood.good → wire 'happy'
    expect(data['draft'], isTrue);
  });

  test('updateCrisi sends the moment inside the crisi block', () async {
    when(
      () => dio.patch<Map<String, dynamic>>(
        '/ups/up-9',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => resp({
        'id': 'up-9',
        'profile_id': 'p1',
        'category': 'emocions',
        'occurred_at': '2026-10-14T16:30:00Z',
        'is_pinned': false,
        'is_crisi': true,
        'crisi': {'trigger_text': 'soroll', 'draft': false},
        'created_at': '2026-10-15T08:35:00Z',
      }),
    );

    await repo.updateCrisi(
      upId: 'up-9',
      occurredAt: DateTime.utc(2026, 10, 14, 16, 30),
      triggerText: 'soroll',
      draft: false,
    );

    final data =
        verify(
              () => dio.patch<Map<String, dynamic>>(
                '/ups/up-9',
                data: captureAny(named: 'data'),
                options: any(named: 'options'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    final crisi = data['crisi'] as Map<String, dynamic>;
    expect(crisi['occurred_at'], '2026-10-14T16:30:00.000Z');
    expect(crisi['trigger_text'], 'soroll');
    expect(crisi['draft'], isFalse);
  });

  test('getUp maps ready attachment indices and metadata', () async {
    when(() => dio.get<Map<String, dynamic>>('/ups/up-1')).thenAnswer(
      (_) async => resp({
        'id': 'up-1',
        'profile_id': 'profile-1',
        'category': 'escola',
        'occurred_at': '2026-07-25T08:00:00Z',
        'mood': 'happy',
        'note': 'Una nota',
        'tag': 'matemàtiques',
        'is_pinned': true,
        'is_crisi': false,
        'attachments_pending': true,
        'attachments': [
          {
            'attachment_index': 0,
            'upload_key': 'opaque',
            'mime': 'image/jpeg',
            'size_bytes': 900,
          },
        ],
        'created_at': '2026-07-25T08:01:00Z',
      }),
    );

    final detail = await repo.getUp('up-1');

    expect(detail.profileId, 'profile-1');
    expect(detail.tag, 'matemàtiques');
    expect(detail.isPinned, isTrue);
    expect(detail.attachments.single.index, 0);
    expect(detail.attachments.single.isImage, isTrue);
    expect(detail.attachmentsPending, isTrue);
    expect(detail.copyWith(isPinned: false).attachmentsPending, isTrue);
  });

  test('attachment read grant uses the stable index route', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/ups/up-1/attachments/2/download',
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => resp({
        'download_url': 'https://objects.example.test/clean?signature=x',
        'mime': 'application/pdf',
        'size_bytes': 1200,
        'expires_at': '2026-07-25T08:01:00Z',
      }),
    );

    final grant = await repo.getAttachmentDownloadGrant(
      upId: 'up-1',
      attachmentIndex: 2,
    );

    expect(grant.url.scheme, 'https');
    expect(grant.mime, 'application/pdf');
    verify(
      () => dio.get<Map<String, dynamic>>(
        '/ups/up-1/attachments/2/download',
        options: any(named: 'options'),
      ),
    ).called(1);
  });
}
