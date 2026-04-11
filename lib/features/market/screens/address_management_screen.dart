import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/address_model.dart';
import '../providers/address_provider.dart';

class AddressManagementScreen extends StatelessWidget {
  const AddressManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adreslerim')),
        body: const Center(child: Text('Lütfen giriş yapın')),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => AddressProvider(userId),
      child: const _AddressListScreen(),
    );
  }
}

class _AddressListScreen extends StatelessWidget {
  const _AddressListScreen();

  @override
  Widget build(BuildContext context) {
    final addressProvider = context.watch<AddressProvider>();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Adreslerim'),
        elevation: 0,
      ),
      body: addressProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : addressProvider.addresses.isEmpty
              ? _buildEmptyState(context)
              : _buildAddressList(context, addressProvider),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAddressDialog(context),
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 24),
          Text(
            'Kayıtlı adresiniz yok',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'İlk adresinizi ekleyin',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _showAddAddressDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Adres Ekle'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressList(BuildContext context, AddressProvider provider) {
    return RefreshIndicator(
      onRefresh: () => provider.loadAddresses(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: provider.addresses.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final address = provider.addresses[index];
          return _buildAddressCard(context, address, provider);
        },
      ),
    );
  }

  Widget _buildAddressCard(BuildContext context, Address address, AddressProvider provider) {
    final isSelected = provider.selectedAddress?.id == address.id;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            address.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (address.isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Varsayılan',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address.fullName,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address.phone,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        _showEditAddressDialog(context, address);
                        break;
                      case 'delete':
                        await _showDeleteConfirmDialog(context, address);
                        break;
                      case 'default':
                        await provider.setDefaultAddress(address.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Varsayılan adres güncellendi')),
                          );
                        }
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'default',
                      child: Row(
                        children: [
                          Icon(Icons.star_border, size: 18),
                          SizedBox(width: 12),
                          Text('Varsayılan Yap'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 18),
                          SizedBox(width: 12),
                          Text('Düzenle'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 18, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Sil', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              address.fullAddress,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddAddressDialog(BuildContext context) async {
    final provider = context.read<AddressProvider>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddressFormSheet(provider: provider),
    );
  }

  Future<void> _showEditAddressDialog(BuildContext context, Address address) async {
    final provider = context.read<AddressProvider>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddressFormSheet(provider: provider, address: address),
    );
  }

  Future<void> _showDeleteConfirmDialog(BuildContext context, Address address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adresi Sil'),
        content: const Text('Bu adresi silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final provider = context.read<AddressProvider>();
      try {
        await provider.deleteAddress(address.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Adres silindi')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Adres silinirken hata: $e')),
          );
        }
      }
    }
  }
}

class AddressFormSheet extends StatefulWidget {
  final Address? address;
  final AddressProvider provider;

  const AddressFormSheet({super.key, this.address, required this.provider});

  @override
  State<AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController(text: 'Şırnak'); // Varsayılan Şırnak
  final _districtController = TextEditingController(text: 'Cizre'); // Varsayılan Cizre
  bool _isDefault = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.address != null) {
      _titleController.text = widget.address!.title;
      _fullNameController.text = widget.address!.fullName;
      _phoneController.text = widget.address!.phone;
      _addressLine1Controller.text = widget.address!.addressLine1;
      _addressLine2Controller.text = widget.address!.addressLine2 ?? '';
      _cityController.text = widget.address!.city;
      _districtController.text = widget.address!.district ?? '';
      _isDefault = widget.address!.isDefault;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Kullanıcı oturumu kapalı')),
        );
      }
      return;
    }

    try {
      debugPrint('🔍 Adres kaydetme başlıyor... User: $userId');
      
      if (widget.address == null) {
        // Yeni adres ekle
        debugPrint('🔍 YENİ ADRES EKLENIYOR');
        debugPrint('  - Başlık: ${_titleController.text}');
        debugPrint('  - Ad Soyad: ${_fullNameController.text}');
        debugPrint('  - Telefon: ${_phoneController.text}');
        debugPrint('  - Adres 1: ${_addressLine1Controller.text}');
        debugPrint('  - Şehir: ${_cityController.text}');
        
        await widget.provider.addAddress(
          title: _titleController.text,
          fullName: _fullNameController.text,
          phone: _phoneController.text,
          addressLine1: _addressLine1Controller.text,
          addressLine2: _addressLine2Controller.text.isNotEmpty ? _addressLine2Controller.text : null,
          city: _cityController.text,
          district: _districtController.text.isNotEmpty ? _districtController.text : null,
          isDefault: _isDefault,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('❌ TIMEOUT: Adres eklemesi 15 saniye geçti');
            throw TimeoutException('Adres eklemesi zaman aşımına uğradı');
          },
        );
        debugPrint('✅ Adres başarıyla eklendi');
      } else {
        // Adres güncelle
        debugPrint('🔍 ADRES GÜNCELLENIYOR - ID: ${widget.address!.id}');
        
        await widget.provider.updateAddress(
          addressId: widget.address!.id,
          title: _titleController.text,
          fullName: _fullNameController.text,
          phone: _phoneController.text,
          addressLine1: _addressLine1Controller.text,
          addressLine2: _addressLine2Controller.text.isNotEmpty ? _addressLine2Controller.text : null,
          city: _cityController.text,
          district: _districtController.text.isNotEmpty ? _districtController.text : null,
          isDefault: _isDefault,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('❌ TIMEOUT: Adres güncellemesi 15 saniye geçti');
            throw TimeoutException('Adres güncellemesi zaman aşımına uğradı');
          },
        );
        debugPrint('✅ Adres başarıyla güncellendi');
      }

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.address == null ? '✅ Adres eklendi' : '✅ Adres güncellendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on TimeoutException catch (e) {
      debugPrint('❌ TimeoutException: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Zaman aşımı: $e\n\nLütfen internet bağlantınızı kontrol edin'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ HATA OLUŞTU: $e');
      debugPrint('📍 Stack Trace: $stackTrace');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.address == null ? 'Yeni Adres' : 'Adresi Düzenle',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Başlık
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Adres Başlığı',
                    hintText: 'Örn: Ev, İş',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 16),

                // Ad Soyad
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 16),

                // Telefon
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 16),

                // Adres Satır 1
                TextFormField(
                  controller: _addressLine1Controller,
                  decoration: const InputDecoration(
                    labelText: 'Adres',
                    hintText: 'Mahalle, Sokak, No',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (value) => value?.isEmpty == true ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 16),

                // Adres Satır 2
                TextFormField(
                  controller: _addressLine2Controller,
                  decoration: const InputDecoration(
                    labelText: 'Adres Devamı',
                    hintText: 'Kat, Daire (Opsiyonel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Şehir
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'Şehir',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Zorunlu' : null,
                ),
                const SizedBox(height: 16),

                // İlçe
                TextFormField(
                  controller: _districtController,
                  decoration: const InputDecoration(
                    labelText: 'İlçe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Varsayılan Adres
                CheckboxListTile(
                  title: const Text('Varsayılan adres yap'),
                  subtitle: const Text('Siparişlerde varsayılan olarak bu adres kullanılacak'),
                  value: _isDefault,
                  onChanged: (value) => setState(() => _isDefault = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 24),

                // Kaydet Butonu
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
