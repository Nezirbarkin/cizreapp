import 'package:flutter/material.dart';

/// Stub implementation for mobile platforms
/// Mobil platformlar için stub implementasyon
Widget buildHtmlView(String htmlContent) {
  // Mobil platformda HTML gösterimi desteklenmiyor
  // Bunun yerine bir placeholder göster
  return Container(
    color: Colors.grey.shade200,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.code, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'HTML İçerik',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Bu içerik sadece web\'de görüntülenebilir',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );
}
