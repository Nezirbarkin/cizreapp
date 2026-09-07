import 'package:flutter/material.dart';

import '../models/okey_models.dart';
import '../services/okey_gift_service.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';
import 'okey_gift_badge.dart';

/// HEDİYE GÖNDERME SAYFASI — "kime" ve "ne" tek ekranda.
///
/// ## Neden tek adım
///
/// İki adımlı bir akış (önce oyuncu seç, sonra hediye seç) masanın ortasında
/// iki dokunuş ve bir geri tuşu demektir; oyuncu bunu sıra kendisindeyken
/// yapamaz. Alıcı yukarıda bir şerit, hediyeler altında bir ızgara: hediyeye
/// dokunmak hem seçim hem gönderimdir.
///
/// ## Kime gönderilebilir
///
/// Masadaki DOLU koltukların hepsine — kendim hariç. Bot koltukları da
/// listede durur ve hediye kabul eder: listede olmasalardı, "kime hediye
/// gönderemiyorum" sorusunun cevabı doğrudan "hangi koltuk bot" olurdu
/// (bkz. OkeyRoomSeat.displayLabel — botlar masada ele verilmez).
class OkeyGiftSheet extends StatefulWidget {
  /// Masadaki koltuklar (boş olanlar burada elenir).
  final List<OkeyRoomSeat> seats;

  /// Kendi koltuğum — listede gösterilmez. İzleyiciysem null.
  final int? mySeatNo;

  /// Hediye menüsünü getiren çağrı (provider üzerinden önbelleklenir).
  final Future<List<OkeyGift>> Function() loadCatalog;

  /// Gönderim: (koltuk, hediye kodu).
  final Future<void> Function(int seatNo, String giftCode) onSend;

  const OkeyGiftSheet({
    super.key,
    required this.seats,
    required this.mySeatNo,
    required this.loadCatalog,
    required this.onSend,
  });

  static Future<void> show(
    BuildContext context, {
    required List<OkeyRoomSeat> seats,
    required int? mySeatNo,
    required Future<List<OkeyGift>> Function() loadCatalog,
    required Future<void> Function(int seatNo, String giftCode) onSend,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OkeyGiftSheet(
        seats: seats,
        mySeatNo: mySeatNo,
        loadCatalog: loadCatalog,
        onSend: onSend,
      ),
    );
  }

  @override
  State<OkeyGiftSheet> createState() => _OkeyGiftSheetState();
}

class _OkeyGiftSheetState extends State<OkeyGiftSheet> {
  late Future<List<OkeyGift>> _catalog;
  int? _seatNo;
  bool _sending = false;

  List<OkeyRoomSeat> get _targets => [
    for (final s in widget.seats)
      if (!s.isEmpty && s.seatNo != widget.mySeatNo) s,
  ];

  @override
  void initState() {
    super.initState();
    _catalog = widget.loadCatalog();
    final t = _targets;
    // Tek bir aday varsa (ör. iki kişilik masa) seçim sorusu sorulmaz.
    if (t.isNotEmpty) _seatNo = t.first.seatNo;
  }

  Future<void> _send(OkeyGift gift) async {
    final seat = _seatNo;
    if (seat == null || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(seat, gift.code);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError('$e'))));
    }
  }

  /// Sunucu hatalarını masada okunabilir bir cümleye çevirir.
  ///
  /// Ham PostgrestException metni ("APP:insufficient_points | mevcut: 40,
  /// gerekli: 100") masanın ortasında gösterilecek bir şey değil; ama
  /// PUANIN YETMEDİĞİ bilgisi tam da oyuncunun bilmesi gereken şey.
  String _friendlyError(String raw) {
    if (raw.contains('insufficient_points')) {
      return 'Çipin yetmiyor — daha ucuz bir hediye seçebilirsin.';
    }
    if (raw.contains('cannot_gift_self')) {
      return 'Kendine hediye gönderemezsin.';
    }
    if (raw.contains('seat_empty')) return 'O koltuk boş.';
    if (raw.contains('not_at_table')) return 'Bu masayı izlemiyorsun.';
    return 'Hediye gönderilemedi.';
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;

    // YATAY EKRAN TAŞMASI — okey masası yatay oynanır ve o ekranda sayfaya
    // düşen yükseklik ~360-420px'dir.
    //
    // Eski hali sabit yükseklikli bir yığındı (başlık + alıcı şeridi +
    // 260px'lik ızgara + düğme) ve toplamı ekranı ~94px aşıyordu:
    // "BOTTOM OVERFLOWED BY 94 PIXELS". Sayfayı kısaltmak çözüm değil —
    // hediye sayısını ADMİN belirliyor, yani içerik yüksekliği önceden
    // BİLİNEMEZ.
    //
    // Yapısal çözüm: sayfa ekranın en fazla %92'sini kaplar, sabit parçalar
    // (başlık, alıcı şeridi, düğme) yerini alır ve ARTAN yüksekliği ızgara
    // alır ([Flexible]). Izgara kendi içinde kaydırılır, dolayısıyla hediye
    // sayısı ne olursa olsun taşma yapısal olarak imkânsızdır.
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.92;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16556E), OkeyColors.screenBackground],
          ),
          borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
          border: Border.all(color: OkeyUI.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OkeyUI.textFaint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: OkeyUI.gapSm),
              // BAŞLIK VE AÇIKLAMA TEK SATIRDA: yatay ekranda her satır,
              // ızgaradan çalınan bir sıra demek.
              const Row(
                children: [
                  Icon(
                    Icons.card_giftcard,
                    size: 18,
                    color: OkeyColors.accentGold,
                  ),
                  SizedBox(width: 7),
                  Text('HEDİYE GÖNDER', style: OkeyUI.title),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'bedeli çipinden düşer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.caption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OkeyUI.gapSm),

              if (targets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Masada hediye gönderilecek oyuncu yok.',
                    style: OkeyUI.body,
                  ),
                )
              else ...[
                const Text('KİME', style: OkeyUI.sectionLabel),
                const SizedBox(height: OkeyUI.gapXs),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: targets.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: OkeyUI.gapXs),
                    itemBuilder: (_, i) {
                      final s = targets[i];
                      final selected = s.seatNo == _seatNo;
                      return _SeatChip(
                        seat: s,
                        selected: selected,
                        onTap: () => setState(() => _seatNo = s.seatNo),
                      );
                    },
                  ),
                ),
                const SizedBox(height: OkeyUI.gapSm),
                const Text('NE', style: OkeyUI.sectionLabel),
                const SizedBox(height: OkeyUI.gapXs),
                // Menü sunucudan gelir; kodda gömülü hediye listesi YOK.
                Flexible(
                  child: FutureBuilder<List<OkeyGift>>(
                    future: _catalog,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: OkeyColors.accentGold,
                              strokeWidth: 2.5,
                            ),
                          ),
                        );
                      }
                      final gifts = snap.data ?? const <OkeyGift>[];
                      if (gifts.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            'Şu an gönderilebilecek hediye yok.',
                            style: OkeyUI.body,
                          ),
                        );
                      }
                      return GridView.builder(
                        // shrinkWrap YOK ve olmamalı: ızgara Flexible'ın
                        // verdiği yüksekliği alır ve içinde kaydırılır.
                        // shrinkWrap ile kendi doğal yüksekliğini isteseydi
                        // taşma geri gelirdi.
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              // Yatay ekranda daha çok hediye aynı anda
                              // görünsün diye küçük hücreler.
                              maxCrossAxisExtent: 88,
                              mainAxisSpacing: OkeyUI.gapXs,
                              crossAxisSpacing: OkeyUI.gapXs,
                              childAspectRatio: 0.95,
                            ),
                        itemCount: gifts.length,
                        itemBuilder: (_, i) => _GiftTile(
                          gift: gifts[i],
                          enabled: !_sending && _seatNo != null,
                          onTap: () => _send(gifts[i]),
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: OkeyUI.gapSm),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OkeyButton(
                  label: 'VAZGEÇ',
                  tone: OkeyButtonTone.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alıcı adayı — avatar + ad.
class _SeatChip extends StatelessWidget {
  final OkeyRoomSeat seat;
  final bool selected;
  final VoidCallback onTap;

  const _SeatChip({
    required this.seat,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? OkeyColors.accentGold.withValues(alpha: 0.18)
              : OkeyUI.cardFill,
          borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
          border: Border.all(
            color: selected ? OkeyColors.accentGold : OkeyUI.cardBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: Colors.white12,
              backgroundImage: seat.avatarUrl == null
                  ? null
                  : NetworkImage(seat.avatarUrl!),
              child: seat.avatarUrl != null
                  ? null
                  : const Icon(Icons.person, size: 14, color: Colors.white70),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                seat.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? OkeyColors.accentGold : OkeyUI.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tek bir hediye: emoji + ad + fiyat.
class _GiftTile extends StatelessWidget {
  final OkeyGift gift;
  final bool enabled;
  final VoidCallback onTap;

  const _GiftTile({
    required this.gift,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: OkeyUI.cardFill,
            borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
            border: Border.all(color: OkeyUI.cardBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // İKON MENÜDE DE OYNAR: "hareketli ikon" bir vaat değil,
              // seçerken görülen şey olmalı — oyuncu gönderdikten sonra
              // masada ne olacağını burada görür.
              OkeyAnimatedGiftIcon(
                icon: gift.icon,
                anim: OkeyGiftAnim.parse(gift.anim),
                size: 26,
              ),
              const SizedBox(height: 3),
              Text(
                gift.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: OkeyUI.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.stars, size: 12, color: Color(0xFFFFD54F)),
                  const SizedBox(width: 3),
                  Text(
                    '${gift.price}',
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
