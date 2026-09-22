// "Yüzünden Avatar Oluştur" motoru: katalogdaki HER seçenek çizilebilmeli ve
// editör her sekmede açılabilmeli. Görsel doğruluk göz ile kontrol edilir; bu
// test yalnızca istisna/çökme ve katalog bütünlüğünü korur.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cizreapp/features/profile/models/face_avatar_config.dart';
import 'package:cizreapp/features/profile/screens/face_avatar_flow_screen.dart';
import 'package:cizreapp/features/profile/widgets/face_avatar_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _paint(FaceAvatarConfig cfg, {bool detailed = false}) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  FaceAvatarPainter(cfg, detailed: detailed).paint(canvas, const ui.Size(120, 120));
  rec.endRecording().dispose();
}

void main() {
  test('katalog boyutları ve benzersiz etiketler', () {
    expect(kHairStyles.length, greaterThanOrEqualTo(80));
    expect(kBeardStyles.length, greaterThanOrEqualTo(40));
    expect(kFaceShapes.length, greaterThanOrEqualTo(12));
    expect(kBrowStyles.length, greaterThanOrEqualTo(20));
    expect(kEyeStyles.length, greaterThanOrEqualTo(16));
    expect(kGlassesStyles.length, greaterThanOrEqualTo(16));
    expect(kHeadwearStyles.length, greaterThanOrEqualTo(16));

    // Foto analizi etiketle arıyor; bunlar silinmemeli.
    for (final l in ['Kel', 'Kısa', 'Uzun Düz', 'Orta Düz']) {
      expect(kHairStyles.any((e) => e.label == l), isTrue, reason: l);
    }
    for (final l in ['Tam Sakal', 'Kısa Sakal', 'Üç Günlük', 'Hafif']) {
      expect(kBeardStyles.any((e) => e.label == l), isTrue, reason: l);
    }

    // Aynı listede tekrar eden etiket kullanıcıyı yanıltır.
    for (final labels in <List<String>>[
      kHairStyles.map((e) => e.label).toList(),
      kBeardStyles.map((e) => e.label).toList(),
      kBrowStyles.map((e) => e.label).toList(),
      kEyeStyles.map((e) => e.label).toList(),
      kGlassesStyles.map((e) => e.label).toList(),
      kHeadwearStyles.map((e) => e.label).toList(),
    ]) {
      expect(labels.toSet().length, labels.length, reason: 'yinelenen etiket');
    }
    expect(kNaturalHairColorCount, lessThan(kHairColors.length));
  });

  testWidgets('her seçenek çizilir (küçük önizleme)', (tester) async {
    await tester.runAsync(() async {
      const base = FaceAvatarConfig();
      for (var i = 0; i < kFaceShapes.length; i++) {
        await _paint(base.copyWith(faceShape: i));
      }
      for (var i = 0; i < kHairStyles.length; i++) {
        await _paint(base.copyWith(hair: i));
        await _paint(base.copyWith(hair: i, headwear: 1 + i % (kHeadwearStyles.length - 1)));
      }
      for (var i = 0; i < kBrowStyles.length; i++) {
        await _paint(base.copyWith(brow: i));
      }
      for (var i = 0; i < kEyeStyles.length; i++) {
        await _paint(base.copyWith(eye: i));
      }
      for (var i = 0; i < kLashStyles.length; i++) {
        await _paint(base.copyWith(lash: i));
      }
      for (var i = 0; i < kNoseStyles.length; i++) {
        await _paint(base.copyWith(nose: i));
      }
      for (var i = 0; i < kLipStyles.length; i++) {
        await _paint(base.copyWith(lips: i));
      }
      for (var i = 0; i < kBeardStyles.length; i++) {
        await _paint(base.copyWith(beard: i));
      }
      for (var i = 0; i < kGlassesStyles.length; i++) {
        await _paint(base.copyWith(glasses: i));
      }
      for (var i = 0; i < kHeadwearStyles.length; i++) {
        await _paint(base.copyWith(headwear: i));
      }
      for (var i = 0; i < kJewelryStyles.length; i++) {
        await _paint(base.copyWith(jewelry: i));
      }
      for (var i = 0; i < kDetailStyles.length; i++) {
        await _paint(base.copyWith(detail: i));
      }
      for (var i = 0; i < kClothingStyles.length; i++) {
        await _paint(base.copyWith(clothing: i));
      }
      for (var i = 0; i < kBackgrounds.length; i++) {
        await _paint(base.copyWith(background: i));
      }
    });
  });

  testWidgets('rastgele kombinasyonlar ayrıntılı çizilir', (tester) async {
    await tester.runAsync(() async {
      final rnd = math.Random(7);
      var cfg = const FaceAvatarConfig();
      for (var i = 0; i < 40; i++) {
        cfg = cfg.shuffled(rnd).copyWith(age: rnd.nextInt(4), faceShape: rnd.nextInt(kFaceShapes.length));
        await _paint(cfg, detailed: true);
      }
    });
  });

  testWidgets('PNG çıktısı üretilir', (tester) async {
    await tester.runAsync(() async {
      final bytes = await renderFaceAvatarToPng(const FaceAvatarConfig(), size: 256);
      expect(bytes.length, greaterThan(2000));
      // PNG imzası
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  testWidgets('editör tüm sekmelerde açılır', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // ML Kit eklentisi testte yok: "yüz bulunamadı" döndüren sahte kanal.
    const channel = MethodChannel('google_mlkit_face_detector');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'vision#startFaceDetector' ? <dynamic>[] : null,
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    // Geçerli bir görüntü baytı (motorun kendi çıktısı).
    final png = (await tester.runAsync(() => renderFaceAvatarToPng(const FaceAvatarConfig(), size: 64)))!;

    await tester.pumpWidget(MaterialApp(home: FaceAvatarFlowScreen(imagePath: '/yok.jpg', photoBytes: png)));
    // Analiz gerçek (fake olmayan) asenkron iş yapar; sahte saati değil gerçek
    // zamanı bekle.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Avatarın hazır'), findsOneWidget);
    await tester.tap(find.text('Özelleştir'));
    await tester.pump(const Duration(milliseconds: 500));

    // Saç grubu filtresi (Saç sekmesi varsayılan olarak açık).
    await tester.tap(find.widgetWithText(ChoiceChip, 'Kısa'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);

    for (final label in [
      'Saç', 'Yüz', 'Ten', 'Kaş', 'Göz', 'Makyaj', 'Burun', 'Dudak', 'Sakal',
      'Gözlük', 'Başlık', 'Takı', 'Detay', 'Kıyafet', 'Arka Plan',
    ]) {
      await tester.ensureVisible(find.text(label).first);
      await tester.tap(find.text(label).first);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull, reason: '$label sekmesi');
    }

  });
}
