import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/services/payment_service.dart';
import 'orders_screen.dart';
import 'payment_webview_mobile.dart' if (dart.library.html) 'payment_webview_web.dart' as platform;

/// iyzico 3D Secure Ödeme Ekranı
/// Mobil: WebView'de iyzico ödeme sayfasını gösterir
/// Web: Yeni sekmede açar ve polling ile sonucu takip eder
class PaymentWebViewScreen extends StatefulWidget {
  final String paymentUrl;
  final String paymentTransactionId;
  final String conversationId;
  final VoidCallback? onPaymentSuccess;
  final VoidCallback? onPaymentFailure;

  const PaymentWebViewScreen({
    super.key,
    required this.paymentUrl,
    required this.paymentTransactionId,
    required this.conversationId,
    this.onPaymentSuccess,
    this.onPaymentFailure,
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;

  int _pollCount = 0;
  static const int _maxPollCount = 60;
  static const int _pollIntervalMs = 2000;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // Web'de yeni sekmede aç
      platform.openUrlInNewTab(widget.paymentUrl);
      setState(() {
        _isLoading = false;
      });
    } else {
      // Mobilde WebView oluştur (bir kez, initState'te)
      _initializeWebView();
    }

    _startPaymentStatusPolling();
  }

  /// Mobil: WebView controller'ı bir kez oluştur
  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            debugPrint('🌐 PAYMENT WV: Page finished - $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            debugPrint('🌐 PAYMENT WV: Page started - $url');
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('🌐 PAYMENT WV: Navigation - ${request.url}');
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ PAYMENT WV: Error - ${error.description}');
            
            // Tracking script hatalarını gösterme
            final isTrackingError = error.description.contains('ERR_NAME_NOT_RESOLVED') ||
                                   error.errorCode == -2;
            
            if (!isTrackingError && mounted) {
              if (error.errorType == WebResourceErrorType.hostLookup &&
                  error.errorCode != -2) {
                setState(() {
                  _errorMessage = 'İnternet bağlantısı hatası. Lütfen tekrar deneyin.';
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  /// Ödeme durumunu periyodik olarak kontrol et
  void _startPaymentStatusPolling() {
    Future.doWhile(() async {
      await Future.delayed(
          const Duration(milliseconds: _pollIntervalMs));

      if (!mounted) return false;

      _pollCount++;

      if (_pollCount >= _maxPollCount) {
        debugPrint('⏱️ PAYMENT WV: Polling timeout');
        if (mounted) {
          setState(() {
            _errorMessage =
                'Ödeme işlemi zaman aşımına uğradı. Lütfen tekrar deneyin.';
          });
        }
        return false;
      }

      final paymentService = PaymentService();
      try {
        final status = await paymentService
            .checkPaymentStatus(widget.paymentTransactionId);

        debugPrint(
            '🔍 PAYMENT WV: Poll $_pollCount - Status: ${status.status}');

        if (status.isSuccess) {
          debugPrint('✅ PAYMENT WV: Ödeme BAŞARILI!');
          _handlePaymentSuccess(status.orderId);
          return false;
        } else if (status.isFailure) {
          debugPrint('❌ PAYMENT WV: Ödeme BAŞARISIZ!');
          _handlePaymentFailure();
          return false;
        } else if (status.isCancelled) {
          debugPrint('🚫 PAYMENT WV: Ödeme İPTAL!');
          _handlePaymentCancelled();
          return false;
        }

        return true;
      } catch (e) {
        debugPrint('⚠️ PAYMENT WV: Polling error - $e');
        return true;
      }
    });
  }

  void _handlePaymentSuccess(String? orderId) {
    if (_isProcessing || !mounted) return;
    setState(() {
      _isProcessing = true;
    });

    widget.onPaymentSuccess?.call();

    if (!mounted) return;

    if (kIsWeb) {
      // Web'de: Dialog yerine direkt siparişler sayfasına git
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const OrdersScreen(),
        ),
      );
    } else {
      // Mobilde: Dialog göster, sonra siparişler sayfasına git
      _showResultDialog(
        title: 'Ödeme Başarılı! 🎉',
        message: 'Siparişiniz başarıyla oluşturuldu.',
        isSuccess: true,
        onDismiss: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const OrdersScreen(),
            ),
          );
        },
      );
    }
  }

  void _handlePaymentFailure() {
    if (_isProcessing || !mounted) return;
    setState(() {
      _isProcessing = true;
    });

    widget.onPaymentFailure?.call();

    if (mounted) {
      _showResultDialog(
        title: 'Ödeme Başarısız',
        message:
            'Ödeme işlemi başarısız oldu. Lütfen kart bilgilerinizi kontrol edip tekrar deneyin.',
        isSuccess: false,
        onDismiss: () {
          Navigator.of(context).pop(false);
        },
      );
    }
  }

  void _handlePaymentCancelled() {
    if (_isProcessing || !mounted) return;

    final paymentService = PaymentService();
    paymentService
        .cancelPaymentTransaction(widget.paymentTransactionId);

    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  void _showResultDialog({
    required String title,
    required String message,
    required bool isSuccess,
    required VoidCallback onDismiss,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess ? Colors.green : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDismiss();
            },
            child: Text(isSuccess ? 'Siparişlerime Git' : 'Tamam'),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ödeme İptal'),
        content: const Text(
          'Ödeme işlemini iptal etmek istediğinizden emin misiniz?\n\n'
          'İptal ederseniz sepetiniz korunacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hayır, Devam Et'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _handlePaymentCancelled();
            },
            child: const Text(
              'Evet, İptal Et',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Web'de: Ödeme sayfası yeni sekmede açılır, burada sadece bekleme ekranı gösterilir
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Güvenli Ödeme'),
          centerTitle: true,
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _showCancelConfirmation,
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_errorMessage != null) ...[
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 16, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Geri Dön'),
                  ),
                ] else if (_isProcessing) ...[
                  const CircularProgressIndicator(color: Colors.green),
                  const SizedBox(height: 16),
                  const Text(
                    'Ödeme işleniyor...',
                    style: TextStyle(fontSize: 16),
                  ),
                ] else ...[
                  const Icon(Icons.open_in_new, size: 64, color: Colors.green),
                  const SizedBox(height: 24),
                  const Text(
                    'Ödeme sayfası yeni sekmede açıldı',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Lütfen açılan sekmede ödemenizi tamamlayın.\n'
                    'Bu sayfa otomatik olarak güncellenecektir.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(color: Colors.green),
                  const SizedBox(height: 16),
                  Text(
                    'Ödeme bekleniyor... ($_pollCount/$_maxPollCount)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: () {
                      platform.openUrlInNewTab(widget.paymentUrl);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Ödeme Sayfasını Tekrar Aç'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Mobil: WebView ile ödeme sayfası göster
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showCancelConfirmation();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Güvenli Ödeme'),
          centerTitle: true,
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _showCancelConfirmation,
          ),
        ),
        body: Stack(
          children: [
            // Error state
            if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Geri Dön'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // WebView (state'te tutulan controller ile - yanıp sönmeyi önler)
              if (_webViewController != null)
                WebViewWidget(controller: _webViewController!),
              // Loading overlay
              if (_isLoading)
                Container(
                  color: Colors.white,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.green),
                        SizedBox(height: 16),
                        Text(
                          'Güvenli ödeme sayfası yükleniyor...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            // Processing overlay
            if (_isProcessing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Ödeme işleniyor...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              top: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, color: Colors.green, size: 14),
              SizedBox(width: 6),
              Text(
                'Ödemeniz 256-bit SSL şifreleme ile korunmaktadır',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
