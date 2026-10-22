import 'package:flutter/material.dart';

import '../../../core/services/announcement_voice_service.dart';
import '../../../core/services/voice_announce_settings_service.dart';

/// Admin > Ayarlar > "Sesli Duyurular".
///
/// Ana anahtar, varsayılan ses (kadın/erkek), otomatik okunan bölümler ve
/// "Merhaba Ahmet," karşılaması. Değişiklik "Kaydet" ile `app_settings`'e yazılır.
class VoiceAnnounceSettingsCard extends StatefulWidget {
  const VoiceAnnounceSettingsCard({super.key, this.loader, this.saver, this.voice});

  /// Testlerde sahte okuma/yazma vermek için.
  final Future<VoiceAnnounceSettings> Function()? loader;
  final Future<void> Function(VoiceAnnounceSettings)? saver;
  final AnnouncementVoiceService? voice;

  @override
  State<VoiceAnnounceSettingsCard> createState() => _VoiceAnnounceSettingsCardState();
}

class _VoiceAnnounceSettingsCardState extends State<VoiceAnnounceSettingsCard> {
  VoiceAnnounceSettings? _saved;
  VoiceAnnounceSettings? _draft;
  bool _saving = false;
  String? _error;

  AnnouncementVoiceService get _voice => widget.voice ?? AnnouncementVoiceService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loader = widget.loader ??
        () => VoiceAnnounceSettingsService.fetch(forceRefresh: true);
    final s = await loader();
    if (!mounted) return;
    setState(() {
      _saved = s;
      _draft = s;
    });
  }

  bool get _dirty => _draft != null && _draft != _saved;

  Future<void> _save() async {
    final d = _draft;
    if (d == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.saver ?? VoiceAnnounceSettingsService.save)(d);
      if (!mounted) return;
      setState(() {
        _saved = d;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesli duyuru ayarları kaydedildi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Kaydedilemedi: $e';
      });
    }
  }

  void _preview() {
    final d = _draft ?? VoiceAnnounceSettings.defaults;
    _voice.toggleListen(
      key: 'admin_voice_preview',
      title: 'Sesli duyuru önizlemesi',
      body: 'Yeni kampanyamız başladı. Ayrıntılar için uygulamaya göz atın.',
      gender: d.gender.key,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: d == null
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: d.enabled,
                    onChanged: (v) => setState(() => _draft = d.copyWith(enabled: v)),
                    secondary: const Icon(Icons.record_voice_over, color: Colors.deepPurple),
                    title: const Text(
                      'Sesli duyurular',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Uygulama açıkken duyurular telefonun Türkçe sesiyle okunur ve '
                      'duyurularda "Dinle" düğmesi çıkar. Kapalıyken hiçbir yerde okunmaz.',
                    ),
                  ),
                  const Divider(),
                  const Text('Varsayılan ses', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final g in VoiceGender.values)
                        ChoiceChip(
                          label: Text(g.label),
                          avatar: Icon(
                            g == VoiceGender.female ? Icons.face_3 : Icons.face_6,
                            size: 18,
                          ),
                          selected: d.gender == g,
                          onSelected: d.enabled
                              ? (_) => setState(() => _draft = d.copyWith(gender: g))
                              : null,
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.volume_up_rounded, size: 18),
                        label: const Text('Önizle'),
                        onPressed: _preview,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Her bildirimde ayrıca farklı bir ses seçilebilir. Telefonda o cinsiyette '
                    'Türkçe ses yoksa (birçok iPhone\'da erkek ses yok) ton ayarlanarak okunur.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Otomatik okunan bölümler',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final a in VoiceArea.values)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: d.areas.contains(a),
                      onChanged: d.enabled
                          ? (v) {
                              final next = {...d.areas};
                              if (v == true) {
                                next.add(a);
                              } else {
                                next.remove(a);
                              }
                              setState(() => _draft = d.copyWith(areas: next));
                            }
                          : null,
                      title: Text(a.label),
                      subtitle: Text(a.description),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: d.greeting,
                    onChanged: d.enabled
                        ? (v) => setState(() => _draft = d.copyWith(greeting: v))
                        : null,
                    title: const Text('Kişiye özel karşılama'),
                    subtitle: const Text('Okumaya "Merhaba Ahmet," gibi kullanıcının adıyla başlar.'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
