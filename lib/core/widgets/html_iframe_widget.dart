import 'package:flutter/material.dart';

// Conditional import: mobil için stub, web için dart:html implementasyonu
import 'html_iframe_stub_impl.dart'
    if (dart.library.html) 'html_iframe_web_impl.dart';

/// HTML içerik gösterme widget'ı
/// Web: dart:html iframe ile render
/// Mobil: WebView ile HTML render
class HtmlIframeWidget extends StatefulWidget {
  final String htmlContent;
  final double? width;
  final double? height;

  const HtmlIframeWidget({
    super.key,
    required this.htmlContent,
    this.width,
    this.height,
  });

  @override
  State<HtmlIframeWidget> createState() => _HtmlIframeWidgetState();
}

class _HtmlIframeWidgetState extends State<HtmlIframeWidget> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    // Sabit viewId - rebuild'te değişmez
    _viewId = 'html-iframe-${widget.htmlContent.hashCode}';
    // Web'de iframe kaydını bir kere yap
    registerWebView(_viewId, widget.htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return buildHtmlView(
      htmlContent: widget.htmlContent,
      width: widget.width ?? double.infinity,
      height: widget.height ?? 200,
      viewId: _viewId,
    );
  }
}
