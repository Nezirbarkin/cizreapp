import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'okey_damask_background.dart';

/// Masanın ARKASINDAKİ "oda" — admin panelinden yüklenmiş bir FOTOĞRAF varsa
/// o, yoksa vektörel bir sıcak oda gradyanı.
///
/// ## Neden iki katman
///
/// Kullanıcı gerçek bir 3D ortam istedi ve fotoğrafın admin panelinden
/// yüklenmesini önerdi (bkz. 20260903000008_okey_table_backgrounds.sql).
/// Ama fotoğraf ZORUNLU DEĞİLDİR: yüklenmemişse, ağ yoksa ya da dosya
/// bozuksa oyun ekranı ASLA boş/siyah kalmaz — vektörel oda devreye girer.
/// Arka plan oyunun işleyişini etkilemeyen saf dekordur; hata durumunda
/// sessizce yedeğe düşmek doğru davranıştır.
///
/// ## Neden widget kendi verisini çekiyor
///
/// URL tek bir küçük string ve TÜM oyuncular için aynı. Provider'a taşımak,
/// masa state'ine dekorasyon sorumluluğu eklerdi. Bunun yerine burada
/// SÜREÇ BOYU tek seferlik bir önbellek var: ilk masa açılışında bir kez
/// okunur, sonraki tüm eller/odalar aynı değeri kullanır.
class OkeyRoomBackdrop extends StatefulWidget {
  const OkeyRoomBackdrop({super.key});

  /// Masa arka planının asset anahtarı (bkz. okey_table_assets).
  static const assetKey = 'room_backdrop';

  /// Süreç boyu önbellek. `null` = henüz okunmadı, `''` = okundu ve yok.
  static String? _cachedUrl;

  /// Admin yeni bir görsel yükleyince önbelleği düşürür ki bir sonraki masa
  /// açılışında yenisi okunsun.
  static void invalidateCache() => _cachedUrl = null;

  /// Test/önizleme için doğrudan değer yazmak.
  @visibleForTesting
  static void debugSetCachedUrl(String? url) => _cachedUrl = url ?? '';

  static Future<String> _loadUrl() async {
    final cached = _cachedUrl;
    if (cached != null) return cached;
    try {
      final row = await Supabase.instance.client
          .from('okey_table_assets')
          .select('public_url')
          .eq('asset_key', assetKey)
          .maybeSingle();
      _cachedUrl = (row?['public_url'] as String?) ?? '';
    } catch (_) {
      // Ağ/oturum hatası: bu turda vektörel yedek kullanılır. Önbelleğe ''
      // yazılır ki her karede yeniden denenmesin.
      _cachedUrl = '';
    }
    return _cachedUrl!;
  }

  @override
  State<OkeyRoomBackdrop> createState() => _OkeyRoomBackdropState();
}

class _OkeyRoomBackdropState extends State<OkeyRoomBackdrop> {
  String? _url;

  @override
  void initState() {
    super.initState();
    OkeyRoomBackdrop._loadUrl().then((u) {
      if (mounted && u.isNotEmpty) setState(() => _url = u);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return Stack(
      fit: StackFit.expand,
      children: [
        const _VectorRoom(),
        if (url != null)
          // Fotoğraf vektörel odanın ÜSTÜNE biner: yüklenirken (ya da hiç
          // yüklenemezse) altta zaten bir oda vardır, ekran hiç boş kalmaz.
          Image.network(
            url,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
            frameBuilder: (_, child, frame, wasSync) {
              if (wasSync || frame != null) {
                return AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 350),
                  child: child,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        // KARARTMA PERDESİ — YALNIZCA fotoğraf varken.
        //
        // Parlak/karışık bir oda fotoğrafı yüklenirse taşlar ve HUD metinleri
        // zeminle karışır; kenarlardan merkeze açılan bu perde kontrastı
        // fotoğrafın "ne olduğu" hakkında hiçbir varsayım yapmadan garanti
        // eder. Vektörel zemin ise ZATEN bu iş için tasarlandı (kendi vinyeti
        // ve doğru kontrastı var) — üstüne bir perde daha atmak onu çamurlu
        // bir griye çeviriyordu.
        if (url != null)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 1.1,
                  colors: [
                    Color(0x1A000000),
                    Color(0x73000000),
                    Color(0xB3000000),
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fotoğraf yokken kullanılan VEKTÖREL zemin.
///
/// 2026-09'da sıcak kahverengi bir "oda duvarı"ndan, referans masadaki
/// ornamentli koyu mavi yüzeye geçti. Sebep sadece zevk değil: kahverengi
/// duvar, üstündeki ahşap ıstakayla ve altın düğmelerle aynı renk
/// ailesindeydi; masadaki her şey birbirine karışıyordu. Soğuk mavi zemin,
/// fildişi taşları ve altın düğmeleri en yüksek kontrastla taşır.
class _VectorRoom extends StatelessWidget {
  const _VectorRoom();

  @override
  Widget build(BuildContext context) => const OkeyDamaskBackground();
}
