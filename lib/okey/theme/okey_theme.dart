import 'package:flutter/material.dart';

import '../engine/okey_tile.dart';
import 'okey_table_theme.dart';

/// 101 Okey modülünün TEK renk kaynağı.
///
/// Önceden her widget kendi rengini elle yazıyordu (aynı fildişi taş
/// gradyanı, aynı lacivert zemin, aynı taş renkleri 4-6 dosyada birebir
/// tekrarlanmıştı) — bir tonu değiştirmek her seferinde tüm dosyaları
/// taramayı gerektiriyordu. Artık her yer buradan okur.
///
/// ## Neden `static const` değil `static Color get` (2026-09-14)
///
/// Kullanıcı isteği: "oyuncu tema seçebilsin ayardan" (bkz.
/// okey_table_theme.dart). MALZEME renkleri (zemin, çuha, ray, taş fildişi,
/// HUD, altın vurgu) artık DERLEME ZAMANI sabiti değil, [OkeyTableThemePrefs]
/// içindeki AKTİF [OkeyTableTheme]den okunan CANLI bir değer — kullanıcı
/// Ayarlar'dan tema değiştirince aynı `OkeyColors.tableBackground` ifadesi
/// bir sonraki build'de başka bir renk döndürür. Bu sayede masayı çizen
/// ~30 dosyanın HİÇBİRİ değişmedi: hepsi hâlâ `OkeyColors.xxx` yazıyor.
///
/// OYUNUN SİNYAL renkleri (işlek taş yeşili, riskli taş kırmızısı, taş
/// mürekkep renkleri, sıra/çekme/atma rengi) BİLEREK `static const` kaldı:
/// bunlar temadan BAĞIMSIZ, evrensel bir anlam taşır — "yeşil = işlenebilir"
/// öğrenimi masa hangi renkte olursa olsun aynı kalmalı.
abstract final class OkeyColors {
  static OkeyTableTheme get _t => OkeyTableThemePrefs.instance.current.value;

  // --- Zeminler (TEMA) --------------------------------------------------
  /// Oyun masası ekranının Scaffold arka planı.
  static Color get tableBackground => _t.tableBackground;

  /// Lobi/oda/puan/sonuç gibi diğer okey ekranlarının Scaffold arka planı.
  static Color get screenBackground => _t.screenBackground;

  /// AppBar / footer / diyalog gibi daha koyu vurgu yüzeyleri.
  static Color get surfaceDark => _t.surfaceDark;

  /// Tahta (per/grup alanı) keçe rengi.
  static Color get felt => _t.screenBackground;

  // --- Taş gövdesi (TEMA) --------------------------------------------------
  static Color get tileIvoryLight => _t.tileIvoryLight;
  static Color get tileIvoryDark => _t.tileIvoryDark;
  static LinearGradient get tileGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tileIvoryLight, tileIvoryDark],
  );

  // --- Taş renkleri (suit) — EVRENSEL, temadan bağımsız -----------------
  static const tileRed = Color(0xFFE53935);
  static const tileYellow = Color(0xFFF9A825);
  static const tileBlack = Color(0xFF212121);
  static const tileBlue = Color(0xFF1E88E5);
  static const falseJoker = Colors.deepPurple;

  static Color tileColorFor(OkeyColor c) {
    switch (c) {
      case OkeyColor.red:
        return tileRed;
      case OkeyColor.yellow:
        return tileYellow;
      case OkeyColor.black:
        return tileBlack;
      case OkeyColor.blue:
        return tileBlue;
    }
  }

  // --- Vurgu / durum renkleri ---------------------------------------------
  /// Otomatik sayılan tamamlanmış per/grup/çift kenarlığı (altın, TEMA).
  static Color get completeMeldGold => _t.completeMeldGold;

  /// Yardımlı modda "işlenebilir" ipucu (yeşil) — EVRENSEL.
  /// İŞLEK TAŞ VURGUSU — masadaki açık bir pere işlenebilen elimdeki taş.
  ///
  /// 0xFF2E7D32 (koyu yeşil) idi ve fildişi taşın üstünde ince bir çizgi
  /// olarak neredeyse görünmüyordu (kullanıcı isteği, 2026-09-06: "işlek
  /// taşlar daha belirgin olsun"). Parlak yeşile çekildi: taşın kendi rengi
  /// (kırmızı/sarı/siyah/mavi) ile karışmayan, masadaki tek "elektrik"
  /// tonu — yani vurgu bir renk değil, bir SİNYAL. Bu yüzden hiçbir temada
  /// değişmez: oyuncunun öğrendiği anlam masa rengiyle birlikte kaymamalı.
  static const hintProcessable = Color(0xFF76FF03);

  /// Vurgunun taşın çevresine yaydığı ışık.
  static const hintProcessableGlow = Color(0xCC64DD17);

  /// Yardımlı modda "per/grup/çift olabilir" ipucu (mavi alt çizgi).
  static const hintMeldable = tileBlue;

  /// RİSKLİ ("işlek") TAŞ — atılırsa +101 ceza yazılır (RULES.md §7).
  ///
  /// Fırsat ipuçlarından (yeşil/mavi) ayrı bir renk: bu işaret "şunu yap"
  /// demiyor, "şunu ATMA" diyor. Cezanın kendisi 2026-09-07'de eli kapalı
  /// oyuncuya da işlemeye başladı; uyarı olmasaydı oyuncu bedelini ancak
  /// ödedikten sonra öğrenirdi.
  static const hintRisky = Color(0xFFFF5252);

  /// Tema vurgusu — altın ailesi (TEMA).
  static Color get accentGold => _t.accentGold;

  // --- Ahşap ıstaka (kullanılmıyor — bkz. OkeyRackStyle) ------------------
  static const woodLight = Color(0xFFD9A441);
  static const woodDark = Color(0xFFB5822B);
  static const woodBorder = Color(0xFF8A5F1A);
  static const woodGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [woodLight, woodDark],
  );

  // --- Oda arka planı (kullanılmıyor — bkz. OkeyDamaskBackground) ---------
  static const roomWallDark = Color(0xFF2A1B12);
  static const roomWallWarm = Color(0xFF4E3420);
  static const roomGlow = Color(0xFFFFD59A);

  // --- Masa rayı + keçe (trapez CustomPainter, kullanılmıyor) --------------
  static const tableRailLight = Color(0xFFC98A3B);
  static const tableRailDark = Color(0xFF7A4A17);
  static Color get tableFeltDeep => _t.feltDeep;
  static const tableFeltEdge = Color(0xFF166571);

  // --- Köşe avatarı + isim hapı ---------------------------------------------
  static Color get avatarRing => _t.avatarRing;
  static const nameTagBg = Color(0xFF1A1410);

  // --- Modern "tablo" (panel/kart) görünümü ---------------------------------
  static const panelGlassFill = Color(0x3D000000); // ~%24 siyah
  static const panelGlassFillTop = Color(0x52000000); // panel üstü biraz koyu
  static const panelBorder = Color(0x26FFFFFF); // ~%15 beyaz
  static const panelHeaderBg = Color(0x40FFD54F); // altın başlık şeridi zemini

  // --- Aksiyon butonları ---------------------------------------------------
  static const buttonDisabled = [Color(0xFF6E7B85), Color(0xFF55606A)];
  static const buttonHighlighted = [Color(0xFFFFD54F), Color(0xFFF9A825)];
  static const buttonNormal = [Color(0xFFFFFDF7), Color(0xFFEFE3C8)];
  static const dizActive = [Color(0xFF4FC3F7), Color(0xFF0288D1)];
  static const dizInactive = [Color(0xFFF5F5F5), Color(0xFFD5D5D5)];
  static const dizGoldActive = [Color(0xFFFFD54F), Color(0xFFC9861A)];

  /// OkeyModeBadge rozetlerini sıcak zemine karşı harmanlamak için taban tonu.
  static Color get surfaceWarm => _t.surfaceWarm;

  // --- Durum renkleri (seat/turn) — EVRENSEL ------------------------------
  static const turnActive = Colors.amber;
  static const drawSource = Colors.lightGreenAccent;
  static const discardTarget = Colors.lightBlueAccent;
  static const idle = Colors.white24;

  // ==========================================================================
  // MERKEZİ MASA TASARIMI (2026-09) — "gerçekçi masa + modern HUD"
  // ==========================================================================
  /// Masa rayının (ahşap/metal çerçeve) dikey gradyanı (TEMA) — üstte cilalı
  /// parlaklık, altta derin gölge.
  static LinearGradient get railGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: _t.railGradient,
    stops: _t.railGradientStops,
  );

  /// Ahşap/metal damarının iki rengi (açık lif / koyu lif) ve şiddeti —
  /// Gece Modu'nda neredeyse sıfıra iner (bkz. OkeyTableFeltPainter).
  static Color get railGrainLight => _t.railGrainLight;
  static Color get railGrainDark => _t.railGrainDark;
  static double get railGrainOpacity => _t.railGrainOpacity;

  /// Keçenin merkezden dışa açılan tonu (TEMA) — masanın üst-ortasına düşen
  /// ışık.
  static Color get feltHighlight => _t.feltHighlight;
  static Color get feltCenter => _t.feltCenter;
  static Color get feltMid => _t.feltMid;
  static Color get feltRim => _t.feltRim;

  // --- GERÇEKTE ÇİZİLEN ZEMİN (TEMA) -----------------------------------------
  // v4 düzeninde masa artık ahşap ray/keçe değil, tek parça işlemeli bir
  // "damask" zemin + perlerin oturduğu oyuk tabla (bkz. OkeyDamaskBackground,
  // OkeyMeldBay). Oyuncunun asıl gördüğü yüzey budur.
  static Color get damaskDeep => _t.damaskDeep;
  static Color get damaskMid => _t.damaskMid;
  static Color get damaskLight => _t.damaskLight;
  static Color get damaskGrainShadow => _t.damaskGrainShadow;
  static Color get damaskGrainLight => _t.damaskGrainLight;
  static Color get damaskVignette => _t.damaskVignette;
  static Color get meldBayTop => _t.meldBayTop;
  static Color get meldBayBottom => _t.meldBayBottom;
  static OkeyBackdropPattern get backdropPattern => _t.backdropPattern;

  // --- Rakip ıstakası (3B kutu, bkz. paintOkeyRackBox — kullanılmıyor) ------
  static Color get rackBoxBack => _t.rackBoxBack;
  static Color get rackBoxCap => _t.rackBoxCap;
  static List<Color> get rackBoxTop => _t.rackBoxTop;
  static List<Color> get rackBoxFront => _t.rackBoxFront;
  static Color get rackBoxGroove => _t.rackBoxGroove;
  static Color get rackBoxEdgeBright => _t.rackBoxEdgeBright;
  static Color get rackBoxEdgeDim => _t.rackBoxEdgeDim;

  // --- Modern HUD (masanın üstüne binen düz katman) — TEMA -------------------
  /// Oyuncu kartı / kontrol düğmesi zemini.
  static Color get hudFill => _t.hudFill;

  /// Mod rozeti zemini.
  static Color get hudBadgeFill => _t.hudBadgeFill;

  /// HUD kenarlığı.
  static Color get hudBorder => _t.hudBorder;

  /// Sıra BENDEYKEN oyuncu kartının sıcak zemini + altın kenarı (kullanılmıyor).
  static const podTurnFill = Color(0xB3261C08);
  static const podTurnBorder = Color(0x73FFC107);

  // --- Modern aksiyon butonları (TEMA) --------------------------------------
  static Color get actionFill => _t.actionFill;
  static Color get actionBorder => _t.actionBorder;
  static Color get actionDisabledFill => _t.actionDisabledFill;
  static Color get actionDisabledBorder => _t.actionDisabledBorder;
  static Color get actionDisabledText => _t.actionDisabledText;

  /// "Yapılabilir" aksiyon (SERİ AÇ hazır) — altın gradyan, koyu metin.
  static List<Color> get actionReady => _t.actionReady;

  /// Bitirme hamlesi — daha parlak altın + dışa vuran parıltı.
  static List<Color> get actionWinning => _t.actionWinning;

  /// Altın butonların üzerindeki metin/ikon rengi.
  static Color get onGold => _t.onGold;

  /// HUD metinleri.
  static Color get hudText => _t.hudText;
  static Color get hudTextDim => _t.hudTextDim;
  static Color get hudTextFaint => _t.hudTextFaint;

  /// Keçeye "kazınmış" başlık (SERİLER & GRUPLAR / ÇİFTLER).
  static const engraved = Color(0x6B000000);
  static const engravedHighlight = Color(0x12FFFFFF);
}

/// Ortak metin stilleri — tahta ve panellerde tekrar eden font ayarları.
abstract final class OkeyTextStyles {
  static const panelTitle = TextStyle(
    color: Colors.white38,
    fontSize: 10,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
  );

  static const badge = TextStyle(
    color: Colors.white70,
    fontSize: 9,
    fontWeight: FontWeight.bold,
  );
}

/// MASA TASARIMI v3 (2026-09) — "sakin keçe, net kontroller".
///
/// ## Neden yeni bir katman
///
/// Önceki tasarımda masanın üstündeki her öğe kendi malzemesini seçiyordu:
/// aksiyon butonları neredeyse görünmez koyu kutulardı, DİZ düğmeleri parlak
/// turuncu ahşap bloklardı, oyuncu kartları siyah şeritlerdi, ıstaka ise
/// bambaşka bir sarıydı. Aynı ekranda dört ayrı görsel dil vardı.
///
/// v3'te kural tek cümle: **masa gerçekçi, kontroller düz.** Keçe ve ahşap
/// ray dokulu kalır; ÜZERİNE BİNEN her kontrol aynı koyu cam yüzeyden,
/// aynı köşe yarıçapından ve aynı kenar çizgisinden yapılır. Renk yalnızca
/// ANLAM taşır:
///
///   * altın  → şu an yapılabilen, değerli hamle (AÇ / BİTİR)
///   * turkuaz→ ıstaka aracı (SERİ DİZ / ÇİFT DİZ)
///   * yeşil  → taş çekilecek yer
///   * mavi   → taş atılacak yer
///
/// Renk anlam taşımadığı her yerde yüzey nötr kalır. Böylece oyuncu ekrana
/// baktığında "ne yapabilirim"i renkten okur, kutuları tek tek gezmez.
///
/// Yüzey/metin tonları artık AKTİF TEMAYA göre değişir (bkz. OkeyColors
/// başındaki not); ANLAM taşıyan `tool`/`draw`/`discard`/`turn` ise
/// EVRENSEL kalır.
abstract final class OkeyV3 {
  static OkeyTableTheme get _t => OkeyTableThemePrefs.instance.current.value;

  // --- Yüzeyler (TEMA) ------------------------------------------------------
  /// Masanın üstüne binen her kontrolün taban dolgusu.
  static Color get surface => _t.v3Surface;

  /// Biraz daha açık yüzey — kontrolün İÇİNDEKİ ikinci kademe (rozet, sayaç).
  static Color get surfaceRaised => _t.v3SurfaceRaised;

  /// Kontrol kenarı. Tek bir değer: her kutu aynı kalınlıkta çizilir.
  static Color get border => _t.v3Border;

  /// Vurgulanmamış ama etkin bir kontrolün kenarı biraz daha belirgin.
  static Color get borderStrong => _t.v3BorderStrong;

  /// Kapalı kontrol — GÖRÜNÜR kalır, sadece söner. "Yapılamaz" ile "yok"
  /// farklı şeylerdir; kaybolan bir buton oyuncuya hiçbir şey öğretmez.
  static Color get surfaceDisabled => _t.v3SurfaceDisabled;
  static Color get borderDisabled => _t.v3BorderDisabled;

  // --- Metin (TEMA) ----------------------------------------------------------
  static Color get text => _t.v3Text;
  static Color get textDim => _t.v3TextDim;
  static Color get textFaint => _t.v3TextFaint;
  static Color get textDisabled => _t.v3TextDisabled;

  // --- Anlam renkleri ------------------------------------------------------
  /// ALTIN (TEMA) — yapılabilir, yüksek değerli hamle.
  static List<Color> get gold => _t.v3Gold;
  static Color get onGold => _t.v3OnGold;
  static Color get goldGlow => _t.v3GoldGlow;

  /// Bitiren hamle — altının daha parlak ve daha çok parlayan hali (TEMA).
  static List<Color> get goldBright => _t.v3GoldBright;

  /// TURKUAZ — ıstaka aracı (dizme). Hamle değil, düzenleme. EVRENSEL: bu
  /// araç rengi masanın malzemesinden bağımsız, her temada aynı okunmalı.
  static const List<Color> tool = [Color(0xFF44D3D8), Color(0xFF12808E)];
  static const Color onTool = Color(0xFF04252B);

  /// Taş ÇEKİLECEK yer (soldaki oyuncunun ıskartası, deste) — EVRENSEL.
  static const Color draw = Color(0xFF8CE071);

  /// Taş ATILACAK yer (kendi ıskartam) — EVRENSEL.
  static const Color discard = Color(0xFF5CB8FF);

  /// Sıra o oyuncuda — EVRENSEL.
  static const Color turn = Color(0xFFFFC845);

  // --- Ölçüler — geometri, temadan bağımsız ---------------------------------
  /// TEK köşe yarıçapı ailesi — kontroller birbirine benzesin diye.
  static const double radius = 11;
  static const double radiusSm = 7;
  static const double radiusPill = 999;

  /// Masadaki kontrollerin ortak gölgesi: yüzeyden ayrılsınlar diye dar ve
  /// koyu. Bulanık geniş gölge, koyu keçede kirli bir leke bırakıyordu.
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
}
