// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../models/ilan_models.dart';

class IlanUi {
  const IlanUi._();

  static Color color(String hex) {
    final normalized = hex.replaceFirst('#', '');
    return Color(int.tryParse('FF$normalized', radix: 16) ?? 0xFF6D28D9);
  }

  static IconData icon(String name) => switch (name) {
    'travel_explore' => Icons.travel_explore_rounded,
    'sell' => Icons.sell_rounded,
    'key' => Icons.key_rounded,
    'handyman' => Icons.handyman_rounded,
    'pets' => Icons.pets_rounded,
    'home' => Icons.home_rounded,
    'directions_car' => Icons.directions_car_rounded,
    'devices' => Icons.devices_rounded,
    'work' => Icons.work_rounded,
    'land' => Icons.landscape_rounded,
    'apartment' => Icons.apartment_rounded,
    'furniture' => Icons.chair_rounded,
    'baby' => Icons.child_care_rounded,
    'sports' => Icons.sports_soccer_rounded,
    'book' => Icons.menu_book_rounded,
    _ => Icons.category_rounded,
  };

  /// Kategori simgesi seçici (admin) için (anahtar, etiket) kataloğu.
  static const List<(String key, String label)> iconCatalog = [
    ('category', 'Genel'),
    ('home', 'Ev'),
    ('apartment', 'Daire'),
    ('land', 'Arsa'),
    ('directions_car', 'Araba'),
    ('key', 'Kiralık'),
    ('sell', 'Satılık'),
    ('handyman', 'Hizmet'),
    ('work', 'İş'),
    ('devices', 'Elektronik'),
    ('furniture', 'Mobilya'),
    ('pets', 'Evcil Hayvan'),
    ('baby', 'Bebek/Çocuk'),
    ('sports', 'Spor'),
    ('book', 'Kitap/Hobi'),
    ('travel_explore', 'Kayıp'),
  ];

  static String price(Ilan ilan) {
    if (!ilan.hasPrice) return 'Fiyat bilgisi yok';
    final symbol = switch (ilan.currency) {
      'USD' => r'$',
      'EUR' => '€',
      _ => '₺',
    };
    return '${NumberFormat.decimalPattern('tr_TR').format(ilan.price)} $symbol${ilan.isNegotiable ? ' • Pazarlık payı var' : ''}';
  }

  static String formatFee(double fee) => fee <= 0
      ? 'Ücretsiz'
      : '${NumberFormat.decimalPattern('tr_TR').format(fee)} ₺';

  static const String kaporaWarning =
      'Güvenliğiniz için kapora göndermeyin, hassas kişisel bilgilerinizi paylaşmayın.';

  static String? remainingLabel(Ilan ilan) {
    if (ilan.status != IlanStatus.published || ilan.expiresAt == null) {
      return null;
    }
    final remaining = ilan.expiresAt!.difference(DateTime.now());
    if (remaining.isNegative) return 'Süresi doldu';
    final days = remaining.inDays;
    if (days <= 0) return 'Bugün son gün';
    if (days == 1) return 'Son 1 gün';
    return '$days gün kaldı';
  }

  static String status(IlanStatus status) => switch (status) {
    IlanStatus.draft => 'Taslak',
    IlanStatus.pending => 'Onay Bekliyor',
    IlanStatus.published => 'Yayında',
    IlanStatus.rejected => 'Reddedildi',
    IlanStatus.sold => 'Satıldı',
    IlanStatus.rented => 'Kiralandı',
    IlanStatus.found => 'Bulundu',
    IlanStatus.expired => 'Süresi Doldu',
    IlanStatus.archived => 'Arşivlendi',
  };

  static Color statusColor(IlanStatus status) => switch (status) {
    IlanStatus.published => AppTheme.success,
    IlanStatus.pending => AppTheme.warning,
    IlanStatus.rejected => AppTheme.error,
    IlanStatus.sold || IlanStatus.rented || IlanStatus.found => AppTheme.info,
    _ => AppTheme.gray400,
  };

  static String friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Aktif ilan limitine'))
      return 'Aktif ilan limitinize ulaştınız.';
    if (text.contains('Kullanıcı ilan paylaşımı'))
      return 'Yeni ilan paylaşımı yönetici tarafından kapatıldı.';
    if (text.contains('İlan sistemi şu anda kapalı'))
      return 'İlanlar şu anda kullanıma kapalı.';
    if (text.contains('AuthException') || text.contains('giriş yapmalısınız'))
      return 'Bu işlem için giriş yapmalısınız.';
    if (text.contains('İlan silinemedi'))
      return 'Bu ilanı silme yetkiniz yok.';
    if (text.contains('Yetersiz bakiye'))
      return 'Bu kategoride ilan yayınlamak için bakiyeniz yetersiz.';
    return 'İşlem tamamlanamadı. Lütfen bilgileri kontrol edip yeniden deneyin.';
  }
}
