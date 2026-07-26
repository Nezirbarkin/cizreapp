// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_favorite_service.dart';

/// Kullanıcı favori durakları ekranı.
class SehiriciFavoritesScreen extends StatefulWidget {
  const SehiriciFavoritesScreen({super.key});

  @override
  State<SehiriciFavoritesScreen> createState() =>
      _SehiriciFavoritesScreenState();
}

class _SehiriciFavoritesScreenState extends State<SehiriciFavoritesScreen> {
  final SehiriciFavoriteService _service = SehiriciFavoriteService();
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _favorites = await _service.getFavoritesDetailed();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Favori Duraklarım')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Henüz favori durağınız yok.\nHat detayında yıldız ikonuna dokunun.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _favorites.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final f = _favorites[i];
                      final stops =
                          f['sehirici_stops'] as Map<String, dynamic>?;
                      final notify =
                          (f['notify_minutes_before'] as num?)?.toInt() ?? 5;
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.star, color: Colors.amber),
                        ),
                        title: Text(stops?['name'] ?? 'Durak'),
                        subtitle: Text(
                          '$notify dk kala bildirim'
                          '${stops?['address'] != null ? '\n${stops?['address']}' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () async {
                            await provider
                                .toggleFavorite(f['stop_id'] as String);
                            _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
