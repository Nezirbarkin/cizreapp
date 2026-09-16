import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'okey_admin_service.dart';
import 'okey_admin_widgets.dart';

/// Admin panelinde Okey ayarları + sistem kazancı özeti.
///
/// Sistem kazancı üç kalemden oluşur ve üçü de buradan ayarlanır:
///   • Oda kurma ücreti  — masayı açan oyuncudan alınan sabit puan
///   • Pot komisyonu (%) — maç sonunda pottan kesilen yüzde
///   • Bot pot payı (%)  — kaybeden bot koltuğunun pota koyduğu, KASANIN
///     bastığı tutar; tek EKSİ kalem budur (bkz. 20260908190001)
class OkeyAdminSettingsTab extends StatefulWidget {
  const OkeyAdminSettingsTab({super.key});

  @override
  State<OkeyAdminSettingsTab> createState() => _OkeyAdminSettingsTabState();
}

class _OkeyAdminSettingsTabState extends State<OkeyAdminSettingsTab> {
  final _service = OkeyAdminService();

  final _maxScore = TextEditingController();
  final _turnSeconds = TextEditingController();
  final _roomFee = TextEditingController();
  final _commission = TextEditingController();
  // Bot koltuğunun pota koyduğu pay — kasa fonlar (bkz. 20260908190001).
  final _botStake = TextEditingController();
  final _hourlyGift = TextEditingController();
  final _adReward = TextEditingController();
  final _startingPoints = TextEditingController();
  // RULES.md §7/§8 ceza ayarları
  final _okeyDiscardPenalty = TextEditingController();
  final _okeyInHandPenalty = TextEditingController();
  final _mistakeDiscardPenalty = TextEditingController();
  final _sideDrawPenalty = TextEditingController();

  OkeyRevenueSummary _revenue = OkeyRevenueSummary.empty;
  bool _loading = true;
  bool _saving = false;

  /// Yüklü masa arka planı (yoksa null → oyun vektörel odayı kullanır).
  String? _backdropUrl;
  bool _backdropBusy = false;

  /// Ayarlar okunamadıysa sebebi.
  ///
  /// Eskiden hata TAMAMEN yutuluyordu: alanlar boş kalıyor, admin de
  /// "ayarlar sıfırlanmış" sanıp boş alanların üzerine kaydetmeye
  /// çalışıyordu. Sorunun ağ mı, yetki mi olduğunu görmesi gerekir.
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _maxScore,
      _turnSeconds,
      _roomFee,
      _commission,
      _botStake,
      _hourlyGift,
      _adReward,
      _startingPoints,
      _okeyDiscardPenalty,
      _okeyInHandPenalty,
      _mistakeDiscardPenalty,
      _sideDrawPenalty,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _service.getSettings();
      final r = await _service.revenueSummary();
      // Bot payı ayrı bir RPC'de yaşıyor (bkz. okey_admin_get_bot_stake_percent);
      // yine de ANA `try` içinde okunur: ekonomi ayarıdır, hatası yutulup alan
      // boş bırakılsaydı admin boş alanın üzerine kaydeder ve botlar farkında
      // olmadan pottan çıkardı.
      final botStake = await _service.botStakePercent();
      if (!mounted) return;
      _maxScore.text = '${s.maxScore}';
      _turnSeconds.text = '${s.turnSeconds}';
      _roomFee.text = '${s.roomCreationFee}';
      _commission.text = '${s.commissionPercent}';
      _botStake.text = '$botStake';
      _hourlyGift.text = '${s.hourlyGiftPoints}';
      _adReward.text = '${s.adRewardPoints}';
      _startingPoints.text = '${s.startingPoints}';
      _okeyDiscardPenalty.text = '${s.okeyDiscardPenalty}';
      _okeyInHandPenalty.text = '${s.okeyInHandPenalty}';
      _mistakeDiscardPenalty.text = '${s.mistakeDiscardPenalty}';
      _sideDrawPenalty.text = '${s.sideDrawPenalty}';
      setState(() {
        _revenue = r;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = OkeyAdminService.describeError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    // Arka plan AYRI okunur ve hatası yutulur: görsel dekoratiftir, ayar
    // ekranının geri kalanını bloke etmemeli.
    try {
      final url = await _service.getTableBackdropUrl();
      if (mounted) setState(() => _backdropUrl = url);
    } catch (_) {
      // yoksayılır
    }
  }

  Future<void> _pickBackdrop() async {
    // TÜM dosyalar gösterilir, doğrulamayı BİZ yaparız — ses yüklemede
    // olduğu gibi: uzantı filtresi cihaza göre dosyaları soluk bırakabiliyor.
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya okunamadı')));
      return;
    }
    // Doğrulama ADA DEĞİL İÇERİĞE de bakar: galeriden seçilen dosya sık sık
    // uzantısız bir adla geliyor ve geçerli bir JPEG reddediliyordu.
    final ext = OkeyAdminService.resolveImageExtension(file.name, bytes);
    if (ext == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bu dosya bir görsel değil: ${file.name}\n'
            'Desteklenen formatlar: ${OkeyAdminService.supportedImageLabel}',
          ),
        ),
      );
      return;
    }
    if (bytes.length > OkeyAdminService.backdropMaxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Görsel 5 MB\'dan küçük olmalı')),
      );
      return;
    }

    setState(() => _backdropBusy = true);
    try {
      final url = await _service.uploadTableBackdrop(
        // Uzantı ADA EKLENİR: depodaki yol ve MIME türü buradan türetiliyor.
        fileName: OkeyAdminService.extensionOf(file.name) == ext
            ? file.name
            : 'backdrop.$ext',
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _backdropUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masa arka planı güncellendi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _backdropBusy = false);
    }
  }

  Future<void> _clearBackdrop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arka plan kaldırılsın mı?'),
        content: const Text(
          'Görsel depodan da silinecek ve bu işlem geri alınamaz. '
          'Oyun ekranı varsayılan oda görünümüne döner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _backdropBusy = true);
    try {
      await _service.clearTableBackdrop();
      if (!mounted) return;
      setState(() => _backdropUrl = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _backdropBusy = false);
    }
  }

  int? _v(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _save() async {
    final score = _v(_maxScore);
    final secs = _v(_turnSeconds);
    final comm = _v(_commission);

    if (score == null || score <= 0 || secs == null || secs <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Puan ve süre sıfırdan büyük olmalı')),
      );
      return;
    }
    if (comm != null && (comm < 0 || comm > 50)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Komisyon %0 ile %50 arasında olmalı')),
      );
      return;
    }
    final botStake = _v(_botStake);
    if (botStake != null && (botStake < 0 || botStake > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bot payı %0 ile %100 arasında olmalı')),
      );
      return;
    }
    final penalties = [
      _v(_okeyDiscardPenalty),
      _v(_okeyInHandPenalty),
      _v(_mistakeDiscardPenalty),
      _v(_sideDrawPenalty),
    ];
    if (penalties.any((p) => p != null && p < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ceza puanı negatif olamaz (0 = kapalı)')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.updateSettings(
        maxScore: score,
        turnSeconds: secs,
        roomCreationFee: _v(_roomFee),
        commissionPercent: comm,
        hourlyGiftPoints: _v(_hourlyGift),
        adRewardPoints: _v(_adReward),
        startingPoints: _v(_startingPoints),
        okeyDiscardPenalty: penalties[0],
        okeyInHandPenalty: penalties[1],
        mistakeDiscardPenalty: penalties[2],
        sideDrawPenalty: penalties[3],
      );
      if (botStake != null) {
        await _service.setBotStakePercent(botStake);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ayarlar kaydedildi')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Girilen oranlara göre iki örnek masanın canlı hesabı.
  ///
  /// İKİ masa gösterilir çünkü ekonominin iki ayrı yüzü var: dört insanın
  /// oturduğu masada kasa KAZANIR (komisyon), botlu masada kasa ÖDER (bot
  /// payını o basar). Yalnız birincisi gösterildiği sürece "bot payı"
  /// alanının bütçeye ne yaptığı hiçbir yerde görünmüyordu.
  ///
  /// Kazanandan masa ücreti alınmadığı için (bkz. 20260905000004) brüt pot
  /// yalnız KAYBEDENLERİN koyduğudur: dört insanlı masada 3 pay.
  String get _example {
    const fee = 100;
    final comm = _v(_commission) ?? 0;
    final room = _v(_roomFee) ?? 0;
    final bot = _v(_botStake) ?? 0;

    const humanPot = fee * 3; // 3 kaybeden insan
    final humanCommission = (humanPot * comm) ~/ 100;
    final humanNet = humanPot - humanCommission;

    final botPot = (fee * bot) ~/ 100 * 3; // 3 kaybeden bot
    final botCommission = (botPot * comm) ~/ 100;
    final botNet = botPot - botCommission;

    return '100 çip masa puanıyla (kazanandan masa ücreti alınmaz):\n'
        '\n'
        '4 GERÇEK OYUNCU\n'
        '• Kaybedenlerin potu: $humanPot\n'
        '• Komisyon (%$comm): $humanCommission\n'
        '• Kazanan alır: $humanNet   (kasa: +$humanCommission)\n'
        '\n'
        '1 OYUNCU + 3 BOT\n'
        '• Botların koyduğu (%$bot): $botPot — bunu KASA basar\n'
        '• Komisyon (%$comm): $botCommission\n'
        '• Kazanan alır: $botNet   (kasa: ${botCommission - botPot})\n'
        '\n'
        '• Oda kurma ücreti: $room';
  }

  Widget _field(TextEditingController c, String label, String helper) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }

  /// Bir ayar bölümünü ikon + başlıklı bir kart içinde gruplar.
  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Ayarlar okunamadıysa BUNU SÖYLE. Alanların boş görünmesi
        // "ayarlar sıfırlanmış" gibi okunuyor; admin boş değerleri
        // kaydedip gerçekten sıfırlayabilirdi.
        if (_loadError != null)
          Card(
            color: Colors.red.shade50,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ayarlar alınamadı: $_loadError\n'
                      'Alanlar eksik olabilir — kaydetmeden önce tekrar '
                      'deneyin.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            ),
          ),
        const Text(
          'Sistem Kazancı',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        // YATAY ŞERİT: altı kart `Wrap` ile dar ekranda üç satıra iniyor ve
        // sekmenin üstünü yiyordu. Kaydırma yüksekliği sabit tutar.
        OkeyStatStrip(
          cards: [
            OkeyStatCard(
              icon: Icons.account_balance_wallet,
              label: 'Toplam Kazanç',
              value: '${_revenue.total}',
              gradient: [Colors.green.shade400, Colors.green.shade700],
            ),
            OkeyStatCard(
              icon: Icons.today,
              label: 'Bugün',
              value: '${_revenue.today}',
              gradient: [Colors.teal.shade400, Colors.teal.shade700],
            ),
            OkeyStatCard(
              icon: Icons.meeting_room,
              label: 'Oda Ücretleri',
              value: '${_revenue.roomFees}',
              gradient: [Colors.blue.shade400, Colors.blue.shade700],
            ),
            OkeyStatCard(
              icon: Icons.percent,
              label: 'Komisyonlar',
              value: '${_revenue.commissions}',
              gradient: [Colors.orange.shade400, Colors.orange.shade700],
            ),
            // Kasanın bot masalarında BASTIĞI çip. "Toplam Kazanç" bunu
            // zaten düşmüştür; ayrı kart olmasaydı toplamın neden düştüğü
            // hiçbir yerde görünmezdi.
            OkeyStatCard(
              icon: Icons.smart_toy,
              label: 'Bot Payı (ödenen)',
              value: '-${_revenue.botStakes}',
              gradient: [Colors.red.shade400, Colors.red.shade700],
            ),
            OkeyStatCard(
              icon: Icons.stars,
              label: 'Dolaşımdaki Çip',
              value: '${_revenue.pointsInCirculation}',
              gradient: [Colors.purple.shade400, Colors.purple.shade700],
            ),
          ],
        ),
        const SizedBox(height: 20),

        _section(
          icon: Icons.payments,
          color: Colors.green.shade700,
          title: 'Sistem Kazancı Ayarları',
          children: [
            _field(
              _roomFee,
              'Oda kurma ücreti (çip)',
              'Masayı açan oyuncudan bir kez alınır',
            ),
            _field(
              _commission,
              'Pot komisyonu (%)',
              'Maç sonunda pottan kesilir. 0 ile 50 arasında olmalı',
            ),
            _field(
              _botStake,
              'Bot koltuğunun pot payı (%)',
              'Kaybeden her BOT, masa puanının bu kadarını pota koyar; '
                  'parayı kasa basar. 0 yazılırsa botlarla oynanan masada '
                  'pot boş kalır ve kazanan yalnızca kendi masa puanını '
                  'geri alır',
            ),
            Card(
              color: Colors.blue.shade50,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_example, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),

        _section(
          icon: Icons.videogame_asset,
          color: Colors.indigo.shade700,
          title: 'Oyun Ayarları',
          children: [
            _field(
              _maxScore,
              'Maç bitiş puanı',
              'Bir oyuncu bu puana ulaşınca maç biter',
            ),
            _field(
              _turnSeconds,
              'Sıra süresi (saniye)',
              'Süre dolunca sıra otomatik ilerler',
            ),
          ],
        ),

        _section(
          icon: Icons.image,
          color: Colors.purple.shade700,
          title: 'Masa Arka Planı',
          children: [
            const Text(
              'Oyun masasının arkasında görünen oda fotoğrafı. Yüklenmezse '
              'varsayılan (vektörel) oda görünümü kullanılır.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _backdropUrl == null
                    ? Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_not_supported,
                              color: Colors.black26,
                              size: 32,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Görsel yok — varsayılan oda',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Image.network(
                        _backdropUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Text('Görsel yüklenemedi'),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _backdropBusy ? null : _pickBackdrop,
                    icon: _backdropBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload),
                    label: Text(
                      _backdropUrl == null ? 'Görsel Yükle' : 'Değiştir',
                    ),
                  ),
                ),
                if (_backdropUrl != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _backdropBusy ? null : _clearBackdrop,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Kaldır'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'En fazla 5 MB · ${OkeyAdminService.supportedImageLabel} · '
              'yatay (16:9) görseller en iyi sonucu verir',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),

        _section(
          icon: Icons.gavel,
          color: Colors.red.shade700,
          title: 'Ceza Ayarları',
          children: [
            _field(
              _okeyDiscardPenalty,
              'Okey atma cezası',
              'Okey taşını ıskartaya atan oyuncuya eklenir (0 = kapalı)',
            ),
            _field(
              _okeyInHandPenalty,
              'Okey elde kalma cezası',
              'El bittiğinde okey hâlâ elindeyse eklenir (0 = kapalı)',
            ),
            _field(
              _mistakeDiscardPenalty,
              'İşlek taş atma cezası',
              'Masadaki bir pere işlenebilecek taşı atmak — eli açık '
                  'olmayan oyuncuya da yazılır (0 = kapalı)',
            ),
            _field(
              _sideDrawPenalty,
              'Yandan çekip kullanmama cezası',
              'Soldan alınan taşı o turda kullanmamak (0 = kapalı)',
            ),
            Card(
              color: Colors.amber.shade50,
              elevation: 0,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Cezalar el sonunda oyuncunun skoruna eklenir. Süre dolumu '
                  'veya bağlantısı kopan oyuncu adına yapılan OTOMATİK '
                  'atmalarda okey ve işlek taş cezası yazılmaz. Okey atıldığında '
                  'yalnızca okey cezası işler; ikisi üst üste binmez.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),

        _section(
          icon: Icons.card_giftcard,
          color: Colors.deepOrange.shade700,
          title: 'Çip Kazanma Ayarları',
          children: [
            _field(
              _startingPoints,
              'Başlangıç çipi',
              'Yeni oyuncuya bir kez verilir',
            ),
            _field(
              _hourlyGift,
              'Saatlik hediye',
              'Saatte bir "Hediye Al" ile verilen çip',
            ),
            _field(_adReward, 'Reklam ödülü', 'Bir reklam izlemenin karşılığı'),
          ],
        ),

        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Kaydet'),
        ),
      ],
    );
  }
}
