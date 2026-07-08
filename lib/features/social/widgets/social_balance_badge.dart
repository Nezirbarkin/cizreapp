// ignore_for_file: use_key_in_widget_constructors

import 'package:flutter/material.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/widgets/balance_header_widget.dart';
import '../../wallet/screens/wallet_screen.dart';

// Sosyal ekran için bakiye badge
class SocialBalanceBadge extends StatefulWidget {
  const SocialBalanceBadge();

  @override
  State<SocialBalanceBadge> createState() => SocialBalanceBadgeState();
}

class SocialBalanceBadgeState extends State<SocialBalanceBadge> {
  final BalanceService _balanceService = BalanceService();
  double? _balance;
  bool _isLoading = true;
  bool _showBalance = true;

  @override
  void initState() {
    super.initState();
    _checkShowBalance();
  }

  Future<void> _checkShowBalance() async {
    try {
      final shouldShow = await BalanceHeaderWidget.getShowBalance();
      if (mounted) {
        setState(() => _showBalance = shouldShow);
        if (shouldShow) {
          _loadBalance();
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBalance() async {
    try {
      final balance = await _balanceService.getBalance();
      if (mounted) {
        setState(() {
          _balance = balance?.availableBalance ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WalletScreen()),
    ).then((_) => _loadBalance());
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBalance) return const SizedBox.shrink();

    if (_isLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }

    return GestureDetector(
      onTap: _navigateToWallet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '₺${(_balance ?? 0).toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
