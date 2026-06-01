import 'package:flutter/material.dart';

/// Başarım türleri
enum AchievementType {
  firstOrder,      // İlk sipariş
  loyalCustomer,   // Sadık müşteri (10 sipariş)
  superCustomer,   // Süper müşteri (50 sipariş)
  reviewer,        // İlk değerlendirme
  topReviewer,     // 10 değerlendirme
  socializer,      // İlk paylaşım
  popular,         // 100 takipçi
  earlyBird,       // İlk kayıt olanlardan
  weeklyStreak,    // 7 gün üst üste giriş
  monthlyStreak,   // 30 gün üst üste giriş
  bigSpender,      // 1000₺ harcama
  explorer,        // 10 farklı mağazadan alışveriş
}

/// Başarım modeli
class Achievement {
  final String id;
  final AchievementType type;
  final String title;
  final String description;
  final String iconName;
  final int requiredCount;    // Gereken sayı (örn: 10 sipariş)
  final int currentCount;      // Mevcut ilerleme
  final int xpReward;          // XP ödülü
  final DateTime? unlockedAt;  // Açıldığı tarih
  final bool isUnlocked;

  Achievement({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.iconName,
    required this.requiredCount,
    this.currentCount = 0,
    this.xpReward = 0,
    this.unlockedAt,
    this.isUnlocked = false,
  });

  /// İlerleme yüzdesi (0.0 - 1.0)
  double get progress {
    if (requiredCount == 0) return 1.0;
    return (currentCount / requiredCount).clamp(0.0, 1.0);
  }

  /// İlerleme yüzdesi (0-100)
  int get progressPercentage => (progress * 100).round();

  /// Henüz açılmadıysa sonraki kilidin ne kadar kaldığı
  String get remainingText {
    if (isUnlocked) return 'Açıldı!';
    final remaining = requiredCount - currentCount;
    if (remaining <= 0) return 'Hazır!';
    return '$remaining kaldı';
  }

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String,
      type: AchievementType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AchievementType.firstOrder,
      ),
      title: json['title'] as String,
      description: json['description'] as String,
      iconName: json['icon_name'] as String,
      requiredCount: json['required_count'] as int? ?? 1,
      currentCount: json['current_count'] as int? ?? 0,
      xpReward: json['xp_reward'] as int? ?? 0,
      unlockedAt: json['unlocked_at'] != null
          ? DateTime.parse(json['unlocked_at'] as String)
          : null,
      isUnlocked: json['is_unlocked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'description': description,
      'icon_name': iconName,
      'required_count': requiredCount,
      'current_count': currentCount,
      'xp_reward': xpReward,
      'unlocked_at': unlockedAt?.toIso8601String(),
      'is_unlocked': isUnlocked,
    };
  }

  Achievement copyWith({
    String? id,
    AchievementType? type,
    String? title,
    String? description,
    String? iconName,
    int? requiredCount,
    int? currentCount,
    int? xpReward,
    DateTime? unlockedAt,
    bool? isUnlocked,
  }) {
    return Achievement(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      requiredCount: requiredCount ?? this.requiredCount,
      currentCount: currentCount ?? this.currentCount,
      xpReward: xpReward ?? this.xpReward,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }
}

/// Kullanıcı rozetleri ve başarımları için model
class UserAchievements {
  final String userId;
  final int totalXp;                // Toplam XP
  final int level;                   // Seviye (XP'ye göre hesaplanır)
  final int streakDays;              // Üst üste giriş günü
  final DateTime? lastLoginDate;     // Son giriş tarihi
  final List<Achievement> achievements;
  final Map<String, int> stats;      // İstatistikler (orders, reviews, etc.)

  UserAchievements({
    required this.userId,
    this.totalXp = 0,
    this.level = 1,
    this.streakDays = 0,
    this.lastLoginDate,
    this.achievements = const [],
    this.stats = const {},
  });

  /// Seviyeye göre XP gereksinimi
  static int xpRequiredForLevel(int level) {
    // Her seviye için 100 * seviye ^ 1.5 XP gerekir
    return (100 * level * 1.5).round();
  }

  /// Sonraki seviyeye kadar gereken XP
  int get xpToNextLevel => xpRequiredForLevel(level + 1) - totalXp;

  /// Mevcut seviyedeki ilerleme
  double get levelProgress {
    final currentLevelXp = xpRequiredForLevel(level);
    final nextLevelXp = xpRequiredForLevel(level + 1);
    return ((totalXp - currentLevelXp) / (nextLevelXp - currentLevelXp)).clamp(0.0, 1.0);
  }

  /// Açılmış başarımlar
  List<Achievement> get unlockedAchievements =>
      achievements.where((a) => a.isUnlocked).toList();

  /// Yakında açılacak başarımlar
  List<Achievement> get upcomingAchievements =>
      achievements.where((a) => !a.isUnlocked && a.currentCount > 0)
        .toList()
        ..sort((a, b) => b.progress.compareTo(a.progress));

  factory UserAchievements.fromJson(Map<String, dynamic> json) {
    return UserAchievements(
      userId: json['user_id'] as String,
      totalXp: json['total_xp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      streakDays: json['streak_days'] as int? ?? 0,
      lastLoginDate: json['last_login_date'] != null
          ? DateTime.parse(json['last_login_date'] as String)
          : null,
      achievements: (json['achievements'] as List<dynamic>?)
          ?.map((a) => Achievement.fromJson(a as Map<String, dynamic>))
          .toList() ?? [],
      stats: Map<String, int>.from(json['stats'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'total_xp': totalXp,
      'level': level,
      'streak_days': streakDays,
      'last_login_date': lastLoginDate?.toIso8601String(),
      'achievements': achievements.map((a) => a.toJson()).toList(),
      'stats': stats,
    };
  }
}

/// Başarım ikonları yardımcı fonksiyonu
class AchievementIcons {
  static IconData getIcon(String iconName) {
    switch (iconName) {
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'star':
        return Icons.star;
      case 'emoji_events':
        return Icons.emoji_events;
      case 'workspace_premium':
        return Icons.workspace_premium;
      case 'military_tech':
        return Icons.military_tech;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'diamond':
        return Icons.diamond;
      case 'explore':
        return Icons.explore;
      case 'celebration':
        return Icons.celebration;
      case 'bolt':
        return Icons.bolt;
      case 'restaurant':
        return Icons.restaurant;
      case 'store':
        return Icons.store;
      default:
        return Icons.emoji_events;
    }
  }

  static Color getColor(AchievementType type) {
    switch (type) {
      case AchievementType.firstOrder:
        return Colors.green;
      case AchievementType.loyalCustomer:
        return Colors.blue;
      case AchievementType.superCustomer:
        return Colors.purple;
      case AchievementType.reviewer:
        return Colors.orange;
      case AchievementType.topReviewer:
        return Colors.deepOrange;
      case AchievementType.socializer:
        return Colors.pink;
      case AchievementType.popular:
        return Colors.red;
      case AchievementType.earlyBird:
        return Colors.amber;
      case AchievementType.weeklyStreak:
        return Colors.teal;
      case AchievementType.monthlyStreak:
        return Colors.indigo;
      case AchievementType.bigSpender:
        return Colors.brown;
      case AchievementType.explorer:
        return Colors.cyan;
    }
  }
}