// ignore_for_file: unnecessary_brace_in_string_interps, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/invoice_info_model.dart';
import '../services/invoice_service.dart';

/// Fatura seçenekleri (int olarak)
class InvoiceOption {
  static const int none = 0;
  static const int sameAsAddress = 1;
  static const int saved = 2;
  static const int custom = 3;
}

/// Fatura bilgileri seçim widget'ı
class InvoiceInfoSelector extends StatefulWidget {
  final InvoiceService invoiceService;
  final AddressInfo? addressInfo;
  final Function(InvoiceInfo?)? onInvoiceChanged;
  final bool showSaveOption;

  const InvoiceInfoSelector({
    super.key,
    required this.invoiceService,
    this.addressInfo,
    this.onInvoiceChanged,
    this.showSaveOption = true,
  });

  @override
  State<InvoiceInfoSelector> createState() => _InvoiceInfoSelectorState();
}

class _InvoiceInfoSelectorState extends State<InvoiceInfoSelector> {
  int _selectedOption = 0;
  InvoiceInfo? _savedInvoiceInfo;
  bool _saveToProfile = false;
  bool _isLoading = true;
  String? _formError;

  final _fullNameController = TextEditingController();
  final _tcNoController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _taxOfficeController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  InvoiceType _invoiceType = InvoiceType.individual;

  @override
  void initState() {
    super.initState();
    _loadSavedInvoiceInfo();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _tcNoController.dispose();
    _taxNumberController.dispose();
    _taxOfficeController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedInvoiceInfo() async {
    try {
      final savedInfo = await widget.invoiceService.getMyInvoiceInfo();
      setState(() {
        _savedInvoiceInfo = savedInfo;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onOptionSelected(int index) {
    InvoiceInfo? result;
    setState(() {
      _selectedOption = index;
      _formError = null;
    });

    switch (index) {
      case 0: // none
        result = null;
        break;
      case 1: // sameAsAddress
        if (widget.addressInfo != null) {
          result = InvoiceInfo(
            type: InvoiceType.individual,
            fullName: widget.addressInfo!.fullName,
            address: widget.addressInfo!.address,
          );
        }
        break;
      case 2: // saved
        result = _savedInvoiceInfo;
        break;
      case 3: // custom
        _updateCustomInvoice();
        return;
    }

    widget.onInvoiceChanged?.call(result);
  }

  void _updateCustomInvoice() {
    if (_selectedOption != 3) return;

    final info = InvoiceInfo(
      type: _invoiceType,
      fullName: _fullNameController.text.isNotEmpty ? _fullNameController.text : null,
      tcNo: _invoiceType == InvoiceType.individual && _tcNoController.text.isNotEmpty
          ? _tcNoController.text
          : null,
      taxNumber: _invoiceType == InvoiceType.corporate && _taxNumberController.text.isNotEmpty
          ? _taxNumberController.text
          : null,
      taxOffice: _invoiceType == InvoiceType.corporate && _taxOfficeController.text.isNotEmpty
          ? _taxOfficeController.text
          : null,
      address: _invoiceType == InvoiceType.corporate && _addressController.text.isNotEmpty
          ? _addressController.text
          : null,
      email: _emailController.text.isNotEmpty ? _emailController.text : null,
    );

    // Alanlar tamamen boşsa henüz doldurulmamış demektir; hata gösterme
    final error = info.isEmpty ? null : info.validate();
    setState(() => _formError = error);

    widget.onInvoiceChanged?.call(error == null && !info.isEmpty ? info : null);

    if (error == null && !info.isEmpty && _saveToProfile) {
      widget.invoiceService.saveInvoiceInfo(info);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            Row(
              children: [
                Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Fatura Bilgileri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Opsiyonel', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 16),

            // Seçenekler
            _buildOptionTile(0, 'Fatura bilgisi eklemek istemiyorum', Icons.remove_circle_outline),
            if (widget.addressInfo != null)
              _buildOptionTile(1, 'Adres bilgilerimle aynı', Icons.home_outlined),
            if (_savedInvoiceInfo != null && !_savedInvoiceInfo!.isEmpty)
              _buildOptionTile(2, 'Kayıtlı: ${_savedInvoiceInfo!.displaySummary}', Icons.bookmark_outline),
            _buildOptionTile(3, 'Farklı bilgi gir', Icons.edit_outlined),

            // Özel form - sadece "Farklı bilgi gir" seçiliyken göster
            if (_selectedOption == 3)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fatura bilgilerini doldurun',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                  ),
                  const SizedBox(height: 12),

                  // Fatura türü
                  const Text('Fatura Türü', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  SegmentedButton<InvoiceType>(
                    segments: const [
                      ButtonSegment(value: InvoiceType.individual, label: Text('Bireysel')),
                      ButtonSegment(value: InvoiceType.corporate, label: Text('Kurumsal')),
                    ],
                    selected: {_invoiceType},
                    onSelectionChanged: (selection) {
                      setState(() => _invoiceType = selection.first);
                      _updateCustomInvoice();
                    },
                  ),
                  const SizedBox(height: 12),

                  // Ad / Ünvan
                  TextField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: _invoiceType == InvoiceType.individual ? 'Ad Soyad' : 'Fatura Ünvanı',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => _updateCustomInvoice(),
                  ),
                  const SizedBox(height: 12),

                  // T.C. No veya Vergi No
                  if (_invoiceType == InvoiceType.individual)
                    TextField(
                      controller: _tcNoController,
                      decoration: const InputDecoration(
                        labelText: 'T.C. Kimlik No',
                        border: OutlineInputBorder(),
                        hintText: '11 haneli T.C. kimlik numarası',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                      onChanged: (_) => _updateCustomInvoice(),
                    )
                  else ...[
                    TextField(
                      controller: _taxNumberController,
                      decoration: const InputDecoration(labelText: 'Vergi No', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                      onChanged: (_) => _updateCustomInvoice(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _taxOfficeController,
                      decoration: const InputDecoration(labelText: 'Vergi Dairesi', border: OutlineInputBorder()),
                      onChanged: (_) => _updateCustomInvoice(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Fatura Adresi', border: OutlineInputBorder()),
                      maxLines: 2,
                      onChanged: (_) => _updateCustomInvoice(),
                    ),
                  ],

                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Fatura E-posta (Opsiyonel)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => _updateCustomInvoice(),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _formError!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            // Kaydet checkbox
            if (widget.showSaveOption && _selectedOption == 3) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _saveToProfile,
                onChanged: (value) {
                  setState(() => _saveToProfile = value ?? false);
                  _updateCustomInvoice();
                },
                title: const Text('Bilgilerimi kaydet', style: TextStyle(fontSize: 14)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(int index, String title, IconData icon) {
    final isSelected = _selectedOption == index;
    return GestureDetector(
      onTap: () {
        debugPrint('Tıklandı! index=$index');
        _onOptionSelected(index);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                  width: 2,
                ),
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
              ),
              child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal))),
            Icon(icon, size: 20, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }
}

/// Adres bilgileri (fatura için)
class AddressInfo {
  final String fullName;
  final String? address;

  const AddressInfo({required this.fullName, this.address});
}

/// Sipariş detayında fatura bilgilerini gösteren widget
class InvoiceInfoDisplay extends StatelessWidget {
  final InvoiceInfo? invoiceInfo;
  final bool showEmail;

  const InvoiceInfoDisplay({super.key, this.invoiceInfo, this.showEmail = true});

  @override
  Widget build(BuildContext context) {
    if (invoiceInfo == null || invoiceInfo!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Fatura Bilgileri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Tür', invoiceInfo!.type.label),
            _buildInfoRow(invoiceInfo!.type == InvoiceType.corporate ? 'Ünvan' : 'Ad Soyad', invoiceInfo!.fullName ?? '-'),
            if (invoiceInfo!.type == InvoiceType.individual && invoiceInfo!.tcNo != null)
              _buildInfoRow('T.C. No', invoiceInfo!.tcNo!),
            if (invoiceInfo!.type == InvoiceType.corporate) ...[
              if (invoiceInfo!.taxNumber != null) _buildInfoRow('Vergi No', invoiceInfo!.taxNumber!),
              if (invoiceInfo!.taxOffice != null) _buildInfoRow('Vergi Dairesi', invoiceInfo!.taxOffice!),
              if (invoiceInfo!.address != null) _buildInfoRow('Adres', invoiceInfo!.address!),
            ],
            if (showEmail && invoiceInfo!.email != null) _buildInfoRow('E-posta', invoiceInfo!.email!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
