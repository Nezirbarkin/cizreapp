import 'dart:async';

import 'package:cizreapp/core/models/product_image_preset_model.dart';
import 'package:cizreapp/features/market/services/product_image_preset_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ağ katmanı sahte; önbellek (ProductImagePresetService.searchPresets /
/// getFoldersCached) gerçek.
class _CountingService extends ProductImagePresetService {
  final List<String> fetches = [];
  int folderFetches = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<List<ProductImagePreset>> fetchSearchPage(
    String query, {
    String? folderId,
    required int limit,
    required int offset,
    required bool matchAny,
  }) async {
    fetches.add('$query|$folderId|$limit|$offset|$matchAny');
    if (gate != null) await gate!.future;
    if (fail) throw Exception('ağ yok');
    return [
      ProductImagePreset(
        id: '$query-$offset',
        name: query,
        imageUrl: 'https://example.invalid/$query.webp',
        createdAt: DateTime(2026, 10, 16),
      ),
    ];
  }

  @override
  Future<List<ProductImageFolder>> getFolders() async {
    folderFetches++;
    if (fail) throw Exception('ağ yok');
    return const [ProductImageFolder(id: 'f1', name: 'Manav', imageCount: 3)];
  }
}

void main() {
  test('aynı arama ağa bir kez gider; boşluk farkı aynı sayılır', () async {
    final svc = _CountingService();
    final a = await svc.searchPresets('domates');
    final b = await svc.searchPresets('  domates  ');
    expect(svc.fetches, ['domates|null|60|0|false']);
    expect(identical(a, b), isTrue);

    // Klasör, sayfa, mod ya da limit farklıysa ayrı istek.
    await svc.searchPresets('domates', folderId: 'f1');
    await svc.searchPresets('domates', offset: 60);
    await svc.searchPresets('domates', matchAny: true);
    await svc.searchPresets('domates', limit: 8);
    expect(svc.fetches.length, 5);
  });

  test('süren istek paylaşılır', () async {
    final svc = _CountingService()..gate = Completer<void>();
    final first = svc.searchPresets('elma');
    final second = svc.searchPresets('elma');
    expect(svc.fetches.length, 1);
    svc.gate!.complete();
    expect(identical(await first, await second), isTrue);
  });

  test(
    'sonuç listesi değiştirilemez (paylaşılan önbellek bozulmasın)',
    () async {
      final list = await _CountingService().searchPresets('elma');
      expect(() => list.add(list.first), throwsUnsupportedError);
    },
  );

  test('hatalı istek önbelleğe girmez; tekrar dene ağa gider', () async {
    final svc = _CountingService()..fail = true;
    await expectLater(svc.searchPresets('elma'), throwsException);
    await expectLater(svc.getFoldersCached(), throwsException);
    svc.fail = false;
    expect((await svc.searchPresets('elma')).single.name, 'elma');
    expect((await svc.getFoldersCached()).single.name, 'Manav');
    expect(svc.fetches.length, 2);
    expect(svc.folderFetches, 2);
  });

  test(
    'klasör özeti: satıcı önbellekten, admin her seferinde güncel',
    () async {
      final svc = _CountingService();
      await svc.getFoldersCached();
      await svc.getFoldersCached();
      expect(svc.folderFetches, 1);
      await svc.getFolders();
      expect(svc.folderFetches, 2);
    },
  );

  test('admin değişikliği (başarısız olsa da) önbelleği boşaltır', () async {
    final svc = _CountingService();
    await svc.searchPresets('elma');
    await svc.getFoldersCached();

    // Supabase başlatılmadığı için istek düşer; önbellek yine boşalmalı
    // (kısmi değişiklik ihtimali).
    await expectLater(svc.setActive(['p1'], false), throwsException);

    await svc.searchPresets('elma');
    await svc.getFoldersCached();
    expect(svc.fetches.length, 2);
    expect(svc.folderFetches, 2);

    svc.clearCache();
    await svc.searchPresets('elma');
    expect(svc.fetches.length, 3);
  });

  test(
    'önbellek sınırlı: en eski arama düşer, yeni kullanılan kalır',
    () async {
      final svc = _CountingService();
      await svc.searchPresets('ilk');
      await svc.searchPresets('ikinci');
      // 2 + 78 = 80: sınır dolu, henüz düşen yok.
      for (var i = 0; i < 78; i++) {
        await svc.searchPresets('q$i');
      }
      // 'ilk' yeniden kullanıldı: sona taşındı. Sonraki ekleme 'ikinci'yi atar.
      await svc.searchPresets('ilk');
      await svc.searchPresets('son');
      final before = svc.fetches.length;
      await svc.searchPresets('ilk');
      expect(svc.fetches.length, before);
      await svc.searchPresets('ikinci');
      expect(svc.fetches.length, before + 1);
    },
  );
}
