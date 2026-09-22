import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin işlemlerinde kullanıcıya gösterilecek TÜRKÇE hata.
///
/// Servisler eskiden hataları yutup `false` dönüyordu; admin, kaydın neden
/// başarısız olduğunu (kod çakışması, boş alan, yetki…) hiç göremiyor, form
/// sessizce açık kalıyordu. Yeni admin akışları bu istisnayı fırlatır ve
/// mesajı doğrudan gösterir.
class SehiriciAdminException implements Exception {
  final String message;
  const SehiriciAdminException(this.message);

  @override
  String toString() => message;
}

/// Herhangi bir hatayı admin'e gösterilecek kısa Türkçe metne çevirir.
///
/// Veritabanı fonksiyonlarımız kullanıcıya dönük mesajı `RAISE EXCEPTION` ile
/// verir (ör. "Hat kodu boş olamaz"); bunlar olduğu gibi gösterilir. Ham
/// Postgres hataları (benzersizlik, yabancı anahtar, yetki) anlaşılır metne
/// çevrilir.
String sehiriciErrorMessage(Object error) {
  if (error is SehiriciAdminException) return error.message;

  if (error is PostgrestException) {
    final code = error.code ?? '';
    final message = error.message;
    switch (code) {
      case '23505':
        if (message.contains('sehirici_lines_city_id_code_key')) {
          return 'Bu hat kodu bu şehirde zaten kullanılıyor.';
        }
        if (message.contains('sehirici_cities_name_key')) {
          return 'Bu ada sahip bir şehir zaten var.';
        }
        if (message.contains('sehirici_cities_slug_key')) {
          return 'Bu bağlantı adı (slug) başka bir şehirde kullanılıyor.';
        }
        if (message.contains('sehirici_drivers_profile_id_key')) {
          return 'Bu kullanıcı zaten şoför olarak kayıtlı.';
        }
        return 'Bu kayıt zaten var.';
      case '23503':
        return 'Bu kayıt başka kayıtlar tarafından kullanıldığı için '
            'değiştirilemez.';
      case '42501':
        return 'Bu işlem için yetkiniz yok.';
      case 'PGRST202':
      case '42883':
        return 'Sunucu tarafı güncel değil (eksik işlev). Yöneticiye bildirin.';
    }
    // RAISE EXCEPTION mesajları (P0001) ve diğerleri: metin zaten Türkçe.
    if (message.trim().isNotEmpty) return message.trim();
  }

  if (error is StorageException) {
    final msg = error.message;
    if (msg.toLowerCase().contains('exceeded') ||
        msg.toLowerCase().contains('too large')) {
      return 'Görsel çok büyük (en fazla 1 MB).';
    }
    if (msg.toLowerCase().contains('mime')) {
      return 'Yalnızca PNG, WebP veya JPEG görsel yüklenebilir.';
    }
    if (msg.toLowerCase().contains('row-level security') ||
        msg.toLowerCase().contains('unauthorized')) {
      return 'Görsel yükleme yetkiniz yok.';
    }
    return 'Görsel yüklenemedi: $msg';
  }

  if (error is TimeoutException) {
    return 'İstek zaman aşımına uğradı. Bağlantınızı kontrol edin.';
  }

  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup')) {
    return 'Bağlantı hatası. İnternetinizi kontrol edip tekrar deneyin.';
  }
  return text.replaceFirst(RegExp(r'^Exception:\s*'), '');
}
