import 'dart:convert';

import 'package:cizreapp/features/moderation/models/moderation_models.dart';
import 'package:cizreapp/features/moderation/services/moderation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.6 — moderasyon modelleri ve servis (RPC parametreleri).
void main() {
  group('modeller', () {
    test('yetki: kapsamlar, bilinmeyen atlanır, eşitlik ve özet', () {
      final access = ModerationAccess.fromJson({
        'is_admin': false,
        'scopes': ['content', 'reports', 'yeni_alan'],
      });
      expect(access.scopes, {ModerationScope.content, ModerationScope.reports});
      expect(access.can(ModerationScope.ilanlar), isFalse);
      expect(access.summary, 'Şikayetler · İçerik');
      expect(access.hasAny, isTrue);
      expect(access, ModerationAccess.fromJson({'scopes': ['reports', 'content']}));
      expect(ModerationAccess.fromJson(null), ModerationAccess.none);
      expect(ModerationAccess.none.hasAny, isFalse);
    });

    test('yetki: kategori sınırları (null = hepsi, liste = yalnız bunlar)', () {
      final access = ModerationAccess.fromJson({
        'scopes': ['ilanlar', 'live', 'reports'],
        'ilan_categories': [
          {'id': 'c1', 'name': 'Emlak'},
          {'id': 'c2', 'name': 'Vasıta'},
          {'name': 'kimliksiz atlanır'},
        ],
        'shop_categories': [],
      });
      expect(access.categoriesFor(ModerationScope.ilanlar), const [
        ModCategory(id: 'c1', name: 'Emlak'),
        ModCategory(id: 'c2', name: 'Vasıta'),
      ]);
      expect(access.categoriesFor(ModerationScope.live), isEmpty, reason: 'atananların hepsi silinmiş');
      expect(access.categoriesFor(ModerationScope.reports), isNull, reason: 'kapsam kategorisiz');
      expect(modCategoryNames(access.ilanCategories), 'Emlak, Vasıta');
      expect(modCategoryNames(null), isNull);

      final unlimited = ModerationAccess.fromJson({'scopes': ['ilanlar', 'live', 'reports']});
      expect(unlimited.categoriesFor(ModerationScope.ilanlar), isNull);
      expect(access == unlimited, isFalse, reason: 'kategori değişikliği yetki değişikliğidir');
      expect(
        access,
        ModerationAccess.fromJson({
          'scopes': ['reports', 'live', 'ilanlar'],
          'ilan_categories': [
            {'id': 'c1', 'name': 'Emlak'},
            {'id': 'c2', 'name': 'Vasıta'},
          ],
          'shop_categories': [],
        }),
      );
    });

    test('kapsam anahtarları sunucu CHECK listesiyle aynı', () {
      expect([for (final s in ModerationScope.values) s.key], ['reports', 'content', 'ilanlar', 'live']);
    });

    test('şikayet: gönderi ve kullanıcı satırları', () {
      final page = ModReportsPage.fromJson({
        'total': 2,
        'rows': [
          {
            'kind': 'post',
            'id': 'r1',
            'reason': 'spam',
            'status': 'pending',
            'created_at': '2026-09-28T10:00:00Z',
            'reporter': {'id': 'u1', 'name': 'Ayşe', 'username': 'ayse'},
            'post': {'id': 'p1', 'content': 'Kampanya!!!', 'is_active': false, 'author_name': 'Mehmet'},
          },
          {
            'kind': 'user',
            'id': 'r2',
            'reason': 'harassment',
            'status': 'resolved',
            'admin_response': 'Uyarıldı',
            'created_at': '2026-09-27T10:00:00Z',
            'images': ['https://x/y.jpg', ''],
            'user': {'id': 'u9', 'name': 'Kötü', 'username': 'kotu', 'status': 'suspended'},
          },
        ],
        'counts': {'open': 3, 'post_open': 2, 'user_open': 1},
      });
      final post = page.rows.first;
      expect(post.isPost, isTrue);
      expect(post.isOpen, isTrue);
      expect(post.statusLabel, 'Bekliyor');
      expect(post.postActive, isFalse);
      expect(post.postAuthorName, 'Mehmet');
      expect(post.reporter!.username, 'ayse');
      final user = page.rows.last;
      expect(user.isPost, isFalse);
      expect(user.isOpen, isFalse);
      expect(user.images, ['https://x/y.jpg']);
      expect(user.targetUser!.status, 'suspended');
      expect(page.open, 3);
      expect(reportReasonLabel('harassment'), 'Taciz / zorbalık');
      expect(reportReasonLabel('yeni'), 'yeni');
      expect(reportReasonLabel(null), 'Diğer');
    });

    test('gönderi ve ilan satırları', () {
      final posts = ModPostsPage.fromJson({
        'total': 1,
        'rows': [
          {
            'id': 'p1',
            'content': 'Merhaba',
            'is_active': true,
            'likes_count': 4,
            'open_reports': 2,
            'created_at': '2026-09-28T10:00:00Z',
            'author': {'id': 'a1', 'name': 'Ali'},
          },
        ],
      });
      expect(posts.rows.single.openReports, 2);
      expect(posts.rows.single.copyWith(isActive: false).isActive, isFalse);
      final ilans = ModIlansPage.fromJson({
        'total': 1,
        'rows': [
          {
            'id': 'i1',
            'title': 'Satılık bisiklet',
            'price': '1250.00',
            'city': 'Şırnak',
            'district': 'Cizre',
            'paid_fee': 10,
            'created_at': '2026-09-28T10:00:00Z',
            'owner': {'id': 'o1', 'name': 'Veli'},
          },
        ],
      });
      final ilan = ilans.rows.single;
      expect(ilan.price, 1250);
      expect(ilan.location, 'Cizre, Şırnak');
      expect(ilan.paidFee, 10);
    });
  });

  group('servis', () {
    late List<http.Request> requests;
    late Object? Function(http.Request req) respond;

    ModerationService service() => ModerationService(
      client: SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response(
            jsonEncode(respond(req)),
            200,
            request: req,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    setUp(() {
      requests = [];
      respond = (req) => switch (req.url.pathSegments.last) {
        'mod_reports' => {'total': 0, 'rows': [], 'counts': {}},
        'mod_posts' => {'total': 0, 'rows': []},
        'mod_pending_ilanlar' => {'total': 0, 'rows': []},
        'mod_set_post_active' => {'changed': true},
        _ => null,
      };
    });

    Map<String, dynamic> body() => jsonDecode(requests.last.body) as Map<String, dynamic>;

    test('RPC adları ve parametreleri; boş metin null gider', () async {
      final s = service();
      await s.reports(status: 'closed', limit: 10, offset: 20);
      expect(requests.last.url.path, '/rest/v1/rpc/mod_reports');
      expect(body(), {'p_status': 'closed', 'p_limit': 10, 'p_offset': 20});

      final report = ModReport(kind: 'post', id: 'r1', status: 'pending', createdAt: DateTime(2026, 9, 28));
      await s.resolveReport(report, status: 'resolved', response: '  ', hidePost: true);
      expect(requests.last.url.path, '/rest/v1/rpc/mod_resolve_report');
      expect(body(), {
        'p_kind': 'post',
        'p_id': 'r1',
        'p_status': 'resolved',
        'p_response': null,
        'p_hide_post': true,
      });

      await s.posts(filter: 'hidden', search: ' spam ');
      expect(body(), {'p_filter': 'hidden', 'p_search': 'spam', 'p_limit': 30, 'p_offset': 0});

      expect(await s.setPostActive('p1', false, reason: 'Reklam'), isTrue);
      expect(body(), {'p_post_id': 'p1', 'p_active': false, 'p_reason': 'Reklam'});

      await s.pendingIlanlar(limit: 5);
      expect(body(), {'p_limit': 5, 'p_offset': 0});

      await s.reviewIlan('i1', approve: false, reason: 'Yanıltıcı');
      expect(requests.last.url.path, '/rest/v1/rpc/mod_review_ilan');
      expect(body(), {'p_ilan_id': 'i1', 'p_approve': false, 'p_reason': 'Yanıltıcı'});
    });

    test('oturum yokken yetki boş döner, hata fırlatmaz', () async {
      expect(await ModerationService.fetchMyAccess(), ModerationAccess.none);
      expect(ModerationService.cachedAccess, ModerationAccess.none);
    });

    test('hata metinleri', () {
      expect(
        ModerationService.errorMessage(const PostgrestException(message: 'x', hint: 'MOD_SCOPE_MISSING')),
        'Gönderi gizlemek için İçerik yetkin olmalı.',
      );
      expect(
        ModerationService.errorMessage(const PostgrestException(message: 'x', hint: 'MOD_REASON_REQUIRED')),
        'Ret nedeni yazmalısın.',
      );
      expect(
        ModerationService.errorMessage(const PostgrestException(message: 'x', code: '42501')),
        'Bu işlem için moderatör yetkin yok.',
      );
      expect(
        ModerationService.errorMessage(
          const PostgrestException(message: 'x', code: '42501', hint: 'MOD_CATEGORY_FORBIDDEN'),
        ),
        'Bu kategori senin moderasyon alanında değil.',
      );
    });
  });
}

