// =============================================================================
// Şüpheli Kullanıcılar Admin Widget
// AdminDashboardScreen'den _selectedMenu = 'Şüpheli Kullanıcılar' ile çağrılır.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SuspiciousUsersContent extends StatefulWidget {
  const SuspiciousUsersContent({super.key});

  @override
  State<SuspiciousUsersContent> createState() =>
      _SuspiciousUsersContentState();
}

class _SuspiciousUsersContentState extends State<SuspiciousUsersContent> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _supabase.rpc('admin_list_suspicious_users');
      _users = List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unflag(String userId) async {
    try {
      await _supabase.rpc('admin_set_user_suspicious', params: {
        'target_user_id': userId,
        'flagged': false,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  Future<void> _flagUserDialog() async {
    final idController = TextEditingController();
    final reasonController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kullanıcıyı Şüpheli İşaretle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              decoration: const InputDecoration(labelText: 'Kullanıcı ID'),
            ),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Sebep'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İşaretle'),
          ),
        ],
      ),
    );

    if (result == true && idController.text.trim().isNotEmpty) {
      try {
        await _supabase.rpc('admin_set_user_suspicious', params: {
          'target_user_id': idController.text.trim(),
          'flagged': true,
          'reason': reasonController.text.trim(),
        });
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text(
                'Şüpheli Kullanıcılar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _flagUserDialog,
                icon: const Icon(Icons.flag),
                label: const Text('Kullanıcı İşaretle'),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? const Center(child: Text('Şüpheli kullanıcı yok'))
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final u = _users[index];
                        final flaggedAt = u['suspicious_flagged_at'] != null
                            ? DateFormat('dd.MM.yyyy HH:mm').format(
                                DateTime.parse(u['suspicious_flagged_at']))
                            : '-';
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.red,
                            child: Icon(Icons.warning, color: Colors.white),
                          ),
                          title: Text(u['full_name'] ?? u['email'] ?? u['id']),
                          subtitle: Text(
                              'Sebep: ${u['suspicious_reason'] ?? '-'}\nİşaretlenme: $flaggedAt'),
                          isThreeLine: true,
                          trailing: TextButton(
                            onPressed: () => _unflag(u['id']),
                            child: const Text('İşareti Kaldır'),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
