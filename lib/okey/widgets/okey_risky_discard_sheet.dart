import 'package:flutter/material.dart';

import '../engine/okey_tile.dart';
import '../theme/okey_ui.dart';
import 'okey_tile_widget.dart';

/// İŞLEK TAŞ ONAYI — cezayı ÖNCE gösterir.
///
/// ## Neden gerekliydi
///
/// Masada açık bir pere işlenebilen bir taşı atmak +101 ceza yazar
/// (RULES.md §6). v4'te bu ceza yalnızca ATILDIKTAN SONRA görünüyordu:
/// kırmızı bir yanıp sönme ve puanın yanında beliren sayı. Yani oyunun en
/// pahalı hatası, yapıldıktan sonra bildiriliyordu.
///
/// Taş ıstakada zaten kızıl bir ışık alıyor ([OkeyTileWidget.hintRisky]) ama
/// o bir UYARIDIR, engel değil — hızlı oynayan oyuncu görmeden basar. Bu kart
/// bedeli rakamla yazar ve kararı oyuncuya bırakır.
///
/// ## Neden SADECE cezalı atışta
///
/// Her atışta onay isteseydi oyun yavaşlar ve daha kötüsü, oyuncu onayı
/// OKUMADAN basmayı öğrenirdi — o zaman kart cezayı önlemek bir yana,
/// önlediği yanılsamasını üretirdi. Nadir olduğu için okunur.
abstract final class OkeyRiskyDiscardSheet {
  /// `true` dönerse oyuncu atmayı onayladı.
  static Future<bool> confirm(
    BuildContext context, {
    required OkeyTile tile,
    required OkeyTile? okeyTile,
    required int penalty,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB3060402),
      builder: (context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OkeyUI.cardFillRaised,
                borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
                border: Border.all(color: const Color(0x80E05A4E)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xBF000000),
                    blurRadius: 30,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x3DE05A4E),
                      borderRadius: BorderRadius.circular(OkeyUI.radius),
                      border: Border.all(color: const Color(0x66E05A4E)),
                    ),
                    child: Row(
                      children: [
                        OkeyTileWidget(
                          tile: tile,
                          width: 40,
                          height: 40 / 0.74,
                          highlightAsOkey:
                              okeyTile != null && tile.isJokerFor(okeyTile),
                        ),
                        const SizedBox(width: OkeyUI.gap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Bu taş masada işleniyor',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFFD9D4),
                                ),
                              ),
                              const SizedBox(height: OkeyUI.gapXs),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(text: 'Atarsan '),
                                    TextSpan(
                                      text: '+$penalty ceza',
                                      style: const TextStyle(
                                        color: Color(0xFFFF9A90),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const TextSpan(
                                      text:
                                          ' yazılır. Başka bir taş atabilir '
                                          'ya da bu taşı işleyebilirsin.',
                                    ),
                                  ],
                                ),
                                style: OkeyUI.body.copyWith(
                                  color: const Color(0xCCFFD9D4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: OkeyUI.gapLg),
                  Row(
                    children: [
                      Expanded(
                        child: _SheetButton(
                          label: 'Vazgeç',
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: OkeyUI.gap),
                      Expanded(
                        child: _SheetButton(
                          label: 'Yine de at',
                          danger: true,
                          onPressed: () => Navigator.of(context).pop(true),
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
    return ok ?? false;
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final bool danger;
  final VoidCallback onPressed;

  const _SheetButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: danger ? null : OkeyUI.cardFill,
          gradient: danger
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE05A4E), Color(0xFFA32C22)],
                )
              : null,
          borderRadius: BorderRadius.circular(OkeyUI.radius),
          border: Border.all(
            color: danger ? const Color(0x00000000) : OkeyUI.cardBorder,
          ),
          boxShadow: danger
              ? const [
                  BoxShadow(color: Color(0xFF6E1A13), offset: Offset(0, 3)),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: danger ? const Color(0xFFFFEDEA) : OkeyUI.text,
          ),
        ),
      ),
    );
  }
}
