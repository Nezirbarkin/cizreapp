// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web platformunda URL'yi yeni sekmede aç
void openUrlInNewTab(String url) {
  html.window.open(url, '_blank');
}

/// Web'de WebView yok - boş container döndür (kullanılmaz)
Widget buildWebView({
  required String paymentUrl,
  required VoidCallback onPageFinished,
  required Function(String) onError,
}) {
  return const SizedBox.shrink();
}
