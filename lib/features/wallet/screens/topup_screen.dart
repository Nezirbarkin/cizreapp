import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/services/bank_account_service.dart';
import '../../../core/models/bank_account_model.dart';

/// Bakiye Yükleme Ekranı
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  final BalanceService _balanceService = BalanceService();
  final BankAccountService _bankAccountService = BankAccountService();
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = false;
  bool _isWebViewOpen = false;
  bool _isLoadingBanks = true;
  String? _error;
  WebViewController? _webViewController;
  String _selectedMethod = 'card';
  List<BankAccount> _bankAccounts = [];
  BankAccount? _selectedBankAccount;
  bool _cardTopupEnabled = true;
  String? _conversationId; // Aktif topup işleminin referansı (sunucu doğrulaması için)
  bool _paymentHandled = false; // Aynı ödemenin iki kez işlenmesini önler

  final List<double> _quickAmounts = [50, 100, 200, 500];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadBankAccounts();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select('card_topup_enabled')
          .maybeSingle();
      
      if (mounted && response != null) {
        setState(() {
          _cardTopupEnabled = response['card_topup_enabled'] as bool? ?? true;
          // Eğer kart ile ödeme kapalıysa ve varsayılan yöntem kart ise havale'ye geç
          if (!_cardTopupEnabled && _selectedMethod == 'card') {
            _selectedMethod = 'transfer';
          }
        });
      }
    } catch (e) {
      debugPrint('Ayarlar yüklenirken hata: $e');
    }
  }

  Future<void> _loadBankAccounts() async {
    try {
      final accounts = await _bankAccountService.getActiveBankAccounts();
      if (mounted) {
        setState(() {
          _bankAccounts = accounts;
          _isLoadingBanks = false;
          if (accounts.isNotEmpty) {
            _selectedBankAccount = accounts.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBanks = false);
      }
    }
  }


  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label kopyalandı'),
                  duration: const Duration(seconds: 1),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _sendTransferNotification(BuildContext context) async {
    final amount = _amountController.text.trim();
    if (amount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tutar girin')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı girişi yapılmadı');
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone')
          .eq('id', userId)
          .single();

      // Admin kullanıcıları bul
      final admins = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('role', 'admin');

      // Her admin'e bildirim gönder
      // Not: notifications tablosunda 'content' kolonu var (body DEĞİL),
      // 'data' kolonu yok, 'entity_id' kullanılıyor.
      // type CHECK constraint'te izin verilen: 'admin_notification' kullanıyoruz.
      for (final admin in admins) {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': admin['id'],
          'type': 'admin_notification',
          'title': 'Havale Bildirimi',
          'content': '${profile['full_name']} havale bildirdi: ₺$amount',
          'entity_id': userId,
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bildirim gönderildi! En kısa sürede kontrol edilecektir.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _initializeTopup(double amount) async {
    if (amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum yükleme tutarı 10 TL\'dir')),
      );
      return;
    }

    // Kart ile ödeme kapalıyken havale yöntemine yönlendir
    if (_selectedMethod == 'card' && !_cardTopupEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kredi kartı ile ödeme şu an kapalı. Lütfen Havale/EFT yöntemini kullanın.'),
          backgroundColor: Colors.orange,
        ),
      );
      setState(() => _selectedMethod = 'transfer');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _balanceService.initializeTopup(amount: amount);

      if (!mounted) return;

      // Ödeme referansını sakla ve durumu sıfırla (sunucu doğrulaması için)
      _conversationId = result.conversationId;
      _paymentHandled = false;

      // WebView ile ödemeyi aç
      _openPaymentWebView(result.paymentPageUrl);
    } catch (e) {
      if (!mounted) return;
      
      // Hata mesajını okunaklı hale getir
      String errorMessage = e.toString();
      
      // "Exception: " prefix'ini kaldır
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }
      
      // JSON formatındaki teknik hataları sadeleştir
      if (errorMessage.contains('"code"') && errorMessage.contains('UNAUTHORIZED')) {
        errorMessage = 'Kredi kartı sistemi yapılandırılmamış. Lütfen yönetici ile iletişime geçin.';
      } else if (errorMessage.contains('"code"') && errorMessage.contains('"message"')) {
        // JSON parse deneyerek kullanıcı dostu mesajı al
        try {
          final match = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(errorMessage);
          if (match != null) {
            errorMessage = match.group(1)!.replaceAll('\\u0027', "'");
          }
        } catch (_) {}
      }
      
      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _openPaymentWebView(String url) {
    setState(() {
      _isWebViewOpen = true;
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              debugPrint('🌐 WebView: $url');
              
              // Başarı kontrolü
              if (url.contains('balance-success') || url.contains('success')) {
                _handlePaymentSuccess();
              }
              // Başarısızlık kontrolü
              else if (url.contains('balance-failed') || url.contains('fail')) {
                _handlePaymentFailed();
              }
            },
            onPageFinished: (String url) {
              debugPrint('✅ WebView finished: $url');
            },
            onNavigationRequest: (NavigationRequest request) {
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
    });
  }

  Future<void> _handlePaymentSuccess() async {
    if (!_isWebViewOpen || _paymentHandled) return;
    _paymentHandled = true;

    // WebView'i kapat ve doğrulama ekranı göster
    setState(() {
      _isWebViewOpen = false;
      _webViewController = null;
      _isLoading = true;
    });

    // ÖNEMLİ: URL'de "success" görünmesi ödemenin gerçekten tamamlandığı
    // anlamına gelmez. Sunucudan (balance_transactions.status) teyit alıyoruz.
    bool confirmed = false;
    if (_conversationId != null) {
      // Callback'in işlenmesi için kısa retry (birkaç saniye gecikebilir)
      for (int i = 0; i < 5; i++) {
        confirmed = await _balanceService.checkTopupStatus(_conversationId!);
        if (confirmed) break;
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (!mounted) return;

    if (confirmed) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bakiye başarıyla yüklendi!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      // Ödeme henüz teyit edilemedi - yanlış "başarılı" göstermiyoruz
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Ödeme alındı, bakiyeye yansıması birkaç dakika sürebilir. '
              'Yansımazsa lütfen destek ile iletişime geçin.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _handlePaymentFailed() {
    if (_paymentHandled) return;
    _paymentHandled = true;
    setState(() {
      _isWebViewOpen = false;
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ödeme başarısız oldu'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _closeWebView() {
    setState(() {
      _isWebViewOpen = false;
      _webViewController = null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isWebViewOpen && _webViewController != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ödeme'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _closeWebView,
          ),
        ),
        body: WebViewWidget(controller: _webViewController!),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bakiye Yükle'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Açıklama
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Kredi kartınızla bakiye yükleyebilirsiniz.\nMinimum yükleme: 10 TL',
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

            // Ödeme Yöntemi Seçimi
            Text(
              'Ödeme Yöntemi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            // Kredi Kartı (sadece aktif ise göster)
            if (_cardTopupEnabled) ...[
              InkWell(
                onTap: () {
                  setState(() => _selectedMethod = 'card');
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _selectedMethod == 'card' ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedMethod == 'card' ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                      width: _selectedMethod == 'card' ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.credit_card, color: _selectedMethod == 'card' ? Theme.of(context).colorScheme.primary : Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kredi Kartı / Banka Kartı', style: TextStyle(fontWeight: FontWeight.w600, color: _selectedMethod == 'card' ? Theme.of(context).colorScheme.primary : Colors.black)),
                            const SizedBox(height: 2),
                            Text('İyzico güvenli ödeme', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      if (_selectedMethod == 'card')
                        Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ] else ...[
              // Kredi kartı pasif uyarısı
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kredi kartı ile ödeme şu an kapalıdır. Bakiye yüklemek için lütfen Havale/EFT yöntemini kullanın.',
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Havale / EFT
            InkWell(
              onTap: () {
                setState(() => _selectedMethod = 'transfer');
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _selectedMethod == 'transfer' ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedMethod == 'transfer' ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                    width: _selectedMethod == 'transfer' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance, color: _selectedMethod == 'transfer' ? Theme.of(context).colorScheme.primary : Colors.grey.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Havale / EFT', style: TextStyle(fontWeight: FontWeight.w600, color: _selectedMethod == 'transfer' ? Theme.of(context).colorScheme.primary : Colors.black)),
                          const SizedBox(height: 2),
                          Text('Banka havalesi ile yükleme', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    if (_selectedMethod == 'transfer')
                      Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),

            // Havale bilgileri
            if (_selectedMethod == 'transfer') ...[
              const SizedBox(height: 20),
              if (_isLoadingBanks)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_bankAccounts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Şu anda aktif banka hesabı bulunmuyor. Lütfen kredi kartı ile yükleme yapın veya daha sonra tekrar deneyin.',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Birden fazla banka varsa seçim
                if (_bankAccounts.length > 1) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.purple.shade700, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Havale Yapılacak Banka',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<BankAccount>(
                          isExpanded: true,
                          value: _selectedBankAccount,
                          items: _bankAccounts.map((bank) {
                            return DropdownMenuItem<BankAccount>(
                              value: bank,
                              child: Text('${bank.bankName} - ${bank.accountName}'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedBankAccount = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Havale Bilgileri',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Banka', _selectedBankAccount?.bankName ?? '-'),
                      _buildInfoRow('Hesap Adı', _selectedBankAccount?.accountName ?? '-'),
                      _buildInfoRow('IBAN', _selectedBankAccount?.iban ?? '-'),
                      if (_selectedBankAccount?.branch != null &&
                          _selectedBankAccount!.branch!.isNotEmpty)
                        _buildInfoRow('Şube', _selectedBankAccount!.branch!),
                      if (_selectedBankAccount?.description != null &&
                          _selectedBankAccount!.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '📝 ${_selectedBankAccount!.description!}',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '⚠️ Açıklama kısmına CizreApp kullanıcı bilginizi yazınız.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Bakiye 0-1 saatte otamtik yansıtılır.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Bildirim butonu
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_active, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text('Havale Yaptınız Mı?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Havale işlemini tamamladıysanız, admin\'e bildirim gönderin.',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : () => _sendTransferNotification(context),
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Admin\'e Bildir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Hızlı seçenekler
            Text(
              'Hızlı Seç',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickAmounts.map((amount) {
                return OutlinedButton(
                  onPressed: _isLoading ? null : () {
                    _amountController.text = amount.toString();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text('₺$amount'),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Tutar girişi
            Text(
              'veya tutar girin',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Tutar (TL)',
                prefixText: '₺ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
            const SizedBox(height: 24),

            // Yükle butonu
            ElevatedButton(
              onPressed: _isLoading ? null : () {
                final amount = double.tryParse(_amountController.text) ?? 0;
                _initializeTopup(amount);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Ödemeye Geç'),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
