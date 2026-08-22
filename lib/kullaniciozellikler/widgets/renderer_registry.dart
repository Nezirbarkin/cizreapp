// Renderer kayıt defteri.
//
// SORUN: bir dekorasyonun `renderer_key`'i üç ayrı `switch` içinde ayrı ayrı
// ele alınıyordu — önizleme (profile_feature_preview.dart), avatar
// (privileged_avatar.dart) ve kapak (cover_effect_frame.dart). Yeni bir efekt
// eklemek üç dosyaya birbirinin kopyası `case` yazmak demekti; biri unutulunca
// efekt bazı yerlerde çiziliyor bazılarında çizilmiyordu.
//
// ÇÖZÜM: yeni çizerler burada TEK yerde kaydedilir. Üç dağıtım noktası da
// kendi switch'inde eşleşme bulamazsa bu deftere düşer. Mevcut (eski) key'ler
// switch'lerde kaldığı için davranışları değişmez — defter yalnız additif.

import 'package:flutter/material.dart';

import 'seasonal_painters.dart';

/// Yüzeyi (fotoğraf/kapak) baştan sona kaplayan çizerler.
typedef SurfaceRenderer =
    void Function({
      required Canvas canvas,
      required Size size,
      required double progress,
      required Color primaryColor,
      required Color secondaryColor,
    });

/// Avatar halkası üzerine çizen çerçeve çizerleri.
typedef FrameRenderer =
    void Function({
      required Canvas canvas,
      required Offset center,
      required double radius,
      required double progress,
      required Color primaryColor,
      required Color secondaryColor,
    });

/// `renderer_key` -> yüzey çizeri.
const Map<String, SurfaceRenderer> kSurfaceRenderers = {
  'photo_hail_storm': paintPhotoHailStorm,
  'photo_ant_march': paintPhotoAntMarch,
  'photo_cherry_blossom': paintPhotoCherryBlossom,
  'photo_autumn_leaves': paintPhotoAutumnLeaves,
  'photo_meteor_shower': paintPhotoMeteorShower,
  'photo_star_rain': paintPhotoStarRain,
  'photo_soap_foam': paintPhotoSoapFoam,
};

/// `renderer_key` -> avatar çerçeve çizeri.
const Map<String, FrameRenderer> kFrameRenderers = {
  'frame_ant_trail': paintAntTrailFrame,
  'frame_gear_rotate': paintGearFrame,
  'frame_laurel_wreath': paintLaurelWreathFrame,
  'frame_chain_links': paintChainFrame,
  'frame_music_notes': paintMusicNoteFrame,
  'frame_paw_prints': paintPawPrintFrame,
  'frame_lightning_arc': paintLightningArcFrame,
  'frame_vine_grow': paintVineGrowFrame,
};

/// Defterdeki bir yüzey çizerini uygular; key kayıtlı değilse `false` döner.
bool tryPaintSurface({
  required String rendererKey,
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final renderer = kSurfaceRenderers[rendererKey];
  if (renderer == null) return false;
  renderer(
    canvas: canvas,
    size: size,
    progress: progress,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
  );
  return true;
}

/// Defterdeki bir çerçeve çizerini uygular; key kayıtlı değilse `false` döner.
bool tryPaintFrame({
  required String rendererKey,
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final renderer = kFrameRenderers[rendererKey];
  if (renderer == null) return false;
  renderer(
    canvas: canvas,
    center: center,
    radius: radius,
    progress: progress,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
  );
  return true;
}

/// Bir `renderer_key` bu defterde tanımlı mı (herhangi bir şekilde)?
bool isRegisteredRenderer(String rendererKey) =>
    kSurfaceRenderers.containsKey(rendererKey) ||
    kFrameRenderers.containsKey(rendererKey);
