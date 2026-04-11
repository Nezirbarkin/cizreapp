class UserReport {
  final String id;
  final String reporterId;
  final String reportedUserId;
  final String reason;
  final String? description;
  final List<String> images;  // Şikayete eklenen görsel URL'leri
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserReport({
    required this.id,
    required this.reporterId,
    required this.reportedUserId,
    required this.reason,
    this.description,
    this.images = const [],
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserReport.fromJson(Map<String, dynamic> json) {
    return UserReport(
      id: json['id'] as String,
      reporterId: json['reporter_id'] as String,
      reportedUserId: json['reported_user_id'] as String,
      reason: json['reason'] as String,
      description: json['description'] as String?,
      images: json['images'] != null
          ? List<String>.from(json['images'] as List)
          : const [],
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reporter_id': reporterId,
      'reported_user_id': reportedUserId,
      'reason': reason,
      'description': description,
      'images': images,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Şikayet türlerini listele
  static const Map<String, String> reportReasons = {
    'spam': 'Spam/Reklam',
    'harassment': 'Taciz/Rahatsızlık',
    'fake': 'Sahte Hesap',
    'inappropriate': 'Uygunsuz İçerik',
    'hate_speech': 'Nefret Söylemi',
    'violence': 'Şiddet/Tehdit',
    'impersonation': 'Kimliğe Bürünme',
    'scam': 'Dolandırıcılık',
    'other': 'Diğer',
  };

  // Durum türlerini listele
  static const Map<String, String> reportStatuses = {
    'pending': 'Beklemede',
    'reviewing': 'İnceleniyor',
    'resolved': 'Çözüldü',
    'rejected': 'Reddedildi',
  };

  // Şikayet nedeninin görünen adını al
  String get reasonDisplayName => reportReasons[reason] ?? reason;

  // Şikayet durumunun görünen adını al
  String get statusDisplayName => reportStatuses[status] ?? status;

  // Şikayetin aktif olup olmadığını kontrol et
  bool get isActive => status == 'pending' || status == 'reviewing';

  // Şikayetin çözülmüş olup olmadığını kontrol et
  bool get isResolved => status == 'resolved';

  // Şikayetin reddedilmiş olup olmadığını kontrol et
  bool get isRejected => status == 'rejected';

  UserReport copyWith({
    String? id,
    String? reporterId,
    String? reportedUserId,
    String? reason,
    String? description,
    List<String>? images,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserReport(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      reportedUserId: reportedUserId ?? this.reportedUserId,
      reason: reason ?? this.reason,
      description: description ?? this.description,
      images: images ?? this.images,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
