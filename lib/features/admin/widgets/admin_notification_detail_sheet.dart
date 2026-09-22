import 'package:flutter/material.dart';

import '../../../core/models/admin_notification_model.dart';
import '../../../core/services/admin_notification_service.dart';
import 'admin_notification_widgets.dart';
import 'admin_ui.dart';

/// Bildirimin ayrıntısı: canlı önizleme, okunma istatistiği ve alıcı listesi
/// (kim okudu / okumadı). Düzenle / tekrar gönder / sil seçilirse o eylemle
/// kapanır; asıl işi çağıran yapar (alt sayfadan SnackBar görünmediği için).
Future<AdminNotifAction?> showAdminNotificationDetail(
  BuildContext context, {
  required AdminNotification item,
  AdminNotificationService? service,
}) {
  return showModalBottomSheet<AdminNotifAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => AdminNotificationDetailSheet(item: item, service: service),
  );
}

class AdminNotificationDetailSheet extends StatefulWidget {
  const AdminNotificationDetailSheet({
    super.key,
    required this.item,
    this.service,
  });

  final AdminNotification item;
  final AdminNotificationService? service;

  @override
  State<AdminNotificationDetailSheet> createState() =>
      _AdminNotificationDetailSheetState();
}

class _AdminNotificationDetailSheetState
    extends State<AdminNotificationDetailSheet> {
  static const int _page = 50;

  late final AdminNotificationService _service =
      widget.service ?? AdminNotificationService();

  String? _filter; // null | 'read' | 'unread'
  final List<AdminNotificationRecipient> _people = [];
  bool _loading = true;
  bool _hasMore = false;
  String? _error;
  int _token = 0;

  AdminNotification get item => widget.item;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final token = ++_token;
    if (reset) {
      setState(() {
        _people.clear();
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loading = true);
    }
    try {
      final list = await _service.recipients(
        item.id,
        filter: _filter,
        limit: _page,
        offset: _people.length,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _people.addAll(list);
        _hasMore = list.length == _page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = adminNotifError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (item.readRate * 100).round();

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: AdminUi.page,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AdminUi.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminNotifBubble(icon: item.icon, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AdminUi.ink,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          AdminBadge(
                            label: item.audienceLabel,
                            color: item.audience.color,
                            icon: item.audience.icon,
                          ),
                          if (item.isScheduled)
                            AdminBadge(
                              label: 'Zamanlandı',
                              color: Colors.amber.shade800,
                              icon: Icons.schedule_rounded,
                            )
                          else
                            const AdminBadge(
                              label: 'Gönderildi',
                              color: Colors.green,
                              icon: Icons.check_circle_rounded,
                            ),
                          if (item.isEdited)
                            const AdminBadge(
                              label: 'Düzenlendi',
                              color: AdminUi.muted,
                              icon: Icons.edit_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AdminNotifPreview(
              title: item.title,
              body: item.content,
              iconKey: item.iconType,
            ),
            const SizedBox(height: 12),
            AdminCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mesajın tamamı',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AdminUi.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    item.content,
                    style: const TextStyle(fontSize: 14, height: 1.45, color: AdminUi.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (item.isScheduled)
              _scheduledInfo()
            else ...[
              Row(
                children: [
                  Expanded(
                    child: AdminMiniStat(
                      icon: Icons.people_alt_rounded,
                      label: 'Alıcı',
                      value: adminCompact(item.recipientCount),
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AdminMiniStat(
                      icon: Icons.mark_email_read_rounded,
                      label: 'Okudu',
                      value: adminCompact(item.readCount),
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AdminMiniStat(
                      icon: Icons.mark_email_unread_rounded,
                      label: 'Okumadı',
                      value: adminCompact(item.unreadCount),
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AdminMiniStat(
                      icon: Icons.percent_rounded,
                      label: 'Okunma',
                      value: '%$pct',
                      color: AdminUi.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: item.readRate,
                  minHeight: 8,
                  backgroundColor: AdminUi.line,
                  valueColor: AlwaysStoppedAnimation(
                    item.readRate >= 0.5 ? Colors.green.shade500 : AdminUi.brand,
                  ),
                ),
              ),
              if (item.liveCount < item.recipientCount) ...[
                const SizedBox(height: 8),
                Text(
                  '${item.recipientCount - item.liveCount} kişi bu bildirimi kendi '
                  'kutusundan sildi; okunma oranı gönderilen kişi sayısına göre hesaplanır.',
                  style: const TextStyle(fontSize: 11.5, height: 1.35, color: AdminUi.muted),
                ),
              ],
            ],
            const SizedBox(height: 12),
            AdminCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  _meta('Gönderen', item.createdByName ?? '—'),
                  _meta(
                    item.isScheduled ? 'Gönderim zamanı' : 'Gönderim',
                    adminDateTime(item.isScheduled ? item.scheduledFor : item.sentAt ?? item.createdAt),
                  ),
                  if (item.isEdited) _meta('Son düzenleme', adminDateTime(item.editedAt)),
                  _meta('Simge', item.icon.label),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _actions(),
            const SizedBox(height: 18),
            _recipientsSection(),
          ],
        ),
      ),
    );
  }

  Widget _scheduledInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${adminDateTime(item.scheduledFor)} tarihinde gönderilecek. '
              'Gönderilene kadar düzenleyebilir, hemen gönderebilir ya da iptal edebilirsiniz.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(k, style: const TextStyle(fontSize: 13, color: AdminUi.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                v,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.ink,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _actions() {
    // Simge üstte, etiket altta: dar ekranda üç etiket de sığar.
    Widget tile(IconData icon, String label, Color color, AdminNotifAction action) {
      return Expanded(
        child: Material(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context, action),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(Icons.edit_rounded, 'Düzenle', AdminUi.brand, AdminNotifAction.edit),
        const SizedBox(width: 8),
        item.isScheduled
            ? tile(Icons.send_rounded, 'Şimdi gönder', Colors.blue.shade700,
                AdminNotifAction.sendNow)
            : tile(Icons.copy_rounded, 'Tekrar gönder', Colors.blue.shade700,
                AdminNotifAction.duplicate),
        const SizedBox(width: 8),
        tile(
          Icons.delete_outline_rounded,
          item.isScheduled ? 'İptal et' : 'Sil',
          Colors.red.shade700,
          AdminNotifAction.delete,
        ),
      ],
    );
  }

  Widget _recipientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Alıcılar',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AdminUi.ink,
              ),
            ),
            const Spacer(),
            if (_loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!item.isScheduled) ...[
          AdminChipBar<String?>(
            selected: _filter,
            onSelected: (f) {
              if (f == _filter) return;
              _filter = f;
              _load(reset: true);
            },
            items: [
              (value: null, label: 'Tümü', icon: null, count: null),
              (value: 'read', label: 'Okuyanlar', icon: null, count: item.readCount),
              (value: 'unread', label: 'Okumayanlar', icon: null, count: item.unreadCount),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null)
          AdminCard(
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          )
        else if (_people.isEmpty && !_loading)
          const AdminCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Bu filtrede alıcı yok.',
                  style: TextStyle(fontSize: 13, color: AdminUi.muted),
                ),
              ),
            ),
          )
        else
          AdminCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _people.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AdminUi.line),
                  _personTile(_people[i]),
                ],
                if (_hasMore)
                  TextButton(
                    onPressed: _loading ? null : () => _load(),
                    child: const Text('Daha fazla göster'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _personTile(AdminNotificationRecipient p) {
    final role = adminRoleLabel(p.role);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          AdminAvatar(url: p.avatarUrl, name: p.displayName, radius: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.ink,
                  ),
                ),
                Text(
                  [
                    if ((p.username ?? '').isNotEmpty) '@${p.username}',
                    if (role.isNotEmpty) role,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                ),
              ],
            ),
          ),
          if (!item.isScheduled)
            AdminBadge(
              label: p.isRead ? 'Okudu' : 'Okumadı',
              color: p.isRead ? Colors.green : Colors.orange,
              icon: p.isRead ? Icons.done_all_rounded : Icons.schedule_rounded,
            ),
        ],
      ),
    );
  }
}
