import 'package:flutter/material.dart';

import '../models/character_avatar_recipes.dart';

/// Uygulamayla birlikte gelen hazır profil avatarları.
///
/// Kullanıcı kendi fotoğrafını yüklemek istemediğinde bunlardan birini seçer;
/// seçilen görsel kaydederken `avatars` bucket'ına yüklenip normal bir
/// avatar_url gibi saklanır (böylece tüm ekranlar değişmeden çalışır).
///
/// Listeler dosya adına göre KURULUR (elle yazılmaz): dosya numarası = üretici
/// betiklerdeki sıra. Kullanıcıların seçtiği avatar dosya adına bağlı olduğu
/// için numaralar asla kaydırılmaz; yeni avatar yalnızca sona eklenir.

/// Klasik (modern düz illüstrasyon) avatar sayısı.
/// Üretici: `scripts/generate_classic_avatars.py`.
const int kClassicAvatarCount = 20;

/// Hareketli (GIF) avatar sayısı. 01-55: `generate_animated_avatars.py`
/// (geometrik), 56-79: `generate_elegant_animated_avatars.py` (şık sahneler
/// ve göz kırpan portreler).
const int kAnimatedAvatarCount = 79;

/// Bu numaradan (dahil) sonrakiler "şık" sette; sekmede öne alınır.
const int kElegantAnimatedFirst = 56;

/// Kız & erkek karakter sayısı (50 erkek + 50 kadın). Tarifler:
/// `character_avatar_recipes.dart`.
const int kCharacterAvatarCount = 100;

String _two(int n) => n.toString().padLeft(2, '0');

/// Klasik avatarlar — modern düz illüstrasyon (kep, bere, gözlük, başörtüsü,
/// kulaklık, kedi kulağı, robot…).
final List<String> kPresetAvatars = List<String>.unmodifiable(<String>[
  for (var i = 1; i <= kClassicAvatarCount; i++) 'assets/avatars/avatar_${_two(i)}.png',
]);

/// Hareketli (animasyonlu GIF) hazır avatarlar.
///
/// NEDEN GIF: Seçilen avatar, kaydederken storage'a yüklenip sıradan bir
/// avatar_url olarak saklanıyor. GIF sayesinde avatarı gösteren HİÇBİR ekranı
/// değiştirmek gerekmedi — CachedNetworkImage/Image.network animasyonlu GIF'i
/// zaten oynatıyor. (Lottie/SVG seçilseydi feed, yorumlar, sohbet, admin...
/// hepsinde ayrı bir oynatıcı gerekirdi.)
final List<String> kAnimatedAvatars = List<String>.unmodifiable(<String>[
  for (var i = 1; i <= kAnimatedAvatarCount; i++) 'assets/avatars_animated/avatar_anim_${_two(i)}.gif',
]);

/// Kız / erkek karakter avatarları: yüzünden avatar oluşturan aynı gerçekçi
/// çizim motoruyla üretilir (gerçekçi ten/göz/saç/sakal). Cinsiyet bilgisi
/// tariflerde tutulur ([isFemaleCharacter]).
final List<String> kCharacterAvatars = List<String>.unmodifiable(<String>[
  for (var i = 1; i <= kCharacterAvatarCount; i++)
    'assets/avatars_characters/avatar_char_${_two(i)}.png',
]);

/// Seçiciye giren tüm hazır avatarlar (sekme sırasıyla).
final List<String> kAllPresetAvatars = List<String>.unmodifiable(<String>[
  ...kCharacterAvatars,
  ...kAnimatedAvatars,
  ...kPresetAvatars,
]);

/// Verilen asset yolu hareketli (GIF) avatar mı?
bool isAnimatedAvatarAsset(String assetPath) => assetPath.toLowerCase().endsWith('.gif');

/// Hazır avatar seçme sayfasını açar. Seçim yapılırsa asset yolunu,
/// vazgeçilirse null döner.
Future<String?> showPresetAvatarPicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PresetAvatarSheet(selected: selected),
  );
}

enum _CharacterFilter { all, male, female }

enum _AnimatedFilter { all, elegant, classic }

class _PresetAvatarSheet extends StatefulWidget {
  const _PresetAvatarSheet({this.selected});

  final String? selected;

  @override
  State<_PresetAvatarSheet> createState() => _PresetAvatarSheetState();
}

class _PresetAvatarSheetState extends State<_PresetAvatarSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late String? _selected = widget.selected;
  _CharacterFilter _characterFilter = _CharacterFilter.all;
  _AnimatedFilter _animatedFilter = _AnimatedFilter.all;

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
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<String> get _characters {
    switch (_characterFilter) {
      case _CharacterFilter.all:
        return kCharacterAvatars;
      case _CharacterFilter.male:
        return [
          for (var i = 0; i < kCharacterAvatars.length; i++)
            if (!isFemaleCharacter(i)) kCharacterAvatars[i],
        ];
      case _CharacterFilter.female:
        return [
          for (var i = 0; i < kCharacterAvatars.length; i++)
            if (isFemaleCharacter(i)) kCharacterAvatars[i],
        ];
    }
  }

  List<String> get _animated {
    final classic = kAnimatedAvatars.sublist(0, kElegantAnimatedFirst - 1);
    final elegant = kAnimatedAvatars.sublist(kElegantAnimatedFirst - 1);
    switch (_animatedFilter) {
      case _AnimatedFilter.all:
        return [...elegant, ...classic]; // şıklar önde
      case _AnimatedFilter.elegant:
        return elegant;
      case _AnimatedFilter.classic:
        return classic;
    }
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
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kendi fotoğrafını yüklemek istemiyorsan birini seç',
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
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
                    _tab(
                      chips: _filterChips<_CharacterFilter>(
                        values: _CharacterFilter.values,
                        current: _characterFilter,
                        labelOf: (f) => switch (f) {
                          _CharacterFilter.all => 'Hepsi',
                          _CharacterFilter.male => 'Erkek',
                          _CharacterFilter.female => 'Kadın',
                        },
                        onPick: (f) => setState(() => _characterFilter = f),
                      ),
                      assets: _characters,
                      controller: scrollController,
                      tabKey: 'char-${_characterFilter.name}',
                    ),
                    _tab(
                      chips: _filterChips<_AnimatedFilter>(
                        values: _AnimatedFilter.values,
                        current: _animatedFilter,
                        labelOf: (f) => switch (f) {
                          _AnimatedFilter.all => 'Hepsi',
                          _AnimatedFilter.elegant => 'Şık & Portre (${kAnimatedAvatarCount - kElegantAnimatedFirst + 1})',
                          _AnimatedFilter.classic => 'Geometrik',
                        },
                        onPick: (f) => setState(() => _animatedFilter = f),
                      ),
                      assets: _animated,
                      controller: null,
                      tabKey: 'anim-${_animatedFilter.name}',
                    ),
                    _tab(chips: null, assets: kPresetAvatars, controller: null, tabKey: 'classic'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChips<T>({
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required void Function(T) onPick,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final v = values[i];
          final selected = v == current;
          return ChoiceChip(
            label: Text(
              labelOf(v),
              style: TextStyle(fontSize: 12, color: selected ? Colors.white : Theme.of(context).hintColor),
            ),
            selected: selected,
            showCheckmark: false,
            selectedColor: primaryColor,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onPick(v),
          );
        },
      ),
    );
  }

  Widget _tab({
    required Widget? chips,
    required List<String> assets,
    required ScrollController? controller,
    required String tabKey,
  }) {
    return Column(
      key: ValueKey(tabKey),
      children: [
        if (chips != null) chips,
        Expanded(child: _grid(assets, controller)),
      ],
    );
  }

  Widget _grid(List<String> assets, ScrollController? controller) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 720
        ? 6
        : width >= 480
        ? 5
        : 4;

    return GridView.builder(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 24),
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
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
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
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                    ),
                    child: const Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
