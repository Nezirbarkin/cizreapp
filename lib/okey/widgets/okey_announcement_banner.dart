import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/okey_ui.dart';

/// Masaya yapılan KISA ANONS — "Seri açıldı", "Çift açıldı",
/// "Ahmet, son üç taş" (kullanıcı isteği, 2026-09-07).
///
/// Hem sesli okunur (bkz. OkeySoundService.speak) hem de ekranda kısa bir
/// bant olarak belirir.
///
/// [id] her anonsta artar: aynı cümle art arda iki kez duyurulduğunda da
/// arayüzün animasyonu baştan oynatabilmesi için gerekli — metne bakmak
/// yetmezdi.
@immutable
class OkeyAnnouncement {
  final int id;
  final String text;

  const OkeyAnnouncement({required this.id, required this.text});
}

/// Anonsun GÖRÜNEN eşi.
///
/// ## Neden hem ses hem yazı
///
/// Ses kapalıyken, telefon sessizdeyken ya da cihazda Türkçe konuşma motoru
/// kurulu değilken anonsun taşıdığı bilgi — özellikle "kimin son üç taşı
/// kaldı" — tamamen kaybolurdu. Bant her koşulda görünür.
///
/// Masanın ÜST ORTASINDA belirir; hata perdesi (_MistakeFlash) biraz daha
/// aşağıda durur, böylece ikisi aynı anda çıktığında üst üste binmezler.
class OkeyAnnouncementBanner extends StatefulWidget {
  final ValueListenable<OkeyAnnouncement?> listenable;

  const OkeyAnnouncementBanner({super.key, required this.listenable});

  @override
  State<OkeyAnnouncementBanner> createState() => _OkeyAnnouncementBannerState();
}

class _OkeyAnnouncementBannerState extends State<OkeyAnnouncementBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  /// Belir → ~1,4 sn tam görünür kal → sön.
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 64),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 24,
    ),
  ]).animate(_controller);

  String _text = '';
  int? _lastId;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onAnnouncement);
    // Widget kurulmadan ÖNCE gelmiş bir anons varsa (masaya girerken) onu
    // "geçmiş" say: kimliğini not et ama oynatma.
    _lastId = widget.listenable.value?.id;
  }

  void _onAnnouncement() {
    final a = widget.listenable.value;
    if (a == null || a.id == _lastId) return;
    _lastId = a.id;
    // setState ŞART: metin animasyonun dışında değişiyor.
    setState(() => _text = a.text);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onAnnouncement);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        final t = _opacity.value;
        if (t <= 0 || _text.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: const Alignment(0, -0.62),
          child: Opacity(
            opacity: t,
            child: MediaQuery.withNoTextScaling(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xF2101A22),
                  borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
                  border: Border.all(
                    color: const Color(0x8AE8C069),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8A000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.campaign,
                      size: 16,
                      color: Color(0xFFE8C069),
                    ),
                    const SizedBox(width: 7),
                    // Uzun bir oyuncu adı bandı ekrandan taşırmasın.
                    Flexible(
                      child: Text(
                        // BÜYÜK HARFE ÇEVRİLMEZ. Dart'ın `toUpperCase()`
                        // Türkçe kurallarını bilmez: "Seri açıldı" → "SERI
                        // AÇILDI", "İbrahim" → "İBRAHIM" olur. Vurgu zaten
                        // yazı kalınlığı ve harf aralığından geliyor.
                        _text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF6EBD6),
                          fontSize: 14,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
