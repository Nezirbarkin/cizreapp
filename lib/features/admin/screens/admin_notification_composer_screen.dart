// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/admin_notification_model.dart';
import '../../../core/services/admin_notification_service.dart';
import '../widgets/admin_notification_widgets.dart';
import '../widgets/admin_ui.dart';

/// Ekranın hangi amaçla açıldığı.
enum AdminNotifComposerMode {
  /// Boş form.
  create,

  /// Var olan bildirimin metnini/ikonunu düzelt (alıcılar sabit).
  edit,

  /// Var olan bildirimi ön dolduruyla yeniden gönder.
  duplicate,
}

/// Admin > Bildirimler > yeni / düzenle / tekrar gönder.
///
/// Solda form (şablon, ikon, içerik, alıcılar, zamanlama), geniş ekranda
/// sağda, dar ekranda içeriğin altında canlı önizleme. Kaydedilirse kullanıcıya
/// gösterilecek kısa bir sonuç metniyle (`String`) kapanır.
class AdminNotificationComposerScreen extends StatefulWidget {
  const AdminNotificationComposerScreen({
    super.key,
    this.source,
    this.mode = AdminNotifComposerMode.create,
    this.service,
  }) : assert(
          mode == AdminNotifComposerMode.create || source != null,
          'edit/duplicate için source gerekir',
        );

  final AdminNotification? source;
  final AdminNotifComposerMode mode;

  /// Testlerde sahte servis vermek için.
  final AdminNotificationService? service;

  @override
  State<AdminNotificationComposerScreen> createState() =>
      _AdminNotificationComposerScreenState();
}

class _AdminNotificationComposerScreenState
    extends State<AdminNotificationComposerScreen> {
  static const int _titleMax = 100;
  static const int _maxRecipients = 200;

  late final AdminNotificationService _service =
      widget.service ?? AdminNotificationService();

  late final TextEditingController _titleC;
  late final TextEditingController _bodyC;
  final TextEditingController _userQueryC = TextEditingController();

  late String _iconKey;
  late AdminNotifAudience _audience;

  // Kişiye özel alıcılar (seçim sırası korunur).
  final Map<String, AdminNotifUser> _picked = {};
  List<AdminNotifUser> _results = const [];
  bool _searching = false;
  bool _prefilling = false;
  String? _searchError;
  Timer? _debounce;
  int _searchToken = 0;

  // Hedef kitle büyüklüğü.
  int? _reach;
  bool _reachLoading = false;
  int _reachToken = 0;

  // Zamanlama / yeniden bildirme.
  bool _scheduleOn = false;
  DateTime? _when;
  bool _renotify = false;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.mode == AdminNotifComposerMode.edit;
  bool get _isDuplicate => widget.mode == AdminNotifComposerMode.duplicate;
  bool get _editingScheduled => _isEdit && (widget.source?.isScheduled ?? false);
  bool get _editingSent => _isEdit && !_editingScheduled;
  bool get _showSchedule => !_isEdit || _editingScheduled;

  int get _bodyMax => _audience == AdminNotifAudience.personal ? 500 : 1000;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _titleC = TextEditingController(text: s?.title ?? '');
    _bodyC = TextEditingController(text: s?.content ?? '');
    _iconKey = s?.iconType ?? 'announcement';
    _audience = s?.audience ?? AdminNotifAudience.allUsers;
    if (_editingScheduled) {
      _scheduleOn = true;
      _when = s!.scheduledFor;
    }
    for (final c in [_titleC, _bodyC]) {
      c.addListener(() => setState(() {}));
    }
    if (!_isEdit) {
      _refreshReach();
      if (_audience == AdminNotifAudience.personal) {
        _runSearch('');
        if (_isDuplicate) _prefillRecipients();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleC.dispose();
    _bodyC.dispose();
    _userQueryC.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Veri
  // ---------------------------------------------------------------------------

  Future<void> _refreshReach() async {
    if (_audience == AdminNotifAudience.personal) {
      setState(() => _reach = _picked.length);
      return;
    }
    final token = ++_reachToken;
    setState(() => _reachLoading = true);
    try {
      final n = await _service.audienceCount(_audience);
      if (!mounted || token != _reachToken) return;
      setState(() {
        _reach = n;
        _reachLoading = false;
      });
    } catch (_) {
      if (!mounted || token != _reachToken) return;
      setState(() {
        _reach = null;
        _reachLoading = false;
      });
    }
  }

  /// "Tekrar gönder" kişiye özel bir bildirimden gelirse eski alıcıları getirir.
  Future<void> _prefillRecipients() async {
    final id = widget.source?.id;
    if (id == null) return;
    setState(() => _prefilling = true);
    try {
      final list = await _service.recipients(id, limit: _maxRecipients);
      if (!mounted) return;
      setState(() {
        for (final r in list) {
          _picked[r.userId] = AdminNotifUser(
            id: r.userId,
            username: r.username,
            fullName: r.fullName,
            avatarUrl: r.avatarUrl,
            role: r.role,
          );
        }
        _reach = _picked.length;
        _prefilling = false;
      });
    } catch (_) {
      if (mounted) setState(() => _prefilling = false);
    }
  }

  void _onUserQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final token = ++_searchToken;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final list = await _service.searchUsers(q);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searching = false;
        _searchError = adminNotifError(e);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Etkileşim
  // ---------------------------------------------------------------------------

  void _applyTemplate(AdminNotifTemplate t) {
    setState(() {
      _titleC.text = t.title;
      _bodyC.text = t.body;
      _iconKey = t.iconKey;
      _error = null;
    });
  }

  void _setAudience(AdminNotifAudience a) {
    if (a == _audience) return;
    setState(() {
      _audience = a;
      _error = null;
    });
    _refreshReach();
    if (a == AdminNotifAudience.personal && _results.isEmpty) _runSearch('');
  }

  void _togglePicked(AdminNotifUser u) {
    setState(() {
      _error = null;
      if (_picked.containsKey(u.id)) {
        _picked.remove(u.id);
      } else if (_picked.length >= _maxRecipients) {
        _error = 'Bir seferde en fazla $_maxRecipients kişi seçilebilir.';
      } else {
        _picked[u.id] = u;
      }
      _reach = _picked.length;
    });
  }

  DateTime _roundedFromNow(Duration d) {
    final t = DateTime.now().add(d);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final base = _when ?? _roundedFromNow(const Duration(hours: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      _error = null;
      _when = DateTime(d.year, d.month, d.day, base.hour, base.minute);
    });
  }

  Future<void> _pickTime() async {
    final base = _when ?? _roundedFromNow(const Duration(hours: 1));
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return;
    setState(() {
      _error = null;
      _when = DateTime(base.year, base.month, base.day, t.hour, t.minute);
    });
  }

  String? _validate() {
    final title = _titleC.text.trim();
    final body = _bodyC.text.trim();
    if (title.isEmpty) return 'Bildirim başlığını yazın.';
    if (body.isEmpty) return 'Mesajı yazın.';
    if (body.length > _bodyMax) {
      return _audience == AdminNotifAudience.personal
          ? 'Kişiye özel bildirimde mesaj en fazla 500 karakter olabilir.'
          : 'Mesaj en fazla 1000 karakter olabilir.';
    }
    if (!_isEdit &&
        _audience == AdminNotifAudience.personal &&
        _picked.isEmpty) {
      return 'En az bir alıcı seçin.';
    }
    if (_showSchedule && _scheduleOn) {
      final w = _when;
      if (w == null || !w.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
        return 'Gönderim zamanı gelecekte olmalı.';
      }
    }
    return null;
  }

  Future<bool> _confirmSend() async {
    final personal = _audience == AdminNotifAudience.personal;
    // Tek kişiye özel mesajda onay sormak gereksiz sürtünme.
    if (personal && _picked.length <= 1) return true;
    final who = personal
        ? '${_picked.length} kişiye'
        : _reach == null
            ? '${_audience.label} grubuna'
            : '≈ ${adminCompact(_reach!)} kişiye (${_audience.label})';
    final when = _scheduleOn && _when != null
        ? '${adminDateTime(_when)} tarihinde'
        : 'hemen';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_scheduleOn ? 'Bildirimi zamanla?' : 'Bildirimi gönder?'),
        content: Text(
          '"${_titleC.text.trim()}" bildirimi $who $when gönderilecek.'
          '${_scheduleOn ? '' : '\n\nGiden push bildirimi geri alınamaz; ancak sonradan düzenleyebilir veya silebilirsiniz.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_scheduleOn ? 'Zamanla' : 'Gönder'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);

    if (!_isEdit && !await _confirmSend()) return;

    setState(() => _saving = true);
    try {
      final title = _titleC.text;
      final body = _bodyC.text;
      String message;
      if (_isEdit) {
        await _service.update(
          widget.source!.id,
          title: title,
          content: body,
          iconType: _iconKey,
          scheduledFor: _editingScheduled && _scheduleOn ? _when : null,
          renotify: _editingSent && _renotify,
        );
        message = _editingSent && _renotify
            ? 'Bildirim güncellendi ve yeniden gönderildi'
            : 'Bildirim güncellendi';
      } else {
        final r = await _service.send(
          audience: _audience,
          title: title,
          content: body,
          iconType: _iconKey,
          userIds: _picked.keys.toList(),
          scheduledFor: _scheduleOn ? _when : null,
        );
        if (r.isScheduled) {
          message = 'Zamanlandı: ${adminDateTime(r.scheduledFor)}';
        } else if (r.recipientCount == 0) {
          message = 'Gönderildi ama bu kitlede alıcı bulunamadı';
        } else {
          message = '${adminCompact(r.recipientCount)} kişiye gönderildi';
        }
      }
      if (!mounted) return;
      Navigator.pop(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminNotifError(e);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------

  InputDecoration _dec({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AdminUi.page,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AdminUi.line),
      enabledBorder: border(AdminUi.line),
      focusedBorder: border(AdminUi.brand, 1.6),
      counterStyle: const TextStyle(fontSize: 11, color: AdminUi.muted),
    );
  }

  String get _screenTitle => switch (widget.mode) {
        AdminNotifComposerMode.create => 'Yeni bildirim',
        AdminNotifComposerMode.edit =>
          _editingScheduled ? 'Zamanlanmışı düzenle' : 'Bildirimi düzenle',
        AdminNotifComposerMode.duplicate => 'Tekrar gönder',
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 940;

    final preview = AdminNotifPreview(
      title: _titleC.text,
      body: _bodyC.text,
      iconKey: _iconKey,
    );

    final sections = <Widget>[
      if (!_isEdit) _templatesSection(),
      _iconSection(),
      _contentSection(),
      if (!wide) preview,
      _isEdit ? _lockedAudienceSection() : _audienceSection(),
      if (_showSchedule || _editingSent) _deliverySection(),
    ];

    Widget spaced(List<Widget> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              items[i],
            ],
          ],
        );

    return Scaffold(
      backgroundColor: AdminUi.page,
      appBar: AppBar(
        title: Text(
          _screenTitle,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AdminUi.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 1120 : 720),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
                        children: [spaced(sections)],
                      ),
                    ),
                    SizedBox(
                      width: 380,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(8, 16, 16, 24),
                        children: [preview],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [spaced(sections)],
                ),
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _bottomBar() {
    final icon = _isEdit
        ? Icons.check_rounded
        : _scheduleOn
            ? Icons.schedule_send_rounded
            : Icons.send_rounded;
    final label = _isEdit
        ? 'Kaydet'
        : _scheduleOn
            ? 'Zamanla'
            : 'Gönder';

    String summary;
    if (_isEdit) {
      summary = _editingScheduled
          ? 'Zamanlanmış bildirim güncellenir'
          : _renotify
              ? 'Alıcılara yeniden bildirilir'
              : 'Alıcıların bildirim kutusu güncellenir';
    } else {
      final who = _audience == AdminNotifAudience.personal
          ? '${_picked.length} kişi'
          : _reachLoading
              ? 'hesaplanıyor…'
              : _reach == null
                  ? _audience.label
                  : '≈ ${adminCompact(_reach!)} kişi';
      final w = _when;
      summary = _scheduleOn && w != null
          ? '${adminDateTime(w)} · $who'
          : 'Anında · $who';
    }

    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width >= 940 ? 1120 : 720,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 18, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AdminUi.brand,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(icon, size: 18),
                        label: Text(
                          _saving ? 'Bekleyin…' : label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Şablonlar --------------------------------------------------------------

  Widget _templatesSection() {
    return _Section(
      icon: Icons.auto_awesome_rounded,
      title: 'Hazır şablonlar',
      subtitle: 'Dokununca başlık, mesaj ve ikon dolar; sonra düzenleyebilirsiniz.',
      // Yatay kaydırılır: dar ekranda üç satıra yayılıp formu aşağı itmesin.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in kAdminNotifTemplates)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  onPressed: () => _applyTemplate(t),
                  avatar: Icon(
                    adminNotifIcon(t.iconKey).icon,
                    size: 16,
                    color: adminNotifIcon(t.iconKey).color,
                  ),
                  label: Text(
                    t.name,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AdminUi.line),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- İkon -------------------------------------------------------------------

  Widget _iconSection() {
    return _Section(
      icon: Icons.emoji_objects_outlined,
      title: 'Simge',
      subtitle: 'Bildirim kutusunda başlığın yanında görünür.',
      child: LayoutBuilder(
        builder: (context, c) {
          // 9 simge: 3 sütun temiz bir 3x3 ızgara verir (yetim satır kalmaz).
          const gap = 8.0;
          final w = (c.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final i in kAdminNotifIcons)
                SizedBox(
                  width: w,
                  child: _IconChoice(
                    icon: i,
                    selected: i.key == _iconKey,
                    onTap: () => setState(() => _iconKey = i.key),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // --- İçerik -----------------------------------------------------------------

  Widget _contentSection() {
    return _Section(
      icon: Icons.edit_note_rounded,
      title: 'İçerik',
      child: Column(
        children: [
          TextField(
            controller: _titleC,
            maxLength: _titleMax,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: _dec(label: 'Başlık', hint: 'Örn. Yeni kampanya başladı'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bodyC,
            minLines: 4,
            maxLines: 8,
            maxLength: _bodyMax,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec(label: 'Mesaj', hint: 'Kullanıcılara iletmek istediğiniz metin'),
          ),
        ],
      ),
    );
  }

  // --- Alıcılar ---------------------------------------------------------------

  Widget _lockedAudienceSection() {
    final s = widget.source!;
    return _Section(
      icon: Icons.groups_2_outlined,
      title: 'Alıcılar',
      trailing: const Icon(Icons.lock_outline_rounded, size: 18, color: AdminUi.muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: s.audience.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(s.audience.icon, size: 21, color: s.audience.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.audienceLabel,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.ink,
                      ),
                    ),
                    if (!s.isScheduled)
                      Text(
                        '${adminCompact(s.recipientCount)} kişiye gönderildi',
                        style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Gönderilmiş bildirimin alıcıları değiştirilemez. Farklı kişilere '
            'göndermek için listeden "Tekrar gönder"i kullanın.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: AdminUi.muted),
          ),
        ],
      ),
    );
  }

  Widget _audienceSection() {
    return _Section(
      icon: Icons.groups_2_outlined,
      title: 'Kime gidecek?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              const gap = 8.0;
              final cols = c.maxWidth >= 560 ? 3 : 2;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final a in AdminNotifAudience.values)
                    SizedBox(
                      width: w,
                      child: _AudienceTile(
                        audience: a,
                        selected: a == _audience,
                        onTap: () => _setAudience(a),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (_audience != AdminNotifAudience.personal)
            _ReachLine(loading: _reachLoading, count: _reach, audience: _audience)
          else
            _personalPicker(),
        ],
      ),
    );
  }

  Widget _personalPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_picked.isNotEmpty) ...[
          Row(
            children: [
              Text(
                '${_picked.length} kişi seçildi',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AdminUi.ink,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _picked.clear();
                  _reach = 0;
                }),
                child: const Text('Temizle'),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final u in _picked.values)
                InputChip(
                  avatar: AdminAvatar(url: u.avatarUrl, name: u.displayName, radius: 11),
                  label: Text(
                    u.displayName,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  onDeleted: () => _togglePicked(u),
                  deleteIconColor: AdminUi.muted,
                  backgroundColor: AdminUi.brandSoft,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _userQueryC,
          onChanged: _onUserQuery,
          textInputAction: TextInputAction.search,
          decoration: _dec(
            label: 'Kişi ara',
            hint: 'Ad, soyad veya kullanıcı adı',
            icon: Icons.search_rounded,
            suffix: _searching || _prefilling
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            border: Border.all(color: AdminUi.line),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: _searchError != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _searchError!,
                    style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                  ),
                )
              : _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          _searching ? 'Aranıyor…' : 'Sonuç bulunamadı',
                          style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AdminUi.line),
                      itemBuilder: (context, i) {
                        final u = _results[i];
                        final on = _picked.containsKey(u.id);
                        return ListTile(
                          dense: true,
                          onTap: () => _togglePicked(u),
                          tileColor: on ? AdminUi.brandSoft : null,
                          leading: AdminAvatar(
                            url: u.avatarUrl,
                            name: u.displayName,
                            radius: 18,
                          ),
                          title: Text(
                            u.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if ((u.username ?? '').isNotEmpty) '@${u.username}',
                              adminRoleLabel(u.role),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          trailing: Icon(
                            on
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: on ? AdminUi.brand : AdminUi.muted,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // --- Zamanlama / yeniden bildirme --------------------------------------------

  Widget _deliverySection() {
    if (_editingSent) {
      return _Section(
        icon: Icons.notifications_active_outlined,
        title: 'Alıcılara bildirme',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bildirim zaten gönderildi; cihazlara giden push geri alınamaz. '
                      'Kaydedince alıcıların bildirim kutusundaki başlık, mesaj ve simge güncellenir.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _renotify,
              activeThumbColor: AdminUi.brand,
              onChanged: (v) => setState(() => _renotify = v),
              title: const Text(
                'Alıcılara yeniden bildir',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Okunmadı olarak işaretler, listenin en üstüne taşır ve yeni bir push gönderir.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    final quick = <({String label, DateTime at})>[
      (label: '1 saat sonra', at: _roundedFromNow(const Duration(hours: 1))),
      () {
        final n = DateTime.now();
        return (label: 'Bugün 20:00', at: DateTime(n.year, n.month, n.day, 20));
      }(),
      () {
        final n = DateTime.now().add(const Duration(days: 1));
        return (label: 'Yarın 09:00', at: DateTime(n.year, n.month, n.day, 9));
      }(),
    ].where((q) => q.at.isAfter(DateTime.now().add(const Duration(minutes: 2)))).toList();

    return _Section(
      icon: Icons.schedule_rounded,
      title: 'Ne zaman?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_editingScheduled)
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AdminUi.brandSoft,
                  selectedForegroundColor: AdminUi.brand,
                ),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.bolt_rounded, size: 18),
                    label: Text(
                      'Hemen',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.schedule_rounded, size: 18),
                    label: Text(
                      'Zamanla',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                selected: {_scheduleOn},
                onSelectionChanged: (s) => setState(() {
                  _scheduleOn = s.first;
                  _error = null;
                  if (_scheduleOn) {
                    _when ??= _roundedFromNow(const Duration(hours: 1));
                  }
                }),
              ),
            ),
          if (_scheduleOn) ...[
            if (!_editingScheduled) const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 17),
                    label: Text(_when == null ? 'Tarih seç' : adminDate(_when)),
                    style: _pickerButtonStyle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time_rounded, size: 17),
                    label: Text(
                      _when == null
                          ? 'Saat seç'
                          : '${_two(_when!.hour)}:${_two(_when!.minute)}',
                    ),
                    style: _pickerButtonStyle,
                  ),
                ),
              ],
            ),
            if (quick.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in quick)
                    ActionChip(
                      onPressed: () => setState(() {
                        _when = q.at;
                        _error = null;
                      }),
                      label: Text(
                        q.label,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AdminUi.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Zamanlanan bildirimler dakikalık kontrolle gönderilir; birkaç dakikalık '
              'sapma olabilir. Gönderilmeden önce düzenleyebilir ya da iptal edebilirsiniz.',
              style: TextStyle(fontSize: 12, height: 1.4, color: AdminUi.muted),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Bildirim "Gönder"e bastığınız anda alıcılara iletilir.',
                style: TextStyle(fontSize: 12, height: 1.4, color: AdminUi.muted),
              ),
            ),
        ],
      ),
    );
  }

  static final ButtonStyle _pickerButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: AdminUi.ink,
    side: const BorderSide(color: AdminUi.line),
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  static String _two(int n) => n.toString().padLeft(2, '0');
}

// -----------------------------------------------------------------------------
// Küçük parçalar
// -----------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AdminUi.brandSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: AdminUi.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AdminUi.ink,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12.5, height: 1.35, color: AdminUi.muted),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AdminNotifIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = icon.color is MaterialColor
        ? (icon.color as MaterialColor).shade700
        : icon.color;
    return Semantics(
      button: true,
      selected: selected,
      label: icon.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? icon.color.withValues(alpha: 0.13) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? icon.color : AdminUi.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon.icon, size: 20, color: selected ? fg : AdminUi.muted),
              const SizedBox(width: 6),
              Expanded(
                // "Güncelleme" gibi uzun etiketler dar ekranda kırpılmasın.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    icon.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? fg : AdminUi.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceTile extends StatelessWidget {
  const _AudienceTile({
    required this.audience,
    required this.selected,
    required this.onTap,
  });

  final AdminNotifAudience audience;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = audience.color;
    return Semantics(
      button: true,
      selected: selected,
      label: audience.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? c : AdminUi.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(audience.icon, size: 22, color: selected ? c : AdminUi.muted),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audience.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.ink,
                      ),
                    ),
                    Text(
                      audience.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AdminUi.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReachLine extends StatelessWidget {
  const _ReachLine({
    required this.loading,
    required this.count,
    required this.audience,
  });

  final bool loading;
  final int? count;
  final AdminNotifAudience audience;

  @override
  Widget build(BuildContext context) {
    final text = loading
        ? 'Kitle hesaplanıyor…'
        : count == null
            ? '${audience.label} grubuna gönderilecek'
            : count == 0
                ? 'Bu kitlede gönderilecek kullanıcı yok'
                : '≈ ${adminCompact(count!)} kişiye ulaşacak';
    final warn = !loading && count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warn ? Colors.amber.shade50 : audience.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            warn ? Icons.warning_amber_rounded : Icons.people_alt_rounded,
            size: 18,
            color: warn ? Colors.amber.shade800 : audience.color,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: warn ? Colors.amber.shade900 : AdminUi.ink,
            ),
          ),
        ],
      ),
    );
  }
}
