import 'dart:math' as math;

import 'package:cizreapp/okey/theme/okey_rack_style.dart';
import 'package:cizreapp/okey/theme/okey_table_theme.dart';
import 'package:cizreapp/okey/theme/okey_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TASARIM SİSTEMİ v6 — kayıt, okunurluk ve tercih kuralları.
///
/// Tasarımlar elle yazılmış paletlerdir (bkz. okey_design.dart üst notu);
/// bu dosya yeni bir tasarım eklenirken yapılabilecek sessiz hataları
/// yakalar: okunmayan metin, eşleşmeyen masa anahtarı, gradyan/durak sayısı
/// uyuşmazlığı (Flutter bunu ancak ÇİZİM ANINDA assert ile bildirir).

double _luminance(Color c) => c.computeLuminance();

/// Saydam [fg]'yi [bg] üstüne bindirip kontrast oranını hesaplar (WCAG).
double _contrast(Color fg, Color bg) {
  final over = Color.alphaBlend(fg, bg);
  final a = _luminance(over);
  final b = _luminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tasarım kaydı', () {
    test('5\'ten fazla tasarım var, anahtar ve adlar benzersiz', () {
      expect(OkeyDesign.all.length, greaterThan(5));
      expect(
        OkeyDesign.all.map((d) => d.key).toSet().length,
        OkeyDesign.all.length,
      );
      expect(
        OkeyDesign.all.map((d) => d.label).toSet().length,
        OkeyDesign.all.length,
      );
    });

    test('anahtarlar sunucunun kabul ettiği biçimde (^[a-z0-9_]{1,32}\$)', () {
      final re = RegExp(r'^[a-z0-9_]{1,32}$');
      for (final d in OkeyDesign.all) {
        expect(re.hasMatch(d.key), isTrue, reason: d.key);
      }
    });

    test('üç lobi düzeninin hepsi en az bir tasarımda kullanılıyor', () {
      expect(
        OkeyDesign.all.map((d) => d.layout).toSet(),
        OkeyLobbyLayout.values.toSet(),
      );
    });

    test('en az bir AÇIK ve bir KOYU tasarım var', () {
      expect(OkeyDesign.all.any((d) => d.isLight), isTrue);
      expect(OkeyDesign.all.any((d) => !d.isLight), isTrue);
    });

    test('her tasarımın masası ve ıstakası gerçekten tanımlı', () {
      for (final d in OkeyDesign.all) {
        expect(OkeyTableTheme.isKnown(d.tableThemeKey), isTrue, reason: d.key);
        expect(OkeyRackStyle.isKnown(d.rackStyleKey), isTrue, reason: d.key);
      }
      for (final t in OkeyTableTheme.all) {
        expect(
          OkeyRackStyle.isKnown(t.pairedRackStyleKey),
          isTrue,
          reason: t.key,
        );
      }
    });

    test('gradyan renk/durak sayıları çizimde assert atmaz', () {
      for (final d in OkeyDesign.all) {
        expect(d.screenGradient.length, d.screenStops.length, reason: d.key);
        // _HeroCard RadialGradient'i stops: [0, 0.6, 1] ile kurar.
        expect(d.heroGradient.length, 3, reason: d.key);
        expect(d.accentGradient.length, greaterThanOrEqualTo(2));
      }
      for (final t in OkeyTableTheme.all) {
        expect(t.railGradient.length, t.railGradientStops.length);
      }
      for (final r in OkeyRackStyle.all) {
        expect(r.body.length, 4, reason: r.key);
      }
    });

    test('bilinmeyen anahtar varsayılana düşer', () {
      expect(OkeyDesign.byKey(null), OkeyDesign.fallback);
      expect(OkeyDesign.byKey('yok_boyle'), OkeyDesign.fallback);
      expect(OkeyDesign.byKey('neon'), OkeyDesign.neon);
      expect(OkeyLobbyLayout.byKey('auto'), isNull);
      expect(OkeyLobbyLayout.byKey('arena'), OkeyLobbyLayout.arena);
    });
  });

  group('Okunurluk (WCAG kontrastı)', () {
    for (final d in OkeyDesign.all) {
      test('${d.label}: metinler kendi zeminlerinde okunur', () {
        // Gövde metni kartta ≥ 4.5 (AA).
        expect(_contrast(d.text, d.cardFill), greaterThanOrEqualTo(4.5));
        // Silik metin (açıklama) ≥ 3, en silik (dipnot) ≥ 2.5.
        expect(_contrast(d.textDim, d.cardFill), greaterThanOrEqualTo(3));
        expect(_contrast(d.textFaint, d.cardFill), greaterThanOrEqualTo(2.5));
        // Ekran zemininin üstü (başlık) — en açık durakta da okunur.
        for (final bg in d.screenGradient) {
          expect(_contrast(d.text, bg), greaterThanOrEqualTo(4.5));
        }
        // Vurgu düğmesi yazısı gradyanın İKİ ucunda da okunur.
        for (final bg in d.accentGradient) {
          expect(_contrast(d.onAccent, bg), greaterThanOrEqualTo(3.5));
        }
        // Afiş yazısı afişin her tonunda okunur.
        for (final bg in d.heroGradient) {
          expect(_contrast(d.onHero, bg), greaterThanOrEqualTo(4.5));
        }
        // Kart üstündeki vurgulu sayı/yazı ("mürekkep").
        final ink = d.isLight ? d.accentText : d.accent;
        expect(_contrast(ink, d.cardFill), greaterThanOrEqualTo(3));
        expect(_contrast(d.accentText, d.pillFill), greaterThanOrEqualTo(3));
        // Bölüm başlığı ekranın üst zemininde.
        expect(
          _contrast(d.sectionLabel, d.screenGradient.first),
          greaterThanOrEqualTo(3),
        );
      });
    }
  });

  group('Türkçe büyük/küçük harf', () {
    test('i/ı kuralları', () {
      expect(okeyUpperTr('Seni davet edenler'), 'SENİ DAVET EDENLER');
      expect(okeyLowerTr('KAPALI MASA'), 'kapalı masa');
      expect(okeySentenceTr('OTOMATİK EŞLEŞ'), 'Otomatik eşleş');
      expect(okeySentenceTr('İZLE'), 'İzle');
      expect(okeySentenceTr('GİRİŞ YAP'), 'Giriş yap');
      expect(okeySentenceTr('ISTAKA'), 'Istaka');
    });

    test('BÜYÜK HARFLİ tasarımda düğme etiketi KODDAKİ gibi kalır', () {
      OkeyDesignPrefs.instance.debugReset();
      expect(OkeyUI.design.uppercase, isTrue);
      expect(OkeyUI.label('MASA KUR'), 'MASA KUR');
      expect(OkeyUI.label('Lobiye dön'), 'Lobiye dön');
      expect(OkeyUI.heading('Seni davet edenler'), 'SENİ DAVET EDENLER');
    });

    test('cümle düzenli tasarımda yalnız TAMAMI BÜYÜK etiketler çevrilir', () {
      OkeyDesignPrefs.instance.debugReset(
        admin: const OkeyDesignConfig(designKey: 'ege'),
      );
      addTearDown(OkeyDesignPrefs.instance.debugReset);
      expect(OkeyUI.design.uppercase, isFalse);
      expect(OkeyUI.label('MASA KUR'), 'Masa kur');
      expect(OkeyUI.label('Lobiye dön'), 'Lobiye dön');
      expect(OkeyUI.heading('Seni davet edenler'), 'Seni davet edenler');
    });
  });

  group('Sunucu yanıtı', () {
    test('OkeyDesignConfig.fromJson bozuk alanlarda varsayılana düşer', () {
      expect(
        OkeyDesignConfig.fromJson({
          'design': 'cini',
          'layout': 'arena',
          'user_choice': false,
        }),
        const OkeyDesignConfig(
          designKey: 'cini',
          layout: OkeyLobbyLayout.arena,
          userChoice: false,
        ),
      );
      expect(
        OkeyDesignConfig.fromJson({'design': '', 'layout': 'auto'}),
        OkeyDesignConfig.defaults,
      );
      expect(OkeyDesignConfig.fromJson(null), OkeyDesignConfig.defaults);
      expect(OkeyDesignConfig.fromJson('x'), OkeyDesignConfig.defaults);
      expect(
        OkeyDesignConfig.fromJson({
          'design': 'neon',
          'user_choice': 'false',
        }).userChoice,
        isFalse,
      );
    });
  });

  group('Tercih çözümleme (yönetici + oyuncu)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      OkeyDesignPrefs.instance.debugReset();
    });
    tearDown(() async {
      await OkeyDesignPrefs.instance.clearUserChoice();
      OkeyDesignPrefs.instance.debugReset();
    });

    test('yönetici tasarımı masa ve ıstakayı da getirir', () async {
      await OkeyDesignPrefs.instance.applyAdminConfig(
        const OkeyDesignConfig(designKey: 'neon'),
      );
      expect(OkeyUI.design, OkeyDesign.neon);
      expect(OkeyUI.layout, OkeyLobbyLayout.arena);
      expect(OkeyTableThemePrefs.instance.current.value, OkeyTableTheme.neon);
      expect(OkeyRackStylePrefs.instance.current.value, OkeyRackStyle.neon);
    });

    test(
      'yöneticinin düzen geçersiz kılması tasarımın düzenini ezer',
      () async {
        await OkeyDesignPrefs.instance.applyAdminConfig(
          const OkeyDesignConfig(
            designKey: 'neon',
            layout: OkeyLobbyLayout.kompakt,
          ),
        );
        expect(OkeyUI.layout, OkeyLobbyLayout.kompakt);
      },
    );

    test(
      'izin varken oyuncunun seçimi geçerli, kilitlenince yöneticininki',
      () async {
        final prefs = OkeyDesignPrefs.instance;
        await prefs.applyAdminConfig(
          const OkeyDesignConfig(designKey: 'saray'),
        );
        await prefs.selectByUser(OkeyDesign.cini);
        expect(OkeyUI.design, OkeyDesign.cini);
        expect(OkeyTableThemePrefs.instance.current.value, OkeyTableTheme.cini);

        // Oyuncu masayı ayrıca elle değiştirir.
        await OkeyTableThemePrefs.instance.select(OkeyTableTheme.yesilCuha);
        expect(
          OkeyTableThemePrefs.instance.current.value,
          OkeyTableTheme.yesilCuha,
        );

        // Yönetici kilitler → herkes yöneticinin tasarımını VE masasını görür.
        await prefs.applyAdminConfig(
          const OkeyDesignConfig(designKey: 'saray', userChoice: false),
        );
        expect(OkeyUI.design, OkeyDesign.saray);
        expect(
          OkeyTableThemePrefs.instance.current.value,
          OkeyTableTheme.saray,
        );
        expect(OkeyRackStylePrefs.instance.current.value, OkeyRackStyle.abanoz);

        // Kilitliyken seçim yapılamaz.
        await OkeyTableThemePrefs.instance.select(OkeyTableTheme.geceModu);
        expect(
          OkeyTableThemePrefs.instance.current.value,
          OkeyTableTheme.saray,
        );
        await prefs.selectByUser(OkeyDesign.ege);
        expect(OkeyUI.design, OkeyDesign.saray);

        // Kilit kalkınca oyuncunun eski seçimi geri gelir (silinmemişti).
        await prefs.applyAdminConfig(
          const OkeyDesignConfig(designKey: 'saray'),
        );
        expect(OkeyUI.design, OkeyDesign.cini);
        expect(
          OkeyTableThemePrefs.instance.current.value,
          OkeyTableTheme.yesilCuha,
        );
      },
    );

    test('yeni tasarım seçmek eski elle seçilmiş masayı sıfırlar', () async {
      final prefs = OkeyDesignPrefs.instance;
      await OkeyTableThemePrefs.instance.select(OkeyTableTheme.geceModu);
      await prefs.selectByUser(OkeyDesign.ege);
      expect(OkeyTableThemePrefs.instance.current.value, OkeyTableTheme.ege);
      expect(OkeyRackStylePrefs.instance.current.value, OkeyRackStyle.zeytin);
    });

    test('yöneticinin seçimine dön oyuncu seçimini siler', () async {
      final prefs = OkeyDesignPrefs.instance;
      await prefs.applyAdminConfig(const OkeyDesignConfig(designKey: 'bordo'));
      await prefs.selectByUser(OkeyDesign.neon);
      expect(prefs.userDesignKey, 'neon');
      await prefs.clearUserChoice();
      expect(prefs.userDesignKey, isNull);
      expect(OkeyUI.design, OkeyDesign.bordo);
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('okey_design_user'), isNull);
    });

    test('yönetici ayarı cihazda önbelleğe yazılır', () async {
      await OkeyDesignPrefs.instance.applyAdminConfig(
        const OkeyDesignConfig(
          designKey: 'zumrut',
          layout: OkeyLobbyLayout.salon,
          userChoice: false,
        ),
      );
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('okey_design_admin_cache'), 'zumrut|salon|false');
    });
  });

  group('Etkin tema → OkeyUI token\'ları', () {
    tearDown(OkeyDesignPrefs.instance.debugReset);

    test('token\'lar aktif tasarımı izler', () {
      for (final d in OkeyDesign.all) {
        OkeyDesignPrefs.instance.debugReset(
          admin: OkeyDesignConfig(designKey: d.key),
        );
        expect(OkeyUI.cardFill, d.cardFill);
        expect(OkeyUI.brass, d.accent);
        expect(OkeyUI.text, d.text);
        expect(OkeyUI.screenTop, d.screenGradient.first);
        expect(OkeyUI.isLight, d.isLight);
        expect(
          OkeyUI.materialTheme(ThemeData()).colorScheme.brightness,
          d.brightness,
        );
      }
    });

    test(
      'açık tasarımda pastel sinyal rengi koyulaşır, koyuda aynen kalır',
      () {
        const mint = Color(0xFFB9F6CA);
        OkeyDesignPrefs.instance.debugReset();
        expect(OkeyUI.signal(mint), mint);
        OkeyDesignPrefs.instance.debugReset(
          admin: const OkeyDesignConfig(designKey: 'cini'),
        );
        expect(
          _contrast(OkeyUI.signal(mint), OkeyDesign.cini.cardFill),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  });
}
