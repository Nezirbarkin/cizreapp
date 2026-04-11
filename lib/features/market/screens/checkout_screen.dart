import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/cart_model.dart';
import '../../../core/models/address_model.dart';
import '../../../core/services/app_about_service.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/services/verification_service.dart';
import '../providers/address_provider.dart';
import '../providers/cart_provider.dart';
import '../../shop/services/order_service.dart';
import '../../shop/screens/payment_webview_screen.dart';
import '../services/cart_service.dart';
import 'address_management_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final String shopId;
  final String shopName;

  const CheckoutScreen({
    super.key,
    required this.shopId,
    required this.shopName,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final OrderService _orderService = OrderService();
  final CartService _cartService = CartService();
  final AppAboutService _aboutService = AppAboutService();
  final PaymentService _paymentService = PaymentService();
  final VerificationService _verificationService = VerificationService();
  final _notesController = TextEditingController();

  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _isPlacingOrder = false;
  bool _onlinePaymentEnabled = false;
  bool _isLoadingPaymentSettings = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentSettings();
  }

  Future<void> _loadPaymentSettings() async {
    try {
      final settings = await _aboutService.getAboutSettings();
      setState(() {
        _onlinePaymentEnabled = settings?.onlinePaymentEnabled ?? false;
        _isLoadingPaymentSettings = false;
      });
    } catch (e) {
      setState(() => _isLoadingPaymentSettings = false);
      debugPrint('❌ Ödeme ayarları yüklenirken hata: $e');
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<bool> _checkOrderApprovalCodeEnabled() async {
    try {
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select('order_approval_code_enabled')
          .single();
      return response['order_approval_code_enabled'] ?? true;
    } catch (e) {
      debugPrint('Onay kodu ayarı kontrolü hatası: $e');
      return true;
    }
  }

  Future<bool?> _showVerificationDialog() async {
    String verificationCode = '';
    String? verificationId;
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
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result['message'] ?? 'Kod bildirim olarak gönderildi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                setDialogState(() => isSending = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Güvenlik için size gönderilen 6 haneli kodu girin.',
                  style: TextStyle(fontSize: 14),
                ),
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
                              setDialogState(() {
                                verificationId = result['verification_id'];
                                expiresInSeconds = result['expires_in_seconds'] ?? 300;
                                codeSentTime = DateTime.now();
                                isSending = false;
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(result['message'] ?? 'Kod gönderildi'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              setDialogState(() => isSending = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Hata: $e'),
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
                                  content: Text(result['message'] ?? 'Kod hatalı'),
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

    // Onay kodu gerekmedi veya doğrulandı, devam et
    final summary = await _cartService.getCartSummary(Supabase.instance.client.auth.currentUser!.id);
    
    showDialog(
      // ignore: use_build_context_synchronously
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
              _buildConfirmationRow(Icons.location_on, 'Adres:', selectedAddress.title),
              _buildConfirmationRow(
                Icons.payment,
                'Ödeme:',
                _selectedPaymentMethod == PaymentMethod.cash
                    ? 'Kapıda Nakit'
                    : (_selectedPaymentMethod == PaymentMethod.cardOnDelivery
                        ? 'Kapıda Banka/Kredi Kartı'
                        : 'Online Ödeme'),
              ),
              const Divider(height: 24),
              // Ürünler
              ...summary.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.productName ?? "Ürün"}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('₺${((item.productPrice ?? 0) * item.quantity).toStringAsFixed(2)}'),
                  ],
                ),
              )),
              const Divider(height: 24),
              // Ara toplam
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
              if (summary.discount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('İndirim:', style: TextStyle(color: Colors.green)),
                    Text('-₺${summary.discount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green)),
                  ],
                ),
              ],
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOPLAM:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    '₺${summary.total.toStringAsFixed(2)}',
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
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmOrder(selectedAddress, cartProvider);
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

  Future<void> _confirmOrder(Address selectedAddress, CartProvider cartProvider) async {
    setState(() => _isPlacingOrder = true);
    
    // Online ödeme seçildiyse iyzico akışını başlat
    if (_selectedPaymentMethod == PaymentMethod.online) {
      await _initiateOnlinePayment(selectedAddress, cartProvider);
    } else {
      await _placeOrder(selectedAddress, cartProvider);
    }
  }

  /// Online ödeme (iyzico) akışını başlat
  Future<void> _initiateOnlinePayment(Address selectedAddress, CartProvider cartProvider) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isPlacingOrder = false);
      return;
    }

    try {
      // Sepeti getir
      final cartSummary = await _cartService.getCartSummary(user.id);
      if (cartSummary.items.isEmpty) {
        throw Exception('Sepetiniz boş');
      }

      // Kullanıcı profil bilgilerini al
      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('full_name, email, phone')
          .eq('id', user.id)
          .single();

      final fullName = (profileResponse['full_name'] as String?) ?? 'Müşteri';
      final nameParts = fullName.split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : 'Müşteri';
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : 'Müşteri';
      final email = (profileResponse['email'] as String?) ?? user.email ?? 'musteri@cizreapp.com';
      final phone = (profileResponse['phone'] as String?) ?? selectedAddress.phone;

      // Sipariş verilerini hazırla
      final orderData = {
        'shop_id': widget.shopId,
        'items': cartSummary.items.map((item) => {
          'product_id': item.productId,
          'product_name': item.productName ?? 'Ürün',
          'quantity': item.quantity,
          'price': item.productPrice ?? 0,
        }).toList(),
        'delivery_address_text': selectedAddress.fullAddress,
        'delivery_address_id': selectedAddress.id,
        'total': cartSummary.total,
        'subtotal': cartSummary.subtotal,
        'delivery_fee': cartSummary.deliveryFee,
        'coupon_discount': cartSummary.discount,
        'note': _notesController.text.isNotEmpty ? _notesController.text : null,
      };

      // Buyer bilgileri
      final buyer = {
        'id': user.id,
        'name': firstName,
        'surname': lastName,
        'email': email,
        'phone': phone,
        'identityNumber': '11111111111',
        'address': selectedAddress.fullAddress,
        'city': 'Şırnak',
        'country': 'Turkey',
        'zipCode': '73200',
      };

      debugPrint('💳 MARKET CHECKOUT: iyzico ödeme başlatılıyor...');

      // iyzico ödeme başlat
      final result = await _paymentService.initializePayment(
        orderData: orderData,
        buyer: buyer,
      );

      setState(() => _isPlacingOrder = false);

      if (!mounted) return;

      // WebView ekranına git
      final paymentResult = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentWebViewScreen(
            paymentUrl: result.paymentPageUrl,
            paymentTransactionId: result.paymentTransactionId,
            conversationId: result.conversationId,
            onPaymentSuccess: () async {
              // Sepeti temizle
              await _cartService.clearCart(user.id);
              if (mounted) {
                await cartProvider.clearCart();
              }
            },
          ),
        ),
      );

      debugPrint('💳 MARKET CHECKOUT: WebView kapandı, result: $paymentResult');

    } catch (e) {
      setState(() => _isPlacingOrder = false);
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

  Future<void> _placeOrder(Address? selectedAddress, CartProvider cartProvider) async {
    if (selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen teslimat adresi seçin')),
      );
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isPlacingOrder = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen giriş yapın')),
        );
      }
      return;
    }

    try {
      // Sepeti getir ve teslimat ücretiyle birlikte toplam hesapla
      final cartSummary = await _cartService.getCartSummary(userId);
      if (cartSummary.items.isEmpty) {
        throw Exception('Sepetiniz boş');
      }

      // Müşteri telefon numarasını seçili adresten al
      final customerPhone = selectedAddress.phone;

      // Dükkan bilgisini çek ve minimum tutarı kontrol et
      final shop = await Supabase.instance.client
          .from('shops')
          .select('min_order_amount, name')
          .eq('id', widget.shopId)
          .single();
      
      final minOrderAmount = (shop['min_order_amount'] as num?)?.toDouble() ?? 0.0;
      final shopName = shop['name'] as String? ?? 'Dükkan';
      
      if (minOrderAmount > 0 && cartSummary.subtotal < minOrderAmount) {
        final remaining = minOrderAmount - cartSummary.subtotal;
        
        setState(() => _isPlacingOrder = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$shopName\n'
                'Minimum sipariş tutarı: ₺${minOrderAmount.toStringAsFixed(2)}\n'
                'Mevcut tutar: ₺${cartSummary.subtotal.toStringAsFixed(2)}\n'
                'Eksik tutar: ₺${remaining.toStringAsFixed(2)}',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Sipariş öğelerini hazırla
      final orderItems = cartSummary.items.map((item) {
        return OrderItem(
          id: '',
          orderId: '',
          productId: item.productId,
          productName: item.productName ?? 'Ürün',
          price: item.productPrice ?? 0,
          quantity: item.quantity,
          productImageUrl: item.productImageUrl,
          shopId: item.shopId,
          shopName: item.shopName,
          createdAt: DateTime.now(),
        );
      }).toList();

      // Siparişi oluştur
      final order = await _orderService.createOrder(
        userId: userId,
        shopId: widget.shopId,
        items: orderItems,
        deliveryAddressText: selectedAddress.fullAddress,
        addressId: selectedAddress.id,
        subtotal: cartSummary.subtotal,
        deliveryFee: cartSummary.deliveryFee,
        discount: cartSummary.discount,
        total: cartSummary.total,
        commissionAmount: cartSummary.subtotal * 0.10, // %10 komisyon
        paymentMethod: _selectedPaymentMethod,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        customerPhone: customerPhone,
      );

      if (order != null) {
        // Sepeti temizle (hem database hem UI state)
        await _cartService.clearCart(userId);
        await cartProvider.clearCart(); // CartProvider'ı da temizle

        if (mounted) {
          // Ana sayfaya dön ve MainScreen'deki CartProvider'ı da yenile
          Navigator.of(context).popUntil((route) => route.isFirst);
          
          // MainScreen'deki CartProvider'a erişip yeniden yükle
          // Biraz gecikme ile çünkü navigation tamamlanmalı
          Future.delayed(const Duration(milliseconds: 100), () {
            if (context.mounted) {
              // MainScreen context'inden CartProvider'a eriş
              // ignore: use_build_context_synchronously
              final mainCartProvider = context.read<CartProvider>();
              mainCartProvider.loadCart();
            }
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Siparişiniz başarıyla oluşturuldu!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isPlacingOrder = false);
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
            child: FutureBuilder<CartSummary>(
              future: _cartService.getCartSummary(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Sepetiniz boş'));
                }

                final summary = snapshot.data!;

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
                      _buildAddressSection(addressProvider),
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

  Widget _buildAddressSection(AddressProvider addressProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              // Online Ödeme - sadece aktifse göster
              if (_onlinePaymentEnabled)
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
                    Text('₺${summary.deliveryFee.toStringAsFixed(2)}'),
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
                      '₺${summary.total.toStringAsFixed(2)}',
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