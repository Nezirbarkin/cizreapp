import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin > Dükkanlar'ın bir sayfası (bkz. `admin_shops_page` RPC'si).
class AdminShopsPage {
  const AdminShopsPage({
    required this.rows,
    required this.total,
    required this.summary,
  });

  factory AdminShopsPage.fromJson(Map<String, dynamic> json) {
    final rawSummary = json['summary'];
    return AdminShopsPage(
      rows: [
        for (final row in (json['rows'] as List? ?? const []))
          Map<String, dynamic>.from(row as Map),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      summary: {
        if (rawSummary is Map)
          for (final entry in rawSummary.entries)
            if (entry.value is num) entry.key as String: entry.value as num,
      },
    );
  }

  /// Kart satırları; alan adları eski `_loadShopsWithDetails` ile aynı
  /// (`profiles`, `product_count`, `total_earnings`, `net_earnings` …).
  final List<Map<String, dynamic>> rows;

  /// Arama + filtreye uyan toplam dükkan sayısı (sayfalama için).
  final int total;

  /// Arama/filtreden BAĞIMSIZ tüm dükkanların özeti: `total`, `pending`,
  /// `active`, `passive`, `pinned`, `verified`, `admin_courier`,
  /// `overridden`, `revenue`, `commission`.
  final Map<String, num> summary;

  int count(String key) => summary[key]?.toInt() ?? 0;

  double amount(String key) => summary[key]?.toDouble() ?? 0;
}

/// Admin > Dükkanlar veri katmanı: TEK istek; arama, filtre, sıralama ve
/// sayfalama sunucuda. Eskiden her dükkan için sırayla 4–5 istek atılıyordu.
class AdminShopsService {
  AdminShopsService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  /// Bir seferde yüklenen dükkan sayısı (kartlar büyük olduğu için küçük).
  static const int pageSize = 20;

  /// [filter] `all` ise süzme yok; [sort] `default` = sabitlenen önce + isim.
  Future<AdminShopsPage> fetchPage({
    String? search,
    String filter = 'all',
    String sort = 'default',
    int offset = 0,
    int limit = pageSize,
  }) async {
    final query = search?.trim() ?? '';
    final res = await _db.rpc(
      'admin_shops_page',
      params: {
        'p_search': query.isEmpty ? null : query,
        'p_filter': filter == 'all' ? null : filter,
        'p_sort': sort,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return AdminShopsPage.fromJson(Map<String, dynamic>.from(res as Map));
  }
}
