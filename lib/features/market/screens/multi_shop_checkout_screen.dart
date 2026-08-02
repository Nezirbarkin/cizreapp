// ignore_for_file: deprecated_member_use, unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/address_model.dart';
import '../../../core/models/invoice_info_model.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/services/verification_service.dart';
import '../../../core/services/payment_method_settings_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/invoice_info_widget.dart';
import '../providers/address_provider.dart';
import '../providers/cart_provider.dart';
import '../../shop/services/order_service.dart';
import '../services/cart_service.dart';
import '../services/multi_shop_checkout_mapper.dart';
import 'address_management_screen.dart';
import 'shop_detail_screen.dart';

/// Çok dükkanlı checkout ekranı
/// Sepette birden fazla dükkandan ürün varsa bu ekran kullanılır
class MultiShopCheckoutScreen extends StatefulWidget {
  const MultiShopCheckoutScreen({super.key});

  @override
  State<MultiShopCheckoutScreen> createState() =>
      _MultiShopCheckoutScreenState();
}

class _MultiShopCheckoutScreenState extends State<MultiShopCheckoutScreen> {
  final OrderService _orderService = OrderService();
  final CartService _cartService = CartService();
  final BalanceService _balanceService = BalanceService();
  final VerificationService _verificationService = VerificationService();
  final InvoiceService _invoiceService = InvoiceService();
  final _notesController = TextEditingController();

  // Fatura bilgileri
  InvoiceInfo? _selectedInvoiceInfo;

  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _isPlacingOrder = false;
  bool _isLoading = true;
  bool _onlinePaymentEnabled = false;
  bool _isLoadingPaymentSettings = true;
  double _userBalance = 0;

  /// Admin panelden kontrol edilen sipariş ödeme yöntemi toggle'ları.
  /// load() başarısız olursa allEnabled() fallback döner (mevcut davranış korunur).
  PaymentMethodSettings _paymentSettings =
      const PaymentMethodSettings.allEnabled();

  Map<String, ShopCartSummary> _shopSummaries = {};
  double _grandTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadCartData();
    _loadPaymentSettings();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<bool> _checkOrderApprovalCodeEnabled() async {
    try {
      final response = await _supabase
          .from('app_about_settings')
          .select('order_approval_code_enabled')
          .single();
      return response['order_approval_code_enabled'] ?? true;
    } catch (e) {
      debugPrint('Onay kodu ayarı kontrolü hatası: $e');
      return true;
    }
  }

  Future<void> _loadPaymentSettings() async {
    try {
      // Bakiye bilgisini yükle
      double balance = 0;
      try {
        final balanceData = await _balanceService.getBalance();
        balance = balanceData?.availableBalance ?? 0;
      } catch (e) {
        debugPrint('Bakiye bilgisi yüklenemedi: $e');
      }

      // Tek sorgu ile online_payment_enabled + 3 sipariş toggle'ı çekilir.
      final methodSettings = await PaymentMethodSettings.load();

      if (!mounted) return;
      setState(() {
        _paymentSettings = methodSettings;
        // Tek gerçek kaynak: online_payment_enabled kolonu hem eski
        // _onlinePaymentEnabled hem helper.onlineEnabled tarafından okunur.
        _onlinePaymentEnabled = methodSettings.onlineEnabled;
        _userBalance = balance;
        _isLoadingPaymentSettings = false;
        // Admin bir yöntemi kapattıysa seçili yöntem aktif değilse
        // ilk aktif yönteme otomatik kay (kullanıcı boş seçimde kalmaz).
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

  Future<void> _loadCartData() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // CartProvider'dan shop-scoped kupon state'ini al.
      final cartProvider = context.read<CartProvider>();
      final couponsByShop = cartProvider.couponsByShop;
      debugPrint('🛒 MULTI-SHOP CHECKOUT: couponsByShop=$couponsByShop');

      final summaries = await _cartService.groupCartByShop(
        userId,
        couponsByShop: couponsByShop,
      );

      double total = 0;
      for (final summary in summaries.values) {
        total += summary.total;
        debugPrint(
          '🛒 MULTI-SHOP CHECKOUT: shop=${summary.shopName} '
          'subtotal=${summary.subtotal} discount=${summary.discount} '
          'total=${summary.total} couponCode=${summary.couponCode}',
        );
      }
      debugPrint('🛒 MULTI-SHOP CHECKOUT: grandTotal=$total');

      setState(() {
        _shopSummaries = summaries;
        _grandTotal = total;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Sepet verileri yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _placeOrder(Address selectedAddress) async {
    if (_isPlacingOrder) return;

    setState(() => _isPlacingOrder = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı oturumu bulunamadı');
      }

      // Bakiye ile ödeme kontrolü
      if (_selectedPaymentMethod == PaymentMethod.balance) {
        if (_userBalance < _grandTotal) {
          setState(() => _isPlacingOrder = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Yetersiz bakiye! Mevcut: ₺${_userBalance.toStringAsFixed(2)}, Gerekli: ₺${_grandTotal.toStringAsFixed(2)}',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      // Minimum sipariş tutarı kontrolü - Tüm dükkanları kontrol et
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final failedShops = <String, double>{};

      for (final entry in _shopSummaries.entries) {
        final shopId = entry.key;
        if (!cartProvider.meetsMinOrderAmount(shopId)) {
          final shop = cartProvider.getShop(shopId);
          final remaining = cartProvider.getRemainingForMinOrder(shopId);
          if (shop != null) {
            failedShops['${shop.name} (Min: ₺${shop.minOrderAmount.toStringAsFixed(2)})'] =
                remaining;
          }
        }
      }

      if (failedShops.isNotEmpty) {
        setState(() => _isPlacingOrder = false);
        if (mounted) {
          final message = failedShops.entries
              .map((e) => '${e.key}\nEksik: ₺${e.value.toStringAsFixed(2)}')
              .join('\n\n');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Minimum sipariş tutarı karşılanmıyor:\n\n$message',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Her dükkan için OrderItem listesi oluştur
      final Map<String, List<OrderItem>> itemsByShop = {};

      for (final entry in _shopSummaries.entries) {
        final shopId = entry.key;
        final summary = entry.value;

        itemsByShop[shopId] = summary.items
            .map(
              (cartItem) => OrderItem(
                id: '',
                orderId: '',
                productId: cartItem.productId,
                productName: cartItem.productName ?? 'Ürün',
                price: cartItem
                    .effectivePrice, // flaş sale ise flaş, yoksa indirimli (discount_price), yoksa normal fiyat
                quantity: cartItem.quantity,
                productImageUrl: cartItem.productImageUrl,
                shopId: cartItem.shopId,
                shopName: cartItem.shopName,
                createdAt: DateTime.now(),
                flashSaleId: cartItem.flashSaleId,
                flashPrice: cartItem.flashPrice,
              ),
            )
            .toList();
      }

      // Teslimat adresi metni
      final addressText =
          '${selectedAddress.title} - ${selectedAddress.fullAddress}';

      // Çok dükkanlı sipariş oluştur
      // `discountByShop` her dükkan için kupon/indirim tutarını taşır.
      // (2026-07-29 FIX) Eskiden bu parametre geçilmiyordu ve OrderService
      // `discountByShop?[shopId] ?? 0.0` ile çalışıyordu — yani kupon
      // uygulansa bile DB'ye `discount=0` yazılıyordu. Artık summary üzerinden
      // doğru değer geçiriliyor.
      final discountByShop = buildDiscountByShop(_shopSummaries);
      final couponIdByShop = <String, String?>{};
      final couponDiscountByShop = <String, double>{};
      final couponsByShopMap = cartProvider.couponsByShop;
      for (final entry in _shopSummaries.entries) {
        final shopId = entry.key;
        // Kupon kimliği ve indirimi (orders.coupon_id / coupon_discount).
        // summary.discount zaten clamped kupon indirimi (groupCartByShop).
        couponIdByShop[shopId] = couponsByShopMap[shopId]?.id;
        couponDiscountByShop[shopId] = entry.value.discount;
      }

      final result = await _orderService.createMultiShopOrder(
        userId: userId,
        itemsByShop: itemsByShop,
        deliveryAddressText: addressText,
        addressId: selectedAddress.id,
        paymentMethod: _selectedPaymentMethod,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        customerPhone: selectedAddress.phone,
        invoiceInfo: _selectedInvoiceInfo,
        discountByShop: discountByShop,
        couponIdByShop: couponIdByShop,
        couponDiscountByShop: couponDiscountByShop,
      );

      // Kuponları "kullanıldı" olarak işaretle (use_coupon RPC).
      // Eskiden multi-shop bu RPC'yi hiç çağırmıyordu → kuponlar sonsuz tekrar
      // kullanılabiliyordu. Bakiye yolunda yalnızca ödenen siparişler için.
      Future<void> markCouponUsed(Order order) async {
        final coupon = couponsByShopMap[order.shopId];
        if (coupon == null) return;
        final discount = couponDiscountByShop[order.shopId] ?? 0.0;
        if (discount <= 0) return;
        try {
          await _supabase.rpc(
            'use_coupon',
            params: {
              'p_coupon_id': coupon.id,
              'p_order_id': order.id,
              'p_user_id': userId,
              'p_discount_amount': discount,
            },
          );
        } catch (e) {
          debugPrint('❌ use_coupon RPC başarısız (${order.shopId}): $e');
        }
      }

      // Bakiye dışındaki yöntemlerde sipariş oluşturulduktan sonra işaretle.
      if (_selectedPaymentMethod != PaymentMethod.balance) {
        for (final order in result.orders) {
          await markCouponUsed(order);
        }
      }

      // Bakiye ile ödeme ise sipariş sipariş dene; başarısız siparişleri iptal et.
      if (_selectedPaymentMethod == PaymentMethod.balance &&
          result.orders.isNotEmpty) {
        final paidOrders = <String>[];
        final failedOrders = <String>[];
        for (final order in result.orders) {
          try {
            await _balanceService.useBalanceForOrder(
              orderId: order.id,
              amount: order.totalAmount,
              orderTotal: order.totalAmount,
            );
            paidOrders.add(order.id);
            // Bakiye yolu: kuponu yalnızca ödeme başarılı olunca işaretle.
            await markCouponUsed(order);
            debugPrint('✅ Dükkan siparişi bakiye ile ödendi: ${order.id}');
          } catch (balanceError) {
            debugPrint(
              '❌ Dükkan siparişi için bakiye düşülemedi (${order.id}): $balanceError',
            );
            failedOrders.add(order.id);
            try {
              await _orderService.cancelOrder(
                order.id,
                reason: 'Bakiye düşme başarısız: $balanceError',
              );
              debugPrint('✅ Ödenmeyen sipariş iptal edildi: ${order.id}');
            } catch (cancelError) {
              debugPrint('❌ Ödenmeyen sipariş iptal hatası: $cancelError');
            }
          }
        }

        // Tüm siparişler başarısızsa kullanıcıya bildir, hiçbir şeyi temizleme
        if (paidOrders.isEmpty) {
          throw Exception(
            'Bakiye yetersiz veya ödeme başarısız. Hiçbir sipariş oluşturulmadı.',
          );
        }

        // Kısmi başarı varsa kullanıcıya bildir
        if (failedOrders.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${failedOrders.length} sipariş iptal edildi (bakiye yetersiz). ${paidOrders.length} sipariş ödendi.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }

      // Sepeti sadece en az bir sipariş başarıyla ödendiyse temizle
      await cartProvider.clearCart();

      if (mounted) {
        Navigator.pop(context); // Checkout ekranını kapat

        // Başarı mesajı göster
        String paymentInfo = '';
        if (_selectedPaymentMethod == PaymentMethod.balance) {
          paymentInfo =
              ' (₺${_grandTotal.toStringAsFixed(2)} bakiyenizden ödendi)';
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text('Sipariş Alındı!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.orderCount} dükkan için sipariş oluşturuldu.$paymentInfo',
                ),
                const SizedBox(height: 12),
                Text(
                  'Sipariş Grup No: ${result.groupOrderNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Siparişlerinizi "Siparişlerim" sayfasından takip edebilirsiniz.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Ana sayfaya yönlendir
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Sipariş oluşturulurken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sipariş oluşturulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPlacingOrder = false);
      }
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
              setDialogState(() => isSending = true);
              try {
                final result = await _verificationService.sendVerificationCode(
                  codeType: 'order_verification',
                );
                setDialogState(() {
                  verificationId = result['verification_id'];
                  expiresInSeconds = result['expires_in_seconds'] ?? 300;
                  codeSentTime = DateTime.now();
                  isSending = false;
                  // Kodu al ve ekranda göster
                  displayedCode = result['code']?.toString();
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result['message'] ?? 'Kod bildirim olarak gönderildi',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                setDialogState(() => isSending = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.userMessage),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
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
                  if (kDebugMode &&
                      displayedCode != null &&
                      displayedCode!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.shade300,
                          width: 2,
                        ),
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
                                final result = await _verificationService
                                    .sendVerificationCode(
                                      codeType: 'order_verification',
                                    );
                                setDialogState(() {
                                  verificationId = result['verification_id'];
                                  expiresInSeconds =
                                      result['expires_in_seconds'] ?? 300;
                                  codeSentTime = DateTime.now();
                                  isSending = false;
                                  // Yeni kodu al ve ekranda göster
                                  displayedCode = result['code']?.toString();
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        result['message'] ?? 'Kod gönderildi',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setDialogState(() => isSending = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.userMessage),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      icon: isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        remainingSeconds > 0
                            ? 'Yeniden gönder ($remainingSeconds sn)'
                            : (verificationId != null
                                  ? 'Kodu Yeniden Gönder'
                                  : 'Kod Gönder'),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isVerifying
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed:
                    (isVerifying ||
                        verificationId == null ||
                        verificationCode.length != 6)
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
                              Navigator.pop(context, true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Kod doğrulandı!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            setDialogState(() => isVerifying = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result['message'] ?? 'Kod hatalı',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          setDialogState(() => isVerifying = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Doğrulama hatası: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: isVerifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Doğrula'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showConfirmationDialog(Address selectedAddress) async {
    // Online ödeme kontrolü - çoklu dükkan siparişlerinde desteklenmiyor
    if (_selectedPaymentMethod == PaymentMethod.online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Online ödeme çok dükkanlı siparişlerde henüz desteklenmiyor.\n'
            'Lütfen "Kapıda Nakit" veya "Kapıda Banka/Kredi Kartı" seçeneğini kullanın.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

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

    // Onay kodu doğrulandı, devam et
    _showOrderConfirmationDialog(selectedAddress);
  }

  void _showOrderConfirmationDialog(Address selectedAddress) {
    showDialog(
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
              _buildConfirmationRow(
                Icons.location_on,
                'Adres:',
                selectedAddress.title,
              ),
              _buildConfirmationRow(
                Icons.payment,
                'Ödeme:',
                _selectedPaymentMethod == PaymentMethod.cash
                    ? 'Kapıda Nakit'
                    : (_selectedPaymentMethod == PaymentMethod.cardOnDelivery
                          ? 'Kapıda Banka/Kredi Kartı'
                          : (_selectedPaymentMethod == PaymentMethod.balance
                                ? 'Bakiye ile Ödeme'
                                : 'Online Ödeme')),
              ),
              const Divider(height: 24),
              Text(
                '${_shopSummaries.length} dükkan',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._shopSummaries.values.map(
                (summary) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          summary.shopName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('₺${summary.total.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'GENEL TOPLAM:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    '₺${_grandTotal.toStringAsFixed(2)}',
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
              if (_selectedPaymentMethod == PaymentMethod.cardOnDelivery)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.credit_card, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Teslimatçıya POS cihazında ödeme alacaktır',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_selectedPaymentMethod == PaymentMethod.balance)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bakiyenizden ödenecek',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Mevcut bakiye: ₺${_userBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
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
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _placeOrder(selectedAddress);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Siparişi Onayla'),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sipariş Onayı'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shopSummaries.isEmpty
          ? const Center(child: Text('Sepetiniz boş'))
          : Consumer<AddressProvider>(
              builder: (context, addressProvider, child) {
                final addresses = addressProvider.addresses;
                final selectedAddress = addressProvider.selectedAddress;

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Adres Seçimi
                            _buildAddressSection(
                              addresses,
                              selectedAddress,
                              addressProvider,
                            ),
                            const SizedBox(height: 24),

                            // Dükkanlar ve Ürünler
                            _buildShopsSection(),
                            const SizedBox(height: 24),

                            // Fatura Bilgileri
                            InvoiceInfoSelector(
                              invoiceService: _invoiceService,
                              addressInfo: selectedAddress != null
                                  ? AddressInfo(
                                      fullName: selectedAddress.fullName,
                                      address: selectedAddress.fullAddress,
                                    )
                                  : null,
                              onInvoiceChanged: (info) {
                                setState(() => _selectedInvoiceInfo = info);
                              },
                            ),
                            const SizedBox(height: 24),

                            // Ödeme Yöntemi
                            _buildPaymentSection(),
                            const SizedBox(height: 24),

                            // Sipariş Notu
                            _buildNotesSection(),
                          ],
                        ),
                      ),
                    ),

                    // Alt Toplam ve Sipariş Butonu
                    _buildBottomBar(selectedAddress),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildAddressSection(
    List<Address> addresses,
    Address? selectedAddress,
    AddressProvider addressProvider,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Teslimat Adresi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (addresses.isEmpty)
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddressManagementScreen(),
                    ),
                  );
                  addressProvider.loadAddresses();
                },
                icon: const Icon(Icons.add),
                label: const Text('Adres Ekle'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              )
            else
              Column(
                children: [
                  ...addresses.map(
                    (address) => RadioListTile<String>(
                      value: address.id,
                      groupValue: selectedAddress?.id,
                      onChanged: (value) {
                        if (value != null) {
                          addressProvider.selectAddress(address);
                        }
                      },
                      title: Text(
                        address.title,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        address.fullAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddressManagementScreen(),
                        ),
                      );
                      addressProvider.loadAddresses();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Yeni Adres Ekle'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shopping_bag, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Text(
              '${_shopSummaries.length} Dükkan',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._shopSummaries.values.map((summary) => _buildShopCard(summary)),
      ],
    );
  }

  Widget _buildShopCard(ShopCartSummary summary) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dükkan başlığı - tıklanabilir
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopDetailScreen(shopId: summary.shopId),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.store, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summary.shopName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),

            // Ürünler
            ...summary.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (item.productImageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: item.productImageUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image, size: 20),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.image, size: 20),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName ?? 'Ürün',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${item.quantity} x ₺${item.effectivePrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₺${(item.effectivePrice * item.quantity).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 24),

            // Ara toplam ve teslimat
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ara Toplam:'),
                Text('₺${summary.subtotal.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Teslimat:'),
                Text('₺${summary.deliveryFee.toStringAsFixed(2)}'),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Toplam:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '₺${summary.total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Ödeme Yöntemi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Kapıda Nakit - admin toggle'ı (order_cod_enabled) ile
            if (_paymentSettings.isAvailable(PaymentMethod.cash))
              RadioListTile<PaymentMethod>(
                value: PaymentMethod.cash,
                groupValue: _selectedPaymentMethod,
                onChanged: (value) =>
                    setState(() => _selectedPaymentMethod = value!),
                title: const Text('Kapıda Nakit'),
                subtitle: const Text('Teslimatçıya nakit ödeme'),
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.orange.shade700,
              ),
            // Kapıda Banka/Kredi Kartı - admin toggle'ı (order_card_on_delivery_enabled) ile
            if (_paymentSettings.isAvailable(PaymentMethod.cardOnDelivery))
              RadioListTile<PaymentMethod>(
                value: PaymentMethod.cardOnDelivery,
                groupValue: _selectedPaymentMethod,
                onChanged: (value) =>
                    setState(() => _selectedPaymentMethod = value!),
                title: const Text('Kapıda Banka/Kredi Kartı'),
                subtitle: const Text('Teslimatçıya kart ile ödeme (POS)'),
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.orange.shade700,
              ),
            // Online ödeme çok dükkanlı siparişte DESTEKLENMİYOR (iyzico akışı
            // tek siparişe bağlı). Eskiden radyo gösterilip onayda snackbar ile
            // engelleniyordu — kullanıcı boşuna seçiyordu. Artık radyo gizli;
            // yalnızca online açıkken bilgilendirme notu gösterilir.
            if (_onlinePaymentEnabled && !_isLoadingPaymentSettings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
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
                          'Online ödeme çok dükkanlı siparişlerde desteklenmiyor. Tek dükkan için kullanabilirsiniz.',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_onlinePaymentEnabled && !_isLoadingPaymentSettings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
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
                          'Online ödeme şu an kullanılamıyor',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Bakiye ile ödeme - admin toggle'ı (order_balance_enabled) ile.
            // Not: balance_enabled (bakiye SİSTEMİ) ayrı master anahtardır.
            if (_paymentSettings.isAvailable(PaymentMethod.balance)) ...[
              const Divider(),
              RadioListTile<PaymentMethod>(
                value: PaymentMethod.balance,
                groupValue: _selectedPaymentMethod,
                onChanged: (value) =>
                    setState(() => _selectedPaymentMethod = value!),
                title: Row(
                  children: [
                    const Text('Bakiye ile Ödeme'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _userBalance > 0
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '₺${_userBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: _userBalance > 0
                              ? Colors.green.shade800
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  _userBalance > 0
                      ? 'Mevcut bakiyeniz: ₺${_userBalance.toStringAsFixed(2)}'
                      : 'Bakiyeniz yetersiz',
                  style: TextStyle(
                    fontSize: 12,
                    color: _userBalance > 0 ? null : Colors.orange,
                  ),
                ),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: Colors.green.shade700,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.orange.shade700,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notes, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Sipariş Notu',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                hintText: 'Siparişiniz için notunuz varsa yazabilirsiniz...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(Address? selectedAddress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_shopSummaries.length} dükkan',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const Text(
                      'GENEL TOPLAM',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  '₺${_grandTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (selectedAddress == null || _isPlacingOrder)
                    ? null
                    : () => _showConfirmationDialog(selectedAddress),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isPlacingOrder
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        selectedAddress == null
                            ? 'Lütfen Adres Seçin'
                            : 'Siparişi Onayla',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
