import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/balance_service.dart';

/// Bakiye Yükleme Ekranı
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  final BalanceService _balanceService = BalanceService();
  final TextEditingController _amountController = TextEditingController();
  
  bool _isLoading = false;
  bool _isWebViewOpen = false;
  String? _error;
  WebViewController? _webViewController;
  String _selectedMethod = 'card'; // 'card' veya 'transfer'

  final List<double> _quickAmounts = [50, 100, 200, 500];

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
      for (final admin in admins) {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': admin['id'],
          'type': 'transfer_request',
          'title': 'Havale Bildirimi',
          'body': '${profile['full_name']} havale bildirdi: ₺$amount',
          'data': {
            'from_user_id': userId,
            'from_name': profile['full_name'],
            'from_phone': profile['phone'],
            'amount': amount,
            'payment_method': 'bank_transfer',
          },
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _balanceService.initializeTopup(amount: amount);

      if (!mounted) return;

      // WebView ile ödemeyi aç
      _openPaymentWebView(result.paymentPageUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $_error')),
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

  void _handlePaymentSuccess() {
    if (!_isWebViewOpen) return;
    
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bakiye başarıyla yüklendi!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _handlePaymentFailed() {
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
            // Kredi Kartı
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
                        Text('Havale Bilgileri', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Banka', 'Ziraat Bankası'),
                    _buildInfoRow('Hesap Adı', 'CizreApp Teknoloji A.Ş.'),
                    _buildInfoRow('IBAN', 'TR00 0000 0000 0000 0000 0000 00'),
                    const SizedBox(height: 8),
                    Text(
                      '⚠️ Açıklama kısmına telefon numaranızı yazınız.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bakiye 24 saat içinde yansıtılır.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
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
