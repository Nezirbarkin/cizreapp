// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// "2 al biri bakiye" kampanyalı ürünlerde gösterilen küçük rozet
class CampaignBadge extends StatelessWidget {
  const CampaignBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '2 Al 1 Bakiye',
        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Ürün kartlarında gösterilen animasyonlu "flaş indirim" rozeti.
/// Hafif nabız (pulse) ve parlama efektiyle dikkat çeker.
class FlashDiscountBadge extends StatefulWidget {
  final int percentage;
  final bool compact;

  const FlashDiscountBadge({
    super.key,
    required this.percentage,
    this.compact = false,
  });

  @override
  State<FlashDiscountBadge> createState() => _FlashDiscountBadgeState();
}

class _FlashDiscountBadgeState extends State<FlashDiscountBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 1.08,
  ).animate(_controller);

  /// Rozet göründüğünde kaç kez nabız atar (her nabız = büyü + küçül).
  static const _pulses = 3;
  bool _pulsed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sistem "animasyonları azalt" ayarındaysa rozet sabit durur.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_pulsed) {
      // Sonsuz değil: birkaç nabızdan sonra durur. Eskiden sonsuzdu ve
      // ekranda tek bir flaş ürün bile olsa uygulama hiç boşta kalmıyor,
      // saniyede 120 kare çiziyordu (pil/ısınma; profile ölçümü
      // 2026-10-06). Kart kaydırılıp yeniden görününce tekrar nabız atar.
      _pulsed = true;
      _controller.repeat(reverse: true, count: _pulses * 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  BoxDecoration _decoration(double glow) => BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFFFF5252), Color(0xFFE53935)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(widget.compact ? 4 : 6),
    boxShadow: [
      BoxShadow(
        color: Colors.red.withOpacity(glow),
        blurRadius: 8,
        spreadRadius: 1,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Eskiden AnimatedBuilder her karede rozetin tamamını (Container, Row,
    // Text) yeniden kurup yerleşimini yapıyordu ve RepaintBoundary olmadığı
    // için her karede ÜRÜN KARTININ TAMAMI yeniden boyanıyordu — listede
    // birkaç flaş ürün varken kaydırma takılıyordu. Artık ölçek ve parıltı
    // yalnız boyama aşamasında değişir, yazı tek seferlik bir katmanda kalır.
    return RepaintBoundary(
      child: ScaleTransition(
        scale: _scale,
        child: DecoratedBoxTransition(
          decoration: DecorationTween(
            begin: _decoration(0.25),
            end: _decoration(0.60),
          ).animate(_controller),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 5 : 8,
              vertical: widget.compact ? 2 : 4,
            ),
            child: RepaintBoundary(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, color: Colors.white, size: widget.compact ? 9 : 12),
                  const SizedBox(width: 2),
                  Text(
                    widget.compact ? '%${widget.percentage}' : '%${widget.percentage} İndirim',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 8 : 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
