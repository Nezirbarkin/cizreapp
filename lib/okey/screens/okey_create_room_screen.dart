import 'package:flutter/material.dart';

import '../services/okey_room_service.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';

/// Oda kurma seçimlerinin sonucu.
typedef OkeyRoomOptions = ({
  String gameMode,
  String teamMode,
  String assistMode,
  bool isPrivate,
  int totalHands,
  int entryFee,
});

/// Oda kurma ekranı — tam ekran, kart tabanlı seçim arayüzü.
///
/// ## Yeniden tasarım (2026-09)
///
/// Seçenekler [OkeyScreen] içinde kaydırılır, özet + "ODAYI KUR" sabit alt
/// çubukta durur. Eski hali de bir `ListView` + alt kutuydu ama alt kutunun
/// içindeki özet metni SARMALI değildi ve sistem yazı tipi büyütüldüğünde
/// üç satıra çıkıp butonu ekranın dışına itiyordu.
class OkeyCreateRoomScreen extends StatefulWidget {
  /// KAÇ EL OYNANACAK — masayı kuranın seçtiği süre.
  ///
  /// 2 el kullanıcı isteğiyle eklendi (2026-09-05): tek elde şans, uzun
  /// maçta zaman ağır basıyordu; iki el ikisinin arasındaki en kısa GERÇEK
  /// maç. KURAL DEĞİŞMİYOR — el sonundaki cezalar toplanır, toplamı EN
  /// DÜŞÜK olan kazanır; eşli modda iki eşin toplamı yarışır
  /// (bkz. okey_internal_award_match ve okey_matches.scores'un el başına
  /// taşınması).
  ///
  /// Sunucu 1..20 arasını zaten kabul ediyor (APP:invalid_total_hands); bu
  /// liste yalnızca SUNULAN seçenekler. Testten görünür olması kasıtlı:
  /// "2 el seçilebiliyor mu" sorusu ancak buradan yanıtlanabilir.
  static const List<int> handOptions = [1, 2, 3, 5, 7, 10];

  const OkeyCreateRoomScreen({super.key});

  @override
  State<OkeyCreateRoomScreen> createState() => _OkeyCreateRoomScreenState();
}

class _OkeyCreateRoomScreenState extends State<OkeyCreateRoomScreen> {
  String _gameMode = 'katlamasiz';
  String _teamMode = 'essiz';
  String _assistMode = 'yardimli';
  bool _isPrivate = false;
  int _totalHands = 3;

  /// MASA SADECE PUANLA AÇILIR — ücretsiz seçenek YOKTUR.
  int _entryFee = OkeyRoomService.minEntryFee;

  static const _handOptions = OkeyCreateRoomScreen.handOptions;
  static const _feeOptions = [100, 250, 500, 1000, 5000];

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return OkeyScreen(
      title: 'Oda kur',
      bottomBar: _Summary(
        gameMode: _gameMode,
        teamMode: _teamMode,
        assistMode: _assistMode,
        isPrivate: _isPrivate,
        entryFee: _entryFee,
        totalHands: _totalHands,
        onCreate: () => Navigator.of(context).pop<OkeyRoomOptions>((
          gameMode: _gameMode,
          teamMode: _teamMode,
          assistMode: _assistMode,
          isPrivate: _isPrivate,
          totalHands: _totalHands,
          entryFee: _entryFee,
        )),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _pad(
            const _SectionTitle(
              icon: Icons.layers,
              title: 'Açılış modu',
              subtitle: 'El açma barajı nasıl belirlensin?',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _OptionCard(
              selected: _gameMode == 'katlamasiz',
              icon: Icons.horizontal_rule,
              color: const Color(0xFF80D8FF),
              title: 'Katlamasız (düz)',
              description:
                  'Herkes bağımsız açar. Baraj sabit: 101 puan ya da 5 çift.',
              onTap: () => setState(() => _gameMode = 'katlamasiz'),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _OptionCard(
              selected: _gameMode == 'katlamali',
              icon: Icons.trending_up,
              color: const Color(0xFFFF8A80),
              title: 'Katlamalı',
              description:
                  'Her açılış masadaki en yüksekten en az 1 fazla olmalı '
                  '(101 → 102 → 103…).',
              onTap: () => setState(() => _gameMode = 'katlamali'),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _pad(
            const _SectionTitle(
              icon: Icons.groups,
              title: 'Takım modu',
              subtitle: 'Tek başına mı, eşinle mi?',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _OptionCard(
              selected: _teamMode == 'essiz',
              icon: Icons.person,
              color: const Color(0xFFFFCC80),
              title: 'Eşsiz (tekli)',
              description: '4 oyuncu bireysel yarışır.',
              onTap: () => setState(() => _teamMode = 'essiz'),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _OptionCard(
              selected: _teamMode == 'esli',
              icon: Icons.people,
              color: const Color(0xFFE1BEE7),
              title: 'Eşli (2v2)',
              description:
                  'Karşılıklı oturanlar takım. Eşin açtığında sen barajsız '
                  'açarsın.',
              onTap: () => setState(() => _teamMode = 'esli'),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _pad(
            const _SectionTitle(
              icon: Icons.lightbulb,
              title: 'Yardım modu',
              subtitle: 'İpuçları gösterilsin mi?',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _OptionCard(
              selected: _assistMode == 'yardimli',
              icon: Icons.auto_fix_high,
              color: const Color(0xFFB9F6CA),
              title: 'Yardımlı',
              description:
                  'İşlenebilir taşlar ve tamamlanan perler otomatik vurgulanır.',
              onTap: () => setState(() => _assistMode = 'yardimli'),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _OptionCard(
              selected: _assistMode == 'yardimsiz',
              icon: Icons.visibility_off,
              color: const Color(0xFF90A4AE),
              title: 'Yardımsız',
              description: 'Hiçbir ipucu gösterilmez.',
              onTap: () => setState(() => _assistMode = 'yardimsiz'),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _pad(
            _SectionTitle(
              icon: Icons.stars,
              title: 'Masa çipi (el başına)',
              subtitle:
                  'EL SAYISIYLA ÇARPILIR: seçtiğin çip × kaç el. '
                  'Her oyuncudan düşülür, kazanan potu alır '
                  '(en az ${OkeyRoomService.minEntryFee})',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _ChoiceRow(
              options: _feeOptions,
              selected: _entryFee,
              // Rozette EL BAŞINA puan yazar; toplam masa puanı alt çubuktaki
              // özette çarpımıyla birlikte gösterilir. Burada çarpımı yazmak,
              // el sayısı değiştikçe seçenek şeridinin tamamının değişmesi
              // demek olurdu — seçilen şey değişmediği halde.
              labelOf: (v) => '$v / el',
              onSelected: (v) => setState(() => _entryFee = v),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _pad(
            const _SectionTitle(
              icon: Icons.repeat,
              title: 'Kaç el oynanacak?',
              subtitle:
                  'Bu kadar el sonunda maç biter. MASA PUANINI DE ÇARPAR: '
                  'her el, el başına çip kadar potu büyütür',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            _ChoiceRow(
              options: _handOptions,
              selected: _totalHands,
              labelOf: (v) => '$v el',
              onSelected: (v) => setState(() => _totalHands = v),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _pad(
            const _SectionTitle(
              icon: Icons.lock,
              title: 'Gizlilik',
              subtitle: 'Odanı kimler görebilsin?',
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pad(
            OkeyCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: _isPrivate,
                onChanged: (v) => setState(() => _isPrivate = v),
                activeThumbColor: OkeyColors.accentGold,
                title: const Text(
                  'Özel oda',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title,
                ),
                subtitle: Text(
                  _isPrivate
                      ? 'Sadece davet koduyla girilebilir'
                      : 'Lobide herkese görünür',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.caption,
                ),
                secondary: Icon(
                  _isPrivate ? Icons.lock : Icons.public,
                  color: OkeyUI.textDim,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Alt çubuk: seçim özeti + kur butonu.
class _Summary extends StatelessWidget {
  final String gameMode;
  final String teamMode;
  final String assistMode;
  final bool isPrivate;
  final int entryFee;
  final int totalHands;
  final VoidCallback onCreate;

  const _Summary({
    required this.gameMode,
    required this.teamMode,
    required this.assistMode,
    required this.isPrivate,
    required this.entryFee,
    required this.totalHands,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // SARMALI özet: rozetler dar ekranda alt satıra iner, satırı taşırmaz.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 5,
          runSpacing: 5,
          children: [
            OkeyPill(
              text: gameMode == 'katlamali' ? 'Katlamalı' : 'Katlamasız',
              color: const Color(0xFFFF8A80),
            ),
            OkeyPill(
              text: teamMode == 'esli' ? 'Eşli' : 'Eşsiz',
              color: const Color(0xFF80D8FF),
            ),
            OkeyPill(
              text: assistMode == 'yardimsiz' ? 'Yardımsız' : 'Yardımlı',
              color: const Color(0xFFB9F6CA),
            ),
            OkeyPill(text: '$totalHands el', color: const Color(0xFFE1BEE7)),
            // MASA PUANI = el başına puan × el sayısı. Rozet ÇARPIMI
            // gösterir, çarpanı değil: cüzdandan düşecek olan sayı budur.
            OkeyPill(text: '${entryFee * totalHands} çip', icon: Icons.stars),
            if (isPrivate) const OkeyPill(text: 'Özel', icon: Icons.lock),
          ],
        ),
        const SizedBox(height: OkeyUI.gapSm),
        Text(
          'Masa çipi: $entryFee × $totalHands el = '
          '${entryFee * totalHands} çip. Masayı açınca oda ücretiyle '
          'birlikte düşer, kazanan potu alır.',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: OkeyUI.caption,
        ),
        const SizedBox(height: OkeyUI.gap),
        OkeyButton(
          label: 'ODAYI KUR',
          icon: Icons.add_circle_outline,
          tone: OkeyButtonTone.primary,
          onPressed: onCreate,
        ),
      ],
    );
  }
}

/// Yatay kaydırılabilir seçenek şeridi.
///
/// TAŞMA GÜVENCESİ: `Wrap` yerine YATAY KAYDIRMA. Beş "5000 puan" rozeti
/// büyütülmüş yazı tipiyle iki satıra taşıyor ve bölümün yüksekliğini
/// öngörülemez hale getiriyordu; kaydırma yüksekliği SABİT tutar.
class _ChoiceRow extends StatelessWidget {
  final List<int> options;
  final int selected;
  final String Function(int) labelOf;
  final ValueChanged<int> onSelected;

  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: OkeyUI.gapSm),
        itemBuilder: (context, i) {
          final v = options[i];
          final sel = v == selected;
          return Material(
            color: sel ? OkeyColors.accentGold : OkeyUI.cardFill,
            borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
            child: InkWell(
              borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
              onTap: () => onSelected(v),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                  border: Border.all(
                    color: sel ? Colors.transparent : OkeyUI.cardBorder,
                  ),
                ),
                child: Text(
                  labelOf(v),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: sel ? OkeyUI.onGold : OkeyUI.textDim,
                    fontWeight: sel ? FontWeight.w900 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, OkeyUI.gapLg, 2, OkeyUI.gapSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: OkeyColors.accentGold),
          const SizedBox(width: OkeyUI.gapSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
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

class _OptionCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _OptionCard({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OkeyUI.gapSm),
      child: OkeyCard(
        onTap: onTap,
        highlighted: selected,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: OkeyUI.gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OkeyUI.title,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: OkeyUI.body,
                  ),
                ],
              ),
            ),
            const SizedBox(width: OkeyUI.gapSm),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19,
              color: selected ? OkeyColors.accentGold : OkeyUI.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}
