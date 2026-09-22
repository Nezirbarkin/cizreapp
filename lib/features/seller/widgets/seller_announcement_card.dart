import 'package:flutter/material.dart';

import '../../../core/models/seller_announcement_model.dart';

/// Tek bir duyuru kartı. Satıcı panelinde ve admin düzenleyicisindeki canlı
/// önizlemede aynı bileşen kullanılır; böylece admin ne yazarsa satıcı onu
/// aynen görür.
class SellerAnnouncementCard extends StatelessWidget {
  const SellerAnnouncementCard({
    super.key,
    required this.item,
    this.onDismiss,
    this.onAction,
  });

  final SellerAnnouncement item;

  /// null ise kapatma düğmesi çizilmez (kapatılamayan kartlar için).
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = item.type.style;
    final canDismiss = onDismiss != null && item.isDismissible;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.border),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(11, 11, canDismiss ? 30 : 11, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: s.iconBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(s.icon, size: 20, color: s.iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: s.title,
                              height: 1.25,
                            ),
                          ),
                          if (item.type == AnnouncementType.urgent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: s.text, width: 0.6),
                              ),
                              child: Text(
                                'Önemli',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: s.text,
                                ),
                              ),
                            ),
                          if (item.isNew)
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: Colors.orange.shade700,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.message,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: s.text,
                          height: 1.35,
                        ),
                      ),
                      if (item.hasAction)
                        InkWell(
                          onTap: onAction,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    item.actionLabel!.trim(),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: s.title,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15,
                                  color: s.title,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (canDismiss)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                onPressed: onDismiss,
                tooltip: 'Kapat',
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                color: Colors.black54,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
