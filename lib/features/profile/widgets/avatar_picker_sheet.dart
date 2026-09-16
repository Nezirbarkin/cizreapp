import 'package:flutter/material.dart';

/// Uygulamayla birlikte gelen hazır profil avatarları.
///
/// Kullanıcı kendi fotoğrafını yüklemek istemediğinde bunlardan birini seçer;
/// seçilen görsel kaydederken `avatars` bucket'ına yüklenip normal bir
/// avatar_url gibi saklanır (böylece tüm ekranlar değişmeden çalışır).
const List<String> kPresetAvatars = <String>[
  'assets/avatars/avatar_01.png',
  'assets/avatars/avatar_02.png',
  'assets/avatars/avatar_03.png',
  'assets/avatars/avatar_04.png',
  'assets/avatars/avatar_05.png',
  'assets/avatars/avatar_06.png',
  'assets/avatars/avatar_07.png',
  'assets/avatars/avatar_08.png',
  'assets/avatars/avatar_09.png',
  'assets/avatars/avatar_10.png',
  'assets/avatars/avatar_11.png',
  'assets/avatars/avatar_12.png',
  'assets/avatars/avatar_13.png',
  'assets/avatars/avatar_14.png',
  'assets/avatars/avatar_15.png',
  'assets/avatars/avatar_16.png',
  'assets/avatars/avatar_17.png',
  'assets/avatars/avatar_18.png',
  'assets/avatars/avatar_19.png',
  'assets/avatars/avatar_20.png',
];

/// Hareketli (animasyonlu GIF) hazır avatarlar — 55 adet.
///
/// NEDEN GIF: Seçilen avatar, kaydederken storage'a yüklenip sıradan bir
/// avatar_url olarak saklanıyor. GIF sayesinde avatarı gösteren HİÇBİR ekranı
/// değiştirmek gerekmedi — CachedNetworkImage/Image.network animasyonlu GIF'i
/// zaten oynatıyor. (Lottie/SVG seçilseydi feed, yorumlar, sohbet, admin...
/// hepsinde ayrı bir oynatıcı gerekirdi.)
///
/// İlk 30 tanesi (01-30) orijinal set; 31-55 arası sonradan eklenen 25 yeni
/// animasyon (konfeti, spiral, patlama, parlama, sonsuzluk döngüsü stilleri).
///
/// Dosyalar `scripts/generate_animated_avatars.py` ile üretilir; paleti veya
/// hareketi değiştirmek isteyen o betiği çalıştırmalı.
const List<String> kAnimatedAvatars = <String>[
  'assets/avatars_animated/avatar_anim_01.gif',
  'assets/avatars_animated/avatar_anim_02.gif',
  'assets/avatars_animated/avatar_anim_03.gif',
  'assets/avatars_animated/avatar_anim_04.gif',
  'assets/avatars_animated/avatar_anim_05.gif',
  'assets/avatars_animated/avatar_anim_06.gif',
  'assets/avatars_animated/avatar_anim_07.gif',
  'assets/avatars_animated/avatar_anim_08.gif',
  'assets/avatars_animated/avatar_anim_09.gif',
  'assets/avatars_animated/avatar_anim_10.gif',
  'assets/avatars_animated/avatar_anim_11.gif',
  'assets/avatars_animated/avatar_anim_12.gif',
  'assets/avatars_animated/avatar_anim_13.gif',
  'assets/avatars_animated/avatar_anim_14.gif',
  'assets/avatars_animated/avatar_anim_15.gif',
  'assets/avatars_animated/avatar_anim_16.gif',
  'assets/avatars_animated/avatar_anim_17.gif',
  'assets/avatars_animated/avatar_anim_18.gif',
  'assets/avatars_animated/avatar_anim_19.gif',
  'assets/avatars_animated/avatar_anim_20.gif',
  'assets/avatars_animated/avatar_anim_21.gif',
  'assets/avatars_animated/avatar_anim_22.gif',
  'assets/avatars_animated/avatar_anim_23.gif',
  'assets/avatars_animated/avatar_anim_24.gif',
  'assets/avatars_animated/avatar_anim_25.gif',
  'assets/avatars_animated/avatar_anim_26.gif',
  'assets/avatars_animated/avatar_anim_27.gif',
  'assets/avatars_animated/avatar_anim_28.gif',
  'assets/avatars_animated/avatar_anim_29.gif',
  'assets/avatars_animated/avatar_anim_30.gif',
  'assets/avatars_animated/avatar_anim_31.gif',
  'assets/avatars_animated/avatar_anim_32.gif',
  'assets/avatars_animated/avatar_anim_33.gif',
  'assets/avatars_animated/avatar_anim_34.gif',
  'assets/avatars_animated/avatar_anim_35.gif',
  'assets/avatars_animated/avatar_anim_36.gif',
  'assets/avatars_animated/avatar_anim_37.gif',
  'assets/avatars_animated/avatar_anim_38.gif',
  'assets/avatars_animated/avatar_anim_39.gif',
  'assets/avatars_animated/avatar_anim_40.gif',
  'assets/avatars_animated/avatar_anim_41.gif',
  'assets/avatars_animated/avatar_anim_42.gif',
  'assets/avatars_animated/avatar_anim_43.gif',
  'assets/avatars_animated/avatar_anim_44.gif',
  'assets/avatars_animated/avatar_anim_45.gif',
  'assets/avatars_animated/avatar_anim_46.gif',
  'assets/avatars_animated/avatar_anim_47.gif',
  'assets/avatars_animated/avatar_anim_48.gif',
  'assets/avatars_animated/avatar_anim_49.gif',
  'assets/avatars_animated/avatar_anim_50.gif',
  'assets/avatars_animated/avatar_anim_51.gif',
  'assets/avatars_animated/avatar_anim_52.gif',
  'assets/avatars_animated/avatar_anim_53.gif',
  'assets/avatars_animated/avatar_anim_54.gif',
  'assets/avatars_animated/avatar_anim_55.gif',
];

/// Kız / erkek karakter (bitmoji tarzı) avatarları — 49 adet.
///
/// Klasik set (`kPresetAvatars`) 20 adette sabitlendiği ve eski seçimlerle
/// birebir eşleştiği için yeni karakterler ayrı klasöre + ayrı sekmeye alındı.
/// Dosyalar `scripts/generate_character_avatars.py` ile üretilir; saç/ten/kıyafet
/// paletini değiştirmek isteyen o betiği çalıştırmalı.
///
/// İlk 24'ü (12 erkek + 12 kız) orijinal set. 25-49 arası sonradan eklenen
/// 25 yeni karakter (12 erkek + 13 kız) — yeni saç stilleri (uzun dalgalı,
/// yarım topuz, tek örgü, dağınık, kel, bere) ve yeni aksesuarlar (kolye,
/// saç bandı) ile genişletildi. Ten tonları, saç renkleri ve aksesuarlar:
/// gözlük, sakal, kep, başörtüsü, örgü, topuz, at kuyruğu, küpe, fiyonk...
const List<String> kCharacterAvatars = <String>[
  'assets/avatars_characters/avatar_char_01.png',
  'assets/avatars_characters/avatar_char_02.png',
  'assets/avatars_characters/avatar_char_03.png',
  'assets/avatars_characters/avatar_char_04.png',
  'assets/avatars_characters/avatar_char_05.png',
  'assets/avatars_characters/avatar_char_06.png',
  'assets/avatars_characters/avatar_char_07.png',
  'assets/avatars_characters/avatar_char_08.png',
  'assets/avatars_characters/avatar_char_09.png',
  'assets/avatars_characters/avatar_char_10.png',
  'assets/avatars_characters/avatar_char_11.png',
  'assets/avatars_characters/avatar_char_12.png',
  'assets/avatars_characters/avatar_char_13.png',
  'assets/avatars_characters/avatar_char_14.png',
  'assets/avatars_characters/avatar_char_15.png',
  'assets/avatars_characters/avatar_char_16.png',
  'assets/avatars_characters/avatar_char_17.png',
  'assets/avatars_characters/avatar_char_18.png',
  'assets/avatars_characters/avatar_char_19.png',
  'assets/avatars_characters/avatar_char_20.png',
  'assets/avatars_characters/avatar_char_21.png',
  'assets/avatars_characters/avatar_char_22.png',
  'assets/avatars_characters/avatar_char_23.png',
  'assets/avatars_characters/avatar_char_24.png',
  'assets/avatars_characters/avatar_char_25.png',
  'assets/avatars_characters/avatar_char_26.png',
  'assets/avatars_characters/avatar_char_27.png',
  'assets/avatars_characters/avatar_char_28.png',
  'assets/avatars_characters/avatar_char_29.png',
  'assets/avatars_characters/avatar_char_30.png',
  'assets/avatars_characters/avatar_char_31.png',
  'assets/avatars_characters/avatar_char_32.png',
  'assets/avatars_characters/avatar_char_33.png',
  'assets/avatars_characters/avatar_char_34.png',
  'assets/avatars_characters/avatar_char_35.png',
  'assets/avatars_characters/avatar_char_36.png',
  'assets/avatars_characters/avatar_char_37.png',
  'assets/avatars_characters/avatar_char_38.png',
  'assets/avatars_characters/avatar_char_39.png',
  'assets/avatars_characters/avatar_char_40.png',
  'assets/avatars_characters/avatar_char_41.png',
  'assets/avatars_characters/avatar_char_42.png',
  'assets/avatars_characters/avatar_char_43.png',
  'assets/avatars_characters/avatar_char_44.png',
  'assets/avatars_characters/avatar_char_45.png',
  'assets/avatars_characters/avatar_char_46.png',
  'assets/avatars_characters/avatar_char_47.png',
  'assets/avatars_characters/avatar_char_48.png',
  'assets/avatars_characters/avatar_char_49.png',
];

/// Seçiciye giren tüm hazır avatarlar (sekme sırasıyla).
const List<String> kAllPresetAvatars = <String>[
  ...kCharacterAvatars,
  ...kAnimatedAvatars,
  ...kPresetAvatars,
];

/// Verilen asset yolu hareketli (GIF) avatar mı?
bool isAnimatedAvatarAsset(String assetPath) =>
    assetPath.toLowerCase().endsWith('.gif');

/// Hazır avatar seçme sayfasını açar. Seçim yapılırsa asset yolunu,
/// vazgeçilirse null döner.
Future<String?> showPresetAvatarPicker(
  BuildContext context, {
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PresetAvatarSheet(selected: selected),
  );
}

class _PresetAvatarSheet extends StatefulWidget {
  const _PresetAvatarSheet({this.selected});

  final String? selected;

  @override
  State<_PresetAvatarSheet> createState() => _PresetAvatarSheetState();
}

class _PresetAvatarSheetState extends State<_PresetAvatarSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late String? _selected = widget.selected;

  @override
  void initState() {
    super.initState();
    // Sekmeler: 0 = Kız & Erkek, 1 = Hareketli, 2 = Klasik.
    // Seçili avatar hangi sekmedeyse o sekmeyle açılsın; seçim yoksa yeni
    // karakter avatarları önde.
    int initialIndex = 0;
    if (_selected != null) {
      if (kAnimatedAvatars.contains(_selected)) {
        initialIndex = 1;
      } else if (kPresetAvatars.contains(_selected)) {
        initialIndex = 2;
      }
    }
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Icon(Icons.face_retouching_natural, color: primaryColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hazır Avatar Seç',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kendi fotoğrafını yüklemek istemiyorsan birini seç',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Kapat',
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: theme.hintColor,
                indicatorColor: primaryColor,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                tabs: [
                  Tab(text: 'Kız & Erkek (${kCharacterAvatars.length})'),
                  Tab(text: 'Hareketli (${kAnimatedAvatars.length})'),
                  Tab(text: 'Klasik (${kPresetAvatars.length})'),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Sekmeler arasında geçerken kaydırma konumunun
                    // korunmasını istemiyoruz; her sekme kendi listesini
                    // baştan çizer (DraggableScrollableSheet'in controller'ı
                    // yalnızca ilk sekmeye bağlanabilir).
                    _grid(kCharacterAvatars, scrollController),
                    _grid(kAnimatedAvatars, null),
                    _grid(kPresetAvatars, null),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grid(List<String> assets, ScrollController? controller) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 720
        ? 6
        : width >= 480
        ? 5
        : 4;

    return GridView.builder(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        final isSelected = asset == _selected;

        return InkWell(
          onTap: () {
            setState(() => _selected = asset);
            Navigator.pop(context, asset);
          },
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? primaryColor : theme.dividerColor,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(asset, fit: BoxFit.cover),
                ),
              ),
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
