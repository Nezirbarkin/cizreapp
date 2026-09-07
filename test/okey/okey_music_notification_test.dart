import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BİLDİRİM PANELİ MEDYA KONTROLLERİ — sessiz bozulmaya karşı testler.
///
/// ## Neden dosya tabanlı testler
///
/// Buradaki iki hata da ÇALIŞMA ANINDA HİÇ HATA VERMEZ; yalnızca kullanıcı
/// fark eder:
///
///  1. **Eksik receiver** → bildirim düğmesine basınca uygulama öne fırlar ve
///     oyuncu Okey masasından atılır. Kod tarafında hiçbir istisna yok.
///  2. **Eksik ikon çizimi** → düğme ikonsuz görünür. Eklenti ismi
///     `resources.getIdentifier` ile arar; bulamazsa 0 döner ve SESSİZCE
///     ikonsuz devam eder.
///
/// İkisi de derleyiciden ve analiz aracından kaçar. Bu yüzden burada
/// doğrudan DOSYALAR okunur.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final soundService = File('lib/okey/services/okey_sound_service.dart');
  final drawableDir = Directory('android/app/src/main/res/drawable');
  final resDir = Directory('android/app/src/main/res');

  /// Bir çizim adının res/drawable* klasörlerinden herhangi birinde
  /// karşılığı var mı? (Android kaynağı ADA göre çözer; klasör niteleyicisi
  /// — -nodpi, -hdpi … — ve uzantı fark etmez.)
  File? resolveDrawable(String name) {
    if (!resDir.existsSync()) return null;
    for (final dir in resDir.listSync().whereType<Directory>()) {
      final folder = dir.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (!folder.startsWith('drawable')) continue;
      for (final f in dir.listSync().whereType<File>()) {
        final file = f.uri.pathSegments.last;
        final dot = file.lastIndexOf('.');
        if ((dot < 0 ? file : file.substring(0, dot)) == name) return f;
      }
    }
    return null;
  }

  group('Bildirim düğmeleri uygulamayı öne fırlatmaz', () {
    test('ActionBroadcastReceiver manifest\'te tanımlı', () {
      expect(manifest.existsSync(), isTrue, reason: 'manifest bulunamadı');
      final xml = manifest.readAsStringSync();

      expect(
        xml.contains(
          'com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver',
        ),
        isTrue,
        reason:
            'ActionBroadcastReceiver manifest\'ten silinmiş. '
            'flutter_local_notifications kendi manifest\'inde HİÇBİR receiver '
            'tanımlamaz; bu alıcı olmadan bildirim düğmeleri arka plan '
            'yayınına düşemez ve Android geri düşüş olarak MainActivity\'yi '
            'başlatır — oyuncu masadan atılır.',
      );
    });

    test('MainActivity singleTop — bildirim gövdesi ekranı sıfırlamaz', () {
      final xml = manifest.readAsStringSync();
      expect(
        xml.contains('android:launchMode="singleTop"'),
        isTrue,
        reason:
            'singleTop kalkarsa bildirime dokunmak YENİ bir MainActivity '
            'örneği açar; Flutter baştan kurulur ve oyuncu o an bulunduğu '
            'ekranı kaybeder.',
      );
    });

    test('bildirim düğmeleri arayüz açmaz (showsUserInterface: false)', () {
      // YORUM SATIRLARI ELENİR: bu dosya `showsUserInterface: false`
      // kararını yorumlarda da açıklıyor. Ham metinde saymak, kodda 5
      // düğme varken 7 eşleşme bulup testi yanlış yere düşürüyordu.
      final dart = soundService
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      // Her AndroidNotificationAction için açık bir showsUserInterface: false
      // olmalı. true olan tek bir düğme bile uygulamayı öne fırlatır.
      final actionCount = 'AndroidNotificationAction('.allMatches(dart).length;
      final falseCount = 'showsUserInterface: false'.allMatches(dart).length;
      expect(
        falseCount,
        actionCount,
        reason:
            '$actionCount bildirim düğmesi var ama $falseCount tanesinde '
            'showsUserInterface: false yazıyor — eksik olan düğme '
            'uygulamayı öne getirir.',
      );
    });
  });

  group('Medya düğmelerinin ikonları', () {
    /// Dart tarafında adı geçen her çizim, gerçekten var mı?
    ///
    /// ## Neden TÜM drawable klasörlerine bakılır
    ///
    /// Android bir çizimi `res/drawable*` klasörlerinin HERHANGİ birinde
    /// arar ve uzantıya bakmaz. Test yalnızca `res/drawable/<ad>.xml`
    /// aradığı sürece, doğru yere konmuş bir kaynağı da "eksik" sayıyordu:
    /// bildirimin büyük kapak görseli (`ic_music_art.png`) bilerek
    /// `drawable-nodpi/` altında duruyor — nodpi, Android'in görseli ekran
    /// yoğunluğuna göre ölçeklemesini engeller ve bir kapak görseli için
    /// doğru olan budur. Testin yanlış yeri araması, ortada gerçek bir hata
    /// yokken kırmızı veriyordu.
    test(
      'DrawableResourceAndroidBitmap adlarının hepsi res/drawable\'da var',
      () {
        final dart = soundService.readAsStringSync();
        final names = RegExp(
          r"DrawableResourceAndroidBitmap\('([^']+)'\)",
        ).allMatches(dart).map((m) => m.group(1)!).toSet();

        expect(
          names,
          isNotEmpty,
          reason: 'hiç ikon tanımlanmamış — düğmeler ikonsuz görünür',
        );

        for (final name in names) {
          expect(
            resolveDrawable(name),
            isNotNull,
            reason:
                '$name hiçbir res/drawable* klasöründe yok. Eklenti çizimi ada '
                'göre arar ve bulamazsa SESSİZCE ikonsuz devam eder — hata '
                'almazsın, sadece ikon kaybolur.',
          );
        }
      },
    );

    test('beş medya kontrolünün de ikonu var', () {
      for (final n in const [
        'ic_notif_play',
        'ic_notif_pause',
        'ic_notif_prev',
        'ic_notif_next',
        'ic_notif_close',
      ]) {
        expect(resolveDrawable(n), isNotNull, reason: '$n eksik');
      }
    });

    test('ikonlar TEK RENK beyaz — Android onları tonlar', () {
      for (final f in drawableDir.listSync().whereType<File>().where(
        (f) => f.path.contains('ic_notif_'),
      )) {
        final xml = f.readAsStringSync();
        expect(
          xml.contains('#FFFFFFFF'),
          isTrue,
          reason:
              '${f.uri.pathSegments.last} beyaz değil. Bildirim aksiyon '
              'ikonları sistem temasına göre tonlanır; renkli bir ikon gri '
              'bir lekeye döner.',
        );
      }
    });
  });

  group('Çalma listesi kontrolleri', () {
    final dart = soundService.readAsStringSync();

    test('önceki/sonraki YALNIZCA çok şarkılı listede gösterilir', () {
      // Tek şarkıda bu iki düğme işlevsiz olurdu (previousTrack/nextTrack
      // `length < 2` iken erken döner) — panelde ölü düğme durmamalı.
      expect(
        dart.contains('final multi = _playlist.length > 1;'),
        isTrue,
        reason:
            'çok şarkı kontrolü kaldırılmış — tek şarkılık listede '
            'basıldığında hiçbir şey yapmayan iki düğme görünür',
      );
    });

    test('dört aksiyonun dördü de işleniyor', () {
      for (final id in const [
        '_actionPrev',
        '_actionNext',
        '_actionPause',
        '_actionResume',
        '_actionClose',
      ]) {
        expect(
          dart.contains('case $id:'),
          isTrue,
          reason:
              '$id tanımlı ama _onNotificationAction içinde işlenmiyor — '
              'düğme görünür ama hiçbir şey yapmaz',
        );
      }
    });
  });
}
