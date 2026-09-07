import 'package:cizreapp/okey/admin/okey_admin_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADMIN PANELİ — MASA LİSTESİ VE BOT KAYDI
///
/// Buradaki testler 2026-09'da bulunan iki gerçek hatanın etrafındadır:
///
///  1. Terk edilmiş masaları kapatan bir kural yoktu; canlıda 40 "aktif"
///     masa birikmişti, en eskisi 5 günlük. Panel bunları oynanıyor diye
///     gösteriyordu. Artık son etkinlik bilgisi modele geliyor ve
///     [OkeyAdminRoom.isIdle] onu yorumluyor.
///
///  2. `upsertBotProfile` void dönüyordu; yeni bir bota fotoğraf yüklemek
///     için gereken id elde edilemiyordu. Artık id dönüyor ve PostgREST'in
///     iki farklı cevap biçimine de dayanıklı.

Map<String, dynamic> _roomMap({
  String? lastActivity,
  int? spectatorCount,
  String createdAt = '2026-09-04T10:00:00.000Z',
}) => {
  'room_id': 'room-1',
  'status': 'in_progress',
  'game_mode': 'katlamasiz',
  'team_mode': 'essiz',
  'assist_mode': 'yardimli',
  'is_private': false,
  'hand_no': 2,
  'turn_seat': 1,
  'seated_count': 2,
  'bot_count': 2,
  if (spectatorCount != null) 'spectator_count': spectatorCount,
  if (lastActivity != null) 'last_activity': lastActivity,
  'created_at': createdAt,
};

void main() {
  group('OkeyAdminRoom', () {
    test('son etkinlik ve izleyici sayısı okunur', () {
      final r = OkeyAdminRoom.fromMap(
        _roomMap(lastActivity: '2026-09-04T12:30:00.000Z', spectatorCount: 3),
      );
      expect(r.spectatorCount, 3);
      expect(r.lastActivity, DateTime.parse('2026-09-04T12:30:00.000Z'));
    });

    test('son etkinlik gelmezse KURULMA ANINA düşer (çökmez)', () {
      // Eski sunucu sürümüyle konuşan bir istemci alanı hiç görmez; kart
      // yine de çizilebilmeli.
      final r = OkeyAdminRoom.fromMap(_roomMap());
      expect(r.lastActivity, r.createdAt);
      expect(r.spectatorCount, 0);
    });

    test('30 dakikadan eski etkinlik TERK EDİLMİŞ sayılır', () {
      final now = DateTime.now();
      final fresh = OkeyAdminRoom.fromMap(
        _roomMap(
          lastActivity: now
              .subtract(const Duration(minutes: 5))
              .toUtc()
              .toIso8601String(),
        ),
      );
      final stale = OkeyAdminRoom.fromMap(
        _roomMap(
          lastActivity: now
              .subtract(const Duration(hours: 5))
              .toUtc()
              .toIso8601String(),
        ),
      );
      expect(fresh.isIdle, isFalse);
      expect(stale.isIdle, isTrue);
    });
  });

  group('OkeyAdminService.parseUpsertedId', () {
    test('map cevabından id okunur', () {
      expect(
        OkeyAdminService.parseUpsertedId({'id': 'abc', 'display_name': 'X'}),
        'abc',
      );
    });

    test('tek elemanlı LİSTE cevabından da id okunur', () {
      expect(
        OkeyAdminService.parseUpsertedId([
          {'id': 'abc'},
        ]),
        'abc',
      );
    });

    test('id gelmezse sessizce geçilmez, hata verilir', () {
      // Sessizce null dönseydi çağıran taraf fotoğrafı yüklemeyi atlar ve
      // admin "kaydettim ama fotoğraf gitmedi" derdi.
      expect(() => OkeyAdminService.parseUpsertedId(null), throwsStateError);
      expect(() => OkeyAdminService.parseUpsertedId([]), throwsStateError);
      expect(
        () => OkeyAdminService.parseUpsertedId({'display_name': 'X'}),
        throwsStateError,
      );
    });
  });
}
