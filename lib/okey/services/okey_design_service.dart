import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/okey_design.dart';

/// Yöneticinin seçtiği 101 Okey tasarımını sunucudan okur / yazar
/// (`app_settings.okey_design`, `okey_lobby_layout`,
/// `okey_design_user_choice` — bkz. 20261005000020_okey_design_settings.sql).
///
/// ## Bu bir güvenlik sınırı DEĞİL
///
/// Tasarım yalnızca görünümdür; okuma herkese açık bir RPC'dir
/// (`public.okey_design_config()`, misafir de okur). Yazma, app_settings'in
/// mevcut yönetici politikalarına tabidir ([OkeyModuleService] ile aynı yol).
class OkeyDesignService {
  OkeyDesignService._();

  static const Duration _timeout = Duration(seconds: 4);

  /// Sunucudaki ayarı okur ve uygular. ASLA hata fırlatmaz — okunamazsa
  /// cihazdaki son bilinen ayar (ya da varsayılan) geçerli kalır. Okey'e
  /// girişte modül kapısı bunu bekler; zaman aşımı girişi uzun süre tutmasın
  /// diye kısadır.
  static Future<void> refresh() async {
    await OkeyDesignPrefs.instance.load();
    try {
      final raw = await Supabase.instance.client
          .rpc('okey_design_config')
          .timeout(_timeout);
      await OkeyDesignPrefs.instance.applyAdminConfig(
        OkeyDesignConfig.fromJson(raw),
      );
    } catch (e) {
      debugPrint('⚠️ Okey tasarım ayarı okunamadı: $e');
    }
  }

  /// Admin ekranı için: hatayı GİZLEMEZ (yönetici sorunun ağ mı yetki mi
  /// olduğunu görmeli).
  static Future<OkeyDesignConfig> fetchForAdmin() async {
    final raw = await Supabase.instance.client.rpc('okey_design_config');
    return OkeyDesignConfig.fromJson(raw);
  }

  /// Yönetici ayarı kaydeder. Değerler DÜZ METİN yazılır: PostgREST Dart
  /// string'ini jsonb metne çevirir (bkz. reference app_settings yazım
  /// biçimi — '"true"' yazmak tırnaklı metin bırakırdı).
  static Future<void> saveAdmin(OkeyDesignConfig config) async {
    await Supabase.instance.client.from('app_settings').upsert([
      {'key': 'okey_design', 'value': config.designKey},
      {'key': 'okey_lobby_layout', 'value': config.layout?.name ?? 'auto'},
      {
        'key': 'okey_design_user_choice',
        'value': config.userChoice ? 'true' : 'false',
      },
    ], onConflict: 'key');
    // Yöneticinin kendi cihazında da hemen geçerli olsun.
    await OkeyDesignPrefs.instance.applyAdminConfig(config);
  }
}
