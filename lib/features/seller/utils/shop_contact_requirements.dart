/// Satıcı zorunlu alanları: telefon + haritadan konum (Görev 3.7).
///
/// Sunucudaki kural (`shop_phone_is_valid`, `guard_shop_contact_info`) ile
/// aynıdır: telefon 10–13 rakam (5xx…, 05xx…, +90 5xx…, sabit hat). Yeni
/// mağaza bu ikisi olmadan açılamaz; girilmiş bilgi silinemez. Eksik olanlar
/// satıcı panelinde kalıcı bir şeritle tamamlatılır.
enum ShopMissingInfo { phone, location }

class ShopContactRequirements {
  ShopContactRequirements._();

  static int _digits(String? value) => (value ?? '').replaceAll(RegExp(r'\D'), '').length;

  static bool isValidPhone(String? phone) {
    final n = _digits(phone);
    return n >= 10 && n <= 13;
  }

  /// Form doğrulayıcı: boşsa "gerekli", biçim yanlışsa örnekli uyarı.
  static String? phoneError(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Telefon gerekli';
    if (!isValidPhone(value)) return 'Geçerli bir telefon girin (örn. 0532 123 45 67)';
    return null;
  }

  static List<ShopMissingInfo> missing({String? phone, Object? latitude, Object? longitude}) => [
    if (!isValidPhone(phone)) ShopMissingInfo.phone,
    if (latitude == null || longitude == null) ShopMissingInfo.location,
  ];

  /// `shops` satırından (phone, latitude, longitude). Satır yoksa eksik sayılmaz.
  static List<ShopMissingInfo> missingFromShop(Map<String, dynamic>? shop) {
    if (shop == null) return const [];
    return missing(
      phone: shop['phone']?.toString(),
      latitude: shop['latitude'],
      longitude: shop['longitude'],
    );
  }

  static String label(ShopMissingInfo item) => switch (item) {
    ShopMissingInfo.phone => 'telefon numarası',
    ShopMissingInfo.location => 'haritadan mağaza konumu',
  };

  /// Sunucu tetikleyicisinin ipucu (HINT) → kullanıcı mesajı; tanımsızsa null.
  static String? messageForHint(String? hint) => switch (hint) {
    'SHOP_PHONE_REQUIRED' => 'Mağaza telefonu zorunlu (en az 10 haneli numara).',
    'SHOP_LOCATION_REQUIRED' => 'Mağaza konumunu haritadan seçmelisin.',
    'SHOP_LOCATION_INVALID' => 'Seçilen konum geçersiz; haritadan yeniden seç.',
    _ => null,
  };

  /// Şerit metni: neyin eksik olduğu ve neden gerektiği.
  static String bannerText(List<ShopMissingInfo> missing) {
    if (missing.isEmpty) return '';
    final items = missing.map(label).toList();
    final what = items.length == 1 ? items.first : '${items.first} ve ${items.last}';
    return 'Mağazanın $what eksik. Müşterilerin sana ulaşabilmesi ve kuryenin '
        'mağazanı bulabilmesi için bu bilgiler zorunlu.';
  }
}
