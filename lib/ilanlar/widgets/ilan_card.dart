import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../models/ilan_models.dart';
import '../utils/ilan_ui.dart';

class IlanCard extends StatelessWidget {
  const IlanCard({
    super.key,
    required this.ilan,
    required this.onTap,
    this.compact = false,
    this.showPrice = true,
    this.showStats = true,
    this.showStatusBadge = false,
    this.onDelete,
  });

  final Ilan ilan;
  final VoidCallback onTap;
  final bool compact;
  final bool showPrice;
  final bool showStats;
  final bool showStatusBadge;
  final VoidCallback? onDelete;

  bool get _isNew =>
      DateTime.now().difference(ilan.createdAt) < const Duration(hours: 48);

  @override
  Widget build(BuildContext context) {
    final color = IlanUi.color(ilan.category?.colorHex ?? '#6D28D9');
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: compact ? 220 : null,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: compact ? 1.65 : 1.7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ilan.coverImageUrl != null)
                      CachedNetworkImage(
                        imageUrl: ilan.coverImageUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 700,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey.shade100),
                        errorWidget: (_, __, ___) => _placeholder(color),
                      )
                    else
                      _placeholder(color),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ilan.category?.name ?? 'İlan',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (_isNew)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.success,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Yeni',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ilan.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (showPrice) ...[
                      Text(
                        IlanUi.price(ilan),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ilan.hasPrice ? color : Colors.grey.shade600,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                    ],
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            ilan.locationText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showStats || showStatusBadge) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (showStats) ...[
                            Icon(
                              Icons.visibility_outlined,
                              size: 13,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${ilan.viewCount}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.favorite_border,
                              size: 13,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${ilan.favoriteCount}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          if (showStatusBadge) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: IlanUi.statusColor(
                                  ilan.status,
                                ).withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                IlanUi.status(ilan.status),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: IlanUi.statusColor(ilan.status),
                                ),
                              ),
                            ),
                          ],
                          if (onDelete != null) ...[
                            if (!showStatusBadge) const Spacer(),
                            SizedBox(
                              width: 26,
                              height: 26,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 16,
                                tooltip: 'Sil',
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red.shade400,
                                onPressed: onDelete,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (IlanUi.remainingLabel(ilan) case final label?) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 13,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(Color color) => Container(
    color: color.withValues(alpha: .08),
    child: Icon(
      IlanUi.icon(ilan.category?.iconName ?? 'category'),
      size: 48,
      color: color.withValues(alpha: .65),
    ),
  );
}
