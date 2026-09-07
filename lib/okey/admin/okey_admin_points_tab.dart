import 'dart:async';

import 'package:flutter/material.dart';

import 'okey_admin_service.dart';
import 'okey_admin_widgets.dart';

/// Admin panelinde Okey puanı ekleme/düşme sekmesi.
///
/// Bu puanlar SADECE Okey oyununda kullanılır; uygulamanın diğer bakiye ve
/// ödül sistemlerinden tamamen ayrıdır.
class OkeyAdminPointsTab extends StatefulWidget {
  const OkeyAdminPointsTab({super.key});

  @override
  State<OkeyAdminPointsTab> createState() => _OkeyAdminPointsTabState();
}

class _OkeyAdminPointsTabState extends State<OkeyAdminPointsTab> {
  final _service = OkeyAdminService();
  final _search = TextEditingController();
  final _amount = TextEditingController(text: '1000');
  final _note = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  int? _selectedPoints;
  bool _searching = false;
  bool _saving = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Yazarken 300ms bekleyip arar; kullanıcı Enter'a basmak zorunda kalmaz.
  /// Arama butonu manuel bir yedek olarak kalır.
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _doSearch);
  }

  Future<void> _doSearch() async {
    setState(() => _searching = true);
    try {
      final r = await _service.searchUsers(_search.text);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Arama hatası: ${OkeyAdminService.describeError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _select(Map<String, dynamic> user) async {
    setState(() {
      _selected = user;
      _selectedPoints = null;
    });
    try {
      final p = await _service.getUserPoints(user['id'] as String);
      if (mounted) setState(() => _selectedPoints = p);
    } catch (_) {
      if (mounted) setState(() => _selectedPoints = 0);
    }
  }

  Future<bool> _confirmGrant(Map<String, dynamic> user, int amount) async {
    final isGrant = amount > 0;
    final userLabel =
        (user['full_name'] ?? user['username'] ?? 'Oyuncu') as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isGrant ? 'Çip ekle' : 'Çip düş'),
        content: Text(
          '$userLabel için ${amount.abs()} çip '
          '${isGrant ? 'eklenecek' : 'düşülecek'}.\n'
          'Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isGrant ? Colors.green : Colors.red,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _grant() async {
    final user = _selected;
    final amount = int.tryParse(_amount.text.trim());
    if (user == null || amount == null || amount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı seç ve 0 olmayan bir miktar gir'),
        ),
      );
      return;
    }

    final confirmed = await _confirmGrant(user, amount);
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final newPoints = await _service.grantPoints(
        user['id'] as String,
        amount,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      setState(() => _selectedPoints = newPoints);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${amount > 0 ? '+' : ''}$amount çip işlendi. '
            'Yeni bakiye: $newPoints',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Colors.amber.shade50,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Bu çipler SADECE Okey oyununda kullanılır; uygulamanın diğer '
              'bakiye/ödül sistemlerinden tamamen ayrıdır.\n'
              'Negatif miktar girerek çip düşebilirsiniz.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Kullanıcı ara (ad veya kullanıcı adı)...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                onSubmitted: (_) => _doSearch(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _searching ? null : _doSearch,
              child: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._results.map((u) {
          final isSel = _selected?['id'] == u['id'];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            elevation: isSel ? 2 : 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSel
                    ? Colors.deepPurple.withValues(alpha: 0.5)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            color: isSel ? Colors.deepPurple.shade50 : null,
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              dense: true,
              leading: CircleAvatar(
                backgroundImage: u['avatar_url'] != null
                    ? NetworkImage(u['avatar_url'] as String)
                    : null,
                child: u['avatar_url'] == null
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(
                (u['full_name'] ?? u['username'] ?? 'Oyuncu') as String,
              ),
              subtitle: Text('@${u['username'] ?? '-'}'),
              trailing: isSel
                  ? OkeyBadgeChip(
                      icon: Icons.stars,
                      label: _selectedPoints == null
                          ? '…'
                          : '$_selectedPoints çip',
                      color: Colors.deepPurple,
                    )
                  : null,
              onTap: () => _select(u),
            ),
          );
        }),
        if (_selected != null) ...[
          const Divider(height: 24),
          Text(
            'Seçili: '
            '${(_selected!['full_name'] ?? _selected!['username'] ?? '')}'
            '${_selectedPoints != null ? '  ·  mevcut: $_selectedPoints çip' : ''}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: InputDecoration(
              labelText: 'Miktar (negatif = düş)',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: 'Not (opsiyonel)',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _grant,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_circle),
            label: const Text('Çipi İşle'),
          ),
        ],
      ],
    );
  }
}
