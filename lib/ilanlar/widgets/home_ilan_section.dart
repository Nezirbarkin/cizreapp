// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../models/ilan_models.dart';
import '../screens/ilan_detail_screen.dart';
import '../screens/ilan_form_screen.dart';
import '../screens/ilan_list_screen.dart';
import '../services/ilan_service.dart';
import '../utils/ilan_ui.dart';
import 'ilan_card.dart';

class HomeIlanSection extends StatefulWidget {
  const HomeIlanSection({super.key});

  @override
  State<HomeIlanSection> createState() => _HomeIlanSectionState();
}

class _HomeIlanSectionState extends State<HomeIlanSection> {
  final _service = IlanService();
  late Future<_HomeIlanData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeIlanData> _load() async {
    final settings = await _service.getSettings();
    if (!settings.isEnabled)
      return _HomeIlanData(
        settings: settings,
        categories: const [],
        ilanlar: const [],
      );
    final values = await Future.wait([
      _service.getCategories(),
      _service.getLatest(limit: settings.homeIlanLimit),
    ]);
    return _HomeIlanData(
      settings: settings,
      categories: (values[0] as List<IlanCategory>)
          .take(settings.homeCategoryLimit)
          .toList(),
      ilanlar: values[1] as List<Ilan>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeIlanData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.withValues(alpha: .25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined, color: Colors.orange),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'İlanlar şu anda yüklenemedi.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _future = _load();
                  }),
                  child: const Text('Yenile'),
                ),
              ],
            ),
          );
        }
        if (snapshot.data?.settings.isEnabled != true) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!;
        final primary = Theme.of(context).colorScheme.primary;
        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: EdgeInsets.fromLTRB(
            0,
            8,
            0,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.campaign_rounded, color: primary),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'İlanlar',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Cizre’den güncel ilanları keşfet',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const IlanListScreen(),
                        ),
                      ),
                      child: const Text('Tümünü Gör'),
                    ),
                  ],
                ),
              ),
              if (data.categories.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 94,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: data.categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final category = data.categories[index];
                      final color = IlanUi.color(category.colorHex);
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                IlanListScreen(initialCategory: category),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 112,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: color.withValues(alpha: .15),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                IlanUi.icon(category.iconName),
                                color: color,
                                size: 27,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                category.name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (data.ilanlar.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Yeni İlanlar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 288,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: data.ilanlar.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final ilan = data.ilanlar[index];
                      return IlanCard(
                        ilan: ilan,
                        compact: true,
                        showPrice: data.settings.showPricesOnHome,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => IlanDetailScreen(ilanId: ilan.id),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'İlk ilanı sen paylaş!',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              if (data.settings.allowUserCreate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const IlanFormScreen(),
                          ),
                        );
                        if (saved == true && mounted)
                          setState(() {
                            _future = _load();
                          });
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(
                        data.settings.requireApproval
                            ? 'İlan Ver (Onaya Gönderilir)'
                            : 'İlan Ver • Anında Yayınlanır',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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

class _HomeIlanData {
  const _HomeIlanData({
    required this.settings,
    required this.categories,
    required this.ilanlar,
  });
  final IlanSettings settings;
  final List<IlanCategory> categories;
  final List<Ilan> ilanlar;
}
