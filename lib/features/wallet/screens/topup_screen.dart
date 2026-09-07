import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/services/bank_account_service.dart';
import '../../../core/services/transfer_service.dart';
import '../../../core/models/bank_account_model.dart';

/// Bakiye Yükleme Ekranı - Modern Tasarım
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  final BalanceService _balanceService = BalanceService();
  final BankAccountService _bankAccountService = BankAccountService();
  final TransferService _transferService = TransferService();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _senderNameController = TextEditingController();
  final _senderNameFormKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isWebViewOpen = false;
  bool _isLoadingBanks = true;
  bool _isCheckingPending = true;
  bool _hasPendingConfirmation = false;
  String? _error;
  WebViewController? _webViewController;
  String _selectedMethod = 'card';
  List<BankAccount> _bankAccounts = [];
  BankAccount? _selectedBankAccount;
  bool _cardTopupEnabled = true;
  String? _conversationId;
  bool _paymentHandled = false;

  final List<double> _quickAmounts = [50, 100, 200, 500];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadBankAccounts();
    _loadPendingStatus();
  }

  Future<void> _loadPendingStatus() async {
    final hasPending = await _transferService.hasPendingConfirmation();
    if (mounted) {
      setState(() {
        _hasPendingConfirmation = hasPending;
        _isCheckingPending = false;
      });
    }
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label kopyalandı'),
                  duration: const Duration(seconds: 1),
                  backgroundColor: Colors.green.shade600,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.copy_rounded,
                size: 16,
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitTransferConfirmation(BuildContext context) async {
    final raw = _amountController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lütfen tutar girin'),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    final amount = double.tryParse(raw) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Geçersiz tutar'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final form = _senderNameFormKey.currentState;
    if (form == null || !form.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lütfen gönderen ad soyad bilgisini girin'),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _transferService.submitTransferConfirmation(
        amount: amount,
        senderFullName: _senderNameController.text.trim(),
        bankAccountId: _selectedBankAccount?.id,
      );

      if (!mounted) return;
      if (!context.mounted) return;
      setState(() => _hasPendingConfirmation = true);
      final bankName = _selectedBankAccount?.bankName ?? 'seçili banka';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bildiriminiz alındı. ₺${amount.toStringAsFixed(2)} tutarındaki '
            '$bankName havaleniz admin onayından sonra bakiyenize yansıyacak.',
          ),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e.toString())),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('oturum') ||
        lower.contains('session') ||
        lower.contains('expired') ||
        lower.contains('unauthorized')) {
      return 'Ödeme sağlayıcısına bağlanılamıyor. Lütfen tekrar deneyin.';
    }
    if (lower.contains('yapılandırılmamış') || lower.contains('credentials')) {
      return 'Ödeme sistemi henüz yapılandırılmamış.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Bağlantı sorunu. İnternetinizi kontrol edin.';
    }
    if (lower.contains('rate') || lower.contains('limit')) {
      return 'Çok fazla deneme yaptınız. Lütfen bekleyin.';
    }
    return 'Hata: $raw';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _senderNameController.dispose();
    super.dispose();
  }

  Future<void> _initializeTopup(double amount) async {
    if (amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Minimum yükleme tutarı 10 TL\'dir'),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    if (_selectedMethod == 'card' && !_cardTopupEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Kredi kartı ile ödeme şu an kapalı. Havale/EFT kullanın.',
          ),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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

      _conversationId = result.conversationId;
      _paymentHandled = false;
      _openPaymentWebView(result.paymentPageUrl);
    } catch (e) {
      if (!mounted) return;

      String errorMessage = e.toString();

      for (final prefix in ['Exception: ', 'FriendlyException: ']) {
        if (errorMessage.startsWith(prefix)) {
          errorMessage = errorMessage.substring(prefix.length);
          break;
        }
      }

      final lower = errorMessage.toLowerCase();
      if (lower.contains('oturum') ||
          lower.contains('session') ||
          lower.contains('expired') ||
          lower.contains('unauthorized') ||
          lower.contains('yapılandırılmamış') ||
          lower.contains('credentials')) {
        errorMessage = _friendlyError(errorMessage);
      } else if (errorMessage.contains('"code"') &&
          errorMessage.contains('"message"')) {
        try {
          final match = RegExp(
            r'"message"\s*:\s*"([^"]+)"',
          ).firstMatch(errorMessage);
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
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
              debugPrint('WebView: $url');
              if (url.contains('balance-success') || url.contains('success')) {
                _handlePaymentSuccess();
              } else if (url.contains('balance-failed') ||
                  url.contains('fail')) {
                _handlePaymentFailed();
              }
            },
            onPageFinished: (String url) {
              debugPrint('WebView finished: $url');
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

    setState(() {
      _isWebViewOpen = false;
      _webViewController = null;
      _isLoading = true;
    });

    bool confirmed = false;
    if (_conversationId != null) {
      for (int i = 0; i < 5; i++) {
        confirmed = await _balanceService.checkTopupStatus(_conversationId!);
        if (confirmed) break;
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (!mounted) return;

    if (confirmed) {
      // Messenger pop'TAN ÖNCE çözülür; pop'tan sonra bu element deactive
      // olur ve `ScaffoldMessenger.of(context)` "Looking up a deactivated
      // widget's ancestor is unsafe" atar.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Bakiye başarıyla yüklendi!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Ödeme alındı, bakiyeye yansıması birkaç dakika sürebilir.',
          ),
          backgroundColor: Colors.orange.shade600,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
      SnackBar(
        content: const Text('Ödeme başarısız oldu'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final theme = Theme.of(context);

    if (_isWebViewOpen && _webViewController != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ödeme'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _closeWebView,
          ),
        ),
        body: WebViewWidget(controller: _webViewController!),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Bakiye Yükle',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst Bilgi Kartı
            _buildHeaderCard(theme),
            const SizedBox(height: 24),

            // Ödeme Yöntemi Seçimi
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildPaymentMethods(theme),
            ),
            const SizedBox(height: 24),

            // Hızlı Seçenekler
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildQuickAmounts(theme),
            ),
            const SizedBox(height: 20),

            // Tutar Girişi
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildAmountInput(theme),
            ),

            // Havale Bilgileri
            if (_selectedMethod == 'transfer') ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTransferSection(theme),
              ),
            ],

            // Yükle Butonu
            if (_selectedMethod == 'card') ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTopupButton(theme),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade600, Colors.blue.shade800],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bakiye Yükleme',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Minimum yükleme: 10 TL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ödeme Yöntemi',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),

        // Kredi Kartı
        if (_cardTopupEnabled) ...[
          _buildMethodCard(
            theme,
            icon: Icons.credit_card_rounded,
            title: 'Kredi Kartı / Banka Kartı',
            subtitle: 'İyzico güvenli ödeme',
            method: 'card',
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kredi kartı ile ödeme şu an kapalıdır.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Havale / EFT
        _buildMethodCard(
          theme,
          icon: Icons.account_balance_rounded,
          title: 'Havale / EFT',
          subtitle: 'Banka havalesi ile yükleme',
          method: 'transfer',
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildMethodCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String method,
    required Color color,
  }) {
    final isSelected = _selectedMethod == method;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? color : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedMethod = method),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? color : Colors.grey.shade600,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isSelected ? color : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAmounts(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hızlı Seç',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: _quickAmounts.map((amount) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: amount != _quickAmounts.last ? 10 : 0,
                ),
                child: _buildQuickAmountChip(theme, amount),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildQuickAmountChip(ThemeData theme, double amount) {
    final isSelected = _amountController.text == amount.toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading
            ? null
            : () {
                setState(() {
                  _amountController.text = amount.toString();
                });
              },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '₺$amount',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountInput(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'veya tutar girin',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Tutar',
              prefixText: '₺ ',
              prefixStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransferSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banka Seçimi
        if (_isLoadingBanks)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (_bankAccounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aktif banka hesabı bulunmuyor.',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Banka Seçimi
          if (_bankAccounts.length > 1) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_rounded,
                        color: Colors.purple.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Havale Yapılacak Banka',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<BankAccount>(
                      isExpanded: true,
                      underline: const SizedBox(),
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
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Havale Bilgileri
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Havale Bilgileri',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildInfoRow('Banka', _selectedBankAccount?.bankName ?? '-'),
                _buildInfoRow(
                  'Hesap',
                  _selectedBankAccount?.accountName ?? '-',
                ),
                _buildInfoRow('IBAN', _selectedBankAccount?.iban ?? '-'),
                if (_selectedBankAccount?.branch != null &&
                    _selectedBankAccount!.branch!.isNotEmpty)
                  _buildInfoRow('Şube', _selectedBankAccount!.branch!),
                if (_selectedBankAccount?.description != null &&
                    _selectedBankAccount!.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.note_outlined,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _selectedBankAccount!.description!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Bakiye 0-1 saatte otomatik yansıtılır.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Zaten onay bekleyen bir bildirim varsa formu gösterme
          if (_hasPendingConfirmation)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Zaten onay bekleyen bir havale bildiriminiz var. '
                      'Yeni bildirim gönderebilmek için admin onayını/reddini bekleyin.',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            // Bildirim Formu
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Form(
                key: _senderNameFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Havale Yaptınız Mı?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Havale işlemini tamamladıysanız, admin\'e bildirim gönderin.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _senderNameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Gönderen Ad Soyad *',
                        hintText: 'Havaleyi yapan kişinin adı soyadı',
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.green.shade700,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) {
                          return 'Gönderen ad soyad zorunludur';
                        }
                        if (v.length < 3) {
                          return 'En az 3 karakter girin';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.shade600,
                              Colors.green.shade700,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: (_isLoading || _isCheckingPending)
                                ? null
                                : () => _submitTransferConfirmation(context),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isLoading)
                                    const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Sisteme Bildir',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildTopupButton(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading
              ? null
              : () {
                  final amount = double.tryParse(_amountController.text) ?? 0;
                  _initializeTopup(amount);
                },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lock_open_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Ödemeye Geç',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
