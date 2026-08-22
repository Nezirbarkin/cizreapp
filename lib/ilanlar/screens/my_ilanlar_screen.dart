import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ilan_models.dart';
import '../services/ilan_service.dart';
import '../utils/ilan_ui.dart';
import '../widgets/ilan_card.dart';
import 'ilan_detail_screen.dart';
import 'ilan_form_screen.dart';

class MyIlanlarScreen extends StatefulWidget {
  const MyIlanlarScreen({super.key});

  @override
  State<MyIlanlarScreen> createState() => _MyIlanlarScreenState();
}

const _tabs = [
  ('Tümü', <IlanStatus>[]),
  ('Yayında', [IlanStatus.published]),
  ('Bekleyen', [IlanStatus.draft, IlanStatus.pending]),
  ('Reddedilen', [IlanStatus.rejected]),
  (
    'Arşiv',
    [
      IlanStatus.sold,
      IlanStatus.rented,
      IlanStatus.found,
      IlanStatus.expired,
      IlanStatus.archived,
    ],
  ),
];

class _MyIlanlarScreenState extends State<MyIlanlarScreen>
    with SingleTickerProviderStateMixin {
  final _service = IlanService();
  late final TabController _tabController = TabController(
    length: _tabs.length,
    vsync: this,
  );
  Future<List<Ilan>>? _future;

  @override
  void initState() {
    super.initState();
    if (Supabase.instance.client.auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İlanlarınızı görmek için giriş yapmalısınız.'),
          ),
        );
        Navigator.pop(context);
      });
      return;
    }
    _future = _service.getMine();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (Supabase.instance.client.auth.currentUser == null) return;
    setState(() {
      _future = _service.getMine();
    });
  }

  Future<void> _confirmAndDelete(Ilan ilan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İlanı sil'),
        content: Text('"${ilan.title}" ilanını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteIlan(ilan.id);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İlan silindi.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(IlanUi.friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İlanlarım'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((tab) => Tab(text: tab.$1)).toList(),
        ),
      ),
      body: _future == null
          ? const SizedBox.shrink()
          : FutureBuilder<List<Ilan>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 54,
                          color: Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        Text(IlanUi.friendlyError(snapshot.error!)),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Yeniden dene'),
                        ),
                      ],
                    ),
                  );
                }
                final all = snapshot.data ?? const <Ilan>[];
                return TabBarView(
                  controller: _tabController,
                  children: _tabs
                      .map(
                        (tab) => _IlanGroupList(
                          ilanlar: tab.$2.isEmpty
                              ? all
                              : all
                                    .where(
                                      (ilan) => tab.$2.contains(ilan.status),
                                    )
                                    .toList(),
                          onRefresh: () async => _refresh(),
                          onDelete: _confirmAndDelete,
                        ),
                      )
                      .toList(),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const IlanFormScreen()),
          );
          if (saved == true) _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Yeni İlan Ver'),
      ),
    );
  }
}

class _IlanGroupList extends StatelessWidget {
  const _IlanGroupList({
    required this.ilanlar,
    required this.onRefresh,
    required this.onDelete,
  });

  final List<Ilan> ilanlar;
  final Future<void> Function() onRefresh;
  final void Function(Ilan ilan) onDelete;

  @override
  Widget build(BuildContext context) {
    if (ilanlar.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 54,
                      color: Colors.black26,
                    ),
                    SizedBox(height: 12),
                    Text('Bu kategoride ilan bulunmuyor'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 310,
          mainAxisExtent: 324,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: ilanlar.length,
        itemBuilder: (context, index) {
          final ilan = ilanlar[index];
          return IlanCard(
            ilan: ilan,
            showStatusBadge: true,
            onDelete: () => onDelete(ilan),
            onTap: () async {
              final deleted = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => IlanDetailScreen(ilanId: ilan.id),
                ),
              );
              if (deleted == true) await onRefresh();
            },
          );
        },
      ),
    );
  }
}
