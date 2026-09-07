import 'package:cizreapp/okey/services/okey_profile_service.dart';
import 'package:cizreapp/okey/widgets/okey_profile_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MASADAN TAKİP — kullanıcı isteği, 2026-09-05:
/// "okey oyunda profile tıklandığında kişiyi takip isteği vs atabilsin".
///
/// ## Neden widget testi
///
/// Sunucu tarafı zaten çalışıyordu (okey_profile_follow). Kırık olan şey
/// ULAŞILABİLİRLİKTİ: kartın tamamı tek bir kaydırma alanının içindeydi ve
/// okey masası YATAY oynandığı için (~360px) avatar halkası + ad + takipçi
/// satırı + 2x2 istatistik + puan şeridi bu yüksekliği tek başına
/// dolduruyordu. Düğmeler görünür alanın DIŞINDA kalıyor, oyuncu takip
/// düğmesini hiç görmüyordu.
///
/// Bu tür bir hata derleyiciden, analizden ve sunucu testlerinden kaçar;
/// yalnızca gerçek bir ekran ölçüsünde widget ağacı kurulunca yakalanır.
OkeyProfileCard _card({
  bool following = false,
  bool requested = false,
  bool isPrivate = false,
  bool isSelf = false,
  String? userId = 'u1',
}) => OkeyProfileCard(
  userId: userId,
  displayName: 'Ayşe Y.',
  points: 4820,
  matchesPlayed: 214,
  matchesWon: 98,
  handsPlayed: 900,
  handsWon: 300,
  bestMatchScore: -181,
  followersCount: 128,
  followingCount: 96,
  friendsCount: 41,
  isFollowing: following,
  isFollowRequested: requested,
  isPrivate: isPrivate,
  isSelf: isSelf,
);

Widget _sheet({
  required OkeyProfileCard? card,
  Future<OkeyFollowState> Function(String, bool)? onFollow,
  Key? key,
}) => MaterialApp(
  home: Scaffold(
    // Gerçek kullanımdaki gibi: kart alttan açılır, ekranın dibine oturur.
    body: Align(
      alignment: Alignment.bottomCenter,
      child: OkeyProfileSheet(
        // Anahtar, art arda farklı ekran ölçüleriyle kurulan testlerde
        // State'in TAŞINMAMASI için: anahtarsız kaldığında ikinci ölçü,
        // birinci ölçüde basılmış düğmenin durumunu miras alıyordu.
        key: key,
        userId: 'u1',
        loadCard: () async => card,
        setFollow:
            onFollow ??
            (_, follow) async => OkeyFollowState(
              isFollowing: follow,
              isRequested: false,
              followersCount: follow ? 129 : 128,
            ),
      ),
    ),
  ),
);

void main() {
  group('Masadaki profil kartı — TAKİP', () {
    testWidgets('takip düğmesi YATAY ekranda GÖRÜNÜR ve basılabilir', (
      tester,
    ) async {
      for (final size in const [Size(800, 360), Size(640, 320)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        var tapped = false;
        await tester.pumpWidget(
          _sheet(
            key: ValueKey(size),
            card: _card(),
            onFollow: (_, follow) async {
              tapped = true;
              return OkeyFollowState(
                isFollowing: follow,
                isRequested: false,
                followersCount: 129,
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '$size ekranda taştı');

        final button = find.text('TAKİP ET');
        expect(
          button,
          findsOneWidget,
          reason: '$size ekranda takip düğmesi yok',
        );

        // GÖRÜNÜR ALANIN İÇİNDE Mİ: kaydırmadan basılabilmeli.
        final rect = tester.getRect(button);
        expect(
          rect.bottom,
          lessThanOrEqualTo(size.height + 0.5),
          reason:
              '$size ekranda takip düğmesi ekranın altında kaldı '
              '(${rect.bottom.toStringAsFixed(0)}px)',
        );

        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tapped, isTrue, reason: '$size ekranda düğmeye basılamadı');
      }
    });

    testWidgets('GİZLİ hesapta düğme "istek gönder" der', (tester) async {
      // Beklenti KURAR: gizli bir hesapta düğmeye basmanın sonucu takip
      // değil, ONAY BEKLEYEN bir istektir — bunu bastıktan sonra öğrenmek
      // şaşırtıcı olurdu.
      await tester.pumpWidget(_sheet(card: _card(isPrivate: true)));
      await tester.pumpAndSettle();

      expect(find.text('TAKİP İSTEĞİ GÖNDER'), findsOneWidget);
      expect(find.text('TAKİP ET'), findsNothing);
    });

    testWidgets('istek gönderilince düğme BEKLİYOR durumuna geçer', (
      tester,
    ) async {
      await tester.pumpWidget(
        _sheet(
          card: _card(isPrivate: true),
          // Gizli hesap: sunucu "takip başlamadı, istek bekliyor" der.
          onFollow: (_, _) async => const OkeyFollowState(
            isFollowing: false,
            isRequested: true,
            followersCount: 128,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('TAKİP İSTEĞİ GÖNDER'));
      await tester.pumpAndSettle();

      expect(find.text('İSTEK GÖNDERİLDİ'), findsOneWidget);
      expect(
        find.textContaining('Takip isteği gönderildi'),
        findsOneWidget,
        reason: 'sessiz kalmak "bir şey olmadı" hissi verir',
      );
    });

    testWidgets('takip edilen hesapta düğme geri almayı önerir', (
      tester,
    ) async {
      await tester.pumpWidget(_sheet(card: _card(following: true)));
      await tester.pumpAndSettle();
      expect(find.text('TAKİPTESİN'), findsOneWidget);
    });

    testWidgets('KENDİ kartımda takip düğmesi YOK', (tester) async {
      await tester.pumpWidget(_sheet(card: _card(isSelf: true)));
      await tester.pumpAndSettle();

      expect(find.text('TAKİP ET'), findsNothing);
      expect(find.text('KAPAT'), findsOneWidget);
    });

    testWidgets('BOT kartında takip düğmesi YOK', (tester) async {
      // Bot koltuğunun kullanıcı kimliği yoktur. Düğme görünseydi
      // "takip edilemedi" hatası botu ele verirdi — masada botlar gerçek
      // oyuncular gibi görünür (bkz. OkeyRoomSeat.displayLabel).
      await tester.pumpWidget(_sheet(card: _card(userId: null)));
      await tester.pumpAndSettle();

      expect(find.text('TAKİP ET'), findsNothing);
      expect(find.text('TAKİP İSTEĞİ GÖNDER'), findsNothing);
    });
  });
}
