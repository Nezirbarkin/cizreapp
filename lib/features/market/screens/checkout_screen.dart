// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/cart_model.dart';
import '../../../core/models/coupon_model.dart';
import '../../../core/models/address_model.dart';
import '../../../core/models/invoice_info_model.dart';
import '../../../core/services/app_about_service.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/services/verification_service.dart';
import '../../../core/services/payment_method_settings_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/invoice_info_widget.dart';
import '../../../models/checkout_session_model.dart';
import '../../../services/checkout_service.dart';
import '../providers/address_provider.dart';
import '../providers/cart_provider.dart';
import '../../shop/screens/payment_webview_screen.dart';
import '../services/cart_checkout_request.dart';
import '../services/cart_service.dart';
import 'address_management_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final String shopId;
  final String shopName;
  /// Sepet ekranındaki CartProvider'ın in-memory kupon durumu. Eski sürümde
  /// CheckoutScreen taze bir CartProvider yaratıyordu, bu nedenle
  /// `_couponsByShop` boş başlıyor ve uygulanan kupon tek-dükkan checkout'ta
  /// sessizce kayboluyordu. Bu harita sepette uygulanan kuponları taşır.
  final Map<String, AppliedCoupon> couponsByShop;

  const CheckoutScreen({
    super.key,
    required this.shopId,
    required this.shopName,
    this.couponsByShop = const {},
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // Sipariş yalnız sunucu oturumuyla oluşturulur (prepare → commit); eski
  // istemci-INSERT akışı (OrderService.createOrder) bu ekranda kullanılmaz.
  late final CheckoutService _checkoutService =
      CheckoutService(Supabase.instance.client);
  final CartService _cartService = CartService();
  final AppAboutService _aboutService = AppAboutService();
  final BalanceService _balanceService = BalanceService();
  final VerificationService _verificationService = VerificationService();
  final InvoiceService _invoiceService = InvoiceService();
  final _notesController = TextEditingController();
  
  // Fatura bilgileri
  InvoiceInfo? _selectedInvoiceInfo;

  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _isPlacingOrder = false;
  bool _onlinePaymentEnabled = false;
  bool _isLoadingPaymentSettings = true;
  /// Admin panelden kontrol edilen sipariş ödeme yöntemi toggle'ları.
  /// load() başarısız olursa allEnabled() fallback döner (mevcut davranış korunur).
  PaymentMethodSettings _paymentSettings = const PaymentMethodSettings.allEnabled();

  /// Bu dükkan için uygulanan kupon (sepet ekranından taşınır).
  /// Eskiden taze CartProvider yüzünden hep null geliyordu.
  AppliedCoupon? get _appliedCoupon => widget.couponsByShop[widget.shopId];

  // "Gel Al" (mağazadan teslim) - dükkan aktif ettiyse checkout'ta seçenek
  // gösterilir. Seçiliyse teslimat ücreti alınmaz ve kurye devreye girmez.
  bool _shopPickupEnabled = false;
  bool _isPickupSelected = false;

  // Bakiye durumu. "Gel Al" siparişleri peşin olarak bakiyeden tahsil edilir,
  // bu yüzden seçeneğin gösterilip gösterilmeyeceğine karar vermek ve yetersiz
  // bakiyeyi sipariş anından ÖNCE uyarabilmek için state'te tutulur.
  double _availableBalance = 0;
  bool _balanceSystemEnabled = false;

  /// Bakiye ile ödeme hem admin toggle'ı hem de bakiye sistemi açıksa mümkün.
  bool get _balancePaymentAvailable =>
      _paymentSettings.isAvailable(PaymentMethod.balance) && _balanceSystemEnabled;

  /// "Gel Al" yalnızca bakiyeden ödenebildiği için, bakiye ödemesi kapalıysa
  /// seçenek hiç gösterilmez (tamamlanamayacak bir akışa sokmamak için).
  bool get _canOfferPickup => _shopPickupEnabled && _balancePaymentAvailable;

  /// CheckoutScreen'in ÜSTÜNDEKİ (ör. MainScreen'deki) CartProvider — yoksa
  /// null döner.
  ///
  /// Sipariş tamamlandıktan sonra ana ekrandaki sepet rozeti yenilenmeli.
  /// Eskiden bu, `popUntil`den 100 ms sonra `context.read<CartProvider>()`
  /// ile yapılıyordu ve üç ayrı hata üretiyordu:
  ///   * pop sonrası element deactive olduğu için "Looking up a deactivated
  ///     widget's ancestor is unsafe" (`context.mounted` o anda hâlâ true
  ///     olduğundan koruma işe yaramıyordu),
  ///   * CheckoutScreen'in üstünde hiç CartProvider olmayan navigasyon
  ///     yollarında `ProviderNotFoundException`,
  ///   * yerel provider bu arada dispose edildiği için "A CartProvider was
  ///     used after being disposed".
  /// Çözüm: pop'TAN ÖNCE, element hâlâ aktifken çözmek. `build()` içinde
  /// yaratılan yerel MultiProvider bu context'in ALTINDA kaldığı için buradan
  /// okunmaz; aranan zaten ana ekranın sepetidir.
  static CartProvider? _readAncestorCart(BuildContext context) {
    try {
      return context.read<CartProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// "Gel Al" seçiliyken gösterim amaçlı teslimat ücreti/toplam. `summary`
  /// `CartProvider`dan geldiği için pickup seçimini bilmez - ekranda tutarlı
  /// görünsün diye burada override edilir (siparişin gerçek tutarlarını
  /// sunucu `prepare_checkout_session`'da hesaplar; onay penceresi onları
  /// gösterir).
  double _effectiveDeliveryFee(CartSummary summary) =>
      _isPickupSelected ? 0.0 : summary.deliveryFee;

  double _effectiveTotal(CartSummary summary) =>
      summary.total - summary.deliveryFee + _effectiveDeliveryFee(summary);

  @override
  void initState() {
    super.initState();
    _loadPaymentSettings();
    _loadShopPickupInfo();
    _refreshBalanceState();
  }

  /// Bakiye bilgisini state'e alır. "Gel Al" seçeneğinin görünürlüğü ve
  /// yetersiz bakiye uyarısı buna bağlı.
  Future<void> _refreshBalanceState() async {
    final info = await _loadBalanceInfo();
    if (!mounted || info == null) return;
    setState(() {
      _availableBalance = (info['balance'] as double?) ?? 0;
      _balanceSystemEnabled = (info['enabled'] as bool?) ?? false;
    });
  }

  /// Dükkanın "Gel Al" aktifliğini yükler. Hata durumunda sessizce false
  /// kalır - checkout'un geri kalanı normal teslimat akışıyla çalışmaya
  /// devam eder.
  Future<void> _loadShopPickupInfo() async {
    try {
      final response = await Supabase.instance.client
          .from('shops')
          .select('pickup_enabled')
          .eq('id', widget.shopId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _shopPickupEnabled = response?['pickup_enabled'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Gel Al bilgisi alınamadı: $e');
    }
  }

  Future<void> _loadPaymentSettings() async {
    try {
      final methodSettings = await PaymentMethodSettings.load();
      if (!mounted) return;
      setState(() {
        _paymentSettings = methodSettings;
        // Eski _onlinePaymentEnabled referansı helper'ın onlineEnabled'ı ile beslenir
        // (tek gerçek kaynak prensibi: online_payment_enabled kolonu).
        _onlinePaymentEnabled = methodSettings.onlineEnabled;
        _isLoadingPaymentSettings = false;
        // Seçili yöntem artık aktif değilse (admin kapatmışsa) ilk aktif
        // yönteme otomatik kay — kullanıcı hiçbir yöntemi seçemez kalmaz.
        _selectedPaymentMethod = methodSettings.pickDefault(
          preferred: _selectedPaymentMethod,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentSettings = const PaymentMethodSettings.allEnabled();
        _onlinePaymentEnabled = true;
        _isLoadingPaymentSettings = false;
      });
      debugPrint('❌ Ödeme ayarları yüklenirken hata: $e');
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadBalanceInfo() async {
    try {
      final balance = await _balanceService.getBalance();
      final settings = await _aboutService.getAboutSettings();
      return {
        'balance': balance?.availableBalance ?? 0,
        'enabled': settings?.balanceEnabled ?? false,
      };
    } catch (e) {
      debugPrint('Bakiye bilgisi yüklenemedi: $e');
      return {'balance': 0.0, 'enabled': false};
    }
  }

  Future<bool> _checkOrderApprovalCodeEnabled() async {
    try {
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select('order_approval_code_enabled')
          .maybeSingle();
      // Satır yoksa onay kodu zorunlu olsun (güvenli taraf)
      return response?['order_approval_code_enabled'] ?? true;
    } catch (e) {
      debugPrint('Onay kodu ayarı kontrolü hatası: $e');
      return true;
    }
  }

  Future<bool?> _showVerificationDialog() async {
    String verificationCode = '';
    String? verificationId;
    String? displayedCode; // Ekranda gösterilecek kod
    DateTime? codeSentTime;
    int expiresInSeconds = 300;
    bool isSending = false;
    bool isVerifying = false;
    bool autoSendTriggered = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Dialog açıldığında otomatik olarak kodu gönder (sadece bir kez)
          if (!autoSendTriggered && verificationId == null && !isSending) {
            autoSendTriggered = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!context.mounted) return;
              setDialogState(() => isSending = true);
              try {
                final result = await _verificationService.sendVerificationCode(
                  codeType: 'order_verification',
                );
                // Kod gelene kadar diyalog "İptal" ile kapatılmış olabilir;
                // ölü StatefulBuilder'da setDialogState admin Loglar'da
                // "setState() called after dispose()" veriyordu.
                if (!context.mounted) return;
                setDialogState(() {
                  verificationId = result['verification_id'];
                  expiresInSeconds = result['expires_in_seconds'] ?? 300;
                  codeSentTime = DateTime.now();
                  isSending = false;
                  // Kodu al ve ekranda göster
                  displayedCode = result['code']?.toString();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message'] ?? 'Kod bildirim olarak gönderildi'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                setDialogState(() => isSending = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.userMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            });
          }

          int remainingSeconds = 0;
          if (codeSentTime != null) {
            remainingSeconds = _verificationService.getRemainingSeconds(
              codeSentTime,
              expiresInSeconds,
            );
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified_user, color: Colors.orange),
                SizedBox(width: 8),
                Text('Sipariş Onay Kodu'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Güvenlik için size gönderilen 6 haneli kodu girin.',
                    style: TextStyle(fontSize: 14),
                  ),
                // Kod ekranda gösteriliyorsa prominent şekilde göster
                // (2026-07-29 FIX) Sadece DEBUG modda — production'da SMS-only
                // olmalı, ekranda kodun açık görünmesi güvenlik riski yaratır.
                if (kDebugMode && displayedCode != null && displayedCode!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade300, width: 2),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sms, color: Colors.green, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Onay Kodunuz',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          displayedCode!,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                
                TextField(
                  onChanged: (value) {
                    verificationCode = value;
                    setDialogState(() {}); // UI'ı güncelle
                  },
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: const InputDecoration(
                    hintText: '000000',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                
                const SizedBox(height: 16),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (isSending || remainingSeconds > 0)
                        ? null
                        : () async {
                            setDialogState(() => isSending = true);
                            try {
                              final result = await _verificationService.sendVerificationCode(
                                codeType: 'order_verification',
                              );
                              if (!context.mounted) return;
                              setDialogState(() {
                                verificationId = result['verification_id'];
                                expiresInSeconds = result['expires_in_seconds'] ?? 300;
                                codeSentTime = DateTime.now();
                                isSending = false;
                                // Yeni kodu al ve ekranda göster
                                displayedCode = result['code']?.toString();
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['message'] ?? 'Kod gönderildi'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              setDialogState(() => isSending = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.userMessage),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                    icon: isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      remainingSeconds > 0
                          ? 'Yeniden gönder ($remainingSeconds sn)'
                          : (verificationId != null ? 'Kodu Yeniden Gönder' : 'Kod Gönder'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ),
                
                if (verificationId != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Kod ${expiresInSeconds ~/ 60} dakika geçerlidir',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: (isVerifying || verificationId == null || verificationCode.length != 6)
                    ? null
                    : () async {
                        setDialogState(() => isVerifying = true);
                        try {
                          final result = await _verificationService.verifyCode(
                            code: verificationCode,
                            codeType: 'order_verification',
                          );
                           
                          if (result['success'] == true) {
                            if (context.mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context, true);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Kod doğrulandı!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            if (!context.mounted) return;
                            setDialogState(() => isVerifying = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result['message'] ?? 'Kod hatalı'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          setDialogState(() => isVerifying = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Doğrulama hatası: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isVerifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Doğrula'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showConfirmationDialog(Address selectedAddress, CartProvider cartProvider) async {
    // Kapıda ödeme ise - admin ayarına göre onay kodu iste
    // Bakiye ve online ödemelerde onay kodu gerekmez
    if (_selectedPaymentMethod == PaymentMethod.cash ||
        _selectedPaymentMethod == PaymentMethod.cardOnDelivery) {
      final approvalCodeEnabled = await _checkOrderApprovalCodeEnabled();
      if (approvalCodeEnabled) {
        final verified = await _showVerificationDialog();
        if (verified != true) {
          return; // Kullanıcı iptal etti veya kod yanlış
        }
      }
      // approvalCodeEnabled = false ise direkt devam et
    }

    // Bakiye SİSTEMİ master anahtarı (balance_enabled) ayrıdır; radyo
    // yalnızca order_balance_enabled ile görünür ama sistem kapalıysa
    // ödeme yapılmamalı.
    if (_selectedPaymentMethod == PaymentMethod.balance) {
      final balanceInfo = await _loadBalanceInfo();
      if (!((balanceInfo?['enabled'] as bool?) ?? false)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bakiye ile ödeme şu an kullanılamıyor.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // Tutarlar sunucuda hesaplanır: önce oturum açılır, onay penceresi
    // sunucunun döndürdüğü fiyatları gösterir (istemci tutar göndermez).
    setState(() => _isPlacingOrder = true);
    CheckoutSession? session;
    try {
      session = await _prepareSession(selectedAddress);
    } on CheckoutException catch (e) {
      _showCheckoutError(e);
    } catch (e) {
      _showCheckoutError(CheckoutException('prepare_failed', e.toString()));
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
    if (session == null || !mounted) return;

    // Bakiye yetersizse siparişe hiç geçme (sunucu da ayrıca reddeder).
    if (session.isBalance) {
      final balanceInfo = await _loadBalanceInfo();
      final availableBalance = (balanceInfo?['balance'] as double?) ?? 0;
      if (availableBalance < session.serverTotal) {
        unawaited(_checkoutService.cancelCheckoutSession(session.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Yetersiz bakiye! Mevcut: ₺${availableBalance.toStringAsFixed(2)}, Gerekli: ₺${session.serverTotal.toStringAsFixed(2)}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;

    final quote = session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Siparişi Onayla'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sipariş detaylarını lütfen kontrol edin:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              _buildConfirmationRow(Icons.store, 'Dükkan:', widget.shopName),
              if (_isPickupSelected)
                _buildConfirmationRow(Icons.storefront, 'Teslim Şekli:', 'Gel Al - Mağazadan Teslim')
              else
                _buildConfirmationRow(Icons.location_on, 'Adres:', selectedAddress.title),
              _buildConfirmationRow(
                Icons.payment,
                'Ödeme:',
                // Bakiye ayrı ele alınmalı: eskiden else dalına düşüp "Online
                // Ödeme" yazıyordu. Gel Al siparişleri her zaman bakiyeden
                // ödendiği için bu yanlış etiket artık her pickup siparişinde
                // görünürdü.
                switch (_selectedPaymentMethod) {
                  PaymentMethod.cash => 'Kapıda Nakit',
                  PaymentMethod.cardOnDelivery => 'Kapıda Banka/Kredi Kartı',
                  PaymentMethod.balance => 'Bakiye ile Ödeme',
                  _ => 'Online Ödeme',
                },
              ),
              const Divider(height: 24),
              // Ürünler (sunucu fiyatıyla)
              ...quote.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.productName.isEmpty ? "Ürün" : item.productName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('₺${item.lineTotal.toStringAsFixed(2)}'),
                  ],
                ),
              )),
              if (quote.endedFlashProductNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Flaş fırsatı sona erdi, normal fiyat uygulandı: '
                  '${quote.endedFlashProductNames.join(', ')}',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ],
              const Divider(height: 24),
              // Ara toplam
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ara Toplam:'),
                  Text('₺${quote.serverSubtotal.toStringAsFixed(2)}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Teslimat:'),
                  Text('₺${quote.serverDeliveryFee.toStringAsFixed(2)}'),
                ],
              ),
              if (quote.serverCouponDiscount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('İndirim:', style: TextStyle(color: Colors.green)),
                    Text('-₺${quote.serverCouponDiscount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green)),
                  ],
                ),
              ],
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOPLAM:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    '₺${quote.serverTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_selectedPaymentMethod == PaymentMethod.cash)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Teslimatçı kapıda ödemeyi alacaktır',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Siparişi Onayla'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      // Flaş rezervasyonu 15 dk beklemesin.
      unawaited(_checkoutService.cancelCheckoutSession(quote.id));
      return;
    }
    if (!mounted) return;
    await _confirmOrder(quote, cartProvider);
  }

  Widget _buildConfirmationRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  /// Bu dükkanın sepet satırlarından sunucu oturumu açar. Tutar, teslimat,
  /// kupon ve Gel Al hesabı `prepare_checkout_session`'da yapılır.
  Future<CheckoutSession> _prepareSession(Address selectedAddress) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw CheckoutException('auth_required', 'Lütfen giriş yapın');
    }
    // Yalnız bu dükkanın satırları: mağaza içi sepetten gelindiğinde ana
    // sepette başka dükkanların ürünleri de olabilir (eskiden hepsi bu
    // dükkanın siparişine yazılıyordu).
    final items = (await _cartService.getCart(userId))
        .where((item) => item.shopId == widget.shopId)
        .toList();
    if (items.isEmpty) {
      throw CheckoutException('empty_cart', 'Sepetiniz boş');
    }
    final coupon = _appliedCoupon;
    return _checkoutService.prepareCheckout(
      buildCartCheckoutRequest(
        items: items,
        addressId: selectedAddress.id,
        paymentMethod: _selectedPaymentMethod,
        idempotencyKey: CheckoutService.generateIdempotencyKey(prefix: 'cart'),
        coupons: [if (coupon != null) coupon],
        pickupShopIds: [if (_isPickupSelected) widget.shopId],
        notes: _notesController.text,
        invoiceInfo: _selectedInvoiceInfo,
      ),
    );
  }

  /// Oturum açılırken gelen hatayı seçili ödeme yönteminin eski mesaj
  /// biçimiyle gösterir.
  void _showCheckoutError(CheckoutException e) {
    if (!mounted) return;
    if (e.code == 'min_order_amount') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    final prefix = switch (_selectedPaymentMethod) {
      PaymentMethod.balance => 'Bakiye ödeme hatası',
      PaymentMethod.online => 'Ödeme başlatılamadı',
      _ => 'Sipariş oluşturulurken hata',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$prefix: ${e.userMessage}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Sipariş oluşunca sepetten bu dükkanın satırları silinir. Flaş talepleri
  /// geri VERİLMEZ: sunucu commit'i talebi tüketip satışı saydı.
  Future<void> _clearOrderedItems(CartProvider cartProvider) async {
    try {
      final onlyThisShop =
          cartProvider.items.every((item) => item.shopId == widget.shopId);
      if (onlyThisShop) {
        await cartProvider.clearCart(releaseFlashSales: false);
      } else {
        await cartProvider.clearShopCart(widget.shopId, releaseFlashSales: false);
      }
      debugPrint('✅ Sepet temizlendi');
    } catch (cartError) {
      // Sepet temizleme hatası kritik değil — sipariş oluşmuş, kullanıcı
      // sepeti sonra kendi temizleyebilir. Sadece log bırak.
      debugPrint('⚠️ Sepet temizleme hatası (sipariş etkilenmez): $cartError');
    }
  }

  /// Sipariş sonrası ana sayfaya dönüş + başarı mesajı.
  void _finishWithSuccess(String message) {
    if (!mounted) return;
    // Messenger ve ana ekranın CartProvider'ı POP'TAN ÖNCE çözülür.
    // Bkz. [_readAncestorCart].
    final messenger = ScaffoldMessenger.of(context);
    final rootCart = _readAncestorCart(context);

    // Ana sayfaya dön ve MainScreen'deki CartProvider'ı da yenile
    Navigator.of(context).popUntil((route) => route.isFirst);
    rootCart?.loadCart();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _confirmOrder(CheckoutSession session, CartProvider cartProvider) async {
    setState(() => _isPlacingOrder = true);

    try {
      // Ödeme yöntemi oturumda sabittir (prepare'de seçilen).
      if (session.isOnline) {
        await _initiateOnlinePayment(session, cartProvider);
      } else if (session.isBalance) {
        await _processBalancePayment(session, cartProvider);
      } else {
        await _placeOrder(session, cartProvider);
      }
    } finally {
      // Her durumda (_isPlacingOrder) sıfırla — erken return'ları da kapsar
      if (mounted) {
        setState(() => _isPlacingOrder = false);
      }
    }
  }

  /// Bakiye ile ödeme: sipariş(ler) + bakiye düşümü sunucuda tek işlemde.
  /// Bakiye yetmezse hiçbir sipariş açılmaz (eskiden açılıp iptal ediliyordu).
  Future<void> _processBalancePayment(CheckoutSession session, CartProvider cartProvider) async {
    try {
      final result = await _checkoutService.commitBalanceOrder(session.id);
      await _clearOrderedItems(cartProvider);
      _finishWithSuccess(
        'Siparişiniz bakiyenizden ödenerek oluşturuldu! (₺${result.amountPaid.toStringAsFixed(2)})',
      );
    } on CheckoutException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'insufficient_balance'
                ? e.userMessage
                : 'Bakiye ödeme hatası: ${e.userMessage}',
          ),
          backgroundColor:
              e.code == 'insufficient_balance' ? Colors.orange : Colors.red,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bakiye ödeme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Online ödeme (iyzico): oturum kimliğiyle başlatılır; tutar, ürün ve
  /// alıcı bilgisi sunucuda oturumdan/profilden okunur. Sipariş iyzico geri
  /// çağrısında oturumdan oluşturulur.
  Future<void> _initiateOnlinePayment(CheckoutSession session, CartProvider cartProvider) async {
    try {
      debugPrint('💳 MARKET CHECKOUT: iyzico ödeme başlatılıyor...');

      final result = await _checkoutService.initOnlinePayment(
        checkoutSessionId: session.id,
        idempotencyKey: CheckoutService.generateIdempotencyKey(prefix: 'pay'),
      );

      if (!mounted) return;
      setState(() => _isPlacingOrder = false);

      // WebView ekranına git
      final paymentResult = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentWebViewScreen(
            paymentUrl: result.paymentPageUrl ?? '',
            paymentTransactionId: result.paymentTransactionId ?? '',
            conversationId: result.conversationId ?? '',
            onPaymentSuccess: () async {
              // Sepeti temizle
              if (mounted) {
                await _clearOrderedItems(cartProvider);
              }
            },
          ),
        ),
      );

      debugPrint('💳 MARKET CHECKOUT: WebView kapandı, result: $paymentResult');
    } on CheckoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ödeme başlatılamadı: ${e.userMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ödeme başlatılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Kapıda nakit / kart: sipariş sunucuda oturumdan oluşturulur (kupon
  /// kullanımı, kampanya ödülü ve satıcı bildirimi dahil).
  Future<void> _placeOrder(CheckoutSession session, CartProvider cartProvider) async {
    try {
      await _checkoutService.commitCodOrder(session.id);
      await _clearOrderedItems(cartProvider);
      _finishWithSuccess('Siparişiniz başarıyla oluşturuldu!');
    } on CheckoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sipariş oluşturulurken hata: ${e.userMessage}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sipariş oluşturulurken hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sipariş Onayı')),
        body: const Center(child: Text('Lütfen giriş yapın')),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider(userId)),
        ChangeNotifierProvider(create: (_) => AddressProvider(userId)),
      ],
      child: Consumer2<CartProvider, AddressProvider>(
        builder: (context, cartProvider, addressProvider, _) {
        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: const Text('Sipariş Onayı'),
            elevation: 0,
          ),
          body: SafeArea(
            // ESKİ: `FutureBuilder` + `_cartService.getCartSummary` kupon
            // indirimini BİLMİYORDU (servis DB'den okur, kupon state
            // CartProvider'da). "Sipariş Özeti" kuponsuz fiyat gösteriyordu
            // (UI ile INSERT tutarsız). Şimdi `cartProvider.summary`
            // kullanılıyor — kupon _couponsByShop'tan toplanır.
            child: Builder(
              builder: (context) {
                final summary = cartProvider.summary;
                if (summary.isEmpty) {
                  return const Center(child: Text('Sepetiniz boş'));
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 100, // Alt çubuk için yer bırak
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Teslimat Adresi Seçimi
                      _buildAddressSection(addressProvider, _effectiveTotal(summary)),
                      const SizedBox(height: 16),

                      // Dükkan bilgisi
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.store),
                          title: Text(widget.shopName),
                          subtitle: const Text('Dükkan'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Fatura Bilgileri
                      InvoiceInfoSelector(
                        invoiceService: _invoiceService,
                        addressInfo: addressProvider.selectedAddress != null
                            ? AddressInfo(
                                fullName: addressProvider.selectedAddress!.fullName,
                                address: addressProvider.selectedAddress!.fullAddress,
                              )
                            : null,
                        onInvoiceChanged: (info) {
                          setState(() => _selectedInvoiceInfo = info);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Ödeme Yöntemi
                      _buildPaymentMethodSection(),
                      const SizedBox(height: 16),

                      // Not
                      _buildNotesSection(),
                      const SizedBox(height: 16),

                      // Sipariş Özeti
                      _buildOrderSummary(summary),
                      const SizedBox(height: 16),

                      // Sipariş Ver Butonu
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isPlacingOrder
                              ? null
                              : () {
                                  if (addressProvider.selectedAddress != null) {
                                    _showConfirmationDialog(addressProvider.selectedAddress!, cartProvider);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Lütfen teslimat adresi seçin')),
                                    );
                                  }
                                },
                          child: _isPlacingOrder
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Siparişi Onayla'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        },
      ),
    );
  }

  /// "Gel Al" seçiliyken bakiye durumunu gösterir; yetersizse kullanıcıyı
  /// sipariş onayına gitmeden önce uyarır (sert kontrol `_processBalancePayment`
  /// içinde ayrıca duruyor, bu erken/görsel uyarı).
  Widget _buildPickupBalanceNotice(double orderTotal) {
    final yetersiz = _availableBalance < orderTotal;
    final color = yetersiz ? Colors.orange : Colors.green;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade200),
        ),
        child: Row(
          children: [
            Icon(
              yetersiz ? Icons.warning_amber_rounded : Icons.account_balance_wallet,
              size: 18,
              color: color.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                yetersiz
                    ? 'Bakiyeniz yetersiz. Gerekli: ₺${orderTotal.toStringAsFixed(2)} • '
                        'Mevcut: ₺${_availableBalance.toStringAsFixed(2)}'
                    : 'Sipariş tutarı (₺${orderTotal.toStringAsFixed(2)}) bakiyenizden '
                        'tahsil edilecek • Mevcut: ₺${_availableBalance.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 12, color: color.shade900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressSection(AddressProvider addressProvider, double orderTotal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_canOfferPickup) ...[
          Card(
            color: _isPickupSelected ? Colors.blue.shade50 : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _isPickupSelected ? Colors.blue.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  value: _isPickupSelected,
                  onChanged: (value) => setState(() {
                    _isPickupSelected = value ?? false;
                    if (_isPickupSelected) {
                      // "Gel Al" siparişleri peşin olarak bakiyeden tahsil edilir:
                      // kurye yok, kapıda ödeme anlamsız; online akış da ayrı bir
                      // Edge Function kullandığı için pickup ile uyumlu değil.
                      _selectedPaymentMethod = PaymentMethod.balance;
                    }
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    '🏪 Gel Al (Mağazadan Teslim)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Siparişinizi kurye beklemeden mağazadan teslim alın - '
                    'teslimat ücreti alınmaz, tutar bakiyenizden tahsil edilir',
                  ),
                ),
                if (_isPickupSelected) _buildPickupBalanceNotice(orderTotal),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Teslimat Adresi',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddressManagementScreen(),
                  ),
                );
                // Adresler güncellendiğinde yenile
                addressProvider.loadAddresses();
              },
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Düzenle'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (addressProvider.isLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (!addressProvider.hasAddresses)
          Card(
            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddressManagementScreen(),
                  ),
                );
                addressProvider.loadAddresses();
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_location_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adres Ekle',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Teslimat için adres eklemelisiniz',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        addressProvider.selectedAddress?.title ?? 'Adres',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    addressProvider.selectedAddress?.fullName ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addressProvider.selectedAddress?.phone ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addressProvider.selectedAddress?.fullAddress ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (addressProvider.addresses.length > 1) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _showAddressSelectionDialog(addressProvider),
                      child: Text(
                        'Farklı adres seç',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showAddressSelectionDialog(AddressProvider addressProvider) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Teslimat Adresi Seç',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...addressProvider.addresses.map((address) {
              final isSelected = addressProvider.selectedAddress?.id == address.id;
              return Card(
                // ignore: deprecated_member_use
                color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                child: InkWell(
                  onTap: () {
                    addressProvider.selectAddress(address);
                    Navigator.pop(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                address.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                address.shortAddress,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ödeme Yöntemi',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              // "Gel Al" seçiliyse ödeme yalnızca bakiyeden yapılır: kurye
              // olmadığı için kapıda ödeme anlamsız, online akış ise ayrı bir
              // Edge Function kullandığından pickup ile uyumlu değil.
              if (_isPickupSelected)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gel Al siparişleri bakiyenizden peşin tahsil edilir.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              // Kapıda Nakit - admin toggle'ı (order_cod_enabled) ile
              if (!_isPickupSelected && _paymentSettings.isAvailable(PaymentMethod.cash))
                RadioListTile<PaymentMethod>(
                  title: const Text('Kapıda Nakit'),
                  subtitle: const Text('Teslimatçıya nakit ödeme'),
                  value: PaymentMethod.cash,
                  // ignore: deprecated_member_use
                  groupValue: _selectedPaymentMethod,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    setState(() => _selectedPaymentMethod = value!);
                  },
                ),
              // Kapıda Banka/Kredi Kartı - admin toggle'ı (order_card_on_delivery_enabled) ile
              if (!_isPickupSelected &&
                  _paymentSettings.isAvailable(PaymentMethod.cardOnDelivery))
                RadioListTile<PaymentMethod>(
                  title: const Text('Kapıda Banka/Kredi Kartı'),
                  subtitle: const Text('Teslimatçıda POS cihazı ile ödeme'),
                  value: PaymentMethod.cardOnDelivery,
                  // ignore: deprecated_member_use
                  groupValue: _selectedPaymentMethod,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    setState(() => _selectedPaymentMethod = value!);
                  },
                ),
              // Online Ödeme - sadece aktifse göster (online_payment_enabled).
              // "Gel Al" seçiliyse gizli: online ödeme akışı ayrı bir Edge
              // Function üzerinden sipariş oluşturuyor ve is_pickup/0 teslimat
              // ücreti bilgisini henüz taşımıyor.
              if (_onlinePaymentEnabled && !_isPickupSelected)
                RadioListTile<PaymentMethod>(
                  title: Row(
                    children: [
                      const Text('Online Ödeme'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_user, size: 12, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'iyzico',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  subtitle: const Text('Kredi/Banka kartı ile güvenli online ödeme'),
                  value: PaymentMethod.online,
                  // ignore: deprecated_member_use
                  groupValue: _selectedPaymentMethod,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    setState(() => _selectedPaymentMethod = value!);
                  },
                ),
              // Bakiye ile ödeme - admin toggle'ı (order_balance_enabled) ile.
              // Not: balance_info ayrıca balance_enabled (bakiye SİSTEMİ) kontrol eder;
              // buradaki toggle yalnızca "siparişte bakiye ile öde" seçeneğini filtreler.
              if (_paymentSettings.isAvailable(PaymentMethod.balance))
                FutureBuilder<Map<String, dynamic>?>(
                future: _loadBalanceInfo(),
                builder: (context, snapshot) {
                  final balance = snapshot.data?['balance'] as double? ?? 0;
                  
                  return Column(
                    children: [
                      const Divider(),
                      RadioListTile<PaymentMethod>(
                        value: PaymentMethod.balance,
                        groupValue: _selectedPaymentMethod,
                        onChanged: (value) {
                          setState(() => _selectedPaymentMethod = value!);
                        },
                        title: Row(
                          children: [
                            const Expanded(child: Text('Bakiye ile Ödeme')),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: balance > 0 ? Colors.green.shade100 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '₺${balance.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: balance > 0 ? Colors.green.shade800 : Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          balance > 0
                              ? 'Mevcut bakiyeniz: ₺${balance.toStringAsFixed(2)}'
                              : 'Bakiyeniz yetersiz',
                          style: TextStyle(
                            fontSize: 12,
                            color: balance > 0 ? null : Colors.orange,
                          ),
                        ),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.account_balance_wallet, color: Colors.green.shade700),
                        ),
                      ),
                    ],
                  );
                },
              ),
              
              // Online ödeme kapalıysa bilgilendirme
              if (!_onlinePaymentEnabled && !_isLoadingPaymentSettings)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Online ödeme şu an kullanılamıyor',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sipariş Notu (Opsiyonel)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Örn: Kapı kodu 1234',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummary(CartSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sipariş Özeti',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ara Toplam:'),
                    Text('₺${summary.subtotal.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 4),
                if (summary.discount > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('İndirim:'),
                      Text(
                        '-₺${summary.discount.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Teslimat:'),
                    Text('₺${_effectiveDeliveryFee(summary).toStringAsFixed(2)}'),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Toplam:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '₺${_effectiveTotal(summary).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}