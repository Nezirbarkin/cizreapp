import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/image_url.dart';
import '../../social/services/muted_users_service.dart';
import 'user_profile_screen.dart';

/// Sessize alınan kişiler: gönderileri ve hikâyeleri akışta görünmez.
/// Engellemeden farkı: karşı taraf fark etmez, profilin ve mesajlar açık kalır.
class MutedUsersScreen extends StatefulWidget {
  const MutedUsersScreen({super.key});

  @override
  State<MutedUsersScreen> createState() => _MutedUsersScreenState();
}

class _MutedUsersScreenState extends State<MutedUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await MutedUsersService.instance.listMuted();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Sessize alınanlar yüklenemedi: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unmute(Map<String, dynamic> user) async {
    final id = user['id'] as String;
    if (!_busy.add(id)) return;
    setState(() {});
    try {
      await MutedUsersService.instance.unmute(id);
      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u['id'] == id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('@${user['username'] ?? 'kullanıcı'} sesi açıldı')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: themeProvider.primaryColor,
        elevation: 0,
        title: const Text(
          'Sessize alınanlar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Sessize aldığın kişilerin gönderileri ve hikâyeleri akışında '
                            'görünmez. Haberleri olmaz; profillerini ve mesajlarını '
                            'görmeye devam edersin.',
                            style: TextStyle(fontSize: 12.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_users.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(Icons.volume_off_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Sessize aldığın kimse yok',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  for (final user in _users) _tile(user),
                ],
              ),
            ),
    );
  }

  Widget _tile(Map<String, dynamic> user) {
    final id = user['id'] as String;
    final username = (user['username'] as String?) ?? 'kullanici';
    final fullName = (user['full_name'] as String?)?.trim().isNotEmpty == true
        ? user['full_name'] as String
        : username;
    final avatarUrl = user['avatar_url'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)),
        ),
        leading: CircleAvatar(
          radius: 22,
          backgroundImage: avatarUrl != null ? avatarImage(avatarUrl) : null,
          backgroundColor: Colors.grey.shade300,
          child: avatarUrl == null
              ? Text(
                  username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                )
              : null,
        ),
        title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('@$username'),
        trailing: OutlinedButton(
          onPressed: _busy.contains(id) ? null : () => _unmute(user),
          child: const Text('Sesi aç'),
        ),
      ),
    );
  }
}
