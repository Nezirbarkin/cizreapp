import 'package:supabase_flutter/supabase_flutter.dart';

import '../../moderation/models/moderation_models.dart';

/// Admin > Moderatörler (Görev 4.6): listeleme, kullanıcı arama, kapsam
/// atama/kaldırma. Yazma yalnız `admin_set_moderator` RPC'siyle (denetim
/// günlüğü + kişiye bildirim); tabloya istemci yazamaz.
class AdminModerator {
  const AdminModerator({
    required this.userId,
    required this.scopes,
    required this.createdAt,
    this.fullName,
    this.username,
    this.avatarUrl,
    this.role,
    this.status,
    this.note,
    this.grantedByName,
    this.actions30d = 0,
    this.ilanCategories,
    this.shopCategories,
  });

  final String userId;
  final Set<ModerationScope> scopes;
  final DateTime createdAt;
  final String? fullName;
  final String? username;
  final String? avatarUrl;
  final String? role;
  final String? status;
  final String? note;
  final String? grantedByName;
  final int actions30d;

  /// Kategori sınırları (null = tüm kategoriler).
  final List<ModCategory>? ilanCategories;
  final List<ModCategory>? shopCategories;

  String get displayName {
    final full = fullName?.trim() ?? '';
    if (full.isNotEmpty) return full;
    final user = username?.trim() ?? '';
    return user.isNotEmpty ? user : 'Kullanıcı';
  }

  bool get isSuspended => status == 'suspended';

  factory AdminModerator.fromJson(Map<String, dynamic> json) {
    final scopes = json['scopes'];
    return AdminModerator(
      userId: json['user_id'].toString(),
      scopes: {
        if (scopes is List)
          for (final key in scopes)
            if (ModerationScope.fromKey(key) case final scope?) scope,
      },
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
      fullName: json['full_name'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String?,
      status: json['status'] as String?,
      note: (json['note'] as String?)?.trim(),
      grantedByName: json['granted_by_name'] as String?,
      actions30d: (json['actions_30d'] as num?)?.toInt() ?? 0,
      ilanCategories: ModCategory.listFromJson(json['ilan_categories']),
      shopCategories: ModCategory.listFromJson(json['shop_categories']),
    );
  }
}

/// Kategori seçicisinin seçenekleri (`admin_moderation_categories`).
class ModerationCategoryOptions {
  const ModerationCategoryOptions({this.ilan = const [], this.shop = const []});

  final List<ModCategory> ilan;
  final List<ModCategory> shop;

  factory ModerationCategoryOptions.fromJson(Object? raw) {
    final json = raw is Map ? raw : const {};
    return ModerationCategoryOptions(
      ilan: ModCategory.listFromJson(json['ilan']) ?? const [],
      shop: ModCategory.listFromJson(json['shop']) ?? const [],
    );
  }
}

/// Moderatör yapılabilecek kişi (arama sonucu).
class ModeratorCandidate {
  const ModeratorCandidate({required this.id, this.fullName, this.username, this.avatarUrl, this.role});

  final String id;
  final String? fullName;
  final String? username;
  final String? avatarUrl;
  final String? role;

  String get displayName {
    final full = fullName?.trim() ?? '';
    if (full.isNotEmpty) return full;
    final user = username?.trim() ?? '';
    return user.isNotEmpty ? user : 'Kullanıcı';
  }

  bool get isAdmin => role == 'admin';
}

class AdminModeratorsService {
  AdminModeratorsService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  Future<List<AdminModerator>> list() async {
    final data = await _client.rpc('admin_moderators_list');
    return [
      for (final row in (data as List? ?? const []).whereType<Map>())
        AdminModerator.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// Admin > Kullanıcılar'ın sayfalı aramasıyla (ad, kullanıcı adı, e-posta).
  Future<List<ModeratorCandidate>> searchUsers(String query) async {
    final text = query.trim();
    if (text.length < 2) return const [];
    final data = await _client.rpc(
      'admin_users_page',
      params: {'p_search': text, 'p_limit': 20, 'p_offset': 0},
    );
    final rows = data is Map ? data['rows'] : null;
    return [
      for (final row in (rows as List? ?? const []).whereType<Map>())
        ModeratorCandidate(
          id: row['id'].toString(),
          fullName: row['full_name'] as String?,
          username: row['username'] as String?,
          avatarUrl: row['avatar_url'] as String?,
          role: row['role'] as String?,
        ),
    ];
  }

  /// Moderatöre atanabilecek ilan ve mağaza kategorileri.
  Future<ModerationCategoryOptions> fetchCategories() async {
    final data = await _client.rpc('admin_moderation_categories');
    return ModerationCategoryOptions.fromJson(data);
  }

  /// Kapsamları yazar; boş küme moderatörlükten çıkarır. Sunucunun kaydettiği
  /// kapsamları döner.
  ///
  /// Kategori listeleri: null = değiştirme, boş liste = tüm kategoriler,
  /// dolu = yalnız bunlar (kapsam seçili değilse sunucu sınırı siler).
  Future<Set<ModerationScope>> setModerator(
    String userId,
    Set<ModerationScope> scopes, {
    String? note,
    List<String>? ilanCategoryIds,
    List<String>? shopCategoryIds,
  }) async {
    final text = note?.trim();
    final data = await _client.rpc(
      'admin_set_moderator',
      params: {
        'p_user_id': userId,
        'p_scopes': [for (final s in ModerationScope.values) if (scopes.contains(s)) s.key],
        'p_note': text == null || text.isEmpty ? null : text,
        'p_ilan_category_ids': ilanCategoryIds,
        'p_shop_category_ids': shopCategoryIds,
      },
    );
    final saved = data is Map ? data['scopes'] : null;
    return {
      if (saved is List)
        for (final key in saved)
          if (ModerationScope.fromKey(key) case final scope?) scope,
    };
  }

  static String errorMessage(Object error) {
    if (error is PostgrestException) {
      switch (error.hint) {
        case 'MOD_SCOPE_INVALID':
          return 'Geçersiz yetki alanı.';
        case 'MOD_USER_NOT_FOUND':
          return 'Kullanıcı bulunamadı.';
        case 'MOD_USER_INVALID':
          return 'Bot ya da misafir hesap moderatör olamaz.';
        case 'MOD_USER_IS_ADMIN':
          return 'Yöneticiler zaten tüm yetkilere sahip.';
        case 'MOD_CATEGORY_INVALID':
          return 'Seçilen kategorilerden biri artık yok; listeyi yenileyip tekrar dene.';
      }
      if (error.code == '42501') return 'Bu işlem için yönetici yetkisi gerekli.';
      return error.message;
    }
    return 'İşlem tamamlanamadı: $error';
  }
}
