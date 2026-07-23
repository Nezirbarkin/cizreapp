import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/delivery_card_model.dart';
import '../widgets/delivery_card_selector.dart';

class SendPackageScreen extends StatefulWidget {
  const SendPackageScreen({super.key});

  @override
  State<SendPackageScreen> createState() => _SendPackageScreenState();
}

class _SendPackageScreenState extends State<SendPackageScreen> {
  List<DeliveryCard> _deliveryCards = [];
  String? _selectedCardId;
  bool _isLoading = true;

  final _recipientController = TextEditingController();
  final _recipientPhoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDeliveryCards();
  }

  Future<void> _loadDeliveryCards() async {
    try {
      final response = await Supabase.instance.client
          .from('delivery_card_options')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      final cards = (response as List)
          .map((card) => DeliveryCard.fromJson(card as Map<String, dynamic>))
          .toList();

      setState(() {
        _deliveryCards = cards;
        _selectedCardId = cards.isNotEmpty ? cards.first.id : null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Teslimat kartları yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitRequest() async {
    if (_recipientController.text.isEmpty ||
        _recipientPhoneController.text.isEmpty ||
        _addressController.text.isEmpty ||
        _selectedCardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurunuz')),
      );
      return;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final selectedCard = _deliveryCards.firstWhere(
        (c) => c.id == _selectedCardId,
        orElse: () => _deliveryCards.first,
      );

      await Supabase.instance.client.from('courier_requests').insert({
        'sender_id': userId,
        'recipient_name': _recipientController.text,
        'recipient_phone': _recipientPhoneController.text,
        'delivery_address': _addressController.text,
        'description': _descriptionController.text,
        'delivery_card_id': _selectedCardId,
        'delivery_fee': selectedCard.fee,
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kargo talebiniz gönderildi!'),
            backgroundColor: Colors.green,
          ),
        );
        if (mounted) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context);
          });
        }
      }
    } catch (e) {
      debugPrint('Kargo talebini gönderme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kargo Gönder'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telefon',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Teslimat Adresi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Adres',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_deliveryCards.isNotEmpty)
                    DeliveryCardSelector(
                      cards: _deliveryCards,
                      selectedCardId: _selectedCardId,
                      onCardSelected: (cardId) {
                        setState(() => _selectedCardId = cardId);
                      },
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Kargo Talebini Gönder',
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
    _recipientController.dispose();
    _recipientPhoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
