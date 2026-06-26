import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/bank_account_model.dart';
import '../../../core/services/bank_account_service.dart';

/// Admin: Banka Hesapları Yönetim Sekmesi
class BankAccountsTabWidget extends StatefulWidget {
  const BankAccountsTabWidget({super.key});

  @override
  State<BankAccountsTabWidget> createState() => _BankAccountsTabWidgetState();
}

class _BankAccountsTabWidgetState extends State<BankAccountsTabWidget> {
  final BankAccountService _service = BankAccountService();
  List<BankAccount> _bankAccounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    try {
      final accounts = await _service.getAllBankAccounts(includeInactive: true);
      if (mounted) {
        setState(() {
          _bankAccounts = accounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addOrEditAccount({BankAccount? existing}) async {
    final result = await showDialog<BankAccount>(
      context: context,
      builder: (context) => BankAccountFormDialog(existing: existing),
    );

    if (result != null) {
      try {
        if (existing == null) {
          await _service.addBankAccount(
            bankName: result.bankName,
            iban: result.iban,
            accountName: result.accountName,
            branch: result.branch,
            accountNumber: result.accountNumber,
            description: result.description,
            displayOrder: result.displayOrder,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Banka hesabı eklendi'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          await _service.updateBankAccount(
            id: existing.id,
            bankName: result.bankName,
            iban: result.iban,
            accountName: result.accountName,
            branch: result.branch,
            accountNumber: result.accountNumber,
            description: result.description,
            displayOrder: result.displayOrder,
            isActive: result.isActive,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Banka hesabı güncellendi'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
        _loadAccounts();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteAccount(BankAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Banka Hesabını Sil'),
        content: Text(
          '${account.bankName} bankasındaki hesabı silmek istediğinize emin misiniz?\n\nIBAN: ${account.maskedIban}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteBankAccount(account.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Banka hesabı silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadAccounts();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleStatus(BankAccount account) async {
    try {
      await _service.toggleBankAccountStatus(account.id, !account.isActive);
      _loadAccounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAccounts,
              child: _bankAccounts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz banka hesabı yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kullanıcıların havale yapabileceği banka hesaplarını ekleyin',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _bankAccounts.length,
                      itemBuilder: (context, index) {
                        return _buildAccountCard(_bankAccounts[index]);
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditAccount(),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Banka Hesabı'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildAccountCard(BankAccount account) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: account.isActive
                      ? Colors.green.shade100
                      : Colors.grey.shade300,
                  child: Icon(
                    Icons.account_balance,
                    color: account.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.bankName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        account.accountName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: account.isActive ? Colors.green.shade100 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    account.isActive ? 'Aktif' : 'Pasif',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: account.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.credit_card, size: 14, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          account.iban,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'IBAN Kopyala',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: account.iban));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('IBAN kopyalandı'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  if (account.branch != null && account.branch!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Şube: ${account.branch}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ),
                  if (account.description != null && account.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Not: ${account.description}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleStatus(account),
                    icon: Icon(
                      account.isActive ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                    ),
                    label: Text(account.isActive ? 'Pasif Yap' : 'Aktif Yap'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addOrEditAccount(existing: account),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Düzenle'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteAccount(account),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Sil'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Banka hesabı ekleme/düzenleme formu
class BankAccountFormDialog extends StatefulWidget {
  final BankAccount? existing;

  const BankAccountFormDialog({super.key, this.existing});

  @override
  State<BankAccountFormDialog> createState() => _BankAccountFormDialogState();
}

class _BankAccountFormDialogState extends State<BankAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _bankNameController = TextEditingController();
  final _ibanController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _branchController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _displayOrderController = TextEditingController(text: '0');
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _bankNameController.text = existing.bankName;
      _ibanController.text = existing.iban;
      _accountNameController.text = existing.accountName;
      _branchController.text = existing.branch ?? '';
      _accountNumberController.text = existing.accountNumber ?? '';
      _descriptionController.text = existing.description ?? '';
      _displayOrderController.text = existing.displayOrder.toString();
      _isActive = existing.isActive;
    }
  }

  @override
  void dispose() {
    _bankNameController.dispose();
    _ibanController.dispose();
    _accountNameController.dispose();
    _branchController.dispose();
    _accountNumberController.dispose();
    _descriptionController.dispose();
    _displayOrderController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final result = BankAccount(
      id: widget.existing?.id ?? '',
      bankName: _bankNameController.text.trim(),
      iban: _ibanController.text.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
      accountName: _accountNameController.text.trim(),
      branch: _branchController.text.trim().isEmpty ? null : _branchController.text.trim(),
      accountNumber: _accountNumberController.text.trim().isEmpty
          ? null
          : _accountNumberController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      isActive: _isActive,
      displayOrder: int.tryParse(_displayOrderController.text) ?? 0,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing == null ? 'Yeni Banka Hesabı' : 'Banka Hesabını Düzenle',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bankNameController,
                  decoration: const InputDecoration(
                    labelText: 'Banka Adı *',
                    hintText: 'Örn: Ziraat Bankası',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_balance),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Banka adı gerekli';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ibanController,
                  decoration: const InputDecoration(
                    labelText: 'IBAN *',
                    hintText: 'TR00 0000 0000 0000 0000 0000 00',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.credit_card),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'IBAN gerekli';
                    }
                    final cleanIban = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
                    if (cleanIban.length != 26) {
                      return 'IBAN 26 karakter olmalı';
                    }
                    if (!cleanIban.startsWith('TR')) {
                      return 'IBAN TR ile başlamalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accountNameController,
                  decoration: const InputDecoration(
                    labelText: 'Hesap Sahibi *',
                    hintText: 'Ad Soyad',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Hesap sahibi gerekli';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _branchController,
                  decoration: const InputDecoration(
                    labelText: 'Şube (opsiyonel)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accountNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Hesap No (opsiyonel)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (opsiyonel)',
                    hintText: 'Havale için not',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayOrderController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Görüntüleme Sırası',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sort),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Aktif'),
                  subtitle: Text(_isActive ? 'Kullanıcılar görebilir' : 'Kullanıcılar göremez'),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() => _isActive = value);
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('İptal'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Kaydet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}