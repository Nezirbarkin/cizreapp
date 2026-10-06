import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/profile_background_service.dart';

/// Hazır profil arka planı seçme sayfasını açar (Görev 2.7). Seçim yapılırsa
/// seçilen arka planı, vazgeçilirse null döner.
Future<ProfileBackgroundPreset?> showProfileBackgroundPicker(
  BuildContext context, {
  String? selectedUrl,
  ProfileBackgroundService? service,
}) {
  return showModalBottomSheet<ProfileBackgroundPreset>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProfileBackgroundPickerSheet(
      selectedUrl: selectedUrl,
      service: service ?? ProfileBackgroundService(),
    ),
  );
}

class ProfileBackgroundPickerSheet extends StatefulWidget {
  const ProfileBackgroundPickerSheet({
    super.key,
    required this.service,
    this.selectedUrl,
  });

  final ProfileBackgroundService service;
  final String? selectedUrl;

  @override
  State<ProfileBackgroundPickerSheet> createState() => _ProfileBackgroundPickerSheetState();
}

class _ProfileBackgroundPickerSheetState extends State<ProfileBackgroundPickerSheet> {
  late Future<List<ProfileBackgroundPreset>> _future = widget.service.fetchPresets();

  /// null = tüm temalar.
  String? _category;

  void _retry() {
    setState(() => _future = widget.service.fetchPresets(forceRefresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
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
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.wallpaper_outlined, color: primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hazır Arka Plan Seç',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Profil kapağın için bir arka plan seç',
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
              Expanded(
                child: FutureBuilder<List<ProfileBackgroundPreset>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ErrorState(onRetry: _retry);
                    }
                    final all = snapshot.data ?? const <ProfileBackgroundPreset>[];
                    if (all.isEmpty) {
                      return const Center(child: Text('Henüz hazır arka plan yok.'));
                    }
                    final categories = <String>[];
                    for (final p in all) {
                      if (!categories.contains(p.category)) categories.add(p.category);
                    }
                    final visible = _category == null
                        ? all
                        : all.where((p) => p.category == _category).toList();
                    return Column(
                      children: [
                        SizedBox(
                          height: 46,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                            children: [
                              _chip('Tümü (${all.length})', _category == null, () => setState(() => _category = null)),
                              for (final c in categories)
                                _chip(c, _category == c, () => setState(() => _category = c)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _grid(visible, scrollController, primary),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(fontSize: 12, color: selected ? Colors.white : Theme.of(context).hintColor),
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: primary,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _grid(List<ProfileBackgroundPreset> items, ScrollController controller, Color primary) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 720 ? 3 : 2;
    return GridView.builder(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.paddingOf(context).bottom + 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 16 / 9,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final preset = items[index];
        final selected = preset.imageUrl == widget.selectedUrl;
        return Semantics(
          button: true,
          selected: selected,
          label: preset.name,
          child: InkWell(
            onTap: () => Navigator.pop(context, preset),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? primary : Colors.black.withValues(alpha: 0.08),
                  width: selected ? 3 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 11 : 13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: preset.thumbUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 480,
                      placeholder: (_, _) => ColoredBox(color: Colors.grey.shade200),
                      errorWidget: (_, _, _) => ColoredBox(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x8C000000)],
                          ),
                        ),
                        child: Text(
                          preset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: primary,
                          child: const Icon(Icons.check, size: 16, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: 8),
            const Text('Arka planlar yüklenemedi.', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
