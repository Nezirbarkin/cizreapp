part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Yardimci metotlar
  // ==========================================================================

  // --- _formatDate ---
  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return '-';
    }
  }

  // --- _formatDateTime ---
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dk önce';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} saat önce';
    } else {
      return '${difference.inDays} gün önce';
    }
  }

  // --- _isValidImageUrl ---
  bool _isValidImageUrl(dynamic url) {
    if (url == null) return false;
    final urlStr = url.toString().trim();
    if (urlStr.isEmpty) return false;
    return urlStr.startsWith('http://') || urlStr.startsWith('https://');
  }
}
