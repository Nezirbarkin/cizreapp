// ignore_for_file: deprecated_member_use, unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/address_model.dart';
import '../../../core/services/app_about_service.dart';
import '../../../core/services/verification_service.dart';
import '../providers/address_provider.dart';
import '../providers/cart_provider.dart';
import '../../shop/services/order_service.dart';
import '../services/cart_service.dart';
import 'address_management_screen.dart';
import 'shop_detail_screen.dart';

/// Çok dükkanlı checkout ekranı
/// Sepette birden fazla dükkandan ürün varsa bu ekran kullanılır
class MultiShopCheckoutScreen extends StatefulWidget {
  const MultiShopCheckoutScreen({super.key});

  @override
  State<MultiShopCheckoutScreen> createState() => _MultiShopCheckoutScreenState();
}

class _MultiShopCheckoutScreenState extends State<MultiShopCheckoutScreen> {
  final OrderService _orderService = OrderService();
  final CartService _cartService = CartService();
  final AppAboutService _aboutService = AppAboutService();
  final VerificationService _verificationService = VerificationService();
  final _notesController = TextEditingController();
  final _supabase = Supabase.instance.client;

  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _isPlacingOrder = false;
  bool _isLoading = true;
  bool _onlinePaymentEnabled = false;
  bool _isLoadingPaymentSettings = true;
  
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

  Future<void> _loadCartData() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final summaries = await _cartService.groupCartByShop(userId);
      
      double total = 0;
      for (final summary in summaries.values) {
        total += summary.total;
      }

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

      // Minimum sipariş tutarı kontrolü - Tüm dükkanları kontrol et
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final failedShops = <String, double>{};
      
      for (final entry in _shopSummaries.entries) {
        final shopId = entry.key;
        if (!cartProvider.meetsMinOrderAmount(shopId)) {
          final shop = cartProvider.getShop(shopId);
          final remaining = cartProvider.getRemainingForMinOrder(shopId);
          if (shop != null) {
            failedShops['${shop.name} (Min: ₺${shop.minOrderAmount.toStringAsFixed(2)})'] = remaining;
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
              content: Text('Minimum sipariş tutarı karşılanmıyor:\n\n$message'),
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
        
        itemsByShop[shopId] = summary.items.map((cartItem) => OrderItem(
          id: '',
          orderId: '',
          productId: cartItem.productId,
          productName: cartItem.productName ?? 'Ürün',
          price: cartItem.productPrice ?? 0,
          quantity: cartItem.quantity,
          productImageUrl: cartItem.productImageUrl,
          shopId: cartItem.shopId,
          shopName: cartItem.shopName,
          createdAt: DateTime.now(),
        )).toList();
      }

      // Teslimat adresi metni
      final addressText = '${selectedAddress.title} - ${selectedAddress.fullAddress}';

      // Çok dükkanlı sipariş oluştur
      final result = await _orderService.createMultiShopOrder(
        userId: userId,
        itemsByShop: itemsByShop,
        deliveryAddressText: addressText,
        addressId: selectedAddress.id,
        paymentMethod: _selectedPaymentMethod,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        customerPhone: selectedAddress.phone, // Adresteki telefon numarasını ekledik
      );

      // Sepeti temizle
      await cartProvider.clearCart();

      if (mounted) {
        Navigator.pop(context); // Checkout ekranını kapat

        // Başarı mesajı göster
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
                Text('${result.orderCount} dükkan için sipariş oluşturuldu.'),
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
              Text(
                '${_shopSummaries.length} dükkan',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._shopSummaries.values.map((summary) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(summary.shopName, overflow: TextOverflow.ellipsis)),
                    Text('₺${summary.total.toStringAsFixed(2)}'),
                  ],
                ),
              )),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('GENEL TOPLAM:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                                _buildAddressSection(addresses, selectedAddress, addressProvider),
                                const SizedBox(height: 24),
                                
                                // Dükkanlar ve Ürünler
                                _buildShopsSection(),
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

  Widget _buildAddressSection(List<Address> addresses, Address? selectedAddress, AddressProvider addressProvider) {
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
                const Text('Teslimat Adresi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (addresses.isEmpty)
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddressManagementScreen()),
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
                  ...addresses.map((address) => RadioListTile<String>(
                    value: address.id,
                    groupValue: selectedAddress?.id,
                    onChanged: (value) {
                      if (value != null) {
                        addressProvider.selectAddress(address);
                      }
                    },
                    title: Text(address.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(address.fullAddress, maxLines: 2, overflow: TextOverflow.ellipsis),
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.orange.shade700,
                  )),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddressManagementScreen()),
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
                    Icon(Icons.chevron_right, color: Colors.orange.shade700, size: 20),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
             
            // Ürünler
            ...summary.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  if (item.productImageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        item.productImageUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
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
                          '${item.quantity} x ₺${(item.productPrice ?? 0).toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₺${((item.productPrice ?? 0) * item.quantity).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )),
            
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
                const Text('Toplam:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '₺${summary.total.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700),
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
                const Text('Sipariş Notu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const Text('GENEL TOPLAM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isPlacingOrder
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        selectedAddress == null
                            ? 'Lütfen Adres Seçin'
                            : 'Siparişi Onayla',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
