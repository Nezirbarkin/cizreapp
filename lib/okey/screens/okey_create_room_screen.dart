import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// SUNUCUDAKİ SINIRLAR — alt sınır, oda açma ücreti, cüzdan.
  ///
  /// Üçü de `okey_settings`/`okey_wallets` içinde ve istemciye kapalı; tek
  /// çağrıda alınır (bkz. OkeyRoomService.roomLimits). Gelene kadar ekran
  /// çalışır: alt sınır istemcideki sabitten, üst sınır "bilinmiyor"dan
  /// okunur ve son sözü zaten sunucu söyler.
  ({int minEntryFee, int roomCreationFee, int walletPoints})? _limits;

  late final TextEditingController _feeCtrl = TextEditingController(
    text: '$_entryFee',
  );

  int get _minFee => _limits?.minEntryFee ?? OkeyRoomService.minEntryFee;

  /// EL BAŞINA TAVAN. Gerçek kısıt `create_okey_room` içindeki
  /// `oda ücreti + çip × el ≤ cüzdan` hesabıdır; bölme burada yapılır çünkü
  /// el sayısı ekranda değişiyor.
  ///
  /// Sınırlar henüz gelmediyse 0 döner — "tavan bilinmiyor" demektir ve
  /// [_FeeField] o durumda üst sınır göstermez, kısıtlamaz.
  int get _maxFeePerHand {
    final l = _limits;
    if (l == null) return 0;
    final spendable = l.walletPoints - l.roomCreationFee;
    if (spendable <= 0) return 0;
    return spendable ~/ _totalHands;
  }

  /// Seçilen çip hem alt sınırı geçiyor hem cüzdana sığıyor mu?
  bool get _feeValid =>
      _entryFee >= _minFee && (_limits == null || _entryFee <= _maxFeePerHand);

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  @override
  void dispose() {
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLimits() async {
    try {
      final l = await OkeyRoomService().roomLimits();
      if (!mounted) return;
      _limits = l;
      // Alt sınır sunucuda yükselmişse seçili tutar onunla hizalanır.
      // _setFee zaten setState çağırır.
      _setFee(_entryFee < l.minEntryFee ? l.minEntryFee : _entryFee);
    } catch (_) {
      // Sessiz: ekran sınırlar olmadan da çalışır, sunucu yine doğrular.
    }
  }

  /// Tutarı hem alana hem duruma yazar (rozet ↔ alan asla ayrışmaz).
  void _setFee(int v) {
    _entryFee = v;
    final text = '$v';
    if (_feeCtrl.text != text) {
      _feeCtrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    if (mounted) setState(() {});
  }

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
        minFee: _minFee,
        maxFeePerHand: _maxFeePerHand,
        // ÇİP GEÇERSİZSE KUR DÜĞMESİ KAPALI: sunucu zaten reddederdi
        // (APP:entry_fee_too_low / APP:insufficient_points), ama oyuncuya
        // sebebi burada, basmadan önce söylenir.
        canCreate: _feeValid,
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
        // KURALLAR — üç ikili seçim tek kartta, her biri bölmeli anahtar.
        //
        // Eskiden altı ayrı radyo kartı (katlama, takım, yardım × 2) alt alta
        // diziliyordu: dört ekran boyu kaydırma, oysa her seçim yalnızca iki
        // seçenek. Şimdi seçenekler yan yana, seçilenin açıklaması altında tek
        // satır. Hiçbir seçenek kalkmadı, sunucuya giden değerler aynı.
        SliverToBoxAdapter(
          child: _pad(
            Column(
              children: [
                _RuleSegment(
                  icon: Icons.layers,
                  title: 'Açılış modu',
                  selected: _gameMode,
                  onSelected: (v) => setState(() => _gameMode = v),
                  options: const [
                    _RuleOption(
                      value: 'katlamasiz',
                      label: 'Katlamasız',
                      description:
                          'Herkes bağımsız açar. Baraj sabit: 101 puan ya da '
                          '5 çift.',
                    ),
                    _RuleOption(
                      value: 'katlamali',
                      label: 'Katlamalı',
                      description:
                          'Her açılış masadaki en yüksekten en az 1 fazla '
                          'olmalı (101 → 102 → 103…).',
                    ),
                  ],
                ),
                _RuleSegment(
                  icon: Icons.groups,
                  title: 'Takım modu',
                  selected: _teamMode,
                  onSelected: (v) => setState(() => _teamMode = v),
                  options: const [
                    _RuleOption(
                      value: 'essiz',
                      label: 'Tekli',
                      description: '4 oyuncu bireysel yarışır.',
                    ),
                    _RuleOption(
                      value: 'esli',
                      label: 'Eşli (2v2)',
                      description:
                          'Karşılıklı oturanlar takım. Eşin açtığında sen '
                          'barajsız açarsın.',
                    ),
                  ],
                ),
                _RuleSegment(
                  icon: Icons.lightbulb,
                  title: 'Yardım modu',
                  selected: _assistMode,
                  onSelected: (v) => setState(() => _assistMode = v),
                  options: const [
                    _RuleOption(
                      value: 'yardimli',
                      label: 'Yardımlı',
                      description:
                          'İşlenebilir taşlar ve tamamlanan perler otomatik '
                          'vurgulanır.',
                    ),
                    _RuleOption(
                      value: 'yardimsiz',
                      label: 'Yardımsız',
                      description: 'Hiçbir ipucu gösterilmez.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _pad(
            _SectionTitle(
              icon: Icons.stars,
              title: 'Masa çipi (el başına)',
              subtitle:
                  'EL SAYISIYLA ÇARPILIR: yazdığın çip × kaç el. '
                  'Her oyuncudan düşülür, kazanan potu alır '
                  '(en az $_minFee)',
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
              onSelected: _setFee,
            ),
          ),
        ),
        // SERBEST TUTAR (kullanıcı isteği, 2026-09-13: "istediği puanla
        // açabilsin", "istenirse tüm puanını masaya koyabilsin").
        //
        // Hazır rozetler KISAYOL olarak kalır: en sık seçilen beş tutar için
        // klavye açmanın anlamı yok. Alan onların yerini değil, ARASINI
        // doldurur.
        SliverToBoxAdapter(
          child: _pad(
            Padding(
              padding: const EdgeInsets.only(top: OkeyUI.gapSm),
              child: _FeeField(
                controller: _feeCtrl,
                minFee: _minFee,
                maxFeePerHand: _maxFeePerHand,
                totalHands: _totalHands,
                limitsKnown: _limits != null,
                onChanged: (v) => setState(() => _entryFee = v),
                onAllIn: _maxFeePerHand >= _minFee
                    ? () => _setFee(_maxFeePerHand)
                    : null,
              ),
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
                activeThumbColor: OkeyUI.brass,
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
  final int minFee;

  /// 0 ise "tavan bilinmiyor" (sınırlar henüz gelmedi).
  final int maxFeePerHand;
  final bool canCreate;
  final VoidCallback onCreate;

  const _Summary({
    required this.gameMode,
    required this.teamMode,
    required this.assistMode,
    required this.isPrivate,
    required this.entryFee,
    required this.totalHands,
    required this.minFee,
    required this.maxFeePerHand,
    required this.canCreate,
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
          canCreate
              ? 'Masa çipi: $entryFee × $totalHands el = '
                    '${entryFee * totalHands} çip. Masayı açınca oda ücretiyle '
                    'birlikte düşer, kazanan potu alır.'
              : (entryFee < minFee
                    ? 'Masa çipi en az $minFee olmalı.'
                    : 'Çipin yetmiyor: $totalHands el için el başına en çok '
                          '$maxFeePerHand koyabilirsin.'),
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
          onPressed: canCreate ? onCreate : null,
        ),
      ],
    );
  }
}

/// SERBEST MASA ÇİPİ — istenen tutar yazılır, "TÜMÜ" cüzdanın tamamını koyar.
///
/// Alan yalnızca RAKAM kabul eder ve BOŞ bırakılabilir: yazarken her tuşta
/// "en az 100" diye bağırmak, 1000 yazmak isteyen oyuncuya üç kez hata
/// göstermek demekti. Geçerlilik alt çubukta, KUR düğmesinin yanında söylenir
/// (bkz. [_Summary.canCreate]) — orası kararın verildiği yer.
class _FeeField extends StatelessWidget {
  final TextEditingController controller;
  final int minFee;

  /// 0 ise tavan bilinmiyor (sınırlar henüz gelmedi): üst sınır yazılmaz.
  final int maxFeePerHand;
  final int totalHands;
  final bool limitsKnown;
  final ValueChanged<int> onChanged;

  /// null ise cüzdan alt sınırı bile karşılamıyor demektir.
  final VoidCallback? onAllIn;

  const _FeeField({
    required this.controller,
    required this.minFee,
    required this.maxFeePerHand,
    required this.totalHands,
    required this.limitsKnown,
    required this.onChanged,
    required this.onAllIn,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  // 9 hane: cüzdanın makul üst sınırının çok üstü, ama
                  // sınırsız bir metni int'e çevirmeye çalışmaktan korur.
                  LengthLimitingTextInputFormatter(9),
                ],
                style: OkeyUI.title,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'El başına çip',
                  labelStyle: OkeyUI.caption,
                  prefixIcon: Icon(
                    Icons.stars,
                    color: OkeyUI.brass,
                    size: 18,
                  ),
                  filled: true,
                  fillColor: OkeyUI.cardFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                    borderSide: const BorderSide(color: OkeyUI.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                    borderSide: const BorderSide(color: OkeyUI.cardBorder),
                  ),
                ),
                onChanged: (t) => onChanged(int.tryParse(t) ?? 0),
              ),
            ),
            const SizedBox(width: OkeyUI.gapSm),
            OkeyButton(
              label: 'TÜMÜ',
              icon: Icons.all_inclusive,
              expand: false,
              onPressed: onAllIn,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          limitsKnown
              ? (maxFeePerHand >= minFee
                    ? 'En az $minFee, en çok $maxFeePerHand '
                          '(cüzdanının tamamı, $totalHands ele bölünmüş).'
                    : 'Çipin bu masaya yetmiyor: en az $minFee gerekiyor.')
              : 'En az $minFee.',
          style: OkeyUI.caption,
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
            color: sel ? OkeyUI.brass : OkeyUI.cardFill,
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
          Icon(icon, size: 17, color: OkeyUI.brass),
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

/// [_RuleSegment]'in tek seçeneği.
class _RuleOption {
  final String value;
  final String label;
  final String description;

  const _RuleOption({
    required this.value,
    required this.label,
    required this.description,
  });
}

/// İkili kural seçimi: başlık + yan yana segmentler + seçilenin açıklaması.
///
/// TAŞMA GÜVENCESİ: segment etiketi `FittedBox(scaleDown)` içinde, açıklama
/// üç satırla sınırlı ve `Expanded` genişlikte — büyütülmüş yazı tipinde de
/// kart yatayda taşmaz.
class _RuleSegment extends StatelessWidget {
  final IconData icon;
  final String title;
  final String selected;
  final List<_RuleOption> options;
  final ValueChanged<String> onSelected;

  const _RuleSegment({
    required this.icon,
    required this.title,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final current = options.firstWhere(
      (o) => o.value == selected,
      orElse: () => options.first,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: OkeyUI.gapSm),
      child: OkeyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: OkeyUI.brass),
                const SizedBox(width: OkeyUI.gapSm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OkeyUI.title,
                  ),
                ),
              ],
            ),
            const SizedBox(height: OkeyUI.gapSm),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0x14FFF0D2),
                borderRadius: BorderRadius.circular(OkeyUI.radius),
                border: Border.all(color: OkeyUI.cardBorder),
              ),
              child: Row(
                children: [
                  for (final o in options)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: o.value == selected,
                        label: o.label,
                        child: GestureDetector(
                          onTap: () => onSelected(o.value),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: o.value == selected
                                  ? const Color(0xFFE4B04C)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                OkeyUI.radiusSm,
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                o.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: o.value == selected
                                      ? OkeyUI.onGold
                                      : OkeyUI.textDim,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: OkeyUI.gapSm),
            Text(
              current.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: OkeyUI.body,
            ),
          ],
        ),
      ),
    );
  }
}
