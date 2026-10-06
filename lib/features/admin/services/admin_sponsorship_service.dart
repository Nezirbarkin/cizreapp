import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/sponsorship_model.dart';

/// numeric sütun JSON sayı ya da metin ("150.00") olarak gelebilir.
double _money(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

/// Admin > Öne Çıkarma (Görev 4.2): başvuru onay/ret (iade), iptal (isteğe
/// bağlı orantılı iade), paketler ve iki genel anahtar.
///
/// Kararlar sunucuda (`admin_review_sponsorship`, `admin_cancel_sponsorship`):
/// zincir, vitrin sütunu, iade ve satıcı bildirimi tek işlemde. Paketler ve
/// anahtarlar mevcut admin RLS'iyle doğrudan yazılır.
class AdminSponsorshipRow {
  const AdminSponsorshipRow({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.placement,
    required this.packageName,
    required this.durationDays,
    required this.pricePaid,
    required this.status,
    required this.createdAt,
    this.productId,
    this.productName,
    this.startsAt,
    this.endsAt,
    this.createdByName,
    this.reviewedAt,
    this.reviewNote,
    this.isRunning = false,
    this.isQueued = false,
  });

  final String id;
  final String shopId;
  final String shopName;
  final String? productId;
  final String? productName;
  final SponsorPlacement placement;
  final String packageName;
  final int durationDays;
  final double pricePaid;
  final SponsorshipStatus status;
  final DateTime createdAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? createdByName;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final bool isRunning;
  final bool isQueued;

  static AdminSponsorshipRow? tryFromJson(Map<String, dynamic> json) {
    final placement = SponsorPlacement.fromDb(json['placement']);
    if (placement == null) return null;
    return AdminSponsorshipRow(
      id: json['id'].toString(),
      shopId: json['shop_id']?.toString() ?? '',
      shopName: (json['shop_name'] as String?) ?? 'Mağaza',
      productId: json['product_id']?.toString(),
      productName: json['product_name'] as String?,
      placement: placement,
      packageName: (json['package_name'] as String?) ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 0,
      pricePaid: _money(json['price_paid']),
      status: SponsorshipStatus.fromDb(json['status']),
      createdAt: parseSponsorTime(json['created_at']) ?? DateTime.now().toUtc(),
      startsAt: parseSponsorTime(json['starts_at']),
      endsAt: parseSponsorTime(json['ends_at']),
      createdByName: json['created_by_name'] as String?,
      reviewedAt: parseSponsorTime(json['reviewed_at']),
      reviewNote: json['review_note'] as String?,
      isRunning: json['is_running'] == true,
      isQueued: json['is_queued'] == true,
    );
  }

  /// Geçmiş sekmesinde gösterilen durum etiketi.
  String get statusLabel => switch (status) {
    SponsorshipStatus.pending => 'Onay bekliyor',
    SponsorshipStatus.rejected => 'Reddedildi',
    SponsorshipStatus.cancelled => 'İptal edildi',
    SponsorshipStatus.active => isRunning ? 'Yayında' : (isQueued ? 'Sırada' : 'Süresi bitti'),
  };
}

class AdminSponsorshipPage {
  const AdminSponsorshipPage({
    this.rows = const [],
    this.total = 0,
    this.pending = 0,
    this.running = 0,
    this.queued = 0,
    this.revenue30d = 0,
    this.enabled = true,
    this.requiresApproval = false,
  });

  final List<AdminSponsorshipRow> rows;
  final int total;
  final int pending;
  final int running;
  final int queued;
  final double revenue30d;
  final bool enabled;
  final bool requiresApproval;

  factory AdminSponsorshipPage.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?) ?? const {};
    final settings = (json['settings'] as Map?) ?? const {};
    int count(Object? v) => (v as num?)?.toInt() ?? 0;
    return AdminSponsorshipPage(
      rows: [
        for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
          if (AdminSponsorshipRow.tryFromJson(Map<String, dynamic>.from(raw)) case final row?) row,
      ],
      total: count(json['total']),
      pending: count(summary['pending']),
      running: count(summary['running']),
      queued: count(summary['queued']),
      revenue30d: _money(summary['revenue_30d']),
      enabled: settings['enabled'] != false,
      requiresApproval: settings['requires_approval'] == true,
    );
  }
}

/// Yöneticinin gördüğü paket (pasifler dahil).
class AdminSponsorPackage {
  const AdminSponsorPackage({
    required this.id,
    required this.placement,
    required this.name,
    required this.durationDays,
    required this.price,
    required this.isActive,
    this.sortOrder = 0,
  });

  final String id;
  final SponsorPlacement placement;
  final String name;
  final int durationDays;
  final double price;
  final bool isActive;
  final int sortOrder;

  static AdminSponsorPackage? tryFromJson(Map<String, dynamic> json) {
    final placement = SponsorPlacement.fromDb(json['placement']);
    if (placement == null) return null;
    return AdminSponsorPackage(
      id: json['id'].toString(),
      placement: placement,
      name: (json['name'] as String?) ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 1,
      price: _money(json['price']),
      isActive: json['is_active'] != false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminSponsorshipService {
  AdminSponsorshipService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  /// status: 'pending' | 'active' | 'history' | 'all'
  Future<AdminSponsorshipPage> fetch(String status, {int limit = 50, int offset = 0}) async {
    final data = await _client.rpc(
      'admin_sponsorships_list',
      params: {'p_status': status, 'p_limit': limit, 'p_offset': offset},
    );
    return AdminSponsorshipPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Onay ya da ret; ret ücreti bakiyeye iade eder. İade edilen tutarı döner.
  Future<double> review(String id, {required bool approve, String? note}) async {
    final data = await _client.rpc(
      'admin_review_sponsorship',
      params: {'p_id': id, 'p_approve': approve, 'p_note': note},
    );
    return _money((data as Map)['refunded']);
  }

  /// İptal; [refund] açıksa başlamamışsa tamamı, sürüyorsa kalan süre kadarı.
  Future<double> cancel(String id, {required bool refund, String? note}) async {
    final data = await _client.rpc(
      'admin_cancel_sponsorship',
      params: {'p_id': id, 'p_refund': refund, 'p_note': note},
    );
    return _money((data as Map)['refunded']);
  }

  Future<List<AdminSponsorPackage>> fetchPackages() async {
    final rows = await _client
        .from('sponsorship_packages')
        .select('id, placement, name, duration_days, price, is_active, sort_order')
        .order('placement', ascending: true)
        .order('sort_order', ascending: true)
        .order('duration_days', ascending: true);
    return [
      for (final raw in (rows as List).whereType<Map>())
        if (AdminSponsorPackage.tryFromJson(Map<String, dynamic>.from(raw)) case final p?) p,
    ];
  }

  /// Yeni paket ([id] null) ya da güncelleme.
  Future<void> savePackage({
    String? id,
    required SponsorPlacement placement,
    required String name,
    required int durationDays,
    required double price,
    required bool isActive,
    int sortOrder = 0,
  }) async {
    final values = {
      'placement': placement.dbValue,
      'name': name.trim(),
      'duration_days': durationDays,
      'price': price,
      'is_active': isActive,
      'sort_order': sortOrder,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (id == null) {
      await _client.from('sponsorship_packages').insert(values);
    } else {
      await _client.from('sponsorship_packages').update(values).eq('id', id);
    }
  }

  Future<void> setPackageActive(String id, bool active) =>
      _client.from('sponsorship_packages').update({'is_active': active}).eq('id', id);

  Future<void> deletePackage(String id) => _client.from('sponsorship_packages').delete().eq('id', id);

  /// 'sponsorship_enabled' | 'sponsorship_requires_approval' (düz 'true'/'false').
  Future<void> setFlag(String key, bool value) => _client.from('app_settings').upsert({
    'key': key,
    'value': value ? 'true' : 'false',
  }, onConflict: 'key');

  /// Sunucu hatası → yöneticiye gösterilecek metin.
  static String errorMessage(Object error) {
    if (error is PostgrestException) {
      switch (error.hint) {
        case 'SPONSORSHIP_NOT_PENDING':
          return 'Bu başvuru zaten sonuçlanmış.';
        case 'SPONSORSHIP_NOT_ACTIVE':
          return 'Yalnız süren ya da sıradaki öne çıkarma iptal edilebilir.';
        case 'SPONSORSHIP_NOT_FOUND':
          return 'Kayıt bulunamadı.';
      }
      if (error.code == '23505') return 'Bu vitrin için aynı süreli bir paket zaten var.';
      if (error.code == '23514') return 'Paket bilgileri geçersiz (ad 1–40 karakter, süre 1–90 gün, fiyat ≥ 0).';
      if (error.code == '42501') return 'Bu işlem için yönetici yetkisi gerekli.';
      return error.message;
    }
    return 'İşlem tamamlanamadı: $error';
  }
}
