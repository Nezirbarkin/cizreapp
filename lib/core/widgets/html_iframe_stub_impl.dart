/// Mobil platform implementasyonu
/// webview_flutter ile HTML içeriklerini render eder

// ignore_for_file: dangling_library_doc_comments

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildHtmlView({
  required String htmlContent,
  required double width,
  required double height,
  String? viewId,
}) {
  return _MobileHtmlView(
    htmlContent: htmlContent,
    width: width,
    height: height,
  );
}

void registerWebView(String viewId, String htmlContent) {
  // Mobilde kayıt gerekmez
}

class _MobileHtmlView extends StatefulWidget {
  final String htmlContent;
  final double width;
  final double height;

  const _MobileHtmlView({
    required this.htmlContent,
    required this.width,
    required this.height,
  });

  @override
  State<_MobileHtmlView> createState() => _MobileHtmlViewState();
}

class _MobileHtmlViewState extends State<_MobileHtmlView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(widget.htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
