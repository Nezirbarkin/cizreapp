import 'package:flutter/material.dart';

/// AI Hızlı Şablon Modeli
/// Admin panelden yönetilebilir şablonlar
/// Görsel thumbnail desteği eklendi
class AIQuickPrompt {
  final String id;
  final String title;
  final String prompt;
  final String icon;
  final String color;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // YENİ: Görsel ve kategori desteği
  final String? imageUrl;
  final String? category;
  final String? thumbnailColor;

  AIQuickPrompt({
    required this.id,
    required this.title,
    required this.prompt,
    this.icon = 'lightbulb_outline',
    this.color = '#FFC107',
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.imageUrl,
    this.category,
    this.thumbnailColor,
  });

  factory AIQuickPrompt.fromMap(Map<String, dynamic> map) {
    return AIQuickPrompt(
      id: map['id'] as String,
      title: map['title'] as String,
      prompt: map['prompt'] as String,
      icon: (map['icon'] as String?) ?? 'lightbulb_outline',
      color: (map['color'] as String?) ?? '#FFC107',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isActive: (map['is_active'] as bool?) ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      // YENİ ALANLAR:
      imageUrl: map['image_url'] as String?,
      category: (map['category'] as String?) ?? 'general',
      thumbnailColor: (map['thumbnail_color'] as String?) ?? '#7B2CBF',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'prompt': prompt,
      'icon': icon,
      'color': color,
      'sort_order': sortOrder,
      'is_active': isActive,
      // YENİ ALANLAR:
      'image_url': imageUrl,
      'category': category ?? 'general',
      'thumbnail_color': thumbnailColor ?? '#7B2CBF',
    };
  }

  AIQuickPrompt copyWith({
    String? id,
    String? title,
    String? prompt,
    String? icon,
    String? color,
    int? sortOrder,
    bool? isActive,
    String? imageUrl,
    String? category,
    String? thumbnailColor,
  }) {
    return AIQuickPrompt(
      id: id ?? this.id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      thumbnailColor: thumbnailColor ?? this.thumbnailColor,
    );
  }

  /// Görsel var mı kontrolü
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  
  /// Kategori ikonu
  IconData get categoryIcon {
    switch (category) {
      case 'shopping':
        return Icons.shopping_bag_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'creative':
        return Icons.brush_rounded;
      case 'productivity':
        return Icons.task_alt_rounded;
      case 'social':
        return Icons.people_rounded;
      case 'travel':
        return Icons.flight_rounded;
      default:
        return Icons.lightbulb_outline_rounded;
    }
  }

  /// Icon name'den Flutter IconData'ya dönüştür
  static IconData? getIconData(String iconName) {
    switch (iconName) {
      case 'shopping_cart':
        return const IconData(0xe8cc, fontFamily: 'MaterialIcons');
      case 'restaurant':
        return const IconData(0xe56c, fontFamily: 'MaterialIcons');
      case 'weekend':
        return const IconData(0xea59, fontFamily: 'MaterialIcons');
      case 'edit':
        return const IconData(0xe3c9, fontFamily: 'MaterialIcons');
      case 'auto_stories':
        return const IconData(0xe16d, fontFamily: 'MaterialIcons');
      case 'today':
        return const IconData(0xe8b4, fontFamily: 'MaterialIcons');
      case 'lightbulb_outline':
      default:
        return const IconData(0xe8f2, fontFamily: 'MaterialIcons');
    }
  }

  /// Color string'den Color'a dönüştür
  static int parseColor(String colorStr) {
    String hex = colorStr.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return int.parse(hex, radix: 16);
  }

  static Color getColorFromString(String colorStr) {
    return Color(parseColor(colorStr));
  }
  
  /// Renkler sabit listesi (Admin panel için)
  static const List<Map<String, String>> colorPresets = [
    {'name': 'Mor', 'color': '#7B2CBF'},
    {'name': 'Mavi', 'color': '#3B82F6'},
    {'name': 'Yeşil', 'color': '#22C55E'},
    {'name': 'Turuncu', 'color': '#F97316'},
    {'name': 'Kırmızı', 'color': '#EF4444'},
    {'name': 'Sarı', 'color': '#EAB308'},
    {'name': 'Pembe', 'color': '#EC4899'},
    {'name': 'Siyah', 'color': '#1F2937'},
  ];
  
  /// Kategoriler sabit listesi (Admin panel için)
  static const List<Map<String, String>> categoryPresets = [
    {'name': 'Genel', 'value': 'general', 'icon': 'lightbulb_outline'},
    {'name': 'Alışveriş', 'value': 'shopping', 'icon': 'shopping_cart'},
    {'name': 'Yemek', 'value': 'food', 'icon': 'restaurant'},
    {'name': 'Yaratıcı', 'value': 'creative', 'icon': 'edit'},
    {'name': 'Verimlilik', 'value': 'productivity', 'icon': 'task_alt'},
    {'name': 'Sosyal', 'value': 'social', 'icon': 'people'},
    {'name': 'Seyahat', 'value': 'travel', 'icon': 'flight'},
  ];
}
