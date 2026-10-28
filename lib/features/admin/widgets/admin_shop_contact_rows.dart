import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Admin ekranlarında satıcıya ulaşma bilgisi (telefon, e-posta, adres,
/// konum, IBAN).
///
/// Satıcı telefonu `shops.phone`'da tutulur (dükkan açarken zorunlu, bkz.
/// `guard_shop_contact_info`); sahibin `profiles.phone`'u neredeyse hep boş.
/// Eskiden admin ekranları yalnız profil telefonunu gösterdiği için satıcı
/// telefonu hiçbir yerde görünmüyordu.
class AdminShopContact {
  const AdminShopContact({
    this.ownerName,
    this.ownerEmail,
    this.phone,
    this.phoneFromProfile = false,
    this.shopEmail,
    this.address,
    this.latitude,
    this.longitude,
    this.iban,
    this.bankName,
    this.accountHolder,
  });

  /// [shop] bir `shops` satırı ya da `admin_shops_page` satırıdır. [owner]
  /// verilmezse `shop['profiles']` kullanılır (admin_shops_page biçimi).
  factory AdminShopContact.fromShop(
    Map<String, dynamic> shop, {
    Map<String, dynamic>? owner,
  }) {
    final rawProfile = shop['profiles'];
    final profile = owner ??
        (rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : null);
    final shopPhone = _clean(shop['phone']);
    final ownerPhone = _clean(profile?['phone']);
    return AdminShopContact(
      ownerName: _clean(profile?['full_name']) ?? _clean(profile?['username']),
      ownerEmail: _clean(profile?['email']),
      phone: shopPhone ?? ownerPhone,
      phoneFromProfile: shopPhone == null && ownerPhone != null,
      shopEmail: _clean(shop['email']),
      address: _clean(shop['address']),
      latitude: _toDouble(shop['latitude']),
      longitude: _toDouble(shop['longitude']),
      iban: _clean(shop['iban']),
      bankName: _clean(shop['bank_name']),
      accountHolder: _clean(shop['account_holder_name']) ??
          _clean(shop['account_holder']),
    );
  }

  final String? ownerName;
  final String? ownerEmail;

  /// Önce dükkan telefonu, yoksa sahibin profil telefonu.
  final String? phone;

  /// [phone] dükkan yerine sahibin profilinden geldiyse true.
  final bool phoneFromProfile;

  final String? shopEmail;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? iban;
  final String? bankName;
  final String? accountHolder;

  bool get hasLocation => latitude != null && longitude != null;

  /// Sahip e-postasıyla aynıysa ayrıca gösterilmez.
  bool get showShopEmail =>
      shopEmail != null &&
      shopEmail!.toLowerCase() != (ownerEmail ?? '').toLowerCase();

  /// `tel:` bağlantısı için yalnız rakam ve baştaki `+`.
  String? get dialablePhone {
    final p = phone;
    if (p == null) return null;
    final digits = p.replaceAll(RegExp(r'[^\d+]'), '');
    return digits.isEmpty ? null : digits;
  }

  String? get locationLabel => hasLocation
      ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}'
      : null;

  Uri? get mapsUri => hasLocation
      ? Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude')
      : null;

  /// `TR12 3456 7890 ...` biçiminde 4'erli gruplar.
  static String formatIban(String iban) {
    final raw = iban.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i += 4) {
      if (i > 0) buf.write(' ');
      buf.write(raw.substring(i, i + 4 > raw.length ? raw.length : i + 4));
    }
    return buf.toString();
  }

  static String? _clean(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// [AdminShopContact] satırları: ara / kopyala / haritada aç düğmeleriyle.
/// Kartı çağıran ekran sarar; bu widget yalnız satırları çizer.
class AdminShopContactRows extends StatelessWidget {
  const AdminShopContactRows({
    super.key,
    required this.contact,
    this.showOwner = true,
    this.showContact = true,
    this.showPayment = true,
    this.labelWidth = 96,
  });

  final AdminShopContact contact;

  /// Sahip adı + sahip e-postası.
  final bool showOwner;

  /// Telefon, dükkan e-postası, adres, konum.
  final bool showContact;

  /// IBAN, banka, hesap sahibi.
  final bool showPayment;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    // Dar yerde (ör. telefondaki "Dükkan Detayı" penceresi) etiket değerin
    // üstüne iner; yan yana kalınca değere ~75 px kalıyordu.
    return LayoutBuilder(
      builder: (context, constraints) => _buildRows(
        context,
        stacked: constraints.maxWidth < labelWidth + 220,
      ),
    );
  }

  Widget _buildRows(BuildContext context, {required bool stacked}) {
    final c = contact;
    Widget row(
      BuildContext context,
      IconData icon,
      String label,
      String? value, {
      String? hint,
      bool copy = false,
      String? copyValue,
      VoidCallback? onTap,
      IconData? tapIcon,
      String? tapTooltip,
      String missing = '-',
    }) =>
        _buildRow(
          context,
          icon,
          label,
          value,
          stacked: stacked,
          hint: hint,
          copy: copy,
          copyValue: copyValue,
          onTap: onTap,
          tapIcon: tapIcon,
          tapTooltip: tapTooltip,
          missing: missing,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showOwner) ...[
          row(context, Icons.person_outline, 'Sahibi', c.ownerName),
          row(context, Icons.alternate_email, 'E-posta', c.ownerEmail,
              copy: true),
        ],
        if (showContact) ...[
          row(
            context,
            Icons.phone_outlined,
            'Telefon',
            c.phone,
            hint: c.phoneFromProfile ? 'Sahibin profilinden' : null,
            copy: true,
            onTap: c.dialablePhone == null
                ? null
                : () => _launch(
                      context,
                      Uri(scheme: 'tel', path: c.dialablePhone),
                    ),
            tapIcon: Icons.call,
            tapTooltip: 'Ara',
            missing: 'Girilmemiş',
          ),
          if (c.showShopEmail)
            row(context, Icons.mail_outline, 'Dükkan e-postası', c.shopEmail,
                copy: true),
          row(context, Icons.place_outlined, 'Adres', c.address,
              copy: true, missing: 'Girilmemiş'),
          row(
            context,
            Icons.my_location,
            'Konum',
            c.locationLabel,
            onTap:
                c.mapsUri == null ? null : () => _launch(context, c.mapsUri!),
            tapIcon: Icons.map_outlined,
            tapTooltip: 'Haritada aç',
            missing: 'Girilmemiş',
          ),
        ],
        if (showPayment) ...[
          row(
            context,
            Icons.account_balance_outlined,
            'IBAN',
            c.iban == null ? null : AdminShopContact.formatIban(c.iban!),
            copyValue: c.iban,
            copy: true,
            missing: 'Girilmemiş',
          ),
          if (c.iban != null || c.bankName != null)
            row(context, Icons.account_balance, 'Banka', c.bankName),
          if (c.iban != null || c.accountHolder != null)
            row(context, Icons.badge_outlined, 'Hesap sahibi',
                c.accountHolder,
                copy: true),
        ],
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    IconData icon,
    String label,
    String? value, {
    required bool stacked,
    String? hint,
    bool copy = false,
    String? copyValue,
    VoidCallback? onTap,
    IconData? tapIcon,
    String? tapTooltip,
    String missing = '-',
  }) {
    final has = value != null && value.trim().isNotEmpty;
    final labelText = Text(
      label,
      style: TextStyle(
        fontSize: stacked ? 11.5 : 13,
        color: Colors.grey.shade600,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: stacked ? 3 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          if (!stacked) SizedBox(width: labelWidth, child: labelText),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stacked) labelText,
                SelectableText(
                  has ? value : missing,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                    color: has ? Colors.black87 : Colors.grey.shade500,
                  ),
                ),
                if (has && hint != null)
                  Text(
                    hint,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          if (has && onTap != null && tapIcon != null)
            _action(tapIcon, tapTooltip ?? label, onTap),
          if (has && copy)
            _action(Icons.copy_rounded, '$label kopyala', () {
              Clipboard.setData(ClipboardData(text: copyValue ?? value));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text('$label kopyalandı'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: Colors.grey.shade700,
    );
  }

  static Future<void> _launch(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Bağlantı açılamadı')),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Bağlantı açılamadı: $e')),
      );
    }
  }
}
