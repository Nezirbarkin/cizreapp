import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// MİSAFİR GİRİŞİ — hesap açmadan masaya oturmak/izlemek.
///
/// ## Neden bir oturum gerekiyor
///
/// Uygulamanın geri kalanında "misafir" = OTURUM YOK demektir; misafir
/// yalnızca herkese açık içeriği okur. Okey böyle çalışamaz: masadaki her
/// satır RLS ile `auth.uid()`'ye bağlıdır, koltuklar ve izleyiciler bir
/// kullanıcı kimliğine yazılır, taşlar SADECE sahibine görünür. Oturumsuz
/// bir istemci masada hiçbir şey göremez.
///
/// Çözüm Supabase'in ANONİM oturumudur: gerçek bir `auth.users` satırı
/// açılır (`is_anonymous = true`), RLS olduğu gibi çalışır, ama kullanıcıdan
/// e-posta/parola istenmez. Kimlik cihazda saklanır; oyuncu sonradan
/// kayıt olursa aynı kimliği yükseltebilir.
///
/// ## Sunucu tarafı ön koşul
///
/// Anonim giriş, Supabase projesinde AÇIK olmalıdır
/// (Authentication → Sign In / Providers → "Allow anonymous sign-ins").
/// Kapalıysa sunucu `anonymous_provider_disabled` döndürür; burada bu
/// durum ayrı bir hata olarak sarmalanır ki arayüz kullanıcıya "sunucu
/// hatası" değil, doğru şeyi söyleyebilsin.
///
/// Ayrıca profil tetikleyicisi (bkz. 20260904000001) misafire BENZERSİZ bir
/// kullanıcı adı üretmek zorundadır: `profiles.username` UNIQUE'tir ve eski
/// tetikleyici boş string yazdığı için İKİNCİ misafir girişi veritabanı
/// hatasıyla düşüyordu.
abstract final class OkeyGuestAuth {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Testler için oturum durumunu sabitler (null = gerçek duruma bak).
  ///
  /// Widget testlerinde Supabase hiç başlatılmaz; oturum sorgusu orada
  /// bir assertion'a çarpar. Bu kanca, lobinin HEM kapı HEM gövde halini
  /// test edilebilir kılar — kapıyı ekledikten sonra lobi gövdesinin taşma
  /// testleri yalnızca kapıyı ölçüyor hale gelmişti.
  @visibleForTesting
  static bool? debugSessionOverride;

  /// Herhangi bir oturum (kayıtlı ya da misafir) var mı?
  ///
  /// Supabase henüz başlatılmamışsa (testler, çok erken bir çağrı)
  /// "oturum yok" sayılır — burada patlamak, çağıran ekranın hiç
  /// çizilememesi demek olurdu.
  static bool get hasSession {
    final override = debugSessionOverride;
    if (override != null) return override;
    try {
      return _client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Oturum var ve MİSAFİR mi?
  static bool get isGuest {
    try {
      return _client.auth.currentUser?.isAnonymous ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Misafir olarak oturum açar. Zaten bir oturum varsa hiçbir şey yapmaz.
  ///
  /// [OkeyGuestAuthException] fırlatır: `disabled` alanı true ise sorun
  /// kullanıcıda değil, projede kapalı bir ayardadır.
  static Future<void> signInAsGuest() async {
    if (hasSession) return;
    try {
      await _client.auth.signInAnonymously();
    } on AuthException catch (e) {
      final code = (e.code ?? '').toLowerCase();
      final message = e.message.toLowerCase();
      final disabled =
          code.contains('anonymous') ||
          message.contains('anonymous') ||
          e.statusCode == '422';
      throw OkeyGuestAuthException(
        disabled
            ? 'Misafir girişi şu an kapalı. Yönetici Supabase panelinden '
                  '"Allow anonymous sign-ins" ayarını açmalı.'
            : 'Misafir girişi yapılamadı: ${e.message}',
        disabled: disabled,
      );
    } catch (e) {
      throw OkeyGuestAuthException('Misafir girişi yapılamadı: $e');
    }
  }

  /// Oturum yoksa misafir olarak açar; varsa dokunmaz.
  ///
  /// Okey'e giren her akışın ilk adımı budur — masayı izlemek de dahil,
  /// çünkü izleyici kaydı da bir kullanıcı kimliğine yazılır.
  static Future<void> ensureSession() => signInAsGuest();
}

/// Misafir girişi başarısız oldu.
class OkeyGuestAuthException implements Exception {
  final String message;

  /// Sunucuda anonim giriş KAPALI (kullanıcının yapabileceği bir şey yok).
  final bool disabled;

  const OkeyGuestAuthException(this.message, {this.disabled = false});

  @override
  String toString() => message;
}
