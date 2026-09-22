import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/models/admin_notification_model.dart';
import 'admin_ui.dart';

/// Hata nesnesinden kullanıcıya gösterilecek kısa Türkçe metin.
String adminNotifError(Object e) {
  if (e is PostgrestException) {
    if (e.code == '42501') return 'Bu işlem için admin yetkisi gerekiyor.';
    final m = e.message.trim();
    if (m.isNotEmpty) return m;
  }
  return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
}

/// `profiles.role` değerinin Türkçe karşılığı.
String adminRoleLabel(String? role) {
  switch (role) {
    case 'customer':
      return 'Müşteri';
    case 'seller':
      return 'Satıcı';
    case 'courier':
      return 'Kurye';
    case 'driver':
      return 'Sürücü';
    case 'admin':
      return 'Yönetici';
    case 'news':
      return 'Haber';
    default:
      return role ?? '';
  }
}

/// Bildirimin ikonunu renkli, yumuşak bir kutuda gösterir.
class AdminNotifBubble extends StatelessWidget {
  const AdminNotifBubble({super.key, required this.icon, this.size = 44});

  final AdminNotifIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Amber/sarı, açık zeminde okunmuyor; ön planı bir ton koyu al.
    final fg = icon.color is MaterialColor
        ? (icon.color as MaterialColor).shade700
        : icon.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: icon.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon.icon, color: fg, size: size * 0.5),
    );
  }
}

/// Bildirimin kullanıcıda nasıl görüneceğinin canlı önizlemesi:
/// telefon kilit ekranındaki push ve uygulama içi bildirim kutusu.
class AdminNotifPreview extends StatefulWidget {
  const AdminNotifPreview({
    super.key,
    required this.title,
    required this.body,
    required this.iconKey,
  });

  final String title;
  final String body;
  final String iconKey;

  @override
  State<AdminNotifPreview> createState() => _AdminNotifPreviewState();
}

const TextStyle _segStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);

class _AdminNotifPreviewState extends State<AdminNotifPreview> {
  bool _push = true;

  @override
  Widget build(BuildContext context) {
    final icon = adminNotifIcon(widget.iconKey);
    final title = widget.title.trim().isEmpty ? 'Bildirim başlığı' : widget.title.trim();
    final body = widget.body.trim().isEmpty
        ? 'Mesajınız burada görünecek.'
        : widget.body.trim();
    final placeholder = widget.title.trim().isEmpty && widget.body.trim().isEmpty;

    return AdminCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 17, color: AdminUi.muted),
              const SizedBox(width: 6),
              const Text(
                'Önizleme',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AdminUi.ink,
                ),
              ),
              const Spacer(),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: AdminUi.brandSoft,
                  selectedForegroundColor: AdminUi.brand,
                ),
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Push', style: _segStyle),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Uygulama', style: _segStyle),
                  ),
                ],
                selected: {_push},
                onSelectionChanged: (s) => setState(() => _push = s.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _push
                ? _PushPreview(
                    key: const ValueKey('push'),
                    title: title,
                    body: body,
                    faded: placeholder,
                  )
                : _InboxPreview(
                    key: const ValueKey('inbox'),
                    title: title,
                    body: body,
                    icon: icon,
                    faded: placeholder,
                  ),
          ),
        ],
      ),
    );
  }
}

class _PushPreview extends StatelessWidget {
  const _PushPreview({
    super.key,
    required this.title,
    required this.body,
    required this.faded,
  });

  final String title;
  final String body;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade900, Colors.purple.shade800],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AdminUi.brand,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.notifications_rounded, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Opacity(
                opacity: faded ? 0.55 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'CIZREAPP',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.muted,
                          ),
                        ),
                        Spacer(),
                        Text('şimdi', style: TextStyle(fontSize: 10.5, color: AdminUi.muted)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, height: 1.3, color: AdminUi.ink),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxPreview extends StatelessWidget {
  const _InboxPreview({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.faded,
  });

  final String title;
  final String body;
  final AdminNotifIcon icon;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.page,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.line),
      ),
      child: Opacity(
        opacity: faded ? 0.55 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminNotifBubble(icon: icon, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AdminUi.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AdminUi.brand,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, height: 1.35, color: AdminUi.muted),
                  ),
                  const SizedBox(height: 6),
                  const Text('şimdi', style: TextStyle(fontSize: 11, color: AdminUi.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste kartı: ikon, başlık, hedef kitle, okunma çubuğu; uzun basınca seçilir.
class AdminNotifCard extends StatelessWidget {
  const AdminNotifCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
    this.selected = false,
    this.selectionMode = false,
  });

  final AdminNotification item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<AdminNotifAction> onAction;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final icon = item.icon;
    final radius = BorderRadius.circular(16);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? AdminUi.brandSoft : AdminUi.surface,
        borderRadius: radius,
        border: Border.all(
          color: selected ? AdminUi.brand : AdminUi.line,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AdminNotifBubble(icon: icon),
                    if (selectionMode)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: selected ? AdminUi.brand : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? AdminUi.brand : AdminUi.line,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AdminUi.ink,
                              ),
                            ),
                          ),
                          if (!selectionMode)
                            _CardMenu(item: item, onSelected: onAction)
                          else
                            const SizedBox(height: 40),
                        ],
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AdminBadge(
                            label: item.audienceLabel.length > 30
                                ? '${item.audienceLabel.substring(0, 29)}…'
                                : item.audienceLabel,
                            color: item.audience.color,
                            icon: item.audience.icon,
                          ),
                          if (item.isScheduled)
                            AdminBadge(
                              label: 'Zamanlandı',
                              color: Colors.amber.shade800,
                              icon: Icons.schedule_rounded,
                            ),
                          if (item.isEdited)
                            const AdminBadge(
                              label: 'Düzenlendi',
                              color: AdminUi.muted,
                              icon: Icons.edit_rounded,
                            ),
                          Text(
                            item.isScheduled
                                ? adminDateTime(item.scheduledFor)
                                : adminTimeAgo(item.when),
                            style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AdminUi.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: item.isScheduled
                            ? _ScheduledFooter(item: item)
                            : _ReadFooter(item: item),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadFooter extends StatelessWidget {
  const _ReadFooter({required this.item});

  final AdminNotification item;

  @override
  Widget build(BuildContext context) {
    final pct = (item.readRate * 100).round();
    return Row(
      children: [
        const Icon(Icons.people_alt_outlined, size: 15, color: AdminUi.muted),
        const SizedBox(width: 4),
        Text(
          '${adminCompact(item.recipientCount)} kişi',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AdminUi.ink,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: item.readRate,
              minHeight: 6,
              backgroundColor: AdminUi.line,
              valueColor: AlwaysStoppedAnimation(
                item.readRate >= 0.5 ? Colors.green.shade500 : AdminUi.brand,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '%$pct okundu',
          style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
        ),
      ],
    );
  }
}

class _ScheduledFooter extends StatelessWidget {
  const _ScheduledFooter({required this.item});

  final AdminNotification item;

  @override
  Widget build(BuildContext context) {
    final at = item.scheduledFor;
    String eta = '';
    if (at != null) {
      final d = at.difference(DateTime.now());
      if (d.isNegative) {
        eta = 'birkaç dakika içinde';
      } else if (d.inMinutes < 60) {
        eta = '${d.inMinutes + 1} dk sonra';
      } else if (d.inHours < 24) {
        eta = '${d.inHours} sa ${d.inMinutes % 60} dk sonra';
      } else {
        eta = '${d.inDays} gün sonra';
      }
    }
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 15, color: Colors.amber.shade800),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            eta.isEmpty ? 'Zamanlanmış' : 'Gönderilecek · $eta',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.amber.shade900,
            ),
          ),
        ),
      ],
    );
  }
}

/// Kart ve detay sayfasındaki eylemler.
enum AdminNotifAction { detail, edit, duplicate, sendNow, delete }

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.item, required this.onSelected});

  final AdminNotification item;
  final ValueChanged<AdminNotifAction> onSelected;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<AdminNotifAction> entry(
      AdminNotifAction v,
      IconData icon,
      String text, {
      Color? color,
    }) =>
        PopupMenuItem(
          value: v,
          height: 42,
          child: Row(
            children: [
              Icon(icon, size: 19, color: color ?? AdminUi.muted),
              const SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: color ?? AdminUi.ink,
                ),
              ),
            ],
          ),
        );

    return PopupMenuButton<AdminNotifAction>(
      tooltip: 'İşlemler',
      icon: const Icon(Icons.more_vert_rounded, size: 21, color: AdminUi.muted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (_) => [
        entry(AdminNotifAction.detail, Icons.insights_rounded, 'Detay ve alıcılar'),
        entry(AdminNotifAction.edit, Icons.edit_rounded, 'Düzenle'),
        if (item.isScheduled)
          entry(AdminNotifAction.sendNow, Icons.send_rounded, 'Şimdi gönder')
        else
          entry(AdminNotifAction.duplicate, Icons.copy_rounded, 'Tekrar gönder'),
        const PopupMenuDivider(height: 6),
        entry(
          AdminNotifAction.delete,
          Icons.delete_outline_rounded,
          item.isScheduled ? 'İptal et' : 'Sil',
          color: Colors.red.shade700,
        ),
      ],
    );
  }
}

/// Yüklenirken gösterilen iskelet kartları.
class AdminNotifSkeleton extends StatelessWidget {
  const AdminNotifSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, {double h = 10}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AdminUi.line,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AdminCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AdminUi.line,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(140, h: 13),
                        const SizedBox(height: 8),
                        bar(double.infinity),
                        const SizedBox(height: 6),
                        bar(200),
                        const SizedBox(height: 12),
                        bar(double.infinity, h: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
