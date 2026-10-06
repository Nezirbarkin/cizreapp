import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/live_shopping_model.dart';

/// Admin > Canlı Yayınlar (Görev 4.3): yayın listesi, yayını kapatma,
/// mağaza bazında yayın izni ve genel ayarlar. Hepsi yönetici kontrollü
/// RPC'lerdir (`admin_live_*`); izin tablosuna istemci doğrudan erişemez.

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? _time(Object? value) => value is String && value.isNotEmpty ? DateTime.tryParse(value)?.toUtc() : null;

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// Mağazanın ya da kullanıcının etkin yayın erişimi (sunucudaki
/// `private.live_shop_access` / `private.live_user_access`).
enum LiveShopAccess {
  ok('Yayın açabilir'),
  disabled('Canlı yayın genel olarak kapalı'),
  revoked('İzni kaldırıldı'),
  notPermitted('İzin bekliyor (yalnız izinliler modu)'),
  usersOff('Kullanıcı yayınları kapalı'),
  accountInactive('Hesap pasif');

  const LiveShopAccess(this.label);

  final String label;

  static LiveShopAccess fromCode(Object? code) => switch (code) {
    'LIVE_DISABLED' => LiveShopAccess.disabled,
    'LIVE_REVOKED' || 'LIVE_USER_REVOKED' => LiveShopAccess.revoked,
    'LIVE_NOT_PERMITTED' || 'LIVE_USER_NOT_PERMITTED' => LiveShopAccess.notPermitted,
    'LIVE_USERS_OFF' => LiveShopAccess.usersOff,
    'LIVE_ACCOUNT_INACTIVE' => LiveShopAccess.accountInactive,
    _ => LiveShopAccess.ok,
  };
}

/// Genel ayarlar: modül açık mı, mağaza erişim modu ('open' | 'invite') ve
/// kullanıcı yayını modu ('open' | 'invite' | 'off').
class AdminLiveSettings {
  const AdminLiveSettings({this.enabled = true, this.access = 'open', this.userMode = 'open'});

  final bool enabled;
  final String access;
  final String userMode;

  bool get inviteOnly => access == 'invite';

  static String parseUserMode(Object? raw) => switch (raw) {
    'invite' => 'invite',
    'off' => 'off',
    _ => 'open',
  };

  factory AdminLiveSettings.fromJson(Object? raw) {
    final json = raw is Map ? raw : const {};
    return AdminLiveSettings(
      enabled: json['enabled'] != false,
      access: json['access'] == 'invite' ? 'invite' : 'open',
      userMode: parseUserMode(json['user_mode']),
    );
  }
}

class AdminLiveSessionRow {
  const AdminLiveSessionRow({
    required this.session,
    this.hostName,
    this.hostUsername,
    this.messageCount = 0,
    this.durationSeconds = 0,
    this.endedNote,
    this.endedByName,
    this.shopAccess = LiveShopAccess.ok,
  });

  final LiveSession session;
  final String? hostName;
  final String? hostUsername;
  final int messageCount;
  final int durationSeconds;
  final String? endedNote;
  final String? endedByName;
  final LiveShopAccess shopAccess;

  factory AdminLiveSessionRow.fromJson(Map<String, dynamic> json) => AdminLiveSessionRow(
    session: LiveSession.fromJson(json),
    hostName: _text(json['host_name']),
    hostUsername: _text(json['host_username']),
    messageCount: _int(json['message_count']),
    durationSeconds: _int(json['duration_seconds']),
    endedNote: _text(json['ended_note']),
    endedByName: _text(json['ended_by_name']),
    shopAccess: LiveShopAccess.fromCode(json['shop_access']),
  );

  /// Bitiş nedeni (geçmiş listesinde).
  String get endedReasonLabel => switch (session.endedReason) {
    'admin' => 'Yönetici kapattı',
    'timeout' => 'Bağlantı koptu',
    _ => session.isUserStream ? 'Yayıncı bitirdi' : 'Satıcı bitirdi',
  };
}

class AdminLiveSessionsPage {
  const AdminLiveSessionsPage({
    this.rows = const [],
    this.total = 0,
    this.liveNow = 0,
    this.preparing = 0,
    this.today = 0,
    this.minutes7d = 0,
    this.adminClosed30d = 0,
    this.grantedShops = 0,
    this.revokedShops = 0,
    this.userLiveNow = 0,
    this.grantedUsers = 0,
    this.revokedUsers = 0,
    this.settings = const AdminLiveSettings(),
  });

  final List<AdminLiveSessionRow> rows;
  final int total;
  final int liveNow;
  final int preparing;
  final int today;
  final int minutes7d;
  final int adminClosed30d;
  final int grantedShops;
  final int revokedShops;

  /// Şu an canlı kullanıcı (mağazasız) yayını ve kullanıcı izin sayaçları.
  final int userLiveNow;
  final int grantedUsers;
  final int revokedUsers;
  final AdminLiveSettings settings;

  factory AdminLiveSessionsPage.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?) ?? const {};
    return AdminLiveSessionsPage(
      rows: [
        for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
          AdminLiveSessionRow.fromJson(Map<String, dynamic>.from(raw)),
      ],
      total: _int(json['total']),
      liveNow: _int(summary['live_now']),
      preparing: _int(summary['preparing']),
      today: _int(summary['today']),
      minutes7d: _int(summary['minutes_7d']),
      adminClosed30d: _int(summary['admin_closed_30d']),
      grantedShops: _int(summary['granted_shops']),
      revokedShops: _int(summary['revoked_shops']),
      userLiveNow: _int(summary['user_live_now']),
      grantedUsers: _int(summary['granted_users']),
      revokedUsers: _int(summary['revoked_users']),
      settings: AdminLiveSettings.fromJson(json['settings']),
    );
  }
}

class AdminLiveShop {
  const AdminLiveShop({
    required this.shopId,
    required this.shopName,
    this.logoUrl,
    this.isActive = true,
    this.isApproved = true,
    this.ownerName,
    this.ownerUsername,
    this.permission,
    this.note,
    this.permissionUpdatedAt,
    this.updatedByName,
    this.effective = LiveShopAccess.ok,
    this.sessionCount = 0,
    this.lastLiveAt,
    this.liveSessionId,
  });

  final String shopId;
  final String shopName;
  final String? logoUrl;
  final bool isActive;
  final bool isApproved;
  final String? ownerName;
  final String? ownerUsername;

  /// 'granted' | 'revoked' | null (varsayılan: moda göre).
  final String? permission;
  final String? note;
  final DateTime? permissionUpdatedAt;
  final String? updatedByName;
  final LiveShopAccess effective;
  final int sessionCount;
  final DateTime? lastLiveAt;

  /// Şu an canlıysa yayının kimliği.
  final String? liveSessionId;

  bool get isLiveNow => liveSessionId != null;

  factory AdminLiveShop.fromJson(Map<String, dynamic> json) => AdminLiveShop(
    shopId: json['shop_id'].toString(),
    shopName: _text(json['shop_name']) ?? 'Mağaza',
    logoUrl: _text(json['logo_url']),
    isActive: json['is_active'] != false,
    isApproved: json['is_approved'] != false,
    ownerName: _text(json['owner_name']),
    ownerUsername: _text(json['owner_username']),
    permission: switch (json['permission']) {
      'granted' => 'granted',
      'revoked' => 'revoked',
      _ => null,
    },
    note: _text(json['note']),
    permissionUpdatedAt: _time(json['permission_updated_at']),
    updatedByName: _text(json['updated_by_name']),
    effective: LiveShopAccess.fromCode(json['effective']),
    sessionCount: _int(json['session_count']),
    lastLiveAt: _time(json['last_live_at']),
    liveSessionId: _text(json['live_session_id']),
  );
}

class AdminLiveShopsPage {
  const AdminLiveShopsPage({
    this.rows = const [],
    this.total = 0,
    this.granted = 0,
    this.revoked = 0,
    this.settings = const AdminLiveSettings(),
  });

  final List<AdminLiveShop> rows;
  final int total;
  final int granted;
  final int revoked;
  final AdminLiveSettings settings;

  factory AdminLiveShopsPage.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?) ?? const {};
    return AdminLiveShopsPage(
      rows: [
        for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
          AdminLiveShop.fromJson(Map<String, dynamic>.from(raw)),
      ],
      total: _int(json['total']),
      granted: _int(summary['granted']),
      revoked: _int(summary['revoked']),
      settings: AdminLiveSettings.fromJson(json['settings']),
    );
  }
}

/// Kullanıcı (mağazasız) yayıncı satırı (`admin_live_users`).
class AdminLiveUser {
  const AdminLiveUser({
    required this.userId,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.status,
    this.permission,
    this.note,
    this.permissionUpdatedAt,
    this.updatedByName,
    this.effective = LiveShopAccess.ok,
    this.sessionCount = 0,
    this.lastLiveAt,
    this.liveSessionId,
  });

  final String userId;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final String? status;

  /// 'granted' | 'revoked' | null (varsayılan: moda göre).
  final String? permission;
  final String? note;
  final DateTime? permissionUpdatedAt;
  final String? updatedByName;
  final LiveShopAccess effective;
  final int sessionCount;
  final DateTime? lastLiveAt;
  final String? liveSessionId;

  bool get isLiveNow => liveSessionId != null;

  String get displayName => username != null ? '@$username' : (fullName ?? 'Kullanıcı');

  factory AdminLiveUser.fromJson(Map<String, dynamic> json) => AdminLiveUser(
    userId: json['user_id'].toString(),
    username: _text(json['username']),
    fullName: _text(json['full_name']),
    avatarUrl: _text(json['avatar_url']),
    status: _text(json['status']),
    permission: switch (json['permission']) {
      'granted' => 'granted',
      'revoked' => 'revoked',
      _ => null,
    },
    note: _text(json['note']),
    permissionUpdatedAt: _time(json['permission_updated_at']),
    updatedByName: _text(json['updated_by_name']),
    effective: LiveShopAccess.fromCode(json['effective']),
    sessionCount: _int(json['session_count']),
    lastLiveAt: _time(json['last_live_at']),
    liveSessionId: _text(json['live_session_id']),
  );
}

class AdminLiveUsersPage {
  const AdminLiveUsersPage({
    this.rows = const [],
    this.total = 0,
    this.granted = 0,
    this.revoked = 0,
    this.settings = const AdminLiveSettings(),
  });

  final List<AdminLiveUser> rows;
  final int total;
  final int granted;
  final int revoked;
  final AdminLiveSettings settings;

  factory AdminLiveUsersPage.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?) ?? const {};
    return AdminLiveUsersPage(
      rows: [
        for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
          AdminLiveUser.fromJson(Map<String, dynamic>.from(raw)),
      ],
      total: _int(json['total']),
      granted: _int(summary['granted']),
      revoked: _int(summary['revoked']),
      settings: AdminLiveSettings.fromJson(json['settings']),
    );
  }
}

/// Yayın bildirimi, ana sayfa kartı ve geçmiş ayarları (`admin_live_options`).
class AdminLiveOptions {
  const AdminLiveOptions({
    this.notifyEnabled = true,
    this.notifyCooldownHours = 3,
    this.notifyFollowers = true,
    this.notifyProductFans = true,
    this.notifyCustomers = false,
    this.notifyMaxRecipients = 2000,
    this.homeCardEnabled = true,
    this.historyDays = 30,
    this.subscriptions = 0,
    this.subscribedShops = 0,
    this.notifications30d = 0,
    this.recipients30d = 0,
    this.cooldownSkips30d = 0,
  });

  final bool notifyEnabled;
  final int notifyCooldownHours;
  final bool notifyFollowers;
  final bool notifyProductFans;
  final bool notifyCustomers;
  final int notifyMaxRecipients;
  final bool homeCardEnabled;
  final int historyDays;

  // Son 30 gün sayaçları
  final int subscriptions;
  final int subscribedShops;
  final int notifications30d;
  final int recipients30d;
  final int cooldownSkips30d;

  /// Sunucudaki sınırlar (`admin_set_live_options` aynı aralığa sıkıştırır).
  static const cooldownRange = (min: 0, max: 72);
  static const maxRecipientsRange = (min: 0, max: 20000);
  static const historyDaysRange = (min: 1, max: 180);

  factory AdminLiveOptions.fromJson(Map<String, dynamic> json) {
    final stats = (json['stats'] as Map?) ?? const {};
    return AdminLiveOptions(
      notifyEnabled: json['notify_enabled'] != false,
      notifyCooldownHours: _int(json['notify_cooldown_hours']),
      notifyFollowers: json['notify_followers'] != false,
      notifyProductFans: json['notify_product_fans'] != false,
      notifyCustomers: json['notify_customers'] == true,
      notifyMaxRecipients: _int(json['notify_max_recipients']),
      homeCardEnabled: json['home_card_enabled'] != false,
      historyDays: json['history_days'] == null ? 30 : _int(json['history_days']),
      subscriptions: _int(stats['subscriptions']),
      subscribedShops: _int(stats['subscribed_shops']),
      notifications30d: _int(stats['notifications_30d']),
      recipients30d: _int(stats['recipients_30d']),
      cooldownSkips30d: _int(stats['cooldown_skips_30d']),
    );
  }
}

/// İzin/ayar değişikliğinin sonucu.
class AdminLiveChange {
  const AdminLiveChange({this.closed = 0, this.effective, this.settings});

  /// Bu işlemle kapatılan yayın sayısı.
  final int closed;
  final LiveShopAccess? effective;
  final AdminLiveSettings? settings;
}

class AdminLiveService {
  AdminLiveService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  /// status: 'live' | 'ended' | 'all'
  Future<AdminLiveSessionsPage> fetchSessions(String status, {int limit = 30, int offset = 0}) async {
    final data = await _client.rpc(
      'admin_live_sessions',
      params: {'p_status': status, 'p_limit': limit, 'p_offset': offset},
    );
    return AdminLiveSessionsPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// filter: 'all' | 'granted' | 'revoked' | 'streamed'
  Future<AdminLiveShopsPage> fetchShops({
    String? search,
    String filter = 'all',
    int limit = 30,
    int offset = 0,
  }) async {
    final text = search?.trim();
    final data = await _client.rpc(
      'admin_live_shops',
      params: {
        'p_search': text == null || text.isEmpty ? null : text,
        'p_filter': filter,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return AdminLiveShopsPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Kullanıcı yayıncıları. Aramasız: izin kaydı olan ya da yayın açmış
  /// olanlar; aramayla eşleşen tüm hesaplar. filter: 'all' | 'granted' |
  /// 'revoked' | 'streamed'.
  Future<AdminLiveUsersPage> fetchUsers({
    String? search,
    String filter = 'all',
    int limit = 30,
    int offset = 0,
  }) async {
    final text = search?.trim();
    final data = await _client.rpc(
      'admin_live_users',
      params: {
        'p_search': text == null || text.isEmpty ? null : text,
        'p_filter': filter,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return AdminLiveUsersPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// permission: 'granted' | 'revoked' | 'default'
  Future<AdminLiveChange> setUserPermission(String userId, String permission, {String? note}) async {
    final data = await _client.rpc(
      'admin_set_user_live_permission',
      params: {'p_user_id': userId, 'p_permission': permission, 'p_note': _clean(note)},
    );
    final json = data is Map ? data : const {};
    return AdminLiveChange(
      closed: _int(json['closed']),
      effective: LiveShopAccess.fromCode(json['effective']),
    );
  }

  /// Kullanıcı yayını modu: 'open' | 'invite' | 'off'. [closeRunning]: yeni
  /// modda izinsiz kalan süren kullanıcı yayınlarını da kapat.
  Future<AdminLiveChange> setUserMode(String mode, {bool closeRunning = false}) async {
    final data = await _client.rpc(
      'admin_set_user_live_mode',
      params: {'p_mode': mode, 'p_close_running': closeRunning},
    );
    final json = data is Map ? data : const {};
    return AdminLiveChange(closed: _int(json['closed']));
  }

  /// Yayını kapatır; hazırlıktaysa kayıt silinir ('discarded').
  Future<String> endSession(String sessionId, {String? note}) async {
    final data = await _client.rpc(
      'admin_end_live_session',
      params: {'p_session_id': sessionId, 'p_note': _clean(note)},
    );
    return (data is Map ? data['status']?.toString() : null) ?? 'ended';
  }

  /// permission: 'granted' | 'revoked' | 'default'
  Future<AdminLiveChange> setShopPermission(String shopId, String permission, {String? note}) async {
    final data = await _client.rpc(
      'admin_set_shop_live_permission',
      params: {'p_shop_id': shopId, 'p_permission': permission, 'p_note': _clean(note)},
    );
    final json = data is Map ? data : const {};
    return AdminLiveChange(
      closed: _int(json['closed']),
      effective: LiveShopAccess.fromCode(json['effective']),
    );
  }

  /// null = değiştirme. [closeRunning]: yeni ayarda izinsiz kalan süren
  /// yayınları da kapat.
  Future<AdminLiveChange> setSettings({bool? enabled, String? access, bool closeRunning = false}) async {
    final data = await _client.rpc(
      'admin_set_live_settings',
      params: {'p_enabled': enabled, 'p_access': access, 'p_close_running': closeRunning},
    );
    final json = data is Map ? data : const {};
    return AdminLiveChange(closed: _int(json['closed']), settings: AdminLiveSettings.fromJson(json));
  }

  /// Bildirim / ana sayfa kartı / geçmiş ayarları ve 30 günlük sayaçlar.
  Future<AdminLiveOptions> fetchOptions() async {
    final data = await _client.rpc('admin_live_options');
    return AdminLiveOptions.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Yalnız verilen anahtarlar yazılır (ör. `{'notify_enabled': false}`);
  /// sunucu sayıları sınırlarına sıkıştırır. Güncel ayarlar döner.
  Future<AdminLiveOptions> saveOptions(Map<String, Object> changes) async {
    final data = await _client.rpc('admin_set_live_options', params: {'p_options': changes});
    return AdminLiveOptions.fromJson(Map<String, dynamic>.from(data as Map));
  }

  static String? _clean(String? note) {
    final text = note?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String errorMessage(Object error) {
    if (error is PostgrestException) {
      switch (error.hint) {
        case 'LIVE_ENDED':
          return 'Bu yayın zaten sona ermiş.';
        case 'LIVE_NOT_FOUND':
          return 'Yayın bulunamadı (satıcı kapatmış olabilir).';
        case 'LIVE_SHOP_NOT_FOUND':
          return 'Mağaza bulunamadı.';
        case 'LIVE_USER_NOT_FOUND':
          return 'Kullanıcı bulunamadı.';
        case 'LIVE_PERMISSION_INVALID':
        case 'LIVE_ACCESS_INVALID':
          return 'Geçersiz seçim.';
        case 'LIVE_OPTIONS_INVALID':
          return 'Geçersiz ayar değeri.';
        case 'MOD_CATEGORY_FORBIDDEN':
          return 'Bu mağazanın kategorisi moderasyon alanında değil.';
      }
      if (error.code == '42501') return 'Bu işlem için yönetici yetkisi gerekli.';
      return error.message;
    }
    return 'İşlem tamamlanamadı: $error';
  }
}
