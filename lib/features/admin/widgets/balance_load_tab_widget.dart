import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/balance_service.dart';

// ========== BAKİYE YÜKLEME SEKME WIDGET ==========
class BalanceLoadTabWidget extends StatefulWidget {
  const BalanceLoadTabWidget({super.key});

  @override
  State<BalanceLoadTabWidget> createState() => _BalanceLoadTabWidgetState();
}

class _BalanceLoadTabWidgetState extends State<BalanceLoadTabWidget> {
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankIbanController = TextEditingController();
  final _bankAccountNameController = TextEditingController();
  bool _isLoading = false;
  bool _isSearching = false;
  String? _message;
  bool _isSuccess = false;
  bool _showBankFields = false;
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedUser;

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _bankNameController.dispose();
    _bankIbanController.dispose();
    _bankAccountNameController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final supabase = Supabase.instance.client;
      // 20260803000006 sonrasında profiles üzerinde authenticated
      // SELECT policy'si yok; phone/email sütunları revoke edildi.
      // SECURITY DEFINER admin_search_users RPC üzerinden arama yapılır.
      final response = await supabase.rpc<List<dynamic>>(
        'admin_search_users',
        params: {'p_query': query, 'p_limit': 10},
      );

      if (mounted) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(response);
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Kullanıcı arama hatası: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _submitTransaction() async {
    final amount = double.tryParse(_amountController.text);
    final description = _descriptionController.text.trim();
    // Açıklama boşsa varsayılan değer kullan
    final finalDescription = description.isEmpty
        ? 'Bakiye düzeltmesi'
        : description;
    final bankName = _bankNameController.text.trim();
    final bankIban = _bankIbanController.text.trim();
    final bankAccountName = _bankAccountNameController.text.trim();

    if (_selectedUser == null || amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı seçin ve tutar girin')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final supabase = Supabase.instance.client;
      if (amount > 0) {
        // Admin bakiye ekleme - banka bilgileri ile birlikte
        await supabase.functions.invoke(
          'admin-add-balance',
          body: {
            'user_id': _selectedUser!['id'],
            'amount': amount,
            'description': finalDescription,
            if (bankName.isNotEmpty) 'bank_name': bankName,
            if (bankIban.isNotEmpty) 'bank_iban': bankIban,
            if (bankAccountName.isNotEmpty)
              'bank_account_name': bankAccountName,
          },
        );
        _isSuccess = true;
        _message = '₺${amount.toStringAsFixed(2)} bakiye eklendi!';
      } else {
        final balanceService = BalanceService();
        await balanceService.adminDeductBalance(
          userId: _selectedUser!['id'],
          amount: amount.abs(),
          description: finalDescription,
        );
        _isSuccess = true;
        _message = '₺${amount.abs().toStringAsFixed(2)} bakiye düşüldü!';
      }

      // Temizle
      if (mounted) {
        setState(() {
          _selectedUser = null;
          _amountController.clear();
          _descriptionController.clear();
          _bankNameController.clear();
          _bankIbanController.clear();
          _bankAccountNameController.clear();
          _searchController.clear();
          _searchResults = [];
          _showBankFields = false;
        });
      }
    } catch (e) {
      _isSuccess = false;
      _message = 'Hata: $e';
    }

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_message!),
          backgroundColor: _isSuccess ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Açıklama
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Kullanıcı adı veya telefon numarası ile arama yapın.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),

          // Arama alanı
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Kullanıcı Ara',
              hintText: 'Ad, soyad veya telefon numarası',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                          _selectedUser = null;
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              if (value.length >= 2) {
                _searchUsers(value);
              } else {
                setState(() => _searchResults = []);
              }
            },
          ),
          const SizedBox(height: 8),

          // Arama sonuçları
          if (_searchResults.isNotEmpty && _selectedUser == null)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final user = _searchResults[index];
                  final name = user['full_name'] ?? 'Bilinmeyen';
                  final phone = user['phone'] ?? '-';
                  final email = user['email'] ?? '-';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        (name.toString().isNotEmpty ? name.toString()[0] : '?')
                            .toUpperCase(),
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                    title: Text(name),
                    subtitle: Text('$phone • $email'),
                    onTap: () {
                      setState(() {
                        _selectedUser = user;
                        _searchResults = [];
                        _searchController.text = name;
                      });
                    },
                  );
                },
              ),
            ),

          // Seçili kullanıcı
          if (_selectedUser != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: Icon(Icons.person, color: Colors.green.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedUser!['full_name'] ?? 'Bilinmeyen',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _selectedUser!['phone'] ?? '-',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _selectedUser = null;
                        _searchController.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tutar
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d*')),
              ],
              decoration: InputDecoration(
                labelText: 'Tutar (TL)',
                hintText: 'Örn: 100 veya -50',
                prefixText: '₺ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.attach_money),
                helperText: 'Pozitif = Ekleme, Negatif = Düşme',
              ),
            ),
            const SizedBox(height: 16),

            // Açıklama
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Açıklama',
                hintText: 'İşlem açıklaması (opsiyonel)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.note),
              ),
            ),
            const SizedBox(height: 12),

            // Banka bilgisi toggle
            Row(
              children: [
                Checkbox(
                  value: _showBankFields,
                  onChanged: (value) {
                    setState(() {
                      _showBankFields = value ?? false;
                    });
                  },
                ),
                const Expanded(
                  child: Text(
                    'Banka bilgisi ekle (opsiyonel)',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),

            // Banka bilgileri (sadece toggle açıksa göster)
            if (_showBankFields) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _bankNameController,
                decoration: InputDecoration(
                  labelText: 'Banka Adı',
                  hintText: 'Örn: Ziraat Bankası',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.account_balance),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bankIbanController,
                decoration: InputDecoration(
                  labelText: 'IBAN',
                  hintText: 'TR00 0000 0000 0000 0000 0000 00',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.credit_card),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bankAccountNameController,
                decoration: InputDecoration(
                  labelText: 'Hesap Sahibi',
                  hintText: 'Ad Soyad',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Ekle butonu
            ElevatedButton.icon(
              onPressed: _isLoading || _selectedUser == null
                  ? null
                  : _submitTransaction,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(_isLoading ? 'İşleniyor...' : 'İşlemi Uygula'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],

          // Mesaj
          if (_message != null && _selectedUser != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _isSuccess
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
