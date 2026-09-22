import 'package:flutter/material.dart';

import '../../services/payout_service.dart';
import '../balance_status_card.dart';
import '../common/seller_stat_card.dart';

/// Satıcı panelinin "Ödemeler" sekmesi.
///
/// Eskiden ayrı "Ödemeler" ve "Geçmiş" üst-sekmeleri olan içerik artık tek
/// sekme içinde, üstte sabit [BalanceStatusCard] + altında bir
/// [SegmentedButton] ile değişen iki bölüm olarak sunuluyor. Tüm veri
/// çekme/mutasyon mantığı `SellerDashboardScreen`'de kalır.
class SellerPaymentsTab extends StatefulWidget {
  const SellerPaymentsTab({
    super.key,
    required this.shopInfo,
    required this.payoutService,
    required this.pendingPayout,
    required this.totalPaid,
    required this.availablePayout,
    required this.pendingRequestsTotal,
    required this.adminCredit,
    required this.hasOwnCourier,
    required this.payoutRequests,
    required this.onEditIban,
    required this.onCreatePayoutRequest,
    required this.onCancelPayoutRequest,
  });

  final Map<String, dynamic>? shopInfo;
  final PayoutService payoutService;
  final double pendingPayout;
  final double totalPaid;
  final double availablePayout;
  final double pendingRequestsTotal;
  final double adminCredit;
  final bool hasOwnCourier;
  final List<Map<String, dynamic>> payoutRequests;
  final VoidCallback onEditIban;
  final VoidCallback onCreatePayoutRequest;
  final Future<void> Function(String payoutId) onCancelPayoutRequest;

  @override
  State<SellerPaymentsTab> createState() => _SellerPaymentsTabState();
}

class _SellerPaymentsTabState extends State<SellerPaymentsTab> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final shopInfo = widget.shopInfo;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shopInfo != null)
            BalanceStatusCard(
              shopId: shopInfo['id'],
              payoutService: widget.payoutService,
            ),
          const SizedBox(height: 16),

          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Güncel Durum'), icon: Icon(Icons.payments_outlined)),
                ButtonSegment(value: true, label: Text('Geçmiş'), icon: Icon(Icons.history)),
              ],
              selected: {_showHistory},
              onSelectionChanged: (selection) => setState(() => _showHistory = selection.first),
            ),
          ),
          const SizedBox(height: 20),

          if (_showHistory) _buildHistorySection() else _buildCurrentSection(context, primary, shopInfo),
        ],
      ),
    );
  }

  Widget _buildCurrentSection(BuildContext context, Color primary, Map<String, dynamic>? shopInfo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Özet Kartları
        Row(
          children: [
            Expanded(
              child: SellerStatCard(
                title: 'Bekleyen Ödeme',
                value: '₺${widget.pendingPayout.toStringAsFixed(2)}',
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SellerStatCard(
                title: 'Toplam Ödenen',
                value: '₺${widget.totalPaid.toStringAsFixed(2)}',
                icon: Icons.check_circle_outline,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // IBAN Bilgileri
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.credit_card, color: primary),
                        const SizedBox(width: 12),
                        const Text(
                          'IBAN Bilgileri',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: widget.onEditIban,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Düzenle'),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (shopInfo?['iban'] != null && shopInfo!['iban'].toString().isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow('IBAN', _formatIban(shopInfo['iban'])),
                      const SizedBox(height: 12),
                      _infoRow('Banka', shopInfo['bank_name'] ?? '-'),
                      const SizedBox(height: 12),
                      _infoRow('Hesap Sahibi', shopInfo['account_holder_name'] ?? '-'),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'IBAN bilgisi girmelisiniz. Ödeme talebi oluşturabilmek için lütfen bilgilerinizi ekleyin.',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Kuryesi olmayan satıcılar için Bilgilendirme Kartı
        if (!widget.hasOwnCourier)
          Card(
            color: Colors.purple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.purple.shade700),
                      const SizedBox(width: 12),
                      const Text(
                        'Platform Kargo Kullanıyorsunuz',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _infoRow('Ödenebilir Tutar', '₺${widget.adminCredit.toStringAsFixed(2)}'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 18, color: Colors.purple.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Kuryeniz olmadığı için her siparişten komisyon ve teslimat ücreti otomatik düşülür. Kalan tutar ödeme alabilirsiniz.',
                            style: TextStyle(color: Colors.purple.shade900, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!widget.hasOwnCourier) const SizedBox(height: 24),

        // Bekleyen Ödeme İstekleri
        if (widget.payoutRequests.any((p) => p['status'] == 'pending'))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bekleyen Ödeme İstekleri',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${widget.payoutRequests.where((p) => p['status'] == 'pending').length}',
                      style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...widget.payoutRequests.where((p) => p['status'] == 'pending').map(_buildPayoutRequestCard),
            ],
          ),

        const SizedBox(height: 24),

        // Yeni Ödeme İsteği Butonu
        if (widget.availablePayout > 0)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onCreatePayoutRequest,
              icon: const Icon(Icons.request_quote_outlined),
              label: Text('Ödeme İsteği Oluştur (₺${widget.availablePayout.toStringAsFixed(2)} kullanılabilir)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.pendingRequestsTotal > 0
                          ? 'Tüm bekleyen ödemeniz için zaten talep oluşturdunuz. Admin onayı bekleyin.'
                          : 'Kullanılabilir ödeme tutarınız bulunmamaktadır.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistorySection() {
    final completedRequests = widget.payoutRequests.where((p) => p['status'] != 'pending');

    if (completedRequests.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Henüz ödeme geçmişi yok', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(children: completedRequests.map(_buildPayoutRequestCard).toList());
  }

  Widget _buildPayoutRequestCard(Map<String, dynamic> payout) {
    final status = payout['status'] as String? ?? 'pending';
    final statusColor = PayoutService.getStatusColorValue(status);
    final statusText = PayoutService.getStatusText(status);
    final amount = (payout['total_amount'] as num?)?.toDouble() ?? 0.0;
    final deliveryFeeDeducted = (payout['delivery_fee_deducted'] as num?)?.toDouble() ?? 0.0;
    final deductionDetail = payout['deduction_detail'] as String?;

    String? rejectionReason;
    if (status == 'rejected' && payout['rejection_reason'] != null) {
      rejectionReason = payout['rejection_reason'].toString();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₺${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(statusColor).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: Color(statusColor), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _payoutInfoRow('Talep Tarihi', _formatDate(payout['requested_at'])),
            if (payout['reviewed_at'] != null) _payoutInfoRow('İnceleme Tarihi', _formatDate(payout['reviewed_at'])),
            if (payout['paid_at'] != null) _payoutInfoRow('Ödeme Tarihi', _formatDate(payout['paid_at'])),
            if (deliveryFeeDeducted > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.local_shipping, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        deductionDetail ?? 'Teslimat ücreti kesintisi: ₺${deliveryFeeDeducted.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (rejectionReason != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Red Sebebi: $rejectionReason',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => widget.onCancelPayoutRequest(payout['id']),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('İptal Et'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.shade300),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _payoutInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _formatIban(String iban) {
    if (iban.length != 26) return iban;
    return '${iban.substring(0, 2)} ${iban.substring(2, 6)} ${iban.substring(6, 10)} ${iban.substring(10, 14)} ${iban.substring(14, 18)} ${iban.substring(18, 22)} ${iban.substring(22, 26)}';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    final dateTime = date is String ? DateTime.parse(date) : date as DateTime;
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
