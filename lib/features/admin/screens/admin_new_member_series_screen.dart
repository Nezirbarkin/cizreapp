import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/admin_notification_model.dart';
import '../../../core/services/admin_new_member_series_service.dart';
import '../../../core/widgets/voice_listen_button.dart';
import '../widgets/admin_notification_widgets.dart';
import '../widgets/admin_ui.dart';

/// Admin > Bildirim merkezi > Yeni üye serisi.
///
/// Yeni kaydolan üyelere zamanlanmış, sesli okunabilen karşılama bildirimleri.
/// Sunucu her dakika çalışır (20261024000001_new_member_messages); bu ekran
/// adımları açar/kapatır, düzenler, sayaçları gösterir ve test gönderir.
class AdminNewMemberSeriesScreen extends StatefulWidget {
  const AdminNewMemberSeriesScreen({super.key, this.service});

  final AdminNewMemberSeriesService? service;

  @override
  State<AdminNewMemberSeriesScreen> createState() =>
      _AdminNewMemberSeriesScreenState();
}

class _AdminNewMemberSeriesScreenState extends State<AdminNewMemberSeriesScreen> {
  late final AdminNewMemberSeriesService _service =
      widget.service ?? AdminNewMemberSeriesService();

  NewMemberSeries? _data;
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = adminNotifError(e);
        _loading = false;
      });
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Colors.red.shade700 : null,
        ),
      );
  }

  Future<void> _run(String key, Future<void> Function() action, {String? ok}) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await action();
      if (ok != null && mounted) _toast(ok);
      await _load();
    } catch (e) {
      if (mounted) _toast(adminNotifError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _openEditor([NewMemberStep? step]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewMemberStepEditor(service: _service, step: step),
      ),
    );
    if (saved == true && mounted) {
      _toast(step == null ? 'Adım eklendi' : 'Adım kaydedildi');
      await _load();
    }
  }

  Future<void> _confirmDelete(NewMemberStep step) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adım silinsin mi?'),
        content: Text(
          '"${step.title}" adımı ve teslim kayıtları silinir. Gönderilmiş '
          'bildirimler üyelerin kutusunda kalır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run('del:${step.id}', () => _service.deleteStep(step.id), ok: 'Adım silindi');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.page,
      appBar: AppBar(
        title: const Text('Yeni üye serisi'),
        backgroundColor: Colors.white,
        foregroundColor: AdminUi.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      floatingActionButton: _data == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: AdminUi.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adım ekle'),
            ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final data = _data;
    if (data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Seri yüklenemedi',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AdminUi.muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      );
    }

    final totalSent = data.steps.fold<int>(0, (s, e) => s + e.sent);
    final totalRead = data.steps.fold<int>(0, (s, e) => s + e.read);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _masterCard(data),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AdminStatTile(
                  icon: Icons.send_rounded,
                  label: 'Gönderilen',
                  value: '$totalSent',
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AdminStatTile(
                  icon: Icons.mark_email_read_rounded,
                  label: 'Okunma oranı',
                  value: totalSent == 0 ? '—' : '%${(totalRead * 100 / totalSent).round()}',
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'ADIMLAR',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w800,
              color: AdminUi.muted,
            ),
          ),
          const SizedBox(height: 8),
          if (data.steps.isEmpty)
            const AdminCard(
              child: Text(
                'Henüz adım yok. "Adım ekle" ile ilk karşılama mesajını oluşturun.',
                style: TextStyle(color: AdminUi.muted),
              ),
            ),
          for (var i = 0; i < data.steps.length; i++)
            _StepTile(
              step: data.steps[i],
              isLast: i == data.steps.length - 1,
              busy: _busy.contains('act:${data.steps[i].id}') ||
                  _busy.contains('test:${data.steps[i].id}'),
              onToggle: (v) => _run(
                'act:${data.steps[i].id}',
                () => _service.setStepActive(data.steps[i].id, v),
              ),
              onEdit: () => _openEditor(data.steps[i]),
              onTest: () => _run(
                'test:${data.steps[i].id}',
                () => _service.sendTest(data.steps[i].id),
                ok: 'Test bildirimi size gönderildi',
              ),
              onDelete: () => _confirmDelete(data.steps[i]),
            ),
        ],
      ),
    );
  }

  Widget _masterCard(NewMemberSeries data) {
    final on = data.enabled;
    return AdminCard(
      borderColor: on ? AdminUi.brand.withValues(alpha: 0.35) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AdminUi.brandSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.waving_hand_rounded, color: AdminUi.brand),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Karşılama serisi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Yeni üyelere otomatik, sesli okunabilen bildirimler',
                      style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: AdminUi.brand,
                onChanged: _busy.contains('master')
                    ? null
                    : (v) => _run(
                          'master',
                          () => _service.setEnabled(v),
                          ok: v ? 'Seri açıldı' : 'Seri kapatıldı',
                        ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _InfoLine(
            icon: Icons.history_toggle_off_rounded,
            text: 'Yalnız seri açıldıktan sonra kaydolan üyelere gider; eski üyelere toplu gönderim yapılmaz.',
          ),
          const _InfoLine(
            icon: Icons.bedtime_outlined,
            text: 'Gece 22:00–09:00 arasında bekleyen adımlar sabah gönderilir.',
          ),
          const _InfoLine(
            icon: Icons.record_voice_over_outlined,
            text: 'Uygulama açıksa mesaj telefonun sesiyle okunur. {ad} yerine üyenin adı gelir.',
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AdminUi.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AdminUi.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zaman çizelgesindeki tek adım: solda gecikme noktası, sağda kart.
class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.isLast,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onTest,
    required this.onDelete,
  });

  final NewMemberStep step;
  final bool isLast;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final icon = adminNotifIcon(step.icon);
    final fg = icon.color is MaterialColor
        ? (icon.color as MaterialColor).shade700
        : icon.color;
    final route = kNewMemberRoutes[step.actionRoute ?? ''];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                const SizedBox(height: 18),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: step.isActive ? fg : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: AdminUi.line),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Opacity(
                opacity: step.isActive ? 1 : 0.6,
                child: AdminCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: icon.color.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon.icon, color: fg, size: 19),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kayıttan ${newMemberDelayLabel(step.delayMinutes)} sonra',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: fg,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  step.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: AdminUi.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else
                            Switch(
                              value: step.isActive,
                              activeThumbColor: AdminUi.brand,
                              onChanged: onToggle,
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 6, 8, 0),
                        child: Text(
                          step.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AdminUi.muted, height: 1.35),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Chip(
                            icon: Icons.filter_alt_outlined,
                            text: kNewMemberConditions[step.condition] ?? step.condition,
                          ),
                          if (route != null && (step.actionRoute ?? '').isNotEmpty)
                            _Chip(icon: Icons.open_in_new_rounded, text: route),
                          if ((step.voiceText ?? '').isNotEmpty)
                            const _Chip(icon: Icons.record_voice_over_outlined, text: 'Sesli metin'),
                          if (!step.respectQuietHours)
                            const _Chip(icon: Icons.nights_stay_outlined, text: 'Gece de gider'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          _Stat(icon: Icons.send_rounded, text: '${step.sent} gönderildi'),
                          _Stat(
                            icon: Icons.mark_email_read_outlined,
                            text: step.readPercent == null ? 'okunma —' : '%${step.readPercent} okundu',
                          ),
                          if (step.skipped > 0)
                            _Stat(icon: Icons.skip_next_rounded, text: '${step.skipped} atlandı'),
                          if (step.failed > 0)
                            _Stat(
                              icon: Icons.error_outline_rounded,
                              text: '${step.failed} hata',
                              color: Colors.red.shade700,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          // Dar ekranda ikinci düğme alt satıra iner (taşma yok).
                          Expanded(
                            child: Wrap(
                              children: [
                                TextButton.icon(
                                  onPressed: onEdit,
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Düzenle'),
                                ),
                                TextButton.icon(
                                  onPressed: busy ? null : onTest,
                                  icon: const Icon(Icons.outbox_outlined, size: 18),
                                  label: const Text('Bana gönder'),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sil',
                            onPressed: onDelete,
                            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AdminUi.page,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminUi.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AdminUi.muted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11.5, color: AdminUi.ink)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AdminUi.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// =============================================================================
// Adım düzenleyici
// =============================================================================

enum _DelayUnit {
  minutes('dakika', 1),
  hours('saat', 60),
  days('gün', 1440);

  const _DelayUnit(this.label, this.factor);
  final String label;
  final int factor;
}

/// Karşılama serisi adımı ekleme / düzenleme sayfası. Kaydedilirse `true` döner.
class NewMemberStepEditor extends StatefulWidget {
  const NewMemberStepEditor({super.key, required this.service, this.step});

  final AdminNewMemberSeriesService service;
  final NewMemberStep? step;

  @override
  State<NewMemberStepEditor> createState() => _NewMemberStepEditorState();
}

class _NewMemberStepEditorState extends State<NewMemberStepEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _voice;
  late final TextEditingController _delay;
  late String _icon;
  late String _gender;
  late String _condition;
  late String _route;
  late bool _quiet;
  late bool _active;
  late _DelayUnit _unit;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.step;
    _title = TextEditingController(text: s?.title ?? '');
    _body = TextEditingController(text: s?.body ?? '');
    _voice = TextEditingController(text: s?.voiceText ?? '');
    _icon = s?.icon ?? 'gift';
    _gender = s?.voiceGender ?? '';
    _condition = s?.condition ?? 'always';
    _route = s?.actionRoute ?? '';
    _quiet = s?.respectQuietHours ?? true;
    _active = s?.isActive ?? true;
    final minutes = s?.delayMinutes ?? 60;
    _unit = minutes > 0 && minutes % 1440 == 0
        ? _DelayUnit.days
        : minutes > 0 && minutes % 60 == 0
            ? _DelayUnit.hours
            : _DelayUnit.minutes;
    _delay = TextEditingController(text: '${minutes ~/ _unit.factor}');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _voice.dispose();
    _delay.dispose();
    super.dispose();
  }

  int? get _delayMinutes {
    final n = int.tryParse(_delay.text.trim());
    if (n == null || n < 0) return null;
    final m = n * _unit.factor;
    return m > 43200 ? null : m;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    final delay = _delayMinutes;
    String? error;
    if (title.isEmpty) {
      error = 'Başlık yazın';
    } else if (body.isEmpty) {
      error = 'Metin yazın';
    } else if (delay == null) {
      error = 'Gecikme 0 dakika ile 30 gün arasında olmalı';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.saveStep(
        id: widget.step?.id,
        title: title,
        body: body,
        voiceText: _voice.text.trim().isEmpty ? null : _voice.text.trim(),
        voiceGender: _gender.isEmpty ? null : _gender,
        icon: _icon,
        delayMinutes: delay!,
        condition: _condition,
        actionRoute: _route,
        respectQuietHours: _quiet,
        isActive: _active,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminNotifError(e);
      });
    }
  }

  InputDecoration _dec(String label, {String? hint, String? helper}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminUi.line),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AdminUi.ink,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.page,
      appBar: AppBar(
        title: Text(widget.step == null ? 'Yeni adım' : 'Adımı düzenle'),
        backgroundColor: Colors.white,
        foregroundColor: AdminUi.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                  ),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AdminUi.brand,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Kaydet'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Ne zaman, kime?', [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _delay,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Kayıttan sonra'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<_DelayUnit>(
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: _dec('Birim'),
                    items: [
                      for (final u in _DelayUnit.values)
                        DropdownMenuItem(value: u, child: Text(u.label)),
                    ],
                    onChanged: (u) => setState(() => _unit = u ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _condition,
              isExpanded: true,
              decoration: _dec('Kimlere gitsin?'),
              items: [
                for (final e in kNewMemberConditions.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _condition = v ?? 'always'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _route,
              isExpanded: true,
              decoration: _dec('Dokununca açılacak ekran'),
              items: [
                for (final e in kNewMemberRoutes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _route = v ?? ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _quiet,
              activeThumbColor: AdminUi.brand,
              onChanged: (v) => setState(() => _quiet = v),
              title: const Text('Gece 22:00–09:00 arasında bekle'),
              subtitle: const Text('Kapalıysa gece de gönderilir'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              activeThumbColor: AdminUi.brand,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Etkin'),
            ),
          ]),
          _section('Bildirim', [
            TextField(
              controller: _title,
              maxLength: 100,
              decoration: _dec('Başlık', hint: 'Ör. Hoş geldin {ad} 👋'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _body,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: _dec(
                'Metin',
                helper: '{ad} yazdığınız yere üyenin adı gelir; ad yoksa kendiliğinden çıkarılır.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                const gap = 8.0;
                final w = (c.maxWidth - gap * 2) / 3;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final i in kAdminNotifIcons)
                      SizedBox(
                        width: w,
                        child: AdminNotifIconChoice(
                          icon: i,
                          selected: i.key == _icon,
                          onTap: () => setState(() => _icon = i.key),
                        ),
                      ),
                  ],
                );
              },
            ),
          ]),
          _section('Sesli okuma', [
            TextField(
              controller: _voice,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: _dec(
                'Sesli okunacak metin (isteğe bağlı)',
                hint: 'Ör. Merhaba {ad}, CizreApp ailesine hoş geldin!',
                helper: 'Boş bırakılırsa başlık ve metin okunur. Uygulama açıkken '
                    'telefonun sesiyle okunur; bildirim detayında "Dinle" düğmesi çıkar.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '', label: Text('Varsayılan')),
                ButtonSegment(value: 'female', label: Text('Kadın')),
                ButtonSegment(value: 'male', label: Text('Erkek')),
              ],
              selected: {_gender},
              onSelectionChanged: (s) => setState(() => _gender = s.first),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: VoiceListenButton(
                listenKey: 'new_member_preview:${widget.step?.id ?? 'new'}',
                title: _title.text,
                body: _body.text,
                voiceText: _voice.text.trim().isEmpty ? null : _voice.text,
                gender: _gender.isEmpty ? null : _gender,
                color: AdminUi.brand,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
