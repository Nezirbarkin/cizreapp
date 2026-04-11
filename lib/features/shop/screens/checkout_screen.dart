// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_screen.dart';
import 'payment_webview_screen.dart';
import '../services/order_service.dart';
import '../services/cart_service.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/address_model.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/services/app_about_service.dart';
import '../../../core/services/verification_service.dart';
import '../../../features/market/providers/cart_provider.dart';
import '../../../features/market/services/address_service.dart';
import '../../../features/market/screens/address_management_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final List<CartItemWithProduct> cartItems;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final double discountAmount;
  final String? appliedCoupon;

  const CheckoutScreen({
    super.key,
    required this.cartItems,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.discountAmount = 0,
    this.appliedCoupon,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final OrderService _orderService = OrderService();
  final CartService _cartService = CartService();
  final AddressService _addressService = AddressService();
  final PaymentService _paymentService = PaymentService();
  final AppAboutService _aboutService = AppAboutService();
  final VerificationService _verificationService = VerificationService();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _isPlacingOrder = false;
  List<Address> _addresses = [];
  Address? _selectedAddress;
  bool _isLoadingAddresses = true;
  bool _onlinePaymentEnabled = false;
  bool _isLoadingPaymentSettings = true;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
    _loadPaymentSettings();
  }

  Future<void> _loadAddresses() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final addresses = await _addressService.getUserAddresses(userId);
      setState(() {
        _addresses = addresses;
        _isLoadingAddresses = false;
        // Varsayılan adresi seç
        if (addresses.isNotEmpty) {
          _selectedAddress = addresses.firstWhere(
            (addr) => addr.isDefault,
            orElse: () => addresses.first,
          );
          _addressController.text = _selectedAddress!.fullAddress;
        }
      });
    } catch (e) {
      setState(() => _isLoadingAddresses = false);
      debugPrint('Adresler yüklenirken hata: $e');
    }
  }

  Future<void> _loadPaymentSettings() async {
    try {
      final settings = await _aboutService.getAboutSettings();
      setState(() {
        _onlinePaymentEnabled = settings?.onlinePaymentEnabled ?? false;
        _isLoadingPaymentSettings = false;
      });
      debugPrint('💳 Online ödeme durumu: $_onlinePaymentEnabled');
    } catch (e) {
      setState(() => _isLoadingPaymentSettings = false);
      debugPrint('❌ Ödeme ayarları yüklenirken hata: $e');
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Sipariş onayla butonuna basıldığında
  Future<void> _handleOrderSubmit() async {
    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen teslimat adresi girin')),
      );
      return;
    }

    // Online ödeme seçildiyse iyzico akışını başlat
    if (_selectedPaymentMethod == PaymentMethod.online) {
      await _initiateOnlinePayment();
    } else {
      // Kapıda ödeme - admin ayarına göre onay kodu iste
      final approvalCodeEnabled = await _checkOrderApprovalCodeEnabled();
      if (approvalCodeEnabled) {
        // Onay kodu gerekli - dialog göster
        final verified = await _showVerificationDialog();
        if (verified == true) {
          await _placeOrder();
        }
      } else {
        // Onay kodu gerekmi - direkt sipariş ver
        await _placeOrder();
      }
    }
  }

  /// Sipariş onay kodu ayarını kontrol et
  Future<bool> _checkOrderApprovalCodeEnabled() async {
    try {
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select('order_approval_code_enabled')
          .single();
      return response['order_approval_code_enabled'] ?? true;
    } catch (e) {
      debugPrint('Onay kodu ayarı kontrolü hatası: $e');
      return true; // Hata durumunda varsayılan: açık
    }
  }

  /// Online ödeme (iyzico) akışını başlat
  Future<void> _initiateOnlinePayment() async {
    setState(() => _isPlacingOrder = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isPlacingOrder = false);
      return;
    }

    try {
      final shopId = widget.cartItems.first.product.shopId;
      final finalTotal = widget.subtotal - widget.discountAmount + widget.deliveryFee;

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
      final phone = (profileResponse['phone'] as String?) ?? (_selectedAddress?.phone ?? '5551234567');
      
      // Müşteri telefon numarasını seçili adresten al
      final customerPhone = _selectedAddress?.phone;

      // Sipariş verilerini hazırla (Edge Function'a gönderilecek)
      final orderData = {
        'shop_id': shopId,
        'items': widget.cartItems.map((item) => {
          'product_id': item.product.id,
          'product_name': item.product.name,
          'quantity': item.cartItem.quantity,
          'price': item.product.effectivePrice,
        }).toList(),
        'delivery_address_text': _addressController.text,
        'delivery_address_id': _selectedAddress?.id,
        'customer_phone': customerPhone, // Müşteri telefonu eklendi
        'total': finalTotal,
        'subtotal': widget.subtotal,
        'delivery_fee': widget.deliveryFee,
        'coupon_discount': widget.discountAmount,
        'note': _notesController.text.isNotEmpty ? _notesController.text : null,
      };

      // Buyer bilgileri
      final buyer = {
        'id': user.id,
        'name': firstName,
        'surname': lastName,
        'email': email,
        'phone': phone,
        'identityNumber': '11111111111', // Varsayılan TC kimlik
        'address': _addressController.text,
        'city': _selectedAddress?.city ?? 'Şırnak',
        'country': 'Turkey',
        'zipCode': '73200', // Sabit posta kodu (Address modelinde zipCode yok)
      };

      debugPrint('💳 CHECKOUT: iyzico ödeme başlatılıyor...');

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
                try {
                  final cartProvider = Provider.of<CartProvider>(context, listen: false);
                  await cartProvider.clearCart();
                } catch (e) {
                  debugPrint('⚠️ CartProvider bulunamadı: $e');
                }
              }
            },
          ),
        ),
      );

      // Ödeme sonucu WebView tarafından yönetiliyor (PaymentWebViewScreen)
      debugPrint('💳 CHECKOUT: WebView kapandı, result: $paymentResult');

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

  /// Kapıda ödeme sipariş oluşturma (mevcut akış)
  Future<void> _placeOrder() async {
    setState(() => _isPlacingOrder = true);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isPlacingOrder = false);
      return;
    }

    try {
      // Müşteri telefon numarasını seçili adresten al
      final customerPhone = _selectedAddress?.phone;

      // Dükkân ID'sini al (tüm ürünler aynı dükkândan olmalı)
      final shopId = widget.cartItems.first.product.shopId;

      // Sipariş öğelerini hazırla
      final orderItems = widget.cartItems
          .map((item) => OrderItem(
                id: '',
                orderId: '',
                productId: item.product.id,
                productName: item.product.name,
                price: item.product.effectivePrice,
                quantity: item.cartItem.quantity,
                createdAt: DateTime.now(),
              ))
          .toList();

      // Komisyon hesapla (%10) - indirim sonrası subtotal'den
      final discountedSubtotal = widget.subtotal - widget.discountAmount;
      final commissionAmount = discountedSubtotal * 0.10;
      
      // Gerçek toplam (indirim dahil)
      final finalTotal = widget.subtotal - widget.discountAmount + widget.deliveryFee;

      // Siparişi oluştur
      await _orderService.createOrder(
        userId: userId,
        shopId: shopId,
        items: orderItems,
        deliveryAddressText: _addressController.text,
        addressId: _selectedAddress?.id, // Kayıtlı adres ID'sini gönder
        subtotal: widget.subtotal,
        deliveryFee: widget.deliveryFee,
        discount: widget.discountAmount,
        total: finalTotal,
        commissionAmount: commissionAmount,
        paymentMethod: _selectedPaymentMethod,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        customerPhone: customerPhone,
      );

      // Sepeti temizle (hem database hem UI state)
      await _cartService.clearCart(userId);
      
      // CartProvider'ı kullanarak UI'da da sepeti temizle
      if (mounted) {
        try {
          final cartProvider = Provider.of<CartProvider>(context, listen: false);
          await cartProvider.clearCart();
        } catch (e) {
          debugPrint('⚠️ CartProvider bulunamadı veya hata: $e');
        }
      }

      if (mounted) {
        // Başarı mesajı ve ana ekrana dön
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Siparişiniz başarıyla oluşturuldu!'),
            backgroundColor: Colors.green,
          ),
        );
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

  void _showAddressSelection() async {
    if (_addresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayıtlı adres bulunamadı. Lütfen manuel girin.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Adreslerim',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _addresses.length,
                itemBuilder: (context, index) {
                  final address = _addresses[index];
                  return ListTile(
                    leading: Icon(
                      address.isDefault ? Icons.home : Icons.location_on,
                      color: address.isDefault ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(address.title),
                    subtitle: Text(
                      address.fullAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: address == _selectedAddress
                        ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(context, address),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedAddress = selected;
        _addressController.text = selected.fullAddress;
      });
    }
  }

  /// Email onay kodu dialogu göster
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
          // Kalan süreyi hesapla
          int remainingSeconds = 0;
          if (codeSentTime != null) {
            remainingSeconds = _verificationService.getRemainingSeconds(
              codeSentTime,
              expiresInSeconds,
            );
          }

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
                
                // Kod input alanı
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
                
                // Kod gönder butonu
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

  @override
  Widget build(BuildContext context) {
    final finalTotal = widget.subtotal - widget.discountAmount + widget.deliveryFee;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sipariş Onayı'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sepetten gelen kupon bilgisi (varsa)
              if (widget.appliedCoupon != null && widget.discountAmount > 0) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kupon Uygulandı',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            Text(
                              '${widget.appliedCoupon!.toUpperCase()} - ₺${widget.discountAmount.toStringAsFixed(2)} indirim',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              
              // Teslimat Adresi
              Text(
                'Teslimat Adresi',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_isLoadingAddresses)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_addresses.isEmpty)
                Card(
                  child: InkWell(
                    onTap: () async {
                      // Adres yönetim ekranına git
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddressManagementScreen(),
                        ),
                      );
                      _loadAddresses();
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
                              _selectedAddress?.title ?? 'Adres',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AddressManagementScreen(),
                                  ),
                                );
                                _loadAddresses();
                              },
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Düzenle', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedAddress?.fullName ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedAddress?.phone ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedAddress?.fullAddress ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (_addresses.length > 1) ...[
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _showAddressSelection,
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

            const SizedBox(height: 24),

            // Ödeme Yöntemi
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payment, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        const Text('Ödeme Yöntemi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<PaymentMethod>(
                      value: PaymentMethod.cash,
                      groupValue: _selectedPaymentMethod,
                      onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
                      title: const Text('Kapıda Nakit'),
                      subtitle: const Text('Teslimatçıya nakit ödeme'),
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.orange.shade700,
                    ),
                    RadioListTile<PaymentMethod>(
                      value: PaymentMethod.cardOnDelivery,
                      groupValue: _selectedPaymentMethod,
                      onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
                      title: const Text('Kapıda Banka/Kredi Kartı'),
                      subtitle: const Text('Teslimatçıya kart ile ödeme (POS)'),
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.orange.shade700,
                    ),
                    // Online Ödeme seçeneği - sadece aktifse göster
                    if (_onlinePaymentEnabled)
                      RadioListTile<PaymentMethod>(
                        value: PaymentMethod.online,
                        groupValue: _selectedPaymentMethod,
                        onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
                        title: const Text('Online Ödeme'),
                        subtitle: const Text('Kredi/Banka kartı ile güvenli ödeme'),
                        contentPadding: EdgeInsets.zero,
                        activeColor: Colors.orange.shade700,
                      ),
                    // Online ödeme kapalıysa bilgilendirme
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
                    // Kapıda ödeme bilgilendirmesi
                    if (_selectedPaymentMethod == PaymentMethod.cash || _selectedPaymentMethod == PaymentMethod.cardOnDelivery)
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
                                  'Teslimatçı kapıda ödemeyi alacaktır',
                                  style: TextStyle(fontSize: 12, color: Colors.blue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Online ödeme bilgilendirmesi
                    if (_selectedPaymentMethod == PaymentMethod.online)
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
                                  'Ödeme iyzico güvenli ödeme altyapısı ile yapılacaktır',
                                  style: TextStyle(fontSize: 12, color: Colors.blue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Not
            Text(
              'Sipariş Notu (Opsiyonel)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Örn: Kapı kodu 1234',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            // Sipariş Özeti
            Text(
              'Sipariş Özeti',
              style: Theme.of(context).textTheme.titleMedium,
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
                        Text('₺${widget.subtotal.toStringAsFixed(2)}'),
                      ],
                    ),
                    if (widget.discountAmount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'İndirim:',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '-₺${widget.discountAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Teslimat:'),
                        Text(
                          widget.deliveryFee == 0
                              ? 'Ücretsiz'
                              : '₺${widget.deliveryFee.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: widget.deliveryFee == 0 ? Colors.green : null,
                            fontWeight: widget.deliveryFee == 0 ? FontWeight.w600 : null,
                          ),
                        ),
                      ],
                    ),
                    // Ücretsiz teslimat bilgilendirmesi
                    if (widget.deliveryFee == 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'Siparişiniz ücretsiz teslimat kapsamındadır!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                          '₺${finalTotal.toStringAsFixed(2)}',
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

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      // Bottom Navigation Bar olarak buton
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isPlacingOrder ? null : _handleOrderSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedPaymentMethod == PaymentMethod.online
                    ? Colors.green
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isPlacingOrder
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_selectedPaymentMethod == PaymentMethod.online) ...[
                          const Icon(Icons.lock, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _selectedPaymentMethod == PaymentMethod.online
                              ? 'Güvenli Ödemeye Geç'
                              : 'Siparişi Onayla',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}