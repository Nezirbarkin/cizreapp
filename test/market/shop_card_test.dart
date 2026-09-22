import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/models/shop_model.dart';
import 'package:cizreapp/features/market/services/shop_service.dart';
import 'package:cizreapp/features/market/widgets/shop_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

// ── yardımcılar ─────────────────────────────────────────────────────────────

const _dayKeys = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Haftanın her günü açık; [off] içindekiler kapalı.
Map<String, dynamic> _week({
  String open = '09:00',
  String close = '18:00',
  Set<String> off = const {},
  Set<String>? only,
}) => {
  for (final d in _dayKeys)
    d: (off.contains(d) || (only != null && !only.contains(d)))
        ? {'open': null, 'close': null, 'active': false}
        : {'open': open, 'close': close, 'active': true},
};

Shop _shop({
  String name = 'Sanal Marketim',
  String? description,
  String? logoUrl,
  double rating = 0,
  int reviews = 0,
  double fee = 0,
  double? freeMin,
  double minOrder = 0,
  String? time,
  bool pinned = false,
  bool verified = false,
  bool pickup = false,
  bool accepting = true,
  bool manualOpen = true,
  Map<String, dynamic>? hours,
  int ageDays = 365,
}) => Shop(
  id: 's-$name',
  ownerId: 'o',
  categoryId: 'c',
  name: name,
  slug: name,
  description: description,
  logoUrl: logoUrl,
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
  createdAt: DateTime.now().subtract(Duration(days: ageDays)),
  updatedAt: DateTime.now(),
);

ShopCardInfo _info(
  Shop shop, {
  bool global = true,
  bool coupon = false,
  DateTime? now,
}) => ShopCardInfo.from(
  shop,
  globalOrdersEnabled: global,
  hasCoupon: coupon,
  now: now,
);

// 1×1 saydam PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

// ── Supabase (yalnızca kupon sorgusu testleri için) ─────────────────────────

final List<Uri> _couponRequests = [];
List<Map<String, dynamic>> Function(Uri url) _couponRows = (_) => [];
int _couponStatus = 200;

MockClient _client() => MockClient((req) async {
  if (req.url.path.endsWith('/rest/v1/shop_coupons')) {
    _couponRequests.add(req.url);
    return http.Response(
      jsonEncode(_couponStatus == 200 ? _couponRows(req.url) : {}),
      _couponStatus,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return http.Response('[]', 404, request: req);
});

Widget _host(
  Widget child, {
  double textScale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  builder: (context, w) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
    ),
    child: w!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Gerçek Roboto metrikleri: yüklenmezse test Ahem'le (her harf 1 em) çizer
    // ve taşma taraması gerçekte olmayan taşmalar üretir.
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _client(),
    );
    // CachedNetworkImage önbellek dizini için path_provider ister.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  // ── saf mantık ────────────────────────────────────────────────────────────

  group('formatShopMoney', () {
    test('tam sayı kuruşsuz, kuruşlu tutar virgüllü yazılır', () {
      expect(formatShopMoney(29), '₺29');
      expect(formatShopMoney(750.0), '₺750');
      expect(formatShopMoney(12.5), '₺12,50');
      // 0,08 → "₺0" yazmak yanıltıcı olurdu
      expect(formatShopMoney(0.08), '₺0,08');
    });
  });

  group('shopTagline', () {
    test('açıklamanın ilk dolu satırını alır', () {
      expect(
        shopTagline(
          'Seçkin tatlılar & Yöresel lezzetler\nPaket Servis • Randevulu\n☎️0541',
        ),
        'Seçkin tatlılar & Yöresel lezzetler',
      );
      expect(shopTagline('\n  \r\n  Merhaba   dünya  \nikinci'), 'Merhaba dünya');
    });

    test('boş ya da yoksa null', () {
      expect(shopTagline(null), isNull);
      expect(shopTagline(''), isNull);
      expect(shopTagline(' \n \n'), isNull);
    });
  });

  group('shopDeliveryTimeLabel', () {
    test('"dakika" kısaltılır, salt sayı/aralığa dk eklenir', () {
      expect(shopDeliveryTimeLabel('30-60 dakika'), '30-60 dk');
      expect(shopDeliveryTimeLabel('30–45'), '30–45 dk');
      expect(shopDeliveryTimeLabel('45'), '45 dk');
      expect(shopDeliveryTimeLabel('45 dk'), '45 dk');
    });

    test('serbest metin olduğu gibi kalır, boş null olur', () {
      expect(shopDeliveryTimeLabel('Otomatik'), 'Otomatik');
      expect(shopDeliveryTimeLabel('1-2 saat'), '1-2 saat');
      expect(shopDeliveryTimeLabel('  '), isNull);
      expect(shopDeliveryTimeLabel(null), isNull);
    });
  });

  group('shopInitial', () {
    test('Türkçe büyük harf: i → İ, ı → I', () {
      expect(shopInitial('içki bayii'), 'İ');
      expect(shopInitial('ılık süt'), 'I');
      expect(shopInitial('  ali'), 'A');
      expect(shopInitial(''), '?');
    });
  });

  group('shopOpensAtLabel', () {
    // 2026-09-21 Pazartesi
    final monday = DateTime(2026, 9, 21);
    DateTime at(int hour, [int minute = 0, DateTime? day]) {
      final d = day ?? monday;
      return DateTime(d.year, d.month, d.day, hour, minute);
    }

    test('takvim varsayımı: 21 Eylül 2026 Pazartesi', () {
      expect(monday.weekday, DateTime.monday);
    });

    test('bugün henüz açılmadıysa bugünkü saat', () {
      final shop = _shop(hours: _week());
      expect(shopOpensAtLabel(shop, nowTurkey: at(7, 30)), 'Açılış: 09:00');
    });

    test('kapanış sonrası ertesi gün ("yarın")', () {
      final shop = _shop(hours: _week());
      expect(
        shopOpensAtLabel(shop, nowTurkey: at(19)),
        'Açılış: yarın 09:00',
      );
    });

    test('açılış saati tam şimdiyse bugünkü açılış geçmiş sayılır', () {
      final shop = _shop(hours: _week());
      expect(
        shopOpensAtLabel(shop, nowTurkey: at(9)),
        'Açılış: yarın 09:00',
      );
    });

    test('ertesi gün kapalıysa gün adı verilir', () {
      final shop = _shop(hours: _week(off: {'tuesday'}));
      expect(
        shopOpensAtLabel(shop, nowTurkey: at(19)),
        'Açılış: Çarşamba 09:00',
      );
    });

    test('hafta sonu → pazartesi sarması', () {
      final sunday = DateTime(2026, 9, 27);
      expect(sunday.weekday, DateTime.sunday);
      final shop = _shop(hours: _week());
      expect(
        shopOpensAtLabel(shop, nowTurkey: at(19, 0, sunday)),
        'Açılış: yarın 09:00',
      );
    });

    test('yalnızca bugünün günü açıksa gelecek hafta aynı gün', () {
      final shop = _shop(hours: _week(only: {'monday'}));
      expect(
        shopOpensAtLabel(shop, nowTurkey: at(19)),
        'Açılış: Pazartesi 09:00',
      );
    });

    test('elle kapatılmışsa, saat yoksa ya da bozuksa null (vaat verilmez)', () {
      expect(
        shopOpensAtLabel(_shop(manualOpen: false, hours: _week()), nowTurkey: at(19)),
        isNull,
      );
      expect(shopOpensAtLabel(_shop(), nowTurkey: at(19)), isNull);
      expect(shopOpensAtLabel(_shop(hours: {}), nowTurkey: at(19)), isNull);
      expect(
        shopOpensAtLabel(_shop(hours: _week(only: {})), nowTurkey: at(19)),
        isNull,
      );
      expect(
        shopOpensAtLabel(
          _shop(
            hours: {
              for (final d in _dayKeys) d: {'open': 'sabah', 'active': true},
            },
          ),
          nowTurkey: at(19),
        ),
        isNull,
      );
      expect(
        shopOpensAtLabel(
          _shop(hours: {for (final d in _dayKeys) d: 'garip'}),
          nowTurkey: at(19),
        ),
        isNull,
      );
    });
  });

  group('ShopCardInfo', () {
    test('durum önceliği: global > geçici kapalı > çalışma saati > açık', () {
      expect(_info(_shop()).status, ShopStatusKind.open);
      expect(_info(_shop(manualOpen: false)).status, ShopStatusKind.closed);
      expect(
        _info(_shop(accepting: false, manualOpen: false)).status,
        ShopStatusKind.paused,
      );
      expect(
        _info(_shop(accepting: false), global: false).status,
        ShopStatusKind.ordersOff,
      );
      // global kapalıyken açık dükkan bile "Kapalı" görünür
      expect(_info(_shop(), global: false).statusLabel, 'Kapalı');
      expect(_info(_shop()).statusLabel, 'Açık');
    });

    test('durum şeridi metinleri', () {
      expect(_info(_shop()).notice, isNull);
      expect(
        _info(_shop(), global: false).notice,
        'Sipariş alma şu anda kapalı',
      );
      expect(
        _info(_shop(accepting: false)).notice,
        'Geçici kapalı · şu an sipariş almıyor',
      );
      // Elle kapatılmış: açılış vaadi yok → ek bilgi taşımayan şerit çıkmaz
      expect(_info(_shop(manualOpen: false, hours: _week())).notice, isNull);
    });

    test('bugün kapalı, yarın açık: "yarın" bilgisi şeritte', () {
      // Bugünü (Türkiye saatiyle) kapat, diğer günleri aç → gün içinde hangi
      // saatte çalışırsa çalışsın durum "kapalı", açılış "yarın 09:00".
      final trNow = DateTime.now().toUtc().add(const Duration(hours: 3));
      final today = _dayKeys[trNow.weekday - 1];
      final info = _info(_shop(hours: _week(off: {today})));
      expect(info.status, ShopStatusKind.closed);
      expect(info.notice, 'Şu an kapalı · Açılış: yarın 09:00');
    });

    test('puan ve "Yeni" kuralı', () {
      final rated = _info(_shop(rating: 4.0, reviews: 3));
      expect(rated.rating, '4.0');
      expect(rated.reviewCount, 3);
      expect(rated.isNew, isFalse);

      // 0.0 göstermek yerine puan hiç yok
      final unrated = _info(_shop(ageDays: 400));
      expect(unrated.rating, isNull);
      expect(unrated.isNew, isFalse);

      final fresh = _info(_shop(ageDays: 4));
      expect(fresh.rating, isNull);
      expect(fresh.isNew, isTrue);

      // 45 günü aşınca artık "yeni" değil
      expect(_info(_shop(ageDays: 46)).isNew, isFalse);
      expect(_info(_shop(ageDays: 44)).isNew, isTrue);

      // yorumu olan dükkan "yeni" sayılmaz
      expect(_info(_shop(ageDays: 4, reviews: 2)).isNew, isFalse);
    });

    test('teslimat / min. sepet etiketleri', () {
      final free = _info(_shop(fee: 0, freeMin: 750));
      expect(free.deliveryFee, 'Ücretsiz teslimat');
      expect(free.freeDelivery, isTrue);
      expect(free.freeOver, isNull); // zaten ücretsiz: eşik göstermek anlamsız

      final paid = _info(_shop(fee: 29, freeMin: 750, minOrder: 200));
      expect(paid.deliveryFee, '₺29');
      expect(paid.freeDelivery, isFalse);
      expect(paid.freeOver, '₺750 üzeri ücretsiz');
      expect(paid.minOrder, 'Min. ₺200');

      final plain = _info(_shop(fee: 12.5));
      expect(plain.deliveryFee, '₺12,50');
      expect(plain.freeOver, isNull);
      expect(plain.minOrder, isNull);

      expect(_info(_shop(minOrder: 0.08)).minOrder, 'Min. ₺0,08');
      expect(_info(_shop(fee: 30, freeMin: 0)).freeOver, isNull);
    });

    test('rozetler: sponsor, Gel Al, kupon', () {
      final plain = _info(_shop());
      expect(plain.sponsored, isFalse);
      expect(plain.pickup, isFalse);
      expect(plain.coupon, isFalse);

      final all = _info(
        _shop(pinned: true, pickup: true),
        coupon: true,
      );
      expect(all.sponsored, isTrue);
      expect(all.pickup, isTrue);
      expect(all.coupon, isTrue);
    });
  });

  // ── kupon sorgusu ─────────────────────────────────────────────────────────

  group('ShopService.getShopIdsWithActiveCoupons', () {
    setUp(() {
      _couponRequests.clear();
      _couponRows = (_) => [];
      _couponStatus = 200;
    });

    test('boş listede hiç istek atılmaz', () async {
      final ids = await ShopService().getShopIdsWithActiveCoupons([]);
      expect(ids, isEmpty);
      expect(_couponRequests, isEmpty);
    });

    test('tek istek atar; aktif + tarih penceresi süzgeci uygulanır', () async {
      _couponRows = (_) => [
        {'shop_id': 'a', 'usage_limit': null, 'usage_count': 0},
      ];
      final ids = await ShopService().getShopIdsWithActiveCoupons(['a', 'b']);
      expect(ids, {'a'});

      expect(_couponRequests, hasLength(1));
      final q = _couponRequests.single.queryParametersAll;
      expect(q['select'], ['shop_id,usage_limit,usage_count']);
      expect(q['is_active'], ['eq.true']);
      expect(q['shop_id']!.single, startsWith('in.('));
      // "Kuponlarım" ekranıyla aynı: bitmemiş VE başlamış
      final ors = q['or']!;
      expect(ors, hasLength(2));
      expect(ors.any((v) => v.contains('end_date.is.null')), isTrue);
      expect(ors.any((v) => v.contains('start_date.is.null')), isTrue);
    });

    test('kotası dolan kupon sayılmaz, kalanı olan sayılır', () async {
      _couponRows = (_) => [
        {'shop_id': 'dolu', 'usage_limit': 5, 'usage_count': 5},
        {'shop_id': 'asilmis', 'usage_limit': 5, 'usage_count': 9},
        {'shop_id': 'kalan', 'usage_limit': 5, 'usage_count': 4},
        {'shop_id': 'limitsiz', 'usage_limit': null, 'usage_count': 99},
      ];
      final ids = await ShopService().getShopIdsWithActiveCoupons([
        'dolu',
        'asilmis',
        'kalan',
        'limitsiz',
      ]);
      expect(ids, {'kalan', 'limitsiz'});
    });

    test('çok sayıda id 80\'lik parçalara bölünür, sonuçlar birleşir', () async {
      final all = [for (var i = 0; i < 170; i++) 'id$i'];
      _couponRows = (url) {
        // her parçanın ilk id'sinde kupon var
        // Dart istemcisi değerleri tırnaklar: in.("id0","id1",...)
        final first = url.queryParameters['shop_id']!
            .replaceFirst('in.(', '')
            .replaceFirst(')', '')
            .split(',')
            .first
            .replaceAll('"', '');
        return [
          {'shop_id': first, 'usage_limit': null, 'usage_count': 0},
        ];
      };
      final ids = await ShopService().getShopIdsWithActiveCoupons(all);
      expect(_couponRequests, hasLength(3)); // 80 + 80 + 10
      expect(ids, {'id0', 'id80', 'id160'});
    });

    test('tekrar eden id\'ler tek sayılır', () async {
      await ShopService().getShopIdsWithActiveCoupons(['a', 'a', 'a']);
      final value = _couponRequests.single.queryParameters['shop_id']!;
      expect(value, 'in.("a")');
    });

    test('sunucu hatasında boş küme döner, istisna fırlatmaz', () async {
      _couponStatus = 500;
      final ids = await ShopService().getShopIdsWithActiveCoupons(['a']);
      expect(ids, isEmpty);
    });
  });

  // ── model ─────────────────────────────────────────────────────────────────

  group('Shop modeli', () {
    Map<String, dynamic> json(Map<String, dynamic> extra) => {
      'id': 'x',
      'owner_id': 'o',
      'name': 'Dükkan',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      ...extra,
    };

    test('yorum sayısı review_count\'tan okunur (total_reviews ölü sütun)', () {
      // Canlıda total_reviews her dükkanda 0; gerçek sayaç review_count.
      final shop = Shop.fromJson(json({'total_reviews': 0, 'review_count': 7}));
      expect(shop.reviewCount, 7);
    });

    test('review_count yoksa total_reviews\'a, o da yoksa 0\'a düşer', () {
      expect(Shop.fromJson(json({'total_reviews': 4})).reviewCount, 4);
      expect(Shop.fromJson(json({})).reviewCount, 0);
    });

    test('isManuallyClosed yalnızca satıcının elle kapatmasını bildirir', () {
      expect(Shop.fromJson(json({'is_open': false})).isManuallyClosed, isTrue);
      expect(Shop.fromJson(json({'is_open': true})).isManuallyClosed, isFalse);
      expect(Shop.fromJson(json({})).isManuallyClosed, isFalse);
    });

    test('copyWith / toJson reviewCount taşır', () {
      final shop = Shop.fromJson(json({'review_count': 3}));
      expect(shop.copyWith(reviewCount: 9).reviewCount, 9);
      expect(shop.toJson()['review_count'], 3);
    });
  });

  // ── widget ────────────────────────────────────────────────────────────────

  group('ShopCard', () {
    void size(WidgetTester t, double width) {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = Size(width, 2400);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }

    testWidgets('içerik: ad, slogan, durum, teslimat ve rozetler', (t) async {
      size(t, 390);
      await t.pumpWidget(
        _host(
          ShopCard(
            shop: _shop(
              name: 'Sanal Marketim',
              description: "Cizre'nin En Ucuz Sanal Marketi\nikinci satır gizli",
              verified: true,
              rating: 4.5,
              reviews: 12,
              fee: 15,
              freeMin: 750,
              minOrder: 150,
              time: '30-45 dakika',
              pickup: true,
            ),
            hasCoupon: true,
            distanceLabel: '1,2 km',
          ),
        ),
      );

      expect(find.textContaining('Sanal Marketim'), findsOneWidget);
      expect(find.text("Cizre'nin En Ucuz Sanal Marketi"), findsOneWidget);
      expect(find.textContaining('ikinci satır'), findsNothing);
      expect(find.text('Açık'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text(' (12)'), findsOneWidget);
      expect(find.text('30-45 dk'), findsOneWidget);
      expect(find.text('1,2 km'), findsOneWidget);
      expect(find.text('₺15'), findsOneWidget);
      expect(find.text('₺750 üzeri ücretsiz'), findsOneWidget);
      expect(find.text('Min. ₺150'), findsOneWidget);
      expect(find.text('Gel Al'), findsOneWidget);
      expect(find.text('Kupon Var'), findsOneWidget);
      // Sabitli değil, açık dükkan: şerit yok
      expect(find.text('Sponsor'), findsNothing);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('rozetler yalnızca verildiğinde görünür', (t) async {
      size(t, 390);
      await t.pumpWidget(_host(ShopCard(shop: _shop())));

      expect(find.text('Ücretsiz teslimat'), findsOneWidget);
      expect(find.text('Gel Al'), findsNothing);
      expect(find.text('Kupon Var'), findsNothing);
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      // tek satır çizildi: slogan yoksa boş slogan satırı da yok
      expect(find.byIcon(Icons.near_me_rounded), findsNothing);
    });

    testWidgets('Sponsor şeridi yalnızca sabitli dükkanda', (t) async {
      size(t, 390);
      await t.pumpWidget(_host(ShopCard(shop: _shop(pinned: true))));
      expect(find.text('Sponsor'), findsOneWidget);
    });

    testWidgets('puansız yeni dükkan "0.0" yerine "Yeni" gösterir', (t) async {
      size(t, 390);
      await t.pumpWidget(_host(ShopCard(shop: _shop(ageDays: 3))));
      expect(find.text('Yeni'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);

      await t.pumpWidget(_host(ShopCard(shop: _shop(ageDays: 400))));
      expect(find.text('Yeni'), findsNothing);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('geçici kapalı: "Kapalı" + durum şeridi', (t) async {
      size(t, 390);
      await t.pumpWidget(
        _host(ShopCard(shop: _shop(accepting: false))),
      );
      expect(find.text('Kapalı'), findsOneWidget);
      expect(find.text('Geçici kapalı · şu an sipariş almıyor'), findsOneWidget);
    });

    testWidgets('global sipariş kapalı: açık dükkan da şerit gösterir', (t) async {
      size(t, 390);
      await t.pumpWidget(
        _host(ShopCard(shop: _shop(), globalOrdersEnabled: false)),
      );
      expect(find.text('Kapalı'), findsOneWidget);
      expect(find.text('Sipariş alma şu anda kapalı'), findsOneWidget);
    });

    testWidgets('kapalı kartın tamamı soluk DEĞİL (yalnızca chip satırı)', (t) async {
      size(t, 390);
      await t.pumpWidget(
        _host(ShopCard(shop: _shop(accepting: false, description: 'Slogan'))),
      );
      // Eskiden tüm kart Opacity(0.55) içindeydi ve durum yazısı da soluyordu.
      final opacities = t
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(opacities, [0.6]);
      // Durum şeridi tam opak: Opacity'nin altında değil
      expect(
        find.ancestor(
          of: find.text('Geçici kapalı · şu an sipariş almıyor'),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('dokununca onTap çağrılır', (t) async {
      size(t, 390);
      var taps = 0;
      await t.pumpWidget(
        _host(ShopCard(shop: _shop(), onTap: () => taps++)),
      );
      await t.tap(find.byType(ShopCard));
      expect(taps, 1);
    });

    testWidgets('en kötü içerik hiçbir genişlik/yazı boyutunda taşmaz', (t) async {
      final worst = _shop(
        name: 'CİZRE MEMİLHEVA KURABİYE VE YÖRESEL LEZZETLER MERKEZİ',
        description:
            'Uzun bir slogan uzun bir slogan uzun bir slogan uzun bir slogan',
        verified: true,
        rating: 4.9,
        reviews: 12800,
        fee: 25.5,
        freeMin: 1500,
        minOrder: 250,
        time: '30-45 dakika arası kapıda',
        pinned: true,
        pickup: true,
        accepting: false,
      );
      final broken = <String>[];
      for (final width in [280.0, 320.0, 360.0, 412.0, 600.0]) {
        for (final scale in [1.0, 1.3, 1.6, 2.0]) {
          size(t, width);
          await t.pumpWidget(
            _host(
              ShopCard(
                shop: worst,
                hasCoupon: true,
                distanceLabel: '12 km',
              ),
              textScale: scale,
            ),
          );
          final error = t.takeException();
          if (error != null) {
            final detail = error
                .toString()
                .split('\n')
                .where((l) => l.contains('overflowed') || l.contains('shop_card.dart') || l.contains('creator:') || l.contains('constraints:'))
                .take(6)
                .join(' | ');
            broken.add('${width}dp × $scale → $detail');
          }
        }
      }
      expect(broken, isEmpty, reason: 'taşan konfigürasyonlar: $broken');
    });

    testWidgets('erişilebilirlik etiketi özet bilgiyi tek cümlede verir', (t) async {
      final handle = t.ensureSemantics();
      size(t, 390);
      await t.pumpWidget(
        _host(
          ShopCard(
            shop: _shop(
              name: 'Sanal Marketim',
              verified: true,
              pinned: true,
              rating: 4.5,
              reviews: 12,
              fee: 15,
              freeMin: 750,
              minOrder: 150,
              time: '30-45 dakika',
              pickup: true,
            ),
            hasCoupon: true,
            distanceLabel: '850 m',
          ),
        ),
      );

      final node = find.bySemanticsLabel(RegExp('^Sanal Marketim, '));
      expect(node, findsOneWidget);
      final label = t.getSemantics(node).label;
      expect(label, contains('Sanal Marketim'));
      expect(label, contains('doğrulanmış dükkan'));
      expect(label, contains('sponsor'));
      expect(label, contains('açık'));
      expect(label, contains('puan 4.5, 12 değerlendirme'));
      expect(label, contains('teslimat 30-45 dk'));
      expect(label, contains('850 m uzaklıkta'));
      expect(label, contains('teslimat ücreti ₺15'));
      expect(label, contains('teslimat ₺750 üzeri ücretsiz'));
      expect(label, contains('Min. ₺150'));
      expect(label, contains('gel al seçeneği var'));
      expect(label, contains('kupon var'));
      handle.dispose();
    });

    testWidgets('kupon simgesi nabız atar; "animasyonları azalt"ta durur', (t) async {
      size(t, 390);
      await t.pumpWidget(_host(ShopCard(shop: _shop(), hasCoupon: true)));
      await t.pump();
      expect(t.hasRunningAnimations, isTrue);

      await t.pumpWidget(
        _host(
          ShopCard(shop: _shop(), hasCoupon: true),
          disableAnimations: true,
        ),
      );
      await t.pump();
      // pumpAndSettle sonsuz animasyonda zaman aşımına uğrardı
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
    });
  });

  group('ShopLogoTile', () {
    testWidgets('görsel yoksa baş harf gösterir', (t) async {
      await t.pumpWidget(_host(const ShopLogoTile(name: 'içki bayii')));
      expect(find.text('İ'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('görsel gelince logo + yumuşak zemin çizilir', (t) async {
      await t.pumpWidget(
        _host(ShopLogoTile(name: 'Ali', imageProvider: MemoryImage(_png))),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      // ön plandaki logo (contain) + arkadaki küçültülmüş zemin
      expect(find.byType(Image), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('bozuk görselde baş harf kalır, istisna sızmaz', (t) async {
      await t.pumpWidget(
        _host(
          ShopLogoTile(
            name: 'Ali',
            imageProvider: MemoryImage(Uint8List.fromList([1, 2, 3])),
          ),
        ),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('A'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('kapalıyken gri tonlanır', (t) async {
      await t.pumpWidget(_host(const ShopLogoTile(name: 'Ali', muted: true)));
      expect(find.byType(ColorFiltered), findsOneWidget);
      await t.pumpWidget(_host(const ShopLogoTile(name: 'Ali')));
      expect(find.byType(ColorFiltered), findsNothing);
    });
  });

  group('ShopCardSkeleton', () {
    testWidgets('liste iskeleti çizilir ve ekran okuyucuya yükleniyor der', (t) async {
      final handle = t.ensureSemantics();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 1200);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ShopCardSkeletonList(count: 3)),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ShopCardSkeleton), findsNWidgets(3));
      expect(find.bySemanticsLabel('Dükkanlar yükleniyor'), findsOneWidget);
      expect(t.takeException(), isNull);
      handle.dispose();
    });
  });
}
