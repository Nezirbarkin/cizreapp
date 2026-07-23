import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/address_model.dart';
import '../../../core/services/notification_service.dart';
import '../../market/screens/address_picker_screen.dart';
import 'package_history_screen.dart';
import '../widgets/couriers_map_card.dart';

class SendPackageScreen extends StatefulWidget {
  const SendPackageScreen({super.key});

  @override
  State<SendPackageScreen> createState() => _SendPackageScreenState();
}

class _SendPackageScreenState extends State<SendPackageScreen> {
  final _senderNameController = TextEditingController();
  final _senderPhoneController = TextEditingController();
  final _recipientController = TextEditingController();
  final _recipientPhoneController = TextEditingController();
  final _recipientAddressDetailController = TextEditingController();
  final _descriptionController = TextEditingController();

  Address? _pickupAddress;
  Address? _deliveryAddress;

  double _baseFee = 15;
  double _perKmFee = 3;
  bool _isLoading = true;
  bool _isSubmitting = false;

  double? get _distanceKm {
    if (_pickupAddress?.latitude == null ||
        _pickupAddress?.longitude == null ||
        _deliveryAddress?.latitude == null ||
        _deliveryAddress?.longitude == null) {
      return null;
    }
    final meters = Geolocator.distanceBetween(
      _pickupAddress!.latitude!,
      _pickupAddress!.longitude!,
      _deliveryAddress!.latitude!,
      _deliveryAddress!.longitude!,
    );
    return meters / 1000;
  }

  double? get _totalFee {
    final km = _distanceKm;
    if (km == null) return null;
    return _baseFee + km * _perKmFee;
  }

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    try {
      final response = await Supabase.instance.client
          .from('courier_service_settings')
          .select()
          .limit(1)
          .maybeSingle();

      if (response != null) {
        _baseFee = (response['base_fee'] as num?)?.toDouble() ?? _baseFee;
        _perKmFee = (response['per_km_fee'] as num?)?.toDouble() ?? _perKmFee;
      }
    } catch (e) {
      debugPrint('Ücret ayarları yükleme hatası: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAddress({required bool isPickup}) async {
    final current = isPickup ? _pickupAddress : _deliveryAddress;
    final result = await Navigator.push<Address>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressPickerScreen(
          initialLatitude: current?.latitude,
          initialLongitude: current?.longitude,
          initialAddress: current?.addressLine1,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        if (isPickup) {
          _pickupAddress = result;
        } else {
          _deliveryAddress = result;
        }
      });
    }
  }

  Future<void> _notifyCouriers() async {
    try {
      final couriers = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('role', 'courier');
      for (final courier in List<Map<String, dynamic>>.from(couriers)) {
        NotificationService().createNotification(
          userId: courier['id'] as String,
          type: 'new_package_request',
          title: 'Yeni Paket Talebi',
          content: 'Alım: ${_pickupAddress?.addressLine1 ?? '-'} → Teslim: ${_deliveryAddress?.addressLine1 ?? '-'}',
        );
      }
    } catch (e) {
      debugPrint('Kurye bildirimi gönderilemedi: $e');
    }
  }

  Future<void> _submitRequest() async {
    if (_senderNameController.text.isEmpty ||
        _senderPhoneController.text.isEmpty ||
        _recipientController.text.isEmpty ||
        _recipientPhoneController.text.isEmpty ||
        _pickupAddress == null ||
        _deliveryAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurunuz')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    Map<String, dynamic>? insertedRequest;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      insertedRequest = await Supabase.instance.client.from('courier_requests').insert({
        'sender_id': userId,
        'sender_name': _senderNameController.text,
        'sender_phone': _senderPhoneController.text,
        'recipient_name': _recipientController.text,
        'recipient_phone': _recipientPhoneController.text,
        'pickup_address': _pickupAddress!.addressLine1,
        'pickup_lat': _pickupAddress!.latitude,
        'pickup_lng': _pickupAddress!.longitude,
        'delivery_address': _deliveryAddress!.addressLine1,
        'delivery_address_detail': _recipientAddressDetailController.text,
        'delivery_lat': _deliveryAddress!.latitude,
        'delivery_lng': _deliveryAddress!.longitude,
        'description': _descriptionController.text,
        'distance_km': _distanceKm,
        'total_fee': _totalFee,
        'status': 'pending',
      }).select().single();

      // Ücreti kullanıcı bakiyesinden düş (yetersizse RPC exception fırlatır)
      await Supabase.instance.client.rpc('deduct_from_balance', params: {
        'p_user_id': userId,
        'p_amount': _totalFee,
        'p_type': 'courier_payment',
        'p_reference_type': 'courier_request',
        'p_reference_id': insertedRequest['id'],
        'p_description': 'Paket gönderim ücreti',
      });

      _notifyCouriers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paket talebiniz gönderildi!'),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      debugPrint('Paket talebini gönderme hatası: $e');
      // Bakiye kesintisi başarısızsa oluşturulan talebi geri al
      if (insertedRequest != null) {
        try {
          await Supabase.instance.client
              .from('courier_requests')
              .delete()
              .eq('id', insertedRequest['id']);
        } catch (_) {}
      }
      if (mounted) {
        // Yetersiz bakiye hatası kontrolü
        final errorMessage = e.toString();
        if (errorMessage.contains('Insufficient balance') || errorMessage.contains('yetersiz bakiye')) {
          // Bakiye miktarlarını ayıkla
          String? availableText;
          String? requiredText;
          try {
            if (errorMessage.contains('Available:')) {
              availableText = errorMessage.split('Available:')[1].split(',')[0].trim();
              requiredText = errorMessage.split('Required:')[1].split(',')[0].trim();
            }
          } catch (_) {}

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Yetersiz Bakiye'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Paket gönderimi için yeterli bakiyeniz yok.'),
                  if (availableText != null && requiredText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mevcut bakiye: ₺$availableText',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text('Gerekli miktar: ₺$requiredText',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('Bakiye yüklemek ister misiniz?',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/wallet');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: const Text('Bakiye Yükle'),
                ),
              ],
            ),
          );
        } else {
          // Diğer hatalar için genel mesaj
          String userFriendlyMessage = 'Paket talebiniz gönderilirken bir sorun oluştu.';

          if (errorMessage.contains('P0001') || errorMessage.contains('PostgrestException')) {
            userFriendlyMessage = 'İşlem sırasında bir sorun oluştu. Lütfen tekrar deneyiniz.';
          } else if (errorMessage.contains('timeout') || errorMessage.contains('Timeout')) {
            userFriendlyMessage = 'Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyiniz.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userFriendlyMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildAddressCard({
    required String title,
    required IconData icon,
    required Address? address,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          address?.addressLine1 ?? 'Haritadan konum seçin',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton(
          onPressed: onTap,
          child: Text(address == null ? 'Seç' : 'Değiştir'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final totalFee = _totalFee;
    final distanceKm = _distanceKm;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paket Gönder/Al'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Geçmiş Paketlerim',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PackageHistoryScreen()),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alım ve Teslim Noktası',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildAddressCard(
                    title: 'Alım Noktası',
                    icon: Icons.storefront,
                    address: _pickupAddress,
                    onTap: () => _pickAddress(isPickup: true),
                  ),
                  const SizedBox(height: 8),
                  _buildAddressCard(
                    title: 'Teslim Noktası',
                    icon: Icons.location_on,
                    address: _deliveryAddress,
                    onTap: () => _pickAddress(isPickup: false),
                  ),
                  const SizedBox(height: 12),
                  CouriersMapCard(
                    pickupLat: _pickupAddress?.latitude,
                    pickupLng: _pickupAddress?.longitude,
                    deliveryLat: _deliveryAddress?.latitude,
                    deliveryLng: _deliveryAddress?.longitude,
                  ),
                  if (totalFee != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: primary.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mesafe: ${distanceKm!.toStringAsFixed(1)} km'),
                            const SizedBox(height: 4),
                            Text(
                              'Açılış: ${_baseFee.toStringAsFixed(2)} ₺  +  ${distanceKm.toStringAsFixed(1)} km × ${_perKmFee.toStringAsFixed(2)} ₺',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Toplam Ücret'),
                                Text(
                                  '${totalFee.toStringAsFixed(2)} ₺',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 16),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Gönderen Bilgileri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senderNameController,
                    decoration: InputDecoration(
                      labelText: 'Gönderen Adı',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senderPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Gönderen Telefonu',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Alıcı Bilgileri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientController,
                    decoration: InputDecoration(
                      labelText: 'Alıcı Adı',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telefon',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientAddressDetailController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Açık Adres (Kat, Daire, Tarif vb.)',
                      prefixIcon: const Icon(Icons.map_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Paket Açıklaması',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Açıklama',
                      prefixIcon: const Icon(Icons.description),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Paket Talebini Gönder',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _senderNameController.dispose();
    _senderPhoneController.dispose();
    _recipientController.dispose();
    _recipientPhoneController.dispose();
    _recipientAddressDetailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
