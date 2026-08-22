import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ilan_models.dart';
import '../services/ilan_service.dart';
import '../utils/ilan_ui.dart';
import '../widgets/ilan_card.dart';
import '../widgets/ilan_filter_sheet.dart';
import 'ilan_detail_screen.dart';
import 'ilan_form_screen.dart';
import 'my_ilanlar_screen.dart';

class IlanListScreen extends StatefulWidget {
  const IlanListScreen({super.key, this.initialCategory});
  final IlanCategory? initialCategory;

  @override
  State<IlanListScreen> createState() => _IlanListScreenState();
}

class _IlanListScreenState extends State<IlanListScreen> {
  final _service = IlanService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<IlanCategory> _categories = const [];
  List<Ilan> _ilanlar = const [];
  IlanCategory? _selectedCategory;
  IlanFilterState _filter = const IlanFilterState();
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _service.getCategories(),
        _service.search(
          categoryId: _selectedCategory?.id,
          query: _searchController.text,
          condition: _filter.condition,
          minPrice: _filter.minPrice,
          maxPrice: _filter.maxPrice,
          sortBy: _filter.sortBy,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = values[0] as List<IlanCategory>;
        _ilanlar = values[1] as List<Ilan>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(IlanUi.friendlyError(error))));
    }
  }

  Future<void> _openFilterSheet() async {
    final allowedConditions = _categories
        .expand((category) => category.allowedConditions)
        .toSet()
        .toList();
    final result = await showIlanFilterSheet(
      context,
      current: _filter,
      availableConditions: allowedConditions,
    );
    if (result == null) return;
    setState(() => _filter = result);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCategory?.name ?? 'İlanlar'),
        actions: [
          IconButton(
            tooltip: 'İlanlarım',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyIlanlarScreen()),
            ),
            icon: const Icon(Icons.folder_shared_outlined),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: 'Filtrele',
                onPressed: _openFilterSheet,
                icon: const Icon(Icons.tune_rounded),
              ),
              if (_filter.isActive)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'İlan ver',
            onPressed: () async {
              final saved = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      IlanFormScreen(initialCategory: _selectedCategory),
                ),
              );
              if (saved == true) _load();
            },
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 450), _load);
                  },
                  decoration: InputDecoration(
                    hintText: 'İlanlarda ara...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _load();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  children: [
                    ChoiceChip(
                      label: const Text('Tümü'),
                      selected: _selectedCategory == null,
                      onSelected: (_) {
                        setState(() => _selectedCategory = null);
                        _load();
                      },
                    ),
                    ..._categories.map(
                      (category) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            IlanUi.icon(category.iconName),
                            size: 17,
                            color: IlanUi.color(category.colorHex),
                          ),
                          label: Text(category.name),
                          selected: _selectedCategory?.id == category.id,
                          onSelected: (_) {
                            setState(() => _selectedCategory = category);
                            _load();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 54,
                        color: Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(IlanUi.friendlyError(_error!)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Yeniden dene'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_ilanlar.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 54,
                        color: Colors.black26,
                      ),
                      SizedBox(height: 12),
                      Text('Bu alanda henüz ilan yok'),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 310,
                    mainAxisExtent: 304,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final ilan = _ilanlar[index];
                    return IlanCard(
                      ilan: ilan,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => IlanDetailScreen(ilanId: ilan.id),
                        ),
                      ),
                    );
                  }, childCount: _ilanlar.length),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  IlanFormScreen(initialCategory: _selectedCategory),
            ),
          );
          if (saved == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('İlan Ver'),
      ),
    );
  }
}
