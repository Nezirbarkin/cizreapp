// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ========== CÜZDAN AYARLARI SEKME WIDGET ==========
class WalletSettingsTabWidget extends StatefulWidget {
  const WalletSettingsTabWidget({super.key});

  @override
  State<WalletSettingsTabWidget> createState() =>
      _WalletSettingsTabWidgetState();
}

class _WalletSettingsTabWidgetState extends State<WalletSettingsTabWidget> {
  bool _isLoading = true;
  bool _cardTopupEnabled = true;
  bool _balanceEnabled = true;
  double _minTopupAmount = 10;
  double _maxTopupAmount = 10000;
  double _withdrawalFeePercent = 2;
  double _minWithdrawalAmount = 50;
  // Sipariş ödeme yöntemi toggle'ları (20260705_PAYMENT_METHOD_TOGGLES.sql).
  // 4 yöntem: Kapıda Nakit, Kapıda Kart, Online, Bakiye.
  bool _orderCodEnabled = true;
  bool _orderCardOnDeliveryEnabled = true;
  bool _orderOnlineEnabled = true;
  bool _orderBalanceEnabled = true;
  // 2026-07-09: Anasayfa kategori kartı sayısı limiti (admin panelinden ayarlanabilir)
  int _homeCategoryLimit = 4;
  // 2026-07-27: Anasayfa haber kartı sayısı limiti (admin panelinden ayarlanabilir)
  int _homeNewsLimit = 3;
  // 2026-08-18: Anasayfa dükkan sayısı limiti (admin panelinden ayarlanabilir)
  int _homeShopLimit = 8;
  bool _isSaving = false;

  // Sayısal alanların TextEditingController'ları kalıcı State alanları olmalı.
  // Eskiden build() içinde her seferinde `TextEditingController(text: ...)`
  // ile yeniden yaratılıyorlardı; onChanged -> setState -> build tetiklendiğinde
  // her tuş vuruşunda YENİ bir controller (ve imleç sıfırlanmış, "güncel"
  // değerden yeniden okunmuş text) oluşuyordu — bu da çok haneli sayı
  // yazmayı fiilen imkansız hale getiriyordu (rakamlar karışık/ters sırada
  // görünüyordu). Kalıcı controller kullanılınca setState artık text'i
  // sıfırlamıyor.
  late final _minTopupController = TextEditingController(
    text: _minTopupAmount.toStringAsFixed(0),
  );
  late final _maxTopupController = TextEditingController(
    text: _maxTopupAmount.toStringAsFixed(0),
  );
  late final _minWithdrawalController = TextEditingController(
    text: _minWithdrawalAmount.toStringAsFixed(0),
  );
  late final _homeCategoryController = TextEditingController(
    text: _homeCategoryLimit.toString(),
  );
  late final _homeNewsController = TextEditingController(
    text: _homeNewsLimit.toString(),
  );
  late final _homeShopController = TextEditingController(
    text: _homeShopLimit.toString(),
  );

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _minTopupController.dispose();
    _maxTopupController.dispose();
    _minWithdrawalController.dispose();
    _homeCategoryController.dispose();
    _homeNewsController.dispose();
    _homeShopController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      // NOT: online_payment_enabled tek gerçek kaynak; siparişlerde de aynı kolon
      // kullanılıyor (payment_method_settings_service.dart). Yeni sipariş toggle'ları
      // 20260705_PAYMENT_METHOD_TOGGLES.sql ile eklendi (migration uygulanmadıysa
      // ?? true fallback tüm yöntemleri aktif gösterir → mevcut davranış korunur).
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select(
            'card_topup_enabled, balance_enabled, min_topup_amount, '
            'max_topup_amount, withdrawal_fee_percent, min_withdrawal_amount, '
            'online_payment_enabled, '
            'order_cod_enabled, order_card_on_delivery_enabled, order_balance_enabled, '
            'home_category_limit, home_news_limit, home_shop_limit',
          )
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _cardTopupEnabled = response['card_topup_enabled'] as bool? ?? true;
          _balanceEnabled = response['balance_enabled'] as bool? ?? true;
          _minTopupAmount =
              (response['min_topup_amount'] as num?)?.toDouble() ?? 10;
          _maxTopupAmount =
              (response['max_topup_amount'] as num?)?.toDouble() ?? 10000;
          _withdrawalFeePercent =
              (response['withdrawal_fee_percent'] as num?)?.toDouble() ?? 2;
          _minWithdrawalAmount =
              (response['min_withdrawal_amount'] as num?)?.toDouble() ?? 50;
          // Sipariş ödeme yöntemi toggle'ları
          _orderOnlineEnabled =
              response['online_payment_enabled'] as bool? ?? true;
          _orderCodEnabled = response['order_cod_enabled'] as bool? ?? true;
          _orderCardOnDeliveryEnabled =
              response['order_card_on_delivery_enabled'] as bool? ?? true;
          _orderBalanceEnabled =
              response['order_balance_enabled'] as bool? ?? true;
          // Anasayfa kategori kartı sayısı limiti (yeni kolon — migration yoksa varsayılan 4)
          _homeCategoryLimit = response['home_category_limit'] as int? ?? 4;
          // Anasayfa haber kartı sayısı limiti (yeni kolon — migration yoksa varsayılan 3)
          _homeNewsLimit = response['home_news_limit'] as int? ?? 3;
          // Anasayfa dükkan sayısı limiti (yeni kolon — migration yoksa varsayılan 8)
          _homeShopLimit = response['home_shop_limit'] as int? ?? 8;
          _isLoading = false;

          _minTopupController.text = _minTopupAmount.toStringAsFixed(0);
          _maxTopupController.text = _maxTopupAmount.toStringAsFixed(0);
          _minWithdrawalController.text =
              _minWithdrawalAmount.toStringAsFixed(0);
          _homeCategoryController.text = _homeCategoryLimit.toString();
          _homeNewsController.text = _homeNewsLimit.toString();
          _homeShopController.text = _homeShopLimit.toString();
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Ayarlar yüklenirken hata: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;

      // Önce mevcut kaydın ID'sini al (UPDATE için WHERE koşulu gerekli)
      final existing = await supabase
          .from('app_about_settings')
          .select('id')
          .limit(1)
          .maybeSingle();

      if (existing == null || existing['id'] == null) {
        throw Exception('app_about_settings tablosunda kayıt bulunamadı');
      }

      // NOT: online_payment_enabled kolonu yalnızca admin bu sekmede değiştirirse
      // yazılır; app_about_service tarafında da aynı kolon kullanılıyor. Çakışma yok
      // (tek gerçek kaynak). Yeni kolonlar (order_*) migration ile geldiyse yazılır,
      // gelmediyse PostgREST 204 verebilir → o durumda migration çalıştırılmalı.
      await supabase
          .from('app_about_settings')
          .update({
            'card_topup_enabled': _cardTopupEnabled,
            'balance_enabled': _balanceEnabled,
            'min_topup_amount': _minTopupAmount,
            'max_topup_amount': _maxTopupAmount,
            'withdrawal_fee_percent': _withdrawalFeePercent,
            'min_withdrawal_amount': _minWithdrawalAmount,
            // Sipariş ödeme yöntemi toggle'ları
            'online_payment_enabled': _orderOnlineEnabled,
            'order_cod_enabled': _orderCodEnabled,
            'order_card_on_delivery_enabled': _orderCardOnDeliveryEnabled,
            'order_balance_enabled': _orderBalanceEnabled,
            // 2026-07-09: Anasayfa kategori kartı sayısı limiti
            'home_category_limit': _homeCategoryLimit,
            // 2026-07-27: Anasayfa haber kartı sayısı limiti
            'home_news_limit': _homeNewsLimit,
            // 2026-08-18: Anasayfa dükkan sayısı limiti
            'home_shop_limit': _homeShopLimit,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existing['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar kaydedildi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Kredi Kartı Ödeme Ayarları
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.credit_card, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Kredi Kartı ile Ödeme',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cardTopupEnabled
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _cardTopupEnabled
                          ? Colors.green.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _cardTopupEnabled ? Icons.check_circle : Icons.warning,
                        color: _cardTopupEnabled
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _cardTopupEnabled
                              ? 'Kredi kartı ile bakiye yükleme aktif'
                              : 'Kredi kartı ile bakiye yükleme pasif - Kullanıcılar sadece havale yöntemini kullanabilir',
                          style: TextStyle(
                            fontSize: 12,
                            color: _cardTopupEnabled
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Kredi Kartı ile Bakiye Yükleme'),
                  subtitle: Text(
                    _cardTopupEnabled
                        ? 'İYZiCo üzerinden kredi/banka kartı ile ödeme açık'
                        : 'Kredi kartı ödemesi kapalı - Havale/EFT yöntemi kullanılmalı',
                  ),
                  value: _cardTopupEnabled,
                  onChanged: (value) =>
                      setState(() => _cardTopupEnabled = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Genel Bakiye Ayarları
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: Colors.purple.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Bakiye Sistemi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Bakiye Sistemi Aktif'),
                  subtitle: const Text('Tüm bakiye işlemlerini aç/kapat'),
                  value: _balanceEnabled,
                  onChanged: (value) => setState(() => _balanceEnabled = value),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                ListTile(
                  title: const Text('Minimum Yükleme Tutarı'),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                        suffixText: 'TL',
                      ),
                      controller: _minTopupController,
                      onChanged: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed != null) {
                          setState(() => _minTopupAmount = parsed);
                        }
                      },
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                ListTile(
                  title: const Text('Maksimum Yükleme Tutarı'),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                        suffixText: 'TL',
                      ),
                      controller: _maxTopupController,
                      onChanged: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed != null) {
                          setState(() => _maxTopupAmount = parsed);
                        }
                      },
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                ListTile(
                  title: const Text('Minimum Çekim Tutarı'),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                        suffixText: 'TL',
                      ),
                      controller: _minWithdrawalController,
                      onChanged: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed != null) {
                          setState(() => _minWithdrawalAmount = parsed);
                        }
                      },
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Sipariş Ödeme Yöntemleri (20260705_PAYMENT_METHOD_TOGGLES.sql)
          // Admin siparişlerde hangi ödeme yöntemlerinin görünür olduğunu kontrol eder.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_outlined, color: Colors.teal.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Sipariş Ödeme Yöntemleri',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Müşteriye sipariş sırasında hangi yöntemlerin gösterileceğini belirleyin. '
                  'Pasif yapılan yöntemler checkout ekranlarında gizlenir.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Kapıda Nakit'),
                  subtitle: const Text('Teslimatçıya nakit ödeme'),
                  value: _orderCodEnabled,
                  onChanged: (value) =>
                      setState(() => _orderCodEnabled = value),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Kapıda Banka/Kredi Kartı'),
                  subtitle: const Text('Teslimatçıda POS cihazı ile ödeme'),
                  value: _orderCardOnDeliveryEnabled,
                  onChanged: (value) =>
                      setState(() => _orderCardOnDeliveryEnabled = value),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Online Ödeme (Kredi/Banka Kartı)'),
                  subtitle: const Text('iyzico üzerinden güvenli online ödeme'),
                  value: _orderOnlineEnabled,
                  onChanged: (value) =>
                      setState(() => _orderOnlineEnabled = value),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Bakiye ile Ödeme'),
                  subtitle: const Text(
                    'Siparişi kullanıcı bakiyesinden öde (bakiye sistemi ayrıca aktif olmalı)',
                  ),
                  value: _orderBalanceEnabled,
                  onChanged: (value) =>
                      setState(() => _orderBalanceEnabled = value),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Bakiye sistemini tamamen kapatmak için yukarıdaki "Bakiye Sistemi Aktif" '
                        'anahtarını kullanın. Bu bölüm yalnızca sipariş ödeme yöntemi seçeneğini filtreler.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2026-07-09: Anasayfa Görünüm Ayarları
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.home_outlined, color: Colors.teal.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Anasayfa Görünüm Ayarları',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Anasayfadaki kategori kartı, haber kartı ve dükkan sayısını belirleyin.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Kategori Kartı Sayısı'),
                  subtitle: Text(
                    '1-20 arası değer girilebilir. Varsayılan: 4',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      controller: _homeCategoryController,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 1 && parsed <= 20) {
                          setState(() => _homeCategoryLimit = parsed);
                        }
                      },
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                ListTile(
                  title: const Text('Haber Kartı Sayısı'),
                  subtitle: Text(
                    '1-10 arası değer girilebilir. Varsayılan: 3',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      controller: _homeNewsController,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 1 && parsed <= 10) {
                          setState(() => _homeNewsLimit = parsed);
                        }
                      },
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                ListTile(
                  title: const Text('Dükkan Sayısı'),
                  subtitle: Text(
                    '1-50 arası değer girilebilir. Varsayılan: 8',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      controller: _homeShopController,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 1 && parsed <= 50) {
                          setState(() => _homeShopLimit = parsed);
                        }
                      },
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Kaydet Butonu
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Kaydediliyor...' : 'Ayarları Kaydet'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Bilgi Kutusu
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Bilgi',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Kredi kartı ödemesi için İYZiCo API ayarlarının yapılandırılmış olması gerekir.\n'
                  '• Havale/EFT yöntemi her zaman aktif kalır.\n'
                  '• Kullanıcılar havale bildirimi gönderdiğinde admin onayı gerekir.',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
