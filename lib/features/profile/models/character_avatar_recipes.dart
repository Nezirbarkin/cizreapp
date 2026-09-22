// "Kız & Erkek" hazır avatarlarının tarifleri.
//
// Her satır, `assets/avatars_characters/avatar_char_NN.png` dosyasının NN'inci
// karakterini üreten [FaceAvatarConfig]'tir. PNG'ler bu tariflerden, yüzünden
// avatar üreten aynı gerçekçi çizim motoruyla üretilir:
//
//   $env:GEN_CHARACTER_AVATARS='1'; flutter test test/tools/generate_character_avatars_test.dart
//   python scripts/finalize_character_avatars.py
//
// APPEND-ONLY: kullanıcıların seçtiği avatar dosya adına bağlı olduğundan sıra
// değişmez, araya ekleme yapılmaz; yeni karakter yalnızca listenin SONUNA eklenir.
// (Aynı satırın görünümünü iyileştirmek serbest — kimlik/cinsiyet/kavram korunur.)
import 'face_avatar_config.dart';

class CharacterRecipe {
  final bool female;
  final FaceAvatarConfig config;
  const CharacterRecipe(this.female, this.config);
}

int _i(List<String> labels, String label) {
  final i = labels.indexOf(label);
  assert(i >= 0, 'Katalogda yok: $label');
  return i < 0 ? 0 : i;
}

final List<String> _hairLabels = kHairStyles.map((e) => e.label).toList();
final List<String> _beardLabels = kBeardStyles.map((e) => e.label).toList();
final List<String> _glassesLabels = kGlassesStyles.map((e) => e.label).toList();
final List<String> _headLabels = kHeadwearStyles.map((e) => e.label).toList();
final List<String> _jewelLabels = kJewelryStyles.map((e) => e.label).toList();
final List<String> _detailLabels = kDetailStyles.map((e) => e.label).toList();

/// Eski 6'lı ten paletinin yeni 14'lü palete karşılığı.
const List<int> _oldSkin = [2, 3, 5, 7, 9, 11];

/// Eski 10'lu arka plan paletinin yeni arka planlara karşılığı.
const List<int> _oldBg = [2, 9, 1, 8, 10, 4, 12, 5, 7, 3];

CharacterRecipe _c(
  bool female,
  String hair,
  int hairColor,
  int skin, {
  int face = 0,
  int eye = 0,
  int eyeColor = 2,
  int brow = 1,
  int lash = 1,
  int nose = 0,
  int lips = 0,
  int lipColor = 0,
  String beard = 'Yok',
  String glasses = 'Yok',
  String headwear = 'Yok',
  String jewelry = 'Yok',
  String detail = 'Yok',
  int age = 0,
  int cloth = 0,
  int clothColor = 0,
  int bg = 0,
  double smile = 0.45,
}) {
  return CharacterRecipe(
    female,
    FaceAvatarConfig(
      faceShape: face,
      skinTone: kSkinTones[skin],
      hair: _i(_hairLabels, hair),
      hairColor: kHairColors[hairColor],
      brow: brow,
      eye: eye,
      eyeColor: kEyeColors[eyeColor],
      lash: lash,
      nose: nose,
      lips: lips,
      lipColor: lipColor,
      beard: _i(_beardLabels, beard),
      glasses: _i(_glassesLabels, glasses),
      headwear: _i(_headLabels, headwear),
      jewelry: _i(_jewelLabels, jewelry),
      detail: _i(_detailLabels, detail),
      age: age,
      clothing: cloth,
      clothingColor: kClothingColors[clothColor],
      background: bg,
      metrics: FaceMetrics(smile: smile),
    ),
  );
}

// Kısayollar: eski tarifler (ten/arka plan indeksleri eski paletten gelir).
CharacterRecipe _m(String hair, int hc, int oldSkin, int oldBg, {int face = 0, int eye = 0, int eyeColor = 2, int brow = 2, int nose = 0, int lips = 0, String beard = 'Yok', String glasses = 'Yok', String headwear = 'Yok', String jewelry = 'Yok', String detail = 'Yok', int age = 0, int cloth = 0, int clothColor = 1, double smile = 0.45}) =>
    _c(false, hair, hc, _oldSkin[oldSkin], face: face, eye: eye, eyeColor: eyeColor, brow: brow, lash: 1, nose: nose, lips: lips, beard: beard, glasses: glasses, headwear: headwear, jewelry: jewelry, detail: detail, age: age, cloth: cloth, clothColor: clothColor, bg: _oldBg[oldBg], smile: smile);

CharacterRecipe _f(String hair, int hc, int oldSkin, int oldBg, {int face = 3, int eye = 2, int eyeColor = 2, int brow = 5, int lash = 2, int nose = 7, int lips = 2, int lipColor = 0, String glasses = 'Yok', String headwear = 'Yok', String jewelry = 'Yok', String detail = 'Yok', int age = 0, int cloth = 9, int clothColor = 13, double smile = 0.55}) =>
    _c(true, hair, hc, _oldSkin[oldSkin], face: face, eye: eye, eyeColor: eyeColor, brow: brow, lash: lash, nose: nose, lips: lips, lipColor: lipColor, glasses: glasses, headwear: headwear, jewelry: jewelry, detail: detail, age: age, cloth: cloth, clothColor: clothColor, bg: _oldBg[oldBg], smile: smile);

/// 100 karakter: 50 erkek + 50 kadın. Sıra = dosya numarası (1'den başlar).
final List<CharacterRecipe> kCharacterRecipes = [
  // ------------------------------------------------ 1-12: erkek (orijinal set)
  _m('Kısa', 2, 0, 0, face: 10, eye: 0, brow: 1, nose: 0, cloth: 0, clothColor: 1, eyeColor: 2),
  _m('Kirpi', 0, 1, 3, face: 2, eye: 1, eyeColor: 8, brow: 2, nose: 8, cloth: 4, clothColor: 3, smile: 0.62),
  _m('Yana Ayrık', 4, 0, 1, face: 0, eye: 3, brow: 1, nose: 1, glasses: 'İnce Çerçeve', cloth: 3, clothColor: 8, eyeColor: 3),
  _m('Kısa', 0, 3, 5, face: 8, eye: 10, brow: 3, nose: 3, beard: 'Tam Sakal', cloth: 2, clothColor: 9, eyeColor: 1, lips: 9),
  _m('Kısa Kıvırcık', 0, 4, 6, face: 1, eye: 4, brow: 2, nose: 3, lips: 2, cloth: 0, clothColor: 11, eyeColor: 0, smile: 0.7),
  _m('Kısa', 2, 1, 2, face: 0, eye: 0, brow: 1, nose: 0, headwear: 'Kasket', cloth: 11, clothColor: 7, eyeColor: 8, smile: 0.5),
  _m('Kirpi', 8, 0, 4, face: 10, eye: 1, brow: 1, nose: 2, cloth: 0, clothColor: 13, eyeColor: 8, smile: 0.7),
  _m('Kısa', 12, 1, 7, face: 0, eye: 0, brow: 1, nose: 2, detail: 'Çok Çil', cloth: 4, clothColor: 4, eyeColor: 6, smile: 0.65),
  _m('Yana Ayrık', 0, 2, 0, face: 2, eye: 7, brow: 2, nose: 1, lips: 9, cloth: 6, clothColor: 0, eyeColor: 1),
  _m('Kısa', 13, 0, 3, face: 8, eye: 17, brow: 12, nose: 8, glasses: 'Yuvarlak', age: 2, cloth: 10, clothColor: 12, eyeColor: 11, lips: 9),
  _m('Kısa Kıvırcık', 4, 2, 5, face: 10, eye: 0, brow: 2, nose: 0, beard: 'Kısa Sakal', cloth: 2, clothColor: 8, eyeColor: 3, smile: 0.6),
  _m('Kısa', 0, 3, 6, face: 2, eye: 10, brow: 3, nose: 3, headwear: 'Kep', cloth: 11, clothColor: 6, eyeColor: 0),

  // ------------------------------------------------- 13-24: kadın (orijinal set)
  _f('Uzun Düz', 0, 0, 4, face: 0, eye: 13, lash: 4, brow: 7, lips: 3, cloth: 9, clothColor: 2, eyeColor: 1),
  _f('At Kuyruğu', 4, 1, 0, face: 3, eye: 2, lash: 2, brow: 5, lips: 8, jewelry: 'Altın Küpe', cloth: 1, clothColor: 1, eyeColor: 2, smile: 0.7),
  _f('Topuz', 2, 2, 1, face: 9, eye: 1, lash: 3, brow: 11, lips: 0, cloth: 10, clothColor: 8, eyeColor: 3),
  _f('İki Örgü', 0, 3, 5, face: 1, eye: 4, lash: 2, brow: 5, lips: 8, headwear: 'Fiyonk', cloth: 0, clothColor: 9, eyeColor: 0, smile: 0.72, detail: 'Yumuşak Allık'),
  _f('Bob', 8, 0, 6, face: 5, eye: 0, lash: 1, brow: 7, lips: 3, cloth: 9, clothColor: 11, eyeColor: 8, lipColor: 1),
  _f('Başörtüsü', 12, 1, 2, face: 0, eye: 2, lash: 2, brow: 11, lips: 0, cloth: 0, clothColor: 7, eyeColor: 3, jewelry: 'Yok'),
  _f('Uzun Düz', 8, 0, 3, face: 3, eye: 0, lash: 2, brow: 11, lips: 3, glasses: 'Okuma', cloth: 10, clothColor: 12, eyeColor: 8, smile: 0.5),
  _f('At Kuyruğu', 0, 4, 7, face: 9, eye: 13, lash: 4, brow: 7, lips: 2, cloth: 1, clothColor: 8, eyeColor: 0, smile: 0.66),
  _f('Topuz', 12, 0, 5, face: 1, eye: 2, lash: 2, brow: 11, lips: 8, detail: 'Çil + Allık', cloth: 9, clothColor: 4, eyeColor: 6, smile: 0.7),
  _f('İki Örgü', 4, 2, 4, face: 3, eye: 4, lash: 3, brow: 5, lips: 8, jewelry: 'Halka Küpe', cloth: 4, clothColor: 13, eyeColor: 2, smile: 0.72),
  _f('Bob', 0, 3, 1, face: 5, eye: 1, lash: 4, brow: 19, lips: 2, cloth: 9, clothColor: 0, eyeColor: 1, lipColor: 3),
  _f('Başörtüsü', 2, 2, 6, face: 9, eye: 0, lash: 2, brow: 11, lips: 8, glasses: 'Yuvarlak', cloth: 0, clothColor: 11, eyeColor: 1, smile: 0.5),

  // --------------------------------------- 25-36: erkek (ikinci grup, orijinal)
  _m('Dağınık Kısa', 2, 5, 8, face: 2, eye: 10, brow: 3, nose: 3, cloth: 4, clothColor: 6, eyeColor: 0, lips: 9),
  _m('Kısa', 13, 1, 9, face: 0, eye: 0, brow: 1, nose: 0, headwear: 'Bere', cloth: 10, clothColor: 5, eyeColor: 11),
  _m('Kel', 14, 2, 3, face: 8, eye: 17, brow: 12, nose: 8, glasses: 'Kalın Çerçeve', age: 3, cloth: 10, clothColor: 3, eyeColor: 1, lips: 9, beard: 'Kıvrık Bıyık'),
  _m('Yana Ayrık', 11, 0, 5, face: 0, eye: 3, brow: 2, nose: 0, cloth: 3, clothColor: 4, eyeColor: 6, smile: 0.55),
  _m('Kısa', 0, 5, 2, face: 2, eye: 10, brow: 3, nose: 3, jewelry: 'Küpe + Kolye', cloth: 0, clothColor: 15, eyeColor: 0, smile: 0.5),
  _m('Kirpi', 12, 1, 9, face: 10, eye: 1, brow: 1, nose: 2, detail: 'Çok Çil', cloth: 0, clothColor: 12, eyeColor: 6, smile: 0.72),
  _m('Kısa', 13, 3, 0, face: 8, eye: 17, brow: 12, nose: 1, headwear: 'Kep', cloth: 2, clothColor: 5, eyeColor: 1, lips: 9, age: 1),
  _m('Kısa Kıvırcık', 11, 2, 6, face: 1, eye: 4, brow: 2, nose: 5, cloth: 11, clothColor: 4, eyeColor: 2, smile: 0.7),
  _m('Kısa', 0, 0, 4, face: 10, eye: 7, brow: 2, nose: 1, headwear: 'Bere', beard: 'Kısa Sakal', cloth: 4, clothColor: 6, eyeColor: 1),
  _m('Dağınık Kısa', 4, 1, 7, face: 0, eye: 0, brow: 1, nose: 0, glasses: 'Yuvarlak', cloth: 0, clothColor: 8, eyeColor: 2, smile: 0.6),
  _m('Kel', 2, 4, 1, face: 2, eye: 10, brow: 3, nose: 3, cloth: 5, clothColor: 6, eyeColor: 0, lips: 9),
  _m('Yana Ayrık', 0, 5, 3, face: 8, eye: 7, brow: 2, nose: 1, beard: 'Tam Sakal', cloth: 6, clothColor: 0, eyeColor: 0, lips: 9),

  // ---------------------------------------- 37-49: kadın (ikinci grup, orijinal)
  _f('Uzun Dalgalı', 8, 0, 4, face: 3, eye: 2, lash: 2, brow: 11, lips: 3, cloth: 9, clothColor: 13, eyeColor: 8, smile: 0.6),
  _f('Yarım Topuz', 4, 1, 5, face: 9, eye: 13, lash: 4, brow: 7, lips: 8, jewelry: 'Altın Küpe', cloth: 10, clothColor: 4, eyeColor: 3, smile: 0.68),
  _f('Yan Örgü', 0, 2, 6, face: 0, eye: 4, lash: 3, brow: 5, lips: 2, cloth: 1, clothColor: 11, eyeColor: 0, smile: 0.7),
  _f('Dağınık Orta', 12, 0, 8, face: 1, eye: 2, lash: 1, brow: 11, lips: 8, detail: 'Çok Çil', cloth: 0, clothColor: 7, eyeColor: 6, smile: 0.75),
  _f('Kısa Bob', 14, 3, 2, face: 5, eye: 0, lash: 2, brow: 7, lips: 3, headwear: 'Bere', cloth: 10, clothColor: 14, eyeColor: 10, age: 1),
  _f('Başörtüsü', 11, 4, 9, face: 9, eye: 1, lash: 2, brow: 11, lips: 8, glasses: 'İnce Çerçeve', cloth: 0, clothColor: 12, eyeColor: 0, smile: 0.55),
  _f('Uzun Dalgalı', 2, 5, 1, face: 3, eye: 13, lash: 4, brow: 19, lips: 2, jewelry: 'Küpe + Kolye', cloth: 1, clothColor: 8, eyeColor: 0, smile: 0.62),
  _f('Yarım Topuz', 13, 2, 7, face: 0, eye: 0, lash: 1, brow: 11, lips: 8, cloth: 10, clothColor: 10, eyeColor: 11, age: 2, glasses: 'Okuma', smile: 0.5),
  _f('At Kuyruğu', 11, 0, 9, face: 9, eye: 2, lash: 2, brow: 5, lips: 8, headwear: 'Saç Bandı', cloth: 4, clothColor: 6, eyeColor: 6, smile: 0.75),
  _f('Bob', 14, 1, 3, face: 3, eye: 4, lash: 2, brow: 19, lips: 3, headwear: 'Fiyonk', cloth: 9, clothColor: 13, eyeColor: 8, smile: 0.6, age: 1),
  _f('Yan Örgü', 4, 3, 0, face: 0, eye: 2, lash: 3, brow: 5, lips: 8, headwear: 'Saç Bandı', cloth: 10, clothColor: 3, eyeColor: 2, smile: 0.7),
  _f('Topuz', 0, 5, 8, face: 9, eye: 13, lash: 4, brow: 7, lips: 2, jewelry: 'Halka Küpe', cloth: 1, clothColor: 2, eyeColor: 0, smile: 0.58),
  _f('Uzun Dalgalı', 12, 2, 5, face: 5, eye: 0, lash: 2, brow: 11, lips: 3, cloth: 9, clothColor: 7, eyeColor: 6, smile: 0.66),

  // ================================================= 50-100: yeni (51 karakter)
  // ---- erkek (26)
  _c(false, 'Fade Kısa', 0, 8, face: 2, eye: 0, eyeColor: 1, brow: 2, lash: 1, nose: 3, lips: 0, beard: 'Kısa Sakal', cloth: 4, clothColor: 6, bg: 6, smile: 0.5),
  _c(false, 'Skin Fade Tepe', 0, 10, face: 10, eye: 1, eyeColor: 0, brow: 3, lash: 1, nose: 9, lips: 2, beard: 'Kutu Sakal', jewelry: 'Gümüş Küpe', cloth: 0, clothColor: 10, bg: 13, smile: 0.62),
  _c(false, 'Pompadur', 1, 3, face: 8, eye: 7, eyeColor: 1, brow: 2, lash: 1, nose: 8, lips: 9, beard: 'Van Dyke', cloth: 6, clothColor: 15, bg: 6),
  _c(false, 'Quiff', 5, 2, face: 0, eye: 0, eyeColor: 8, brow: 1, lash: 1, nose: 0, lips: 8, cloth: 3, clothColor: 1, bg: 2, smile: 0.7),
  _c(false, 'Undercut', 0, 4, face: 10, eye: 1, eyeColor: 2, brow: 2, lash: 1, nose: 6, lips: 0, beard: 'Çene Hattı', cloth: 11, clothColor: 6, bg: 11),
  _c(false, 'Arkaya Taralı', 12, 5, face: 8, eye: 0, eyeColor: 9, brow: 2, lash: 1, nose: 1, lips: 0, beard: 'Tam Sakal', glasses: 'Wayfarer', cloth: 6, clothColor: 0, bg: 0, age: 1),
  _c(false, 'Afro', 0, 11, face: 1, eye: 4, eyeColor: 0, brow: 2, lash: 1, nose: 3, lips: 2, glasses: 'Yuvarlak Güneş', cloth: 4, clothColor: 8, bg: 9, smile: 0.7),
  _c(false, 'Bukle Fade', 0, 9, face: 10, eye: 1, eyeColor: 1, brow: 3, lash: 1, nose: 5, lips: 2, beard: 'Üç Günlük', cloth: 0, clothColor: 12, bg: 3, smile: 0.6),
  _c(false, 'Yüksek Tepe', 0, 12, face: 2, eye: 10, eyeColor: 0, brow: 3, lash: 1, nose: 3, lips: 9, jewelry: 'Altın Küpe', cloth: 4, clothColor: 4, bg: 10),
  _c(false, 'Sıkı Bukle', 0, 10, face: 8, eye: 7, eyeColor: 0, brow: 18, lash: 1, nose: 9, lips: 0, beard: 'Keçi', cloth: 2, clothColor: 9, bg: 8, smile: 0.5),
  _c(false, 'Rasta', 0, 11, face: 10, eye: 17, eyeColor: 0, brow: 2, lash: 1, nose: 3, lips: 2, cloth: 0, clothColor: 12, bg: 3, smile: 0.66),
  _c(false, 'Kutu Örgü', 1, 12, face: 2, eye: 0, eyeColor: 0, brow: 3, lash: 1, nose: 3, lips: 0, beard: 'Çene Şeridi', cloth: 5, clothColor: 6, bg: 6),
  _c(false, 'Erkek Topuz', 2, 3, face: 8, eye: 12, eyeColor: 1, brow: 6, lash: 1, nose: 0, lips: 0, beard: 'Tam Sakal', cloth: 3, clothColor: 4, bg: 5),
  _c(false, 'Uzun Erkek', 4, 2, face: 4, eye: 8, eyeColor: 3, brow: 1, lash: 1, nose: 1, lips: 0, beard: 'Uzun Sakal', cloth: 10, clothColor: 12, bg: 3, age: 1),
  _c(false, 'Uzun Dağınık Erkek', 6, 1, face: 0, eye: 16, eyeColor: 6, brow: 1, lash: 1, nose: 0, lips: 8, beard: 'Hafif', cloth: 3, clothColor: 5, bg: 12, smile: 0.62),
  _c(false, 'Mullet', 3, 3, face: 10, eye: 0, eyeColor: 2, brow: 2, lash: 1, nose: 6, lips: 0, cloth: 11, clothColor: 7, bg: 7),
  _c(false, 'Orta Dalgalı', 5, 4, face: 0, eye: 1, eyeColor: 3, brow: 1, lash: 1, nose: 0, lips: 8, cloth: 0, clothColor: 11, bg: 12, smile: 0.7, detail: 'Güneş Yanığı'),
  _c(false, 'Perde Saç', 3, 1, face: 4, eye: 15, eyeColor: 2, brow: 16, lash: 1, nose: 8, lips: 9, glasses: 'Harry', cloth: 10, clothColor: 10, bg: 0),
  _c(false, 'Asker', 1, 6, face: 2, eye: 3, eyeColor: 1, brow: 4, lash: 1, nose: 3, lips: 9, beard: 'Yoğun Üç Günlük', cloth: 11, clothColor: 12, bg: 11),
  _c(false, 'Sıfır Tıraş', 0, 8, face: 8, eye: 7, eyeColor: 0, brow: 3, lash: 1, nose: 9, lips: 0, beard: 'Uzun Sakal', cloth: 4, clothColor: 15, bg: 6, age: 1),
  _c(false, 'Kısa', 14, 2, face: 8, eye: 17, eyeColor: 8, brow: 12, lash: 1, nose: 1, lips: 9, beard: 'Tam Sakal', glasses: 'Yarım Çerçeve', cloth: 7, clothColor: 0, bg: 0, age: 3),
  _c(false, 'Kel', 13, 7, face: 8, eye: 10, eyeColor: 1, brow: 12, lash: 1, nose: 8, lips: 9, beard: 'Kıvrık Bıyık', glasses: 'İnce Çerçeve', cloth: 6, clothColor: 4, bg: 5, age: 3),
  _c(false, 'Geri Çekilmiş', 13, 3, face: 10, eye: 17, eyeColor: 2, brow: 12, lash: 1, nose: 1, lips: 9, beard: 'Mors Bıyık', cloth: 2, clothColor: 1, bg: 2, age: 2),
  _c(false, 'Yandan Taraklı', 0, 5, face: 0, eye: 0, eyeColor: 1, brow: 2, lash: 1, nose: 0, lips: 0, headwear: 'Fötr Şapka', beard: 'İnce Bıyık', cloth: 7, clothColor: 6, bg: 13),
  _c(false, 'Dağınık Kısa', 8, 1, face: 0, eye: 0, eyeColor: 8, brow: 1, lash: 1, nose: 2, lips: 8, headwear: 'Ters Kep', cloth: 0, clothColor: 13, bg: 4, smile: 0.75),
  _c(false, 'Yana Ayrık Sol', 7, 0, face: 10, eye: 1, eyeColor: 9, brow: 1, lash: 1, nose: 0, lips: 0, headwear: 'Kulaklık', cloth: 4, clothColor: 2, bg: 1, smile: 0.6),

  // ---- kadın (25)
  _c(true, 'Pixie', 8, 0, face: 5, eye: 2, eyeColor: 8, brow: 7, lash: 4, nose: 7, lips: 3, lipColor: 3, jewelry: 'İnci Küpe', cloth: 1, clothColor: 0, bg: 4, smile: 0.5),
  _c(true, 'Wolf Cut', 3, 2, face: 9, eye: 13, eyeColor: 3, brow: 11, lash: 9, nose: 2, lips: 3, cloth: 11, clothColor: 6, bg: 13, smile: 0.5),
  _c(true, 'Shag', 12, 0, face: 3, eye: 0, eyeColor: 6, brow: 5, lash: 2, nose: 7, lips: 8, detail: 'Çil + Allık', cloth: 10, clothColor: 4, bg: 7, smile: 0.72),
  _c(true, 'Çok Uzun Düz', 0, 8, face: 0, eye: 13, eyeColor: 0, brow: 7, lash: 8, nose: 4, lips: 3, lipColor: 3, jewelry: 'Büyük Halka', cloth: 9, clothColor: 15, bg: 6, smile: 0.5),
  _c(true, 'Plaj Dalgası', 9, 1, face: 3, eye: 2, eyeColor: 9, brow: 11, lash: 2, nose: 2, lips: 8, cloth: 9, clothColor: 14, bg: 12, smile: 0.78),
  _c(true, 'Hollywood Dalga', 12, 0, face: 0, eye: 0, eyeColor: 8, brow: 19, lash: 8, nose: 4, lips: 3, lipColor: 3, jewelry: 'Sarkık Küpe', cloth: 9, clothColor: 15, bg: 13, smile: 0.4),
  _c(true, 'Perde Kâkül', 4, 3, face: 9, eye: 1, eyeColor: 1, brow: 11, lash: 2, nose: 7, lips: 2, cloth: 10, clothColor: 4, bg: 5, smile: 0.5),
  _c(true, 'Kâkül Uzun', 0, 0, face: 1, eye: 12, eyeColor: 0, brow: 0, lash: 3, nose: 7, lips: 8, cloth: 0, clothColor: 13, bg: 10, smile: 0.62),
  _c(true, 'Yan Ayrım Uzun', 5, 5, face: 3, eye: 2, eyeColor: 3, brow: 7, lash: 2, nose: 2, lips: 7, headwear: 'Saç Bandı', cloth: 1, clothColor: 12, bg: 8, smile: 0.66),
  _c(true, 'Afro Kabarık', 0, 11, face: 1, eye: 2, eyeColor: 0, brow: 5, lash: 3, nose: 9, lips: 2, lipColor: 4, jewelry: 'Büyük Halka', cloth: 9, clothColor: 8, bg: 9, smile: 0.72),
  _c(true, 'Afro Topuzlar', 0, 10, face: 3, eye: 4, eyeColor: 0, brow: 11, lash: 2, nose: 7, lips: 8, cloth: 4, clothColor: 13, bg: 4, smile: 0.78),
  _c(true, 'Sıkı Bukle Uzun', 1, 12, face: 5, eye: 13, eyeColor: 0, brow: 7, lash: 4, nose: 9, lips: 2, jewelry: 'Altın Küpe', cloth: 1, clothColor: 6, bg: 6, smile: 0.5),
  _c(true, 'Kutu Örgü', 0, 11, face: 9, eye: 2, eyeColor: 0, brow: 19, lash: 3, nose: 9, lips: 3, lipColor: 8, cloth: 9, clothColor: 15, bg: 8, smile: 0.66),
  _c(true, 'Kaba Örgü', 1, 9, face: 0, eye: 1, eyeColor: 0, brow: 7, lash: 2, nose: 9, lips: 2, jewelry: 'Halka Küpe', cloth: 10, clothColor: 4, bg: 9, smile: 0.5),
  _c(true, 'Balık Kılçığı', 6, 2, face: 3, eye: 0, eyeColor: 6, brow: 11, lash: 2, nose: 7, lips: 8, cloth: 9, clothColor: 11, bg: 12, smile: 0.7),
  _c(true, 'Taç Örgü', 8, 0, face: 0, eye: 2, eyeColor: 8, brow: 5, lash: 2, nose: 7, lips: 3, headwear: 'Çiçek Tacı', cloth: 9, clothColor: 13, bg: 10, smile: 0.66),
  _c(true, 'Uzay Topuzları', 15, 1, face: 3, eye: 4, eyeColor: 8, brow: 5, lash: 3, nose: 7, lips: 8, cloth: 4, clothColor: 9, bg: 4, smile: 0.78),
  _c(true, 'Balerin Topuz', 0, 2, face: 9, eye: 13, eyeColor: 1, brow: 19, lash: 8, nose: 4, lips: 3, jewelry: 'İnci Küpe', cloth: 8, clothColor: 15, bg: 13, smile: 0.35),
  _c(true, 'Dağınık Topuz', 3, 1, face: 0, eye: 0, eyeColor: 2, brow: 1, lash: 1, nose: 2, lips: 0, glasses: 'Harry', cloth: 10, clothColor: 10, bg: 5, smile: 0.62),
  _c(true, 'Yüksek Topuz', 7, 0, face: 5, eye: 2, eyeColor: 9, brow: 7, lash: 4, nose: 7, lips: 2, jewelry: 'Mavi Taş', cloth: 1, clothColor: 1, bg: 2, smile: 0.6),
  _c(true, 'Kâküllü Kuyruk', 11, 0, face: 1, eye: 4, eyeColor: 6, brow: 5, lash: 2, nose: 2, lips: 8, detail: 'Çok Çil', cloth: 0, clothColor: 7, bg: 1, smile: 0.78),
  _c(true, 'Yan Kuyruk', 2, 4, face: 0, eye: 1, eyeColor: 1, brow: 11, lash: 2, nose: 0, lips: 3, jewelry: 'Gümüş Halka', cloth: 9, clothColor: 12, bg: 3, smile: 0.66),
  _c(true, 'Sarma Başörtü', 4, 1, face: 3, eye: 2, eyeColor: 2, brow: 11, lash: 2, nose: 7, lips: 8, detail: 'Yumuşak Allık', cloth: 0, clothColor: 14, bg: 8, smile: 0.7),
  _c(true, 'Türban', 0, 6, face: 5, eye: 13, eyeColor: 0, brow: 7, lash: 4, nose: 9, lips: 2, lipColor: 3, jewelry: 'Büyük Halka', cloth: 9, clothColor: 8, bg: 9, smile: 0.55),
  _c(true, 'Fularlı', 13, 3, face: 0, eye: 0, eyeColor: 10, brow: 11, lash: 1, nose: 0, lips: 0, glasses: 'Okuma', age: 3, cloth: 10, clothColor: 5, bg: 5, smile: 0.5),
];

/// Karakter avatarının kız mı olduğu (seçicideki filtre için).
bool isFemaleCharacter(int index) => kCharacterRecipes[index].female;
