import 'package:flutter/material.dart';

import '../theme/okey_rack_style.dart';
import '../theme/okey_theme.dart';

/// MASA AYARLARI DİYALOĞU.
///
/// ## Neden kendi dosyasında ve provider'a bağlı DEĞİL
///
/// Diyalog eskiden `okey_game_screen.dart` içinde, `showDialog`'un
/// `builder`ında elle kurulmuş bir `Column`'du ve `OkeyGameProvider`'a
/// doğrudan bakıyordu. İkisi birden onu TEST EDİLEMEZ yapıyordu: provider
/// Supabase istiyor, diyalog da ekranın içinden çıkarılamıyordu. Oysa
/// kullanıcının bildirdiği sorun tam olarak bir DÜZEN sorunuydu ("ayardaki
/// taşma"), yani pump edilebilseydi otomatik yakalanabilirdi.
///
/// Artık diyalog yalnızca değerleri ve geri çağrıları alıyor; testte düz
/// kapanışlarla kurulabiliyor (bkz. okey_table_settings_dialog_test.dart).
///
/// ## Taşma neden artık olmuyor
///
/// Masa YATAY çalışıyor: 411 px yüksekliğindeki bir telefonda diyaloğa kalan
/// yer ~300 px, yazı ölçeği 1.5 iken çok daha az. Eski düzende içerik sabit
/// bir `Column`du ve sığmayınca "BOTTOM OVERFLOWED BY N PIXELS" veriyordu.
/// İçerik artık `SingleChildScrollView` içinde; `AlertDialog` içeriği zaten
/// `Flexible` olarak yerleştirdiği için yükseklik sınırlıdır ve sığmayan
/// içerik taşmak yerine KAYAR.
class OkeyTableSettingsDialog extends StatefulWidget {
  final bool Function() isSoundOn;
  final bool Function() isVoiceOn;
  final bool Function() isMusicOn;

  final VoidCallback onToggleSound;
  final VoidCallback onToggleVoice;
  final VoidCallback onToggleMusic;

  /// Diyalog KAPANDIKTAN sonra çağrılır — gezinme, diyaloğun ölmüş
  /// context'iyle değil masanın context'iyle yapılmalı.
  final VoidCallback onLeaveTable;

  const OkeyTableSettingsDialog({
    super.key,
    required this.isSoundOn,
    required this.isVoiceOn,
    required this.isMusicOn,
    required this.onToggleSound,
    required this.onToggleVoice,
    required this.onToggleMusic,
    required this.onLeaveTable,
  });

  @override
  State<OkeyTableSettingsDialog> createState() =>
      _OkeyTableSettingsDialogState();
}

class _OkeyTableSettingsDialogState extends State<OkeyTableSettingsDialog> {
  /// "Masadan ayrıl" TEK DOKUNUŞLA çalışmaz.
  ///
  /// Masa puanı elin başında tahsil ediliyor (RULES.md §8); yanlışlıkla
  /// dokunulan bir satır, oyuncuyu ödediği masadan çıkarıyordu. Onay adımı
  /// AYRI bir diyalog açmak yerine aynı satırda beliriyor: yatay ekranda üst
  /// üste iki diyalog, alttakini tamamen kapatır.
  bool _confirmLeave = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OkeyColors.screenBackground,
      // Yatay ekranda varsayılan iç boşluk diyaloğu gereksiz daraltıyordu.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      title: const Text(
        'Ayarlar',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _switchRow(
                icon: Icons.volume_up,
                title: 'Ses efektleri',
                value: widget.isSoundOn(),
                onChanged: (_) {
                  widget.onToggleSound();
                  setState(() {});
                },
              ),
              _switchRow(
                icon: Icons.campaign,
                title: 'Sesli anons',
                subtitle: '"Seri açıldı", "Çift açıldı", "Son üç taş"',
                value: widget.isVoiceOn(),
                onChanged: (_) {
                  widget.onToggleVoice();
                  setState(() {});
                },
              ),
              _switchRow(
                icon: Icons.music_note,
                title: 'Müzik',
                subtitle: 'Arka plan şarkısı',
                value: widget.isMusicOn(),
                onChanged: (_) {
                  widget.onToggleMusic();
                  setState(() {});
                },
              ),
              const Divider(color: Colors.white12, height: 18),
              const OkeyRackStylePicker(),
              const Divider(color: Colors.white12, height: 18),
              _leaveRow(),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
      secondary: Icon(icon, color: Colors.white70, size: 20),
    );
  }

  Widget _leaveRow() {
    if (!_confirmLeave) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.exit_to_app,
          color: Colors.redAccent,
          size: 20,
        ),
        title: const Text(
          'Masadan ayrıl',
          style: TextStyle(color: Colors.redAccent, fontSize: 14),
        ),
        onTap: () => setState(() => _confirmLeave = true),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Masadan ayrılırsan el senin adına otomatik oynanır ve '
          'ödediğin masa puanı geri gelmez.',
          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.25),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _confirmLeave = false),
              child: const Text('Vazgeç'),
            ),
            const SizedBox(width: 4),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onLeaveTable();
              },
              child: const Text('Evet, ayrıl'),
            ),
          ],
        ),
      ],
    );
  }
}

/// ISTAKA (TAKOZ) SEÇİMİ — kullanıcı isteği, 2026-09-07.
///
/// Seçenekler YATAY kaydırılır: dört (ileride daha fazla) önizleme dar bir
/// ekranda yan yana sığmayabilir ve sığmadığında düz bir `Row` sessizce
/// TAŞARDI. Kaydırma, ayarların geri kalanı dikey kayarken de doğru çalışır
/// — iki eksen birbirine karışmaz.
class OkeyRackStylePicker extends StatelessWidget {
  const OkeyRackStylePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OkeyRackStyle>(
      valueListenable: OkeyRackStylePrefs.instance.current,
      builder: (context, selected, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.view_agenda, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              const Text(
                'Takoz',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const Spacer(),
              // Seçili ıstakanın adı: uzun bir ad Row'u taşırmasın diye
              // esnetilir ve kırpılır.
              Flexible(
                child: Text(
                  selected.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFFE8C069),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: OkeyRackStyle.all.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final style = OkeyRackStyle.all[i];
                return _RackStyleChip(
                  style: style,
                  selected: style.key == selected.key,
                  onTap: () => OkeyRackStylePrefs.instance.select(style),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RackStyleChip extends StatelessWidget {
  final OkeyRackStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _RackStyleChip({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 92,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFE8C069) : const Color(0x33FFFFFF),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ÖNİZLEME: gerçek ıstaka painter'ı + üstünde üç minik taş.
            // Taşsız bir önizleme yalnızca rengi gösterirdi; oysa seçimin
            // asıl sonucu, taşların ALTINDA nasıl bir yüzey durduğudur.
            SizedBox(
              height: 30,
              width: double.infinity,
              child: CustomPaint(
                painter: OkeyRackBodyPainter(
                  style: style,
                  tileContactHeight: 4,
                  lipHeight: 5,
                  preview: true,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (_) => Container(
                        width: 9,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E9D2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            // Etiket, yazı ölçeği büyütüldüğünde önizlemeyi taşırmasın diye
            // tek satır + kırpma.
            Flexible(
              child: Text(
                style.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? const Color(0xFFE8C069) : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
