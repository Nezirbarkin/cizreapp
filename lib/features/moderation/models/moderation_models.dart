import 'package:flutter/material.dart';

/// Moderatör yetki alanları (Görev 4.6). Anahtarlar sunucudaki
/// `moderators.scopes` CHECK listesiyle aynıdır.
enum ModerationScope {
  reports(
    'reports',
    'Şikayetler',
    'Kullanıcı ve gönderi şikayetlerini görme ve sonuçlandırma',
    Icons.report_outlined,
  ),
  content(
    'content',
    'İçerik',
    'Gönderi gizleme/açma, yorum silme, gizli içeriği görme',
    Icons.article_outlined,
  ),
  ilanlar(
    'ilanlar',
    'İlanlar',
    'Onay bekleyen ilanları onaylama ya da reddetme',
    Icons.campaign_outlined,
  ),
  live(
    'live',
    'Canlı yayınlar',
    'Canlı yayınları izleme ve kapatma',
    Icons.live_tv_outlined,
  );

  const ModerationScope(this.key, this.label, this.description, this.icon);

  final String key;
  final String label;
  final String description;
  final IconData icon;

  static ModerationScope? fromKey(Object? key) {
    for (final scope in values) {
      if (scope.key == key) return scope;
    }
    return null;
  }
}

/// Moderatöre atanabilen kategori: ilan kategorisi ('ilanlar' kapsamı) ya da
/// mağaza kategorisi ('live' kapsamı).
class ModCategory {
  const ModCategory({required this.id, required this.name, this.isActive = true});

  final String id;
  final String name;
  final bool isActive;

  static ModCategory? tryFromJson(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    return ModCategory(
      id: raw['id'].toString(),
      name: _text(raw['name']) ?? 'Kategori',
      isActive: raw['is_active'] != false,
    );
  }

  /// null = tüm kategoriler; liste = yalnız bunlar.
  static List<ModCategory>? listFromJson(Object? raw) =>
      raw is List ? raw.map(tryFromJson).whereType<ModCategory>().toList() : null;

  @override
  bool operator ==(Object other) => other is ModCategory && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// "Emlak, Vasıta" — null (tümü) için null.
String? modCategoryNames(List<ModCategory>? categories) =>
    categories?.map((c) => c.name).join(', ');

/// Oturumdaki kişinin moderasyon yetkisi (`my_moderation()`).
class ModerationAccess {
  const ModerationAccess({
    this.isAdmin = false,
    this.scopes = const {},
    this.ilanCategories,
    this.shopCategories,
  });

  static const none = ModerationAccess();

  final bool isAdmin;
  final Set<ModerationScope> scopes;

  /// Yönetici atadıysa yalnız bu ilan kategorileri (null = hepsi).
  final List<ModCategory>? ilanCategories;

  /// Yönetici atadıysa yalnız bu mağaza kategorileri (null = hepsi).
  final List<ModCategory>? shopCategories;

  bool get hasAny => scopes.isNotEmpty;

  bool can(ModerationScope scope) => scopes.contains(scope);

  /// Kapsamın kategori sınırı (null = sınırsız ya da kapsam kategorisiz).
  List<ModCategory>? categoriesFor(ModerationScope scope) => switch (scope) {
    ModerationScope.ilanlar => ilanCategories,
    ModerationScope.live => shopCategories,
    _ => null,
  };

  /// "Şikayetler · İçerik" (enum sırasıyla).
  String get summary => [
    for (final scope in ModerationScope.values)
      if (scopes.contains(scope)) scope.label,
  ].join(' · ');

  factory ModerationAccess.fromJson(Object? raw) {
    final json = raw is Map ? raw : const {};
    final list = json['scopes'];
    return ModerationAccess(
      isAdmin: json['is_admin'] == true,
      scopes: {
        if (list is List)
          for (final key in list)
            if (ModerationScope.fromKey(key) case final scope?) scope,
      },
      ilanCategories: ModCategory.listFromJson(json['ilan_categories']),
      shopCategories: ModCategory.listFromJson(json['shop_categories']),
    );
  }

  static bool _sameCategories(List<ModCategory>? a, List<ModCategory>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is ModerationAccess &&
      other.isAdmin == isAdmin &&
      other.scopes.length == scopes.length &&
      other.scopes.containsAll(scopes) &&
      _sameCategories(other.ilanCategories, ilanCategories) &&
      _sameCategories(other.shopCategories, shopCategories);

  @override
  int get hashCode => Object.hash(
    isAdmin,
    Object.hashAllUnordered(scopes),
    ilanCategories == null ? null : Object.hashAll(ilanCategories!),
    shopCategories == null ? null : Object.hashAll(shopCategories!),
  );
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

/// Listelerde görünen kişi (şikayet eden, yazar, ilan sahibi…).
class ModPerson {
  const ModPerson({required this.id, required this.name, this.username, this.avatarUrl, this.status});

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? status;

  static ModPerson? tryFromJson(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    return ModPerson(
      id: raw['id'].toString(),
      name: _text(raw['name']) ?? _text(raw['username']) ?? 'Kullanıcı',
      username: _text(raw['username']),
      avatarUrl: _text(raw['avatar_url']),
      status: _text(raw['status']),
    );
  }
}

/// Şikayet nedeni anahtarı → Türkçe etiket (uygulamadaki şikayet formları).
String reportReasonLabel(String? reason) => switch (reason) {
  'spam' => 'Spam',
  'harassment' => 'Taciz / zorbalık',
  'inappropriate' || 'inappropriate_content' => 'Uygunsuz içerik',
  'fake' || 'impersonation' => 'Sahte hesap / taklit',
  'violence' => 'Şiddet',
  'scam' => 'Dolandırıcılık',
  'copyright' => 'Telif hakkı',
  'other' || null => 'Diğer',
  _ => reason,
};

/// Gönderi ya da kullanıcı şikayeti (`mod_reports`).
class ModReport {
  const ModReport({
    required this.kind,
    required this.id,
    required this.status,
    required this.createdAt,
    this.reason,
    this.description,
    this.adminResponse,
    this.images = const [],
    this.reporter,
    this.postId,
    this.postContent,
    this.postImageUrl,
    this.postActive = true,
    this.postAuthorName,
    this.targetUser,
  });

  /// 'post' | 'user'
  final String kind;
  final String id;
  final String status;
  final DateTime createdAt;
  final String? reason;
  final String? description;
  final String? adminResponse;
  final List<String> images;
  final ModPerson? reporter;
  final String? postId;
  final String? postContent;
  final String? postImageUrl;
  final bool postActive;
  final String? postAuthorName;
  final ModPerson? targetUser;

  bool get isPost => kind == 'post';

  bool get isOpen => status == 'pending' || status == 'reviewing';

  String get statusLabel => switch (status) {
    'pending' => 'Bekliyor',
    'reviewing' => 'İnceleniyor',
    'resolved' => 'Sonuçlandı',
    'rejected' => 'Reddedildi',
    _ => status,
  };

  factory ModReport.fromJson(Map<String, dynamic> json) {
    final post = json['post'];
    final images = json['images'];
    return ModReport(
      kind: json['kind'] == 'user' ? 'user' : 'post',
      id: json['id'].toString(),
      status: _text(json['status']) ?? 'pending',
      createdAt: _time(json['created_at']) ?? DateTime.now(),
      reason: _text(json['reason']),
      description: _text(json['description']),
      adminResponse: _text(json['admin_response']),
      images: images is List ? [for (final i in images) if (_text(i) case final url?) url] : const [],
      reporter: ModPerson.tryFromJson(json['reporter']),
      postId: post is Map ? _text(post['id']) : null,
      postContent: post is Map ? _text(post['content']) : null,
      postImageUrl: post is Map ? _text(post['image_url']) : null,
      postActive: post is Map ? post['is_active'] != false : true,
      postAuthorName: post is Map ? _text(post['author_name']) : null,
      targetUser: ModPerson.tryFromJson(json['user']),
    );
  }
}

class ModReportsPage {
  const ModReportsPage({this.rows = const [], this.total = 0, this.open = 0, this.postOpen = 0, this.userOpen = 0});

  final List<ModReport> rows;
  final int total;
  final int open;
  final int postOpen;
  final int userOpen;

  factory ModReportsPage.fromJson(Map<String, dynamic> json) {
    final counts = (json['counts'] as Map?) ?? const {};
    return ModReportsPage(
      rows: [
        for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
          ModReport.fromJson(Map<String, dynamic>.from(raw)),
      ],
      total: _int(json['total']),
      open: _int(counts['open']),
      postOpen: _int(counts['post_open']),
      userOpen: _int(counts['user_open']),
    );
  }
}

/// Moderasyon listesindeki gönderi (`mod_posts`).
class ModPost {
  const ModPost({
    required this.id,
    required this.createdAt,
    this.content,
    this.imageUrl,
    this.isActive = true,
    this.likesCount = 0,
    this.openReports = 0,
    this.author,
  });

  final String id;
  final DateTime createdAt;
  final String? content;
  final String? imageUrl;
  final bool isActive;
  final int likesCount;
  final int openReports;
  final ModPerson? author;

  factory ModPost.fromJson(Map<String, dynamic> json) => ModPost(
    id: json['id'].toString(),
    createdAt: _time(json['created_at']) ?? DateTime.now(),
    content: _text(json['content']),
    imageUrl: _text(json['image_url']),
    isActive: json['is_active'] != false,
    likesCount: _int(json['likes_count']),
    openReports: _int(json['open_reports']),
    author: ModPerson.tryFromJson(json['author']),
  );

  ModPost copyWith({bool? isActive}) => ModPost(
    id: id,
    createdAt: createdAt,
    content: content,
    imageUrl: imageUrl,
    isActive: isActive ?? this.isActive,
    likesCount: likesCount,
    openReports: openReports,
    author: author,
  );
}

class ModPostsPage {
  const ModPostsPage({this.rows = const [], this.total = 0});

  final List<ModPost> rows;
  final int total;

  factory ModPostsPage.fromJson(Map<String, dynamic> json) => ModPostsPage(
    rows: [
      for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
        ModPost.fromJson(Map<String, dynamic>.from(raw)),
    ],
    total: _int(json['total']),
  );
}

/// Onay bekleyen ilan (`mod_pending_ilanlar`).
class ModIlan {
  const ModIlan({
    required this.id,
    required this.title,
    required this.createdAt,
    this.description,
    this.price,
    this.currency,
    this.city,
    this.district,
    this.coverImageUrl,
    this.categoryName,
    this.paidFee = 0,
    this.owner,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final String? description;
  final double? price;
  final String? currency;
  final String? city;
  final String? district;
  final String? coverImageUrl;
  final String? categoryName;
  final double paidFee;
  final ModPerson? owner;

  String get location => [if (district != null) district!, if (city != null) city!].join(', ');

  factory ModIlan.fromJson(Map<String, dynamic> json) {
    double? money(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return ModIlan(
      id: json['id'].toString(),
      title: _text(json['title']) ?? 'İlan',
      createdAt: _time(json['created_at']) ?? DateTime.now(),
      description: _text(json['description']),
      price: money(json['price']),
      currency: _text(json['currency']),
      city: _text(json['city']),
      district: _text(json['district']),
      coverImageUrl: _text(json['cover_image_url']),
      categoryName: _text(json['category_name']),
      paidFee: money(json['paid_fee']) ?? 0,
      owner: ModPerson.tryFromJson(json['owner']),
    );
  }
}

class ModIlansPage {
  const ModIlansPage({this.rows = const [], this.total = 0});

  final List<ModIlan> rows;
  final int total;

  factory ModIlansPage.fromJson(Map<String, dynamic> json) => ModIlansPage(
    rows: [
      for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
        ModIlan.fromJson(Map<String, dynamic>.from(raw)),
    ],
    total: _int(json['total']),
  );
}
