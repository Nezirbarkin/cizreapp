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

/// Hareketli (GIF) avatarların numara aralığı —
/// `generate_elegant_animated_avatars.py`: 56-67 şık soyut sahneler, 68-79 göz
/// kırpan portreler, 80-91 gerçekçi yeni setten göz kırpan portreler (Görev
/// 2.6). Eski geometrik 01-55 ve klasik düz illüstrasyonlar (Klasik sekmesi)
/// Görev 2.6'da kaldırıldı — dosya numaraları KAYDIRILMADI; daha önce seçenlerin
/// avatarı zaten kendi storage kopyasıdır, etkilenmez.
const int kAnimatedAvatarFirst = 56;
const int kAnimatedAvatarLast = 91;

/// Kız & erkek karakter sayısı (70 erkek + 70 kadın). Tarifler:
/// `character_avatar_recipes.dart`.
const int kCharacterAvatarCount = 140;

/// Bu numaradan (dahil) sonraki karakterler Görev 2.6'nın gerçekçi modern seti;
/// "Hepsi"nde öne alınır, "Yeni" süzgeciyle ayrıca listelenir.
const int kNewCharacterFirst = 101;

String _two(int n) => n.toString().padLeft(2, '0');

/// Hareketli (animasyonlu GIF) hazır avatarlar.
///
/// NEDEN GIF: Seçilen avatar, kaydederken storage'a yüklenip sıradan bir
/// avatar_url olarak saklanıyor. GIF sayesinde avatarı gösteren HİÇBİR ekranı
/// değiştirmek gerekmedi — CachedNetworkImage/Image.network animasyonlu GIF'i
/// zaten oynatıyor. (Lottie/SVG seçilseydi feed, yorumlar, sohbet, admin...
/// hepsinde ayrı bir oynatıcı gerekirdi.)
final List<String> kAnimatedAvatars = List<String>.unmodifiable(<String>[
  for (var i = kAnimatedAvatarFirst; i <= kAnimatedAvatarLast; i++)
    'assets/avatars_animated/avatar_anim_${_two(i)}.gif',
]);

/// Kız / erkek karakter avatarları: yüzünden Bitmoji oluşturan aynı çizim
/// motoruyla (Bitmoji tarzı; 2026-10-06'da yeniden üretildi) çizilir. Cinsiyet bilgisi
/// tariflerde tutulur ([isFemaleCharacter]).
final List<String> kCharacterAvatars = List<String>.unmodifiable(<String>[
  for (var i = 1; i <= kCharacterAvatarCount; i++)
    'assets/avatars_characters/avatar_char_${_two(i)}.png',
]);

/// Seçiciye giren tüm hazır avatarlar (sekme sırasıyla).
final List<String> kAllPresetAvatars = List<String>.unmodifiable(<String>[
  ...kCharacterAvatars,
  ...kAnimatedAvatars,
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

enum _CharacterFilter { all, newest, male, female }

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

  @override
  void initState() {
    super.initState();
    // Sekmeler: 0 = Kız & Erkek, 1 = Hareketli. Seçili avatar hareketliyse o
    // sekmeyle açılır; aksi halde karakterler (yeni set önde).
    final initialIndex = kAnimatedAvatars.contains(_selected) ? 1 : 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<String> get _characters {
    switch (_characterFilter) {
      case _CharacterFilter.all:
        return [
          ...kCharacterAvatars.sublist(kNewCharacterFirst - 1),
          ...kCharacterAvatars.sublist(0, kNewCharacterFirst - 1),
        ];
      case _CharacterFilter.newest:
        return kCharacterAvatars.sublist(kNewCharacterFirst - 1);
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
                          _CharacterFilter.newest =>
                            'Yeni (${kCharacterAvatarCount - kNewCharacterFirst + 1})',
                          _CharacterFilter.male => 'Erkek',
                          _CharacterFilter.female => 'Kadın',
                        },
                        onPick: (f) => setState(() => _characterFilter = f),
                      ),
                      assets: _characters,
                      controller: scrollController,
                      tabKey: 'char-${_characterFilter.name}',
                    ),
                    _tab(chips: null, assets: kAnimatedAvatars, controller: null, tabKey: 'anim'),
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
