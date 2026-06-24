import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/balance_service.dart';
import '../../features/wallet/screens/wallet_screen.dart';

/// Üst Barda Bakiye Widget'ı - Sadece metin, ikonsuz
class BalanceHeaderWidget extends StatefulWidget {
  final bool showBalance;
  final VoidCallback? onBalanceChanged;
  
  // SharedPreferences anahtarı
  static const String _prefKey = 'show_balance_header';

  const BalanceHeaderWidget({
    super.key,
    this.showBalance = true,
    this.onBalanceChanged,
  });

  /// Bakiye header gösterimini değiştir
  static Future<void> setShowBalance(bool show) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, show);
    } catch (e) {
      debugPrint('Bakiye header ayarı kaydedilemedi: $e');
    }
  }

  /// Bakiye header gösterim durumunu al
  static Future<bool> getShowBalance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? true; // Varsayılan: göster
    } catch (e) {
      return true;
    }
  }

  @override
  State<BalanceHeaderWidget> createState() => _BalanceHeaderWidgetState();
}

class _BalanceHeaderWidgetState extends State<BalanceHeaderWidget> {
  final BalanceService _balanceService = BalanceService();
  double? _balance;
  bool _isLoading = true;
  bool _showBalance = true;

  @override
  void initState() {
    super.initState();
    _checkShowBalance();
    if (_showBalance) {
      _loadBalance();
    }
  }

  Future<void> _checkShowBalance() async {
    bool shouldShow = widget.showBalance;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(BalanceHeaderWidget._prefKey)) {
        shouldShow = prefs.getBool(BalanceHeaderWidget._prefKey) ?? true;
      }
    } catch (e) {
      // Varsayılanı kullan
    }
    
    if (mounted && _showBalance != shouldShow) {
      setState(() {
        _showBalance = shouldShow;
      });
    }
  }

  Future<void> _loadBalance() async {
    if (!_showBalance) return;
    
    setState(() => _isLoading = true);
    
    try {
      final balance = await _balanceService.getBalance();
      if (mounted) {
        setState(() {
          _balance = balance?.availableBalance ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WalletScreen()),
    ).then((_) {
      _loadBalance();
      widget.onBalanceChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBalance) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }

    return GestureDetector(
      onTap: _navigateToWallet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Text(
          '₺${(_balance ?? 0).toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
