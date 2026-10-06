import 'dart:convert';

import 'package:cizreapp/features/admin/services/bot_comment_service.dart';
import 'package:cizreapp/features/admin/services/bot_service.dart';
import 'package:cizreapp/features/admin/widgets/bot_comments_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.7 — bot yorumları: servis (RPC/ayar biçimi) ve Yorumlar sekmesi.

class _FakeBotComments extends BotCommentService {
  final calls = <String>[];
  BotCommentSettings settings = const BotCommentSettings();
  Object? failNext;

  List<BotCommentJob> jobRows = [
    BotCommentJob(
      id: 'j1',
      body: 'Eline sağlık',
      source: 'manual',
      status: 'pending',
      createdAt: DateTime(2026, 9, 28, 10),
      dueAt: DateTime(2026, 9, 28, 13),
      botName: 'Nazlı Erkan',
      postPreview: 'Yeni dükkanımız açıldı',
      postAuthorName: 'Ali',
    ),
  ];

  List<BotCommentTemplate> templates = const [
    BotCommentTemplate(id: 't1', body: 'Harika paylaşım', tone: 'genel', useCount: 3),
    BotCommentTemplate(id: 't2', body: 'Pasif metin', tone: 'mizah', isActive: false),
  ];

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  Future<BotCommentSettings> loadSettings() async => settings;

  @override
  Future<void> saveSettings(BotCommentSettings s) async {
    calls.add('settings:${s.enabled}:${s.probability}:${s.minCount}-${s.maxCount}:${s.minHours}-${s.maxHours}:${s.lookbackDays}');
    settings = s;
  }

  @override
  Future<({String status, String jobId, String? commentId})> comment({
    required String botId,
    required String postId,
    required String body,
    DateTime? dueAt,
  }) async {
    calls.add('comment:$botId:$postId:$body:${dueAt == null ? 'now' : 'later'}');
    _maybeFail();
    return (status: dueAt == null ? 'done' : 'pending', jobId: 'j9', commentId: dueAt == null ? 'c9' : null);
  }

  @override
  Future<BotCommentJobsPage> jobs({String status = 'pending', int limit = 30, int offset = 0}) async {
    calls.add('jobs:$status');
    final rows = status == 'pending' ? jobRows.where((j) => j.isPending).toList() : jobRows;
    return BotCommentJobsPage(rows: rows, total: rows.length, pending: jobRows.where((j) => j.isPending).length, done24h: 4);
  }

  @override
  Future<String> cancel(String jobId) async {
    calls.add('cancel:$jobId');
    jobRows = [for (final j in jobRows) if (j.id != jobId) j];
    return 'cancelled';
  }

  @override
  Future<List<BotCommentTemplate>> library() async => templates;

  @override
  Future<String> upsertTemplate({String? id, required String body, required String tone, required bool isActive}) async {
    calls.add('template:${id ?? 'new'}:$body:$tone:$isActive');
    _maybeFail();
    return id ?? 't9';
  }

  @override
  Future<void> deleteTemplate(String id) async => calls.add('delete-template:$id');

  @override
  Future<List<BotPostOption>> recentPosts({String? search, int limit = 20}) async {
    calls.add('posts:${search?.trim() ?? ''}');
    return const [
      BotPostOption(id: 'p1', preview: 'Yeni dükkanımız açıldı', commentsCount: 2, authorName: 'Ali'),
      BotPostOption(id: 'p2', preview: 'Bot paylaşımı', authorName: 'Nazlı', authorIsBot: true),
    ];
  }

  @override
  Future<({int scheduled, int processed})> runQueue() async {
    calls.add('run');
    return (scheduled: 3, processed: 1);
  }
}

const _bots = [
  BotAccount(id: 'b1', fullName: 'Nazlı Erkan', username: 'nazli.erkan'),
  BotAccount(id: 'b2', fullName: 'Pasif Bot', username: 'pasif', isActive: false),
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_FakeBotComments> _pump(WidgetTester tester) async {
  final fake = _FakeBotComments();
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: BotCommentsTab(bots: _bots, service: fake))),
  );
  await _settle(tester);
  return fake;
}

void main() {
  group('servis', () {
    late List<http.Request> requests;

    BotCommentService service() => BotCommentService(
      client: SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((req) async {
          requests.add(req);
          final name = req.url.pathSegments.last;
          final Object? body = switch (name) {
            'admin_bot_comment' => {'job_id': 'j1', 'comment_id': null, 'status': 'pending'},
            'app_settings' when req.method == 'GET' => [
              {'key': 'bot_auto_comment_enabled', 'value': 'true'},
              {'key': 'bot_comment_probability', 'value': '140'},
              {'key': 'bot_comment_min_count', 'value': '2'},
              {'key': 'bot_comment_max_count', 'value': '1'},
            ],
            _ => null,
          };
          return http.Response(
            jsonEncode(body),
            200,
            request: req,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    setUp(() => requests = []);

    test('zamanlı yorum RPC parametreleri; metin kırpılır', () async {
      final due = DateTime.utc(2026, 9, 28, 15);
      final result = await service().comment(botId: 'b1', postId: 'p1', body: '  Merhaba ', dueAt: due);
      expect(requests.single.url.path, '/rest/v1/rpc/admin_bot_comment');
      expect(jsonDecode(requests.single.body), {
        'p_bot_id': 'b1',
        'p_post_id': 'p1',
        'p_body': 'Merhaba',
        'p_due_at': '2026-09-28T15:00:00.000Z',
      });
      expect(result.status, 'pending');
      expect(result.commentId, isNull);
    });

    test('ayarlar düz metin okunur/yazılır; sınırlar ve sıralama düzeltilir', () async {
      final s = await service().loadSettings();
      expect(s.enabled, isTrue);
      expect(s.probability, 100, reason: '0-100 arasına kırpılır');
      expect(s.minCount, 2);
      expect(s.maxCount, 2, reason: 'en çok, en azdan küçük olamaz');

      requests.clear();
      await service().saveSettings(const BotCommentSettings(enabled: false, probability: 30));
      final rows = jsonDecode(requests.single.body) as List;
      expect(requests.single.url.queryParameters['on_conflict'], 'key');
      final map = {for (final r in rows) r['key']: r['value']};
      expect(map['bot_auto_comment_enabled'], 'false');
      expect(map['bot_comment_probability'], '30');
      expect(map.length, 7);
    });

    test('hata metinleri', () {
      expect(
        BotCommentService.errorMessage(const PostgrestException(message: 'x', hint: 'BOT_POST_UNAVAILABLE')),
        'Gönderi bulunamadı ya da gizli.',
      );
      expect(
        BotCommentService.errorMessage(const PostgrestException(message: 'x', hint: 'BOT_COMMENT_DUPLICATE')),
        'Bu yorum kitaplıkta zaten var.',
      );
      expect(BotCommentService.toneLabel('yerel'), 'Yerel');
      expect(BotCommentService.tones, ['genel', 'tebrik', 'soru', 'mizah', 'yerel', 'destek']);
    });
  });

  group('Yorumlar sekmesi', () {
    testWidgets('manuel yorum: bot + gönderi + kitaplıktan metin, hemen', (tester) async {
      final fake = await _pump(tester);

      final send = find.byKey(const ValueKey('bot-comment-send'));
      expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'bot/gönderi/metin seçilmeden gönderilmez');

      await tester.tap(find.byKey(const ValueKey('bot-comment-bot')));
      await _settle(tester);
      expect(find.text('Pasif Bot · @pasif'), findsNothing, reason: 'pasif bot seçilemez');
      await tester.tap(find.text('Nazlı Erkan · @nazli.erkan').last);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('bot-post-p1')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('bot-comment-template')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('pick-template-t2')), findsNothing, reason: 'pasif kitaplık metni önerilmez');
      expect(find.byKey(const ValueKey('pick-template-t1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pick-template-t1')));
      await _settle(tester);

      await tester.tap(send);
      await _settle(tester);
      expect(fake.calls, contains('comment:b1:p1:Harika paylaşım:now'));
      expect(find.text('Yorum yazıldı'), findsOneWidget);
    });

    testWidgets('zamanlama seçilince "Zamanla" ve kuyruğa düşer', (tester) async {
      final fake = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('bot-comment-bot')));
      await _settle(tester);
      await tester.tap(find.text('Nazlı Erkan · @nazli.erkan').last);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('bot-post-p2')));
      await tester.enterText(find.byKey(const ValueKey('bot-comment-body')), 'Sonra');
      await tester.tap(find.byKey(const ValueKey('bot-comment-delay')));
      await _settle(tester);
      await tester.tap(find.text('1 saat sonra').last);
      await _settle(tester);
      expect(find.text('Zamanla'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bot-comment-send')));
      await _settle(tester);
      expect(fake.calls, contains('comment:b1:p2:Sonra:later'));
      expect(find.text('Yorum zamanlandı'), findsOneWidget);
    });

    testWidgets('otomatik ayarlar doğrulanır ve kaydedilir; kuyruk çalıştırılır', (tester) async {
      final fake = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('bot-comment-auto-enabled')));
      await tester.enterText(find.byKey(const ValueKey('bot-set-probability')), '150');
      await tester.tap(find.byKey(const ValueKey('bot-comment-settings-save')));
      await _settle(tester);
      expect(find.text('0–100 arası'), findsOneWidget);
      expect(fake.calls.where((c) => c.startsWith('settings')), isEmpty);

      await tester.enterText(find.byKey(const ValueKey('bot-set-probability')), '40');
      await tester.enterText(find.byKey(const ValueKey('bot-set-max-count')), '3');
      await tester.tap(find.byKey(const ValueKey('bot-comment-settings-save')));
      await _settle(tester);
      expect(fake.calls, contains('settings:true:40:1-3:0-6:2'));

      await tester.tap(find.byKey(const ValueKey('bot-comment-run')));
      await _settle(tester);
      expect(find.text('3 yorum zamanlandı · 1 yorum yazıldı'), findsOneWidget);
    });

    testWidgets('kuyruk: bekleyen iptal edilir; kitaplığa ekleme', (tester) async {
      final fake = await _pump(tester);
      expect(find.text('"Eline sağlık"'), findsOneWidget);
      await tester.tap(find.text('İptal et'));
      await _settle(tester);
      expect(fake.calls, contains('cancel:j1'));
      expect(find.text('Zamanlanmış yorum iptal edildi'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bot-template-add')));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet').last);
      await tester.pump();
      expect(find.text('Yorum boş olamaz'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('template-body')), 'Kolay gelsin');
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet').last);
      await _settle(tester);
      expect(fake.calls, contains('template:new:Kolay gelsin:genel:true'));
    });
  });
}
