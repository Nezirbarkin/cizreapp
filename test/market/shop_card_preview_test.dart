// GEÇİCİ EKRAN ÖNİZLEMESİ — dükkan kartının PNG'sini üretir.
//
//   flutter test test/market/shop_card_preview_test.dart --update-goldens
//
// Karşılaştırma yapmaz, yalnızca üretir. Veriler canlı veritabanındaki 7 gerçek
// dükkandır (2026-09-22); logolar gerçek oranlarını taklit eden sentetik
// görsellerdir (ağdan indirme yok).
@Tags(['preview'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/core/models/shop_model.dart';
import 'package:cizreapp/features/market/widgets/shop_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

const _pink = Color(0xFFD91A73);
final _key = GlobalKey();
final _now = DateTime.now();

// ── sentetik logolar ────────────────────────────────────────────────────────

Future<ImageProvider> _img(
  int w,
  int h,
  void Function(Canvas c, Size s) paint,
) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  paint(canvas, Size(w.toDouble(), h.toDouble()));
  final image = await rec.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(data!.buffer.asUint8List());
}

void _text(
  Canvas c,
  String s,
  Offset at, {
  double size = 40,
  Color color = Colors.black,
  FontWeight weight = FontWeight.w800,
  double? maxWidth,
  TextAlign align = TextAlign.left,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFamily: 'Roboto',
      ),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  tp.paint(c, at);
}

Future<Map<String, ImageProvider>> _logos() async => {
  // Aktar Sepetim — yatay 1.5, beyaz zemin, yazı görsele gömülü
  'aktar': await _img(512, 342, (c, s) {
    c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(40, 150, 190, 110),
        const Radius.circular(20),
      ),
      Paint()..color = const Color(0xFF2E6B34),
    );
    c.drawCircle(
      const Offset(135, 120),
      42,
      Paint()..color = const Color(0xFFE8B931),
    );
    _text(
      c,
      'Aktar\nSepetim',
      const Offset(250, 110),
      size: 58,
      color: const Color(0xFF1F4F27),
    );
  }),
  // SALIPAZARI — dikey 0.75, vitrin fotoğrafı
  'sali': await _img(384, 512, (c, s) {
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8FC3E8), Color(0xFFE3C9A0)],
        ).createShader(Offset.zero & s),
    );
    c.drawRect(
      const Rect.fromLTWH(0, 150, 384, 260),
      Paint()..color = const Color(0xFFD9BC8C),
    );
    c.drawRect(
      const Rect.fromLTWH(30, 200, 324, 40),
      Paint()..color = const Color(0xFF2F5FA8),
    );
    _text(
      c,
      'SALI PAZARI',
      const Offset(60, 205),
      size: 30,
      color: Colors.white,
    );
    c.drawRect(
      const Rect.fromLTWH(50, 260, 120, 120),
      Paint()..color = const Color(0xFF3B3B3B),
    );
    c.drawRect(
      const Rect.fromLTWH(200, 280, 130, 90),
      Paint()..color = const Color(0xFF8A5A3C),
    );
    c.drawRect(
      const Rect.fromLTWH(0, 410, 384, 102),
      Paint()..color = const Color(0xFFA8A6A2),
    );
  }),
  // Memilheva — yeşil zeminli altın amblem, yatay
  'memil': await _img(512, 342, (c, s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF3A5A33));
    final ring = Paint()
      ..color = const Color(0xFFD9B44A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    c.drawCircle(Offset(s.width / 2, s.height / 2), 130, ring);
    c.drawCircle(
      Offset(s.width / 2, s.height / 2),
      95,
      Paint()..color = const Color(0xFF6B4A2A),
    );
    _text(
      c,
      'CİZRE\nMEMİLHEVA',
      Offset(s.width / 2 - 80, s.height / 2 - 34),
      size: 32,
      color: const Color(0xFFF3E3B0),
    );
  }),
  // Sanal Marketim — kare 1.0, beyaz zemin
  'sanal': await _img(512, 512, (c, s) {
    c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
    c.drawCircle(
      Offset(s.width / 2, s.height / 2),
      230,
      Paint()
        ..color = const Color(0xFFF08A24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );
    _text(
      c,
      'Sanal',
      const Offset(150, 190),
      size: 96,
      color: const Color(0xFF1F5B30),
    );
    _text(
      c,
      'Marketim',
      const Offset(120, 300),
      size: 76,
      color: const Color(0xFFF08A24),
    );
  }),
  // GOLD MEDYA — koyu zeminli yatay 1.83
  'gold': await _img(512, 280, (c, s) {
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF15181C), Color(0xFF2B3138)],
        ).createShader(Offset.zero & s),
    );
    _text(
      c,
      'GM',
      const Offset(196, 40),
      size: 96,
      color: const Color(0xFFD9B36A),
    );
    _text(
      c,
      'GOLD MEDYA',
      const Offset(120, 170),
      size: 42,
      color: const Color(0xFFD9B36A),
    );
  }),
  // CizreApp — kare mavi uygulama simgesi
  'cizre': await _img(512, 512, (c, s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1F55A6));
    _text(c, 'CA', const Offset(150, 150), size: 200, color: Colors.white);
  }),
};

// ── canlı dükkanlar ─────────────────────────────────────────────────────────

Shop _shop(
  String name, {
  String? description,
  bool logo = true,
  double rating = 0,
  int reviews = 0,
  double fee = 0,
  double? freeMin,
  double minOrder = 0,
  String? time,
  bool pinned = false,
  bool verified = true,
  bool pickup = false,
  bool accepting = true,
  bool manualOpen = true,
  Map<String, dynamic>? hours,
  int ageDays = 200,
}) => Shop(
  id: name,
  ownerId: 'o',
  categoryId: 'c',
  name: name,
  slug: name,
  description: description,
  logoUrl: logo ? 'https://example.invalid/logo.png' : null,
  rating: rating,
  reviewCount: reviews,
  deliveryFee: fee,
  freeDeliveryMinAmount: freeMin,
  minOrderAmount: minOrder,
  deliveryTime: time,
  isPinned: pinned,
  isVerified: verified,
  pickupEnabled: pickup,
  isAcceptingOrders: accepting,
  isOpen: manualOpen,
  workingHours: hours,
  createdAt: _now.subtract(Duration(days: ageDays)),
  updatedAt: _now,
);

// Bugün/yarın için hep aynı: yalnızca 03:00–03:01 açık ⇒ gün içinde KAPALI.
Map<String, dynamic> _rarelyOpen() => {
  for (final d in [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ])
    d: {'open': '03:00', 'close': '03:01', 'active': true},
};

Map<String, ImageProvider> _l = {};

Shop _asir() => _shop(
  'Asır Kuruyemiş & Aktar',
  description: 'En Taze Kuruyemiş ve Doğal Şifa Bitkileri',
  rating: 4.0,
  reviews: 1,
  fee: 29,
  freeMin: 750,
  minOrder: 200,
  time: '30-60 dakika',
  pinned: true,
);
Shop _sali() => _shop(
  'SALIPAZARI',
  description: 'TEKNOLOJİ ÜRÜNLERİ',
  time: '30-45 dakika',
  pickup: true,
  ageDays: 4,
);
Shop _zuc() => _shop(
  'CİZRE Züccaciye',
  description: 'Elektronik ve züccaciye',
  logo: false,
  fee: 50,
  freeMin: 1000,
  minOrder: 0.08,
  time: '30-45 dakika',
);
Shop _memil({bool accepting = true}) => _shop(
  'CİZRE MEMİLHEVA KURABİYE',
  description:
      'Seçkin tatlılar & Yöresel lezzetler\nPaket Servis • Randevulu Teslimat\nÜretimden Sofranıza Taze Taze\n📦Tüm Türkiye\'ye Express Gıda Kargo \n☎️05413675554',
  time: '30-45 dakika',
  accepting: accepting,
);
Shop _sanal() => _shop(
  'Sanal Marketim',
  description: "Cizre'nin En Ucuz Sanal Marketi",
  fee: 15,
  freeMin: 750,
  minOrder: 150,
  time: '30-45 dakika',
);
Shop _gold() => _shop(
  'GOLD MEDYA',
  description:
      'Tüm Sosyal Medya En Uygunu Burda\n~Takipçi İşlemlerinizde ; Profil linki Veya Kullanıcı adı giriniz.',
  rating: 5.0,
  reviews: 2,
  time: 'Otomatik',
);
Shop _cizre() => _shop(
  'CizreApp',
  description: 'Ürün Test Mağazası',
  rating: 5.0,
  reviews: 7,
  fee: 15,
  freeMin: 2,
  minOrder: 1,
  time: '30-45 dakika',
  pickup: true,
);

ImageProvider? _logoFor(String name) {
  switch (name) {
    case 'Asır Kuruyemiş & Aktar':
      return _l['aktar'];
    case 'SALIPAZARI':
      return _l['sali'];
    case 'CİZRE MEMİLHEVA KURABİYE':
      return _l['memil'];
    case 'Sanal Marketim':
      return _l['sanal'];
    case 'GOLD MEDYA':
      return _l['gold'];
    case 'CizreApp':
      return _l['cizre'];
  }
  return null;
}

Widget _card(
  Shop s, {
  bool global = true,
  bool coupon = false,
  String? distance,
}) => ShopCard(
  shop: s,
  globalOrdersEnabled: global,
  hasCoupon: coupon,
  distanceLabel: distance,
  logoImageProvider: _logoFor(s.name),
  onTap: () {},
);

Widget _page(List<Widget> cards, {double textScale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _pink, primary: _pink),
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        child: RepaintBoundary(
          key: _key,
          child: Container(
            color: const Color(0xFFF5F7FA),
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: cards),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  Future<void> shot(
    WidgetTester t,
    List<Widget> Function() cards,
    String file, {
    double width = 390,
    double textScale = 1,
  }) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = Size(width * 2, 2600 * 2);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.runAsync(() async => _l = await _logos());
    await t.pumpWidget(_page(cards(), textScale: textScale));
    // Görsel çözümleme gerçek zaman ister.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 500));

    final saved = debugDisableShadows;
    debugDisableShadows = false;
    try {
      final boundary =
          _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('test/market/$file').writeAsBytes(
          data!.buffer.asUint8List(),
        );
      });
    } finally {
      debugDisableShadows = saved;
    }
  }

  testWidgets('canlı 7 dükkan', (t) async {
    if (!autoUpdateGoldenFiles) return;
    await shot(
      t,
      () => [
        _card(_asir()),
        _card(_sali(), distance: '850 m'),
        _card(_zuc()),
        _card(_memil(accepting: false)),
        _card(_sanal(), coupon: true),
        _card(_gold()),
        _card(_cizre(), distance: '1,2 km'),
      ],
      'preview_shop_cards_live.png',
    );
  });

  testWidgets('durumlar', (t) async {
    if (!autoUpdateGoldenFiles) return;
    await shot(
      t,
      () => [
        // çalışma saati dışı + açılış saati bilgisi
        _card(
          _shop(
            'Saat Dışı Dükkan',
            description: 'Şu an kapalı, açılış bilgisi gösterilir',
            logo: false,
            rating: 4.6,
            reviews: 128,
            fee: 12.5,
            time: '20-30',
            hours: _rarelyOpen(),
          ),
        ),
        // elle kapatılmış: şerit yok
        _card(
          _shop(
            'Elle Kapatıldı',
            description: 'Satıcı dükkanı kapattı',
            logo: false,
            manualOpen: false,
            rating: 3.9,
            reviews: 12,
          ),
        ),
        // global sipariş kapalı
        _card(_sanal(), global: false, coupon: true),
        // sponsor + kupon + Gel Al + uzaklık
        _card(
          _shop(
            'Sponsor Örnek Dükkan',
            description: 'Sponsor, kupon, Gel Al ve uzaklık bir arada',
            logo: false,
            rating: 4.8,
            reviews: 342,
            fee: 25,
            freeMin: 500,
            minOrder: 100,
            time: '15-25 dakika',
            pinned: true,
            pickup: true,
          ),
          coupon: true,
          distance: '2,4 km',
        ),
      ],
      'preview_shop_cards_states.png',
    );
  });

  testWidgets('dar ekran + büyük yazı', (t) async {
    if (!autoUpdateGoldenFiles) return;
    await shot(
      t,
      () => [
        _card(
          _shop(
            'CİZRE MEMİLHEVA KURABİYE',
            description: 'Uzun ad, uzun slogan: seçkin tatlılar ve yöresel lezzetler',
            logo: false,
            rating: 4.9,
            reviews: 1280,
            fee: 25,
            freeMin: 1500,
            minOrder: 250,
            time: '30-45 dakika',
            pickup: true,
            pinned: true,
          ),
          coupon: true,
          distance: '12 km',
        ),
        _card(_memil(accepting: false)),
      ],
      'preview_shop_cards_narrow.png',
      width: 320,
      textScale: 1.3,
    );
  });

  testWidgets('iskelet', (t) async {
    if (!autoUpdateGoldenFiles) return;
    await shot(
      t,
      () => const [ShopCardSkeleton(), ShopCardSkeleton(), ShopCardSkeleton()],
      'preview_shop_skeleton.png',
    );
  });

  testWidgets('logo karoları (büyük)', (t) async {
    if (!autoUpdateGoldenFiles) return;
    await shot(
      t,
      () => [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final n in const [
              'Asır Kuruyemiş & Aktar',
              'SALIPAZARI',
              'CİZRE MEMİLHEVA KURABİYE',
              'Sanal Marketim',
              'GOLD MEDYA',
              'CizreApp',
            ])
              ShopLogoTile(name: n, size: 104, imageProvider: _logoFor(n)),
            const ShopLogoTile(name: 'İpek Züccaciye', size: 104),
            ShopLogoTile(
              name: 'GOLD MEDYA',
              size: 104,
              muted: true,
              imageProvider: _l['gold'],
            ),
          ],
        ),
      ],
      'preview_shop_logo_tiles.png',
    );
  });
}
