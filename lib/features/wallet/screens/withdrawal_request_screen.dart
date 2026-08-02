import 'package:flutter/material.dart';
import '../../../core/models/balance_model.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/services/withdrawal_service.dart';
import '../../../core/utils/app_error_handler.dart';

/// Satıcı Çekim Talebi Ekranı
class WithdrawalRequestScreen extends StatefulWidget {
  const WithdrawalRequestScreen({super.key});

  @override
  State<WithdrawalRequestScreen> createState() =>
      _WithdrawalRequestScreenState();
}

class _WithdrawalRequestScreenState extends State<WithdrawalRequestScreen> {
  final BalanceService _balanceService = BalanceService();
  final WithdrawalService _withdrawalService = WithdrawalService();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  final TextEditingController _accountNameController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  SellerEarningsSummary? _earningsSummary;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _bankNameController.dispose();
    _ibanController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  Future<void> _loadEarnings() async {
    setState(() => _isLoading = true);

    try {
      final summary = await _balanceService.getSellerEarnings();
      setState(() {
        _earningsSummary = summary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _submitWithdrawal() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text) ?? 0;
    final minWithdrawal = _earningsSummary?.minWithdrawal ?? 50;

    if (amount < minWithdrawal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Minimum çekim tutarı $minWithdrawal TL\'dir')),
      );
      return;
    }

    final availableAmount = _earningsSummary?.availableAmount ?? 0;
    if (amount > availableAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Çekilebilir tutar $availableAmount TL\'den fazla olamaz',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _withdrawalService.requestWithdrawal(
        amount: amount,
        bankName: _bankNameController.text.trim(),
        iban: _ibanController.text.replaceAll(' ', '').toUpperCase(),
        bankAccountName: _accountNameController.text.trim().isNotEmpty
            ? _accountNameController.text.trim()
            : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Çekim talebiniz oluşturuldu'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kazanç Çekme')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final summary = _earningsSummary;
    final availableAmount = summary?.availableAmount ?? 0;
    final feePercent = summary?.withdrawalFeePercent ?? 2;
    final minWithdrawal = summary?.minWithdrawal ?? 50;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kazanç Özeti
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade600, Colors.green.shade400],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'Çekilebilir Tutar',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₺${availableAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        'Bekleyen',
                        summary?.pendingAmount ?? 0,
                      ),
                      _buildSummaryItem(
                        'Çekilen',
                        summary?.withdrawnAmount ?? 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Text(
                'Puanlar çekilebilir TL tutarına dahil değildir; IBAN’a çekilemez veya transfer edilemez.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 24),

            // Bilgi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Minimum çekim: ₺$minWithdrawal | Komisyon: %$feePercent',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tutar
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Çekilecek Tutar',
                prefixText: '₺ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Tutar giriniz';
                }
                final amount = double.tryParse(value);
                if (amount == null || amount <= 0) {
                  return 'Geçerli bir tutar giriniz';
                }
                if (amount > availableAmount) {
                  return 'Çekilebilir tutarı aştınız';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Banka Adı
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                final banks = [
                  'Ziraat Bankası',
                  'Garanti BBVA',
                  'Akbank',
                  'İş Bankası',
                  'Halkbank',
                  'QNB Finansbank',
                  'Yapı Kredi',
                  'TEB',
                  'ING Bank',
                  'Kuveyt Türk',
                ];
                if (textEditingValue.text.isEmpty) {
                  return banks;
                }
                return banks.where(
                  (bank) => bank.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  ),
                );
              },
              onSelected: (selection) {
                _bankNameController.text = selection;
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                // Controller'ı senkronize et
                controller.addListener(() {
                  if (_bankNameController.text != controller.text) {
                    _bankNameController.text = controller.text;
                  }
                });
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Banka Adı',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Banka adı giriniz';
                    }
                    return null;
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // IBAN
            TextFormField(
              controller: _ibanController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'IBAN',
                hintText: 'TR00 0000 0000 0000 0000 0000 00',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'IBAN giriniz';
                }
                final cleanIban = value.replaceAll(' ', '');
                if (!cleanIban.startsWith('TR') || cleanIban.length < 26) {
                  return 'Geçerli bir IBAN giriniz';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Hesap Sahibi (Opsiyonel)
            TextFormField(
              controller: _accountNameController,
              decoration: InputDecoration(
                labelText: 'Hesap Sahibi (Opsiyonel)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tahmini Net Tutar
            Builder(
              builder: (context) {
                final amount = double.tryParse(_amountController.text) ?? 0;
                final fee = (amount * feePercent / 100 * 100).round() / 100;
                final net = amount - fee;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tutar:'),
                          Text('₺${amount.toStringAsFixed(2)}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Komisyon ($feePercent%):',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          Text(
                            '-₺${fee.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Net Tutar:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '₺${net.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Gönder Butonu
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitWithdrawal,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Çekim Talebi Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, double value) {
    return Column(
      children: [
        Text(
          '₺${value.toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
