import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/okey_models.dart';
import '../providers/okey_room_provider.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';
import '../widgets/okey_invite_sheet.dart';
import '../widgets/okey_profile_sheet.dart';
import '../widgets/okey_seat_table.dart';
import 'okey_game_screen.dart';

/// Bekleme odası: 4 koltuk masa düzeninde, oyuncular hazır oldukça oyun başlar.
///
/// ## Yeniden tasarım (2026-09)
///
/// Gövde [OkeyScreen] ile kaydırılabilir; "HAZIRIM" ve ayrıl/bot butonları
/// kaydırmanın DIŞINDA sabit bir alt çubukta durur. Eski hali sabit bir
/// `Column` idi ve dört koltuk kartı (her biri 132px) + başlık + alt butonlar
/// kısa ekranlarda toplamı aşıyordu.
class OkeyRoomScreen extends StatelessWidget {
  final String roomId;

  const OkeyRoomScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OkeyRoomProvider(roomId),
      child: const _OkeyRoomView(),
    );
  }
}

class _OkeyRoomView extends StatefulWidget {
  const _OkeyRoomView();

  @override
  State<_OkeyRoomView> createState() => _OkeyRoomViewState();
}

class _OkeyRoomViewState extends State<_OkeyRoomView> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OkeyRoomProvider>();
    final room = provider.room;

    // Oyun başladıysa otomatik olarak masaya geç.
    if (!_navigated &&
        room?.status == 'in_progress' &&
        room?.currentMatchId != null) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OkeyGameScreen(matchId: room!.currentMatchId!),
          ),
        );
      });
    }

    if (provider.isLoading && room == null) {
      return OkeyScreen(
        title: 'Bekleme odası',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: OkeyUI.brass),
            ),
          ),
        ],
      );
    }

    return OkeyScreen(
      title: 'Bekleme odası',
      onRefresh: () => provider.refresh(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Yenile',
          onPressed: provider.refresh,
        ),
      ],
      bottomBar: room?.status == 'waiting'
          ? _BottomActions(provider: provider)
          : null,
      slivers: [
        if (provider.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, OkeyUI.gap),
              child: _ErrorCard(message: provider.error!),
            ),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _StatusCard(provider: provider),
          ),
        ),

        if (room?.joinCode != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, OkeyUI.gap, 14, 0),
              child: _JoinCodeCard(code: room!.joinCode!),
            ),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: const OkeySectionHeader(label: 'Koltuklar'),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // KOLTUK SEÇİMİ (kullanıcı isteği, 2026-09-21: "oyuncular
            // istediği (eşli) kişinin karşısında oturabilsin"). Boş koltuğa
            // dokunmak oraya geçirir; yalnızca masadayken ve oda bekliyorken.
            child: OkeySeatTable(
              seats: provider.seats,
              mySeatNo: provider.mySeat?.seatNo,
              isTeams: room?.teamMode == 'esli',
              canPick: room?.status == 'waiting' && provider.mySeat != null,
              onPickSeat: provider.chooseSeat,
              onSeatTap: (s) => OkeyProfileSheet.show(
                context,
                userId: s.userId,
                botProfileId: s.botProfileId,
                name: s.displayLabel,
                avatarUrl: s.avatarUrl,
              ),
            ),
          ),
        ),

        // ARKADAŞ DAVETİ — yalnızca davetin bir anlamı varken görünür:
        // masa hâlâ bekliyor, ben masadayım ve oturulacak boş koltuk var.
        // Üçünden biri bozulursa davet edilen kişi geldiğinde yer bulamaz.
        if (room?.status == 'waiting' &&
            provider.mySeat != null &&
            provider.seats.any((s) => s.isEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, OkeyUI.gap, 14, 0),
              child: _InviteFriendCard(
                roomId: provider.roomId,
                joinCode: room?.joinCode,
              ),
            ),
          ),

        if (room != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const OkeySectionHeader(label: 'Masa kuralları'),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _RulesCard(room: room),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OkeyUI.gap),
      decoration: BoxDecoration(
        color: const Color(0x338E2430),
        borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
        border: Border.all(color: const Color(0x66FF8A9B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFFF8A9B)),
          const SizedBox(width: OkeyUI.gapSm),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: OkeyUI.body.copyWith(color: const Color(0xFFFFD9DE)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kaç koltuk dolu, kaç kişi hazır.
class _StatusCard extends StatelessWidget {
  final OkeyRoomProvider provider;

  const _StatusCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final seats = provider.seats;
    final filled = seats.where((s) => !s.isEmpty).length;
    final ready = seats.where((s) => !s.isEmpty && s.isReady).length;
    final starting = provider.room?.status == 'in_progress';

    return OkeyCard(
      highlighted: starting,
      child: Row(
        children: [
          Icon(
            starting ? Icons.play_circle_fill : Icons.hourglass_top,
            size: 26,
            color: starting ? const Color(0xFFB9F6CA) : OkeyUI.brass,
          ),
          const SizedBox(width: OkeyUI.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  starting
                      ? 'Oyun başlıyor…'
                      : (filled < 4
                            ? 'Oyuncular bekleniyor'
                            : 'Herkes hazır olunca başlıyor'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title,
                ),
                const SizedBox(height: 3),
                Text(
                  '$filled/4 koltuk dolu · $ready/4 hazır',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Arkadaşını davet et" — takip edilen kişilere masaya çağrı gönderir.
///
/// Davet, karşı tarafa bildirim ve push yollar; arkadaş masaya oturduğunda
/// davet EDENE de bildirim döner (bkz. 20260905000002 göçü).
class _InviteFriendCard extends StatelessWidget {
  final String roomId;
  final String? joinCode;

  const _InviteFriendCard({required this.roomId, this.joinCode});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      onTap: () =>
          showOkeyInviteSheet(context, roomId: roomId, joinCode: joinCode),
      child: Row(
        children: [
          Icon(Icons.person_add_alt_1, size: 22, color: OkeyUI.brass),
          const SizedBox(width: OkeyUI.gap),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Arkadaşını davet et', style: OkeyUI.title),
                SizedBox(height: 3),
                Text(
                  'Takip ettiklerine masaya çağrı gönder — bildirimle haberi olur.',
                  style: OkeyUI.caption,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: OkeyUI.textFaint),
        ],
      ),
    );
  }
}

/// Özel odalarda paylaşılacak davet kodu (kopyalanabilir).
class _JoinCodeCard extends StatelessWidget {
  final String code;

  const _JoinCodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Davet kodu kopyalandı')));
      },
      child: Row(
        children: [
          Icon(Icons.vpn_key, size: 18, color: OkeyUI.brass),
          const SizedBox(width: OkeyUI.gapSm),
          const Text('Davet kodu', style: OkeyUI.body),
          const SizedBox(width: OkeyUI.gap),
          // Kod esner ve gerekirse küçülür: sabit 2px harf aralığıyla uzun
          // bir kod dar ekranda satırı taşırabilirdi.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                code,
                maxLines: 1,
                style: TextStyle(
                  color: OkeyUI.brass,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const Icon(Icons.copy, size: 16, color: OkeyUI.textFaint),
        ],
      ),
    );
  }
}

/// Masanın kuralları — lobideki etiketlerin ayrıntılı hali.
class _RulesCard extends StatelessWidget {
  final OkeyRoom room;

  const _RulesCard({required this.room});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      child: Column(
        children: [
          OkeyRow(
            icon: Icons.layers,
            label: 'Açılış',
            value: room.gameMode == 'katlamali' ? 'Katlamalı' : 'Katlamasız',
          ),
          OkeyRow(
            icon: Icons.groups,
            label: 'Takım',
            value: room.teamMode == 'esli' ? 'Eşli (2v2)' : 'Eşsiz',
          ),
          OkeyRow(
            icon: Icons.lightbulb_outline,
            label: 'Yardım',
            value: room.assistMode == 'yardimsiz' ? 'Yardımsız' : 'Yardımlı',
          ),
          OkeyRow(
            icon: Icons.style,
            label: 'El sayısı',
            value: '${room.totalHands} el',
          ),
          OkeyRow(
            icon: Icons.flag,
            label: 'Bitiş puanı',
            value: '${room.maxScore}',
          ),
          // MASA PUANI: cüzdandan düşen tutar ve NASIL oluştuğu. Yalnız
          // sonucu yazmak, lobide "500" görüp 1.500 ödeyen oyuncuya hata
          // gibi görünürdü (bkz. OkeyRoom.tableStake).
          if (room.tableStake > 0)
            OkeyRow(
              icon: Icons.stars,
              label: 'Masa çipi',
              value:
                  '${room.tableStake} puan  '
                  '(${room.entryFee} × ${room.totalHands} el)',
              valueColor: OkeyUI.brass,
            ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final OkeyRoomProvider provider;

  const _BottomActions({required this.provider});

  @override
  Widget build(BuildContext context) {
    final my = provider.mySeat;
    final isReady = my?.isReady == true;
    final hasEmpty = provider.seats.any((s) => s.isEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OkeyButton(
          label: isReady ? 'HAZIR DEĞİLİM' : 'HAZIRIM',
          icon: isReady ? Icons.close : Icons.check_circle,
          tone: isReady ? OkeyButtonTone.secondary : OkeyButtonTone.primary,
          onPressed: my == null ? null : provider.toggleReady,
        ),
        const SizedBox(height: OkeyUI.gapSm),
        Row(
          children: [
            if (hasEmpty) ...[
              Expanded(
                // "Bot ekle" DEĞİL: masada bot kelimesi hiçbir yerde geçmez
                // (2026-09, kullanıcı isteği). Düğmenin yaptığı iş zaten
                // "boş koltukları doldur"; kimin oturduğu oyuncunun bilmesi
                // gereken bir uygulama ayrıntısı değil. Havuzun yönetimi
                // admin panelinde, adıyla sanıyla duruyor.
                child: OkeyButton(
                  label: 'Masayı doldur',
                  icon: Icons.group_add,
                  tone: OkeyButtonTone.ghost,
                  onPressed: provider.fillWithBots,
                ),
              ),
              const SizedBox(width: OkeyUI.gapSm),
            ],
            Expanded(
              child: OkeyButton(
                label: 'Ayrıl',
                icon: Icons.exit_to_app,
                tone: OkeyButtonTone.danger,
                onPressed: () async {
                  await provider.leave();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
