import 'package:flutter/material.dart';

import '../../../core/models/seller_announcement_model.dart';
import '../../../core/services/seller_announcement_service.dart';
import 'seller_announcement_card.dart';

/// Satıcı panelinin "Genel Bakış" sekmesinin en üstündeki duyuru bölümü.
///
/// Panel açılır açılmaz kendi kartlarını yükler; hiç kart yoksa (ya da yükleme
/// başarısızsa) hiçbir yer kaplamaz. En fazla [collapsedCount] kart açık
/// durur, kalanı "+N duyuru daha" ile açılır. Kapatma satıcı bazında sunucuya
/// yazılır; başarısız olursa kart geri gelir.
class SellerAnnouncementsSection extends StatefulWidget {
  const SellerAnnouncementsSection({
    super.key,
    required this.onAction,
    this.service,
    this.collapsedCount = 2,
  });

  /// Kartın eylem butonuna basıldığında; yönlendirmeyi panel yapar.
  final ValueChanged<SellerAnnouncement> onAction;

  /// Testlerde sahte servis vermek için.
  final SellerAnnouncementService? service;
  final int collapsedCount;

  @override
  State<SellerAnnouncementsSection> createState() =>
      _SellerAnnouncementsSectionState();
}

class _SellerAnnouncementsSectionState
    extends State<SellerAnnouncementsSection> {
  late final SellerAnnouncementService _service =
      widget.service ?? SellerAnnouncementService();

  List<SellerAnnouncement> _items = const [];
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.fetchMine();
      if (!mounted) return;
      setState(() => _items = list);
      // Turuncu "yeni" noktası bu açılışta görünsün, sonraki açılışta sönsün.
      _service.markSeen(
        list.where((a) => a.isNew && a.id != null).map((a) => a.id!).toList(),
      );
    } catch (e) {
      // Duyuru bölümü ikincil bir alan; hata panelin geri kalanını bozmasın.
      debugPrint('⚠️ satıcı duyuruları yüklenemedi: $e');
    }
  }

  Future<void> _dismiss(SellerAnnouncement item) async {
    final id = item.id;
    if (id == null) return;
    final before = _items;
    setState(() => _items = _items.where((a) => a.id != id).toList());
    try {
      await _service.dismiss(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duyuru kapatılamadı, tekrar deneyin')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    final visible = _expanded
        ? _items
        : _items.take(widget.collapsedCount).toList();
    final hidden = _items.length - widget.collapsedCount;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * -10), child: child),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
              child: Row(
                children: [
                  Icon(Icons.campaign_rounded,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Yönetimden duyurular',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_items.length}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final item in visible)
              SellerAnnouncementCard(
                key: ValueKey(item.id),
                item: item,
                onDismiss: item.isDismissible ? () => _dismiss(item) : null,
                onAction: item.hasAction ? () => widget.onAction(item) : null,
              ),
            if (hidden > 0)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _expanded ? 'Daha az göster' : '+$hidden duyuru daha',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
