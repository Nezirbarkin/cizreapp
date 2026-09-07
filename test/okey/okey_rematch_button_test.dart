import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/screens/okey_match_result_screen.dart';
import 'package:cizreapp/okey/services/okey_room_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "AYNI MASAYLA YENİDEN OYNA" DÜĞMESİ — kullanıcı bildirimi, 2026-09-06:
/// "masa ile devam et dediğinde açılmıyor".
///
/// Sunucu tarafının çalıştığı canlıda doğrulandı (düğmeye basıldığında oda
/// gerçekten kuruluyordu). Açılmayan şey EKRANDI ve bu sınıf hatalar
/// derleyiciden de sunucu testlerinden de kaçar: düğme "hiçbir şey yapmıyor"
/// gibi görünür, hiçbir yere hata düşmez.
///
/// Bu testler tam olarak o soruyu sorar: basınca gezinme çağrılıyor mu, ve
/// bir şey ters giderse düğme KİLİTLİ kalıyor mu.

class _FakeRoomService implements OkeyRoomService {
  _FakeRoomService({this.newRoomId = 'yeni-oda', this.error});

  final String newRoomId;
  final Object? error;
  int rematchCalls = 0;

  @override
  Future<String> rematch(String roomId) async {
    rematchCalls++;
    final e = error;
    if (e != null) throw e;
    return newRoomId;
  }

  @override
  Future<({int seated, String roomId, String status})?> rematchRoomOf(
    String roomId,
  ) async => null;

  @override
  Future<List<OkeyMatchPayout>> matchPayouts(String roomId) async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OkeyRoomSeat _seat(int no, String name) =>
    OkeyRoomSeat(roomId: 'r', seatNo: no, isReady: true, displayName: name);

Widget _screen({
  required _FakeRoomService service,
  void Function(BuildContext, String)? onRematch,
}) => MaterialApp(
  home: OkeyMatchResultScreen(
    seats: [
      _seat(0, 'Ben'),
      _seat(1, 'Ayşe'),
      _seat(2, 'Kadir'),
      _seat(3, 'Zeynep'),
    ],
    roomId: 'eski-oda',
    scores: const {0: 240, 1: 118, 2: 305, 3: 402},
    mySeat: 0,
    handsPlayed: 2,
    service: service,
    onRematch: onRematch ?? (_, _) {},
    onLeave: () {},
  ),
);

void main() {
  group('Yeniden oyna düğmesi', () {
    testWidgets('basınca odayı kurar ve GEZİNMEYİ çağırır', (tester) async {
      final service = _FakeRoomService(newRoomId: 'oda-42');
      String? navigatedTo;

      await tester.pumpWidget(
        _screen(service: service, onRematch: (_, id) => navigatedTo = id),
      );
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.textContaining('yeniden oyna'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(service.rematchCalls, 1);
      expect(
        navigatedTo,
        'oda-42',
        reason: 'oda kuruldu ama ekran açılmadı — bildirilen hata buydu',
      );
    });

    testWidgets('gezinme PATLASA BİLE düğme kilitli kalmaz', (tester) async {
      // ASIL HATA SINIFI: başarı yolunda "meşgul" bayrağı sıfırlanmıyordu.
      // Gezinme sessizce başarısız olursa düğme sonsuza kadar meşgul kalır ve
      // sonraki her basış hiçbir şey yapmaz — dışarıdan "açılmıyor" görünen
      // durum tam olarak budur.
      final service = _FakeRoomService();

      await tester.pumpWidget(
        _screen(
          service: service,
          onRematch: (_, _) => throw StateError('ölü context'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.textContaining('yeniden oyna'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(service.rematchCalls, 1);

      // İKİNCİ basış da sunucuya gitmeli: düğme çözülmüş olmalı.
      await tester.tap(find.textContaining('yeniden oyna'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        service.rematchCalls,
        2,
        reason: 'düğme ilk denemeden sonra kilitli kaldı',
      );
    });

    testWidgets('sunucu hatası masaya YAZIYLA döner', (tester) async {
      final service = _FakeRoomService(
        error: Exception('APP:insufficient_points | mevcut: 40'),
      );

      await tester.pumpWidget(_screen(service: service));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.textContaining('yeniden oyna'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('çipin yetmiyor'), findsOneWidget);
    });

    testWidgets('roomId yoksa düğme HİÇ görünmez', (tester) async {
      // Ödeme özeti gibi, yeniden oyna da odaya bağlıdır: oda kimliği
      // olmadan basılabilir bir düğme göstermek, kesin başarısız olacak bir
      // eylem sunmaktır.
      await tester.pumpWidget(
        MaterialApp(
          home: OkeyMatchResultScreen(
            seats: [_seat(0, 'Ben')],
            scores: const {0: 100},
            mySeat: 0,
            onRematch: (_, _) {},
            onLeave: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('yeniden oyna'), findsNothing);
      expect(find.text('Lobiye dön'), findsOneWidget);
    });
  });
}
