import 'package:cizreapp/core/utils/app_error_handler.dart';
import 'package:cizreapp/core/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canlı kayıt (2026-10-16, shop_detail_screen): "Stokta yeterli ürün yok
/// (kalan: 0)" kullanıcıya "Bir sorun oluştu…" olarak gösteriliyor ve admin
/// hata kartına uygulama hatası diye yazılıyordu.
void main() {
  final sunk = <String>[];

  setUp(() {
    sunk.clear();
    AppLogger.errorSink = (type, details, stackTrace, diagnostics) {
      sunk.add(type);
    };
  });

  tearDown(() => AppLogger.errorSink = null);

  test('FriendlyException mesajı olduğu gibi döner ve hata kaydı üretmez', () {
    const e = FriendlyException('Stokta yeterli ürün yok (kalan: 0)');
    expect(AppErrorHandler.handleError(e), 'Stokta yeterli ürün yok (kalan: 0)');
    expect(sunk, isEmpty);
  });

  test('ekranların "Sepete eklenirken hata: \$e" biçimi teknik önek göstermez', () {
    const e = FriendlyException('Bu üründen en fazla 2 adet alınabilir');
    expect('Sepete eklenirken hata: $e',
        'Sepete eklenirken hata: Bu üründen en fazla 2 adet alınabilir');
  });

  test('bilinmeyen hata hâlâ genel mesaj + hata kaydı', () {
    final msg = AppErrorHandler.handleError(StateError('beklenmeyen'));
    expect(msg, 'Bir sorun oluştu. Lütfen daha sonra tekrar deneyin.');
    expect(sunk, hasLength(1));
  });
}
