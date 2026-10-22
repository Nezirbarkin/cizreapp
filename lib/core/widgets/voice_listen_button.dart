import 'package:flutter/material.dart';

import '../services/announcement_voice_service.dart';
import '../services/voice_announce_settings_service.dart';

/// Bir duyuruyu sesli dinletme düğmesi ("Dinle" / "Durdur").
///
/// Admin sesli duyuruları tamamen kapattıysa hiçbir yer kaplamaz. Aynı
/// [listenKey] okunurken tekrar basılırsa durdurur.
class VoiceListenButton extends StatefulWidget {
  const VoiceListenButton({
    super.key,
    required this.listenKey,
    this.title,
    this.body,
    this.voiceText,
    this.gender,
    this.compact = false,
    this.color,
    this.service,
  });

  /// Okunan içeriğin kimliği (ör. `admin:<kampanya>`); otomatik okumayla aynı
  /// anahtar verilirse dinlenen duyuru bir daha kendiliğinden okunmaz.
  final String listenKey;
  final String? title;
  final String? body;

  /// Admin'in yazdığı ayrı sesli metin (yoksa başlık + metin okunur).
  final String? voiceText;

  /// `female` | `male` | null (admin varsayılanı).
  final String? gender;

  /// true: yalnız ikon; false: ikon + "Dinle" yazısı.
  final bool compact;
  final Color? color;

  /// Testlerde sahte servis vermek için.
  final AnnouncementVoiceService? service;

  @override
  State<VoiceListenButton> createState() => _VoiceListenButtonState();
}

class _VoiceListenButtonState extends State<VoiceListenButton> {
  late bool _enabled = VoiceAnnounceSettingsService.current.enabled;

  AnnouncementVoiceService get _service =>
      widget.service ?? AnnouncementVoiceService.instance;

  @override
  void initState() {
    super.initState();
    VoiceAnnounceSettingsService.fetch().then((s) {
      if (mounted && s.enabled != _enabled) setState(() => _enabled = s.enabled);
    });
  }

  void _toggle() {
    _service.toggleListen(
      key: widget.listenKey,
      title: widget.title,
      body: widget.body,
      voiceText: widget.voiceText,
      gender: widget.gender,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<String?>(
      valueListenable: _service.speakingKey,
      builder: (context, speaking, _) {
        final active = speaking == widget.listenKey;
        final icon = active ? Icons.stop_circle_outlined : Icons.volume_up_rounded;
        final label = active ? 'Durdur' : 'Dinle';
        if (widget.compact) {
          return IconButton(
            tooltip: active ? 'Okumayı durdur' : 'Sesli dinle',
            onPressed: _toggle,
            icon: Icon(icon, color: color),
            visualDensity: VisualDensity.compact,
          );
        }
        return TextButton.icon(
          onPressed: _toggle,
          icon: Icon(icon, size: 20, color: color),
          label: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}
