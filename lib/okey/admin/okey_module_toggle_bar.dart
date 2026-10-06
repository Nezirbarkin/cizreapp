import 'package:flutter/material.dart';

import '../services/okey_module_service.dart';

/// Admin > 101 Okey > Ayarlar sekmesinin başında: modülü uygulama genelinde
/// aç/kapat (Görev 4.1). Kapalıyken kullanıcılar Okey girişlerini görmez, yeni oyun
/// açılamaz (sunucu tetikleyicisi); süren oyunlar biter.
class OkeyModuleToggleBar extends StatefulWidget {
  const OkeyModuleToggleBar({super.key, this.load, this.save});

  /// Testler için.
  final Future<bool> Function()? load;
  final Future<void> Function(bool value)? save;

  @override
  State<OkeyModuleToggleBar> createState() => _OkeyModuleToggleBarState();
}

class _OkeyModuleToggleBarState extends State<OkeyModuleToggleBar> {
  bool? _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    (widget.load ?? () => OkeyModuleService.fetch(forceRefresh: true))().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _set(bool value) async {
    if (!value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('101 Okey kapatılsın mı?'),
          content: const Text(
            'Kullanıcılar Okey girişlerini görmeyecek ve yeni oyun açamayacak. '
            'Süren oyunlar bitene kadar devam eder.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    try {
      await (widget.save ?? OkeyModuleService.setEnabled)(value);
      if (!mounted) return;
      setState(() => _enabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? '101 Okey açıldı' : '101 Okey kapatıldı')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Material(
      color: enabled == false ? const Color(0xFFFEF2F2) : const Color(0xFFF5F3FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: enabled == false ? Colors.red.shade200 : Colors.purple.shade100),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: enabled ?? true,
        onChanged: enabled == null || _saving ? null : _set,
        secondary: Icon(
          enabled == false ? Icons.visibility_off_outlined : Icons.casino,
          color: enabled == false ? Colors.red : Colors.purple,
        ),
        title: const Text('101 Okey uygulamada görünsün', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          enabled == null
              ? 'Yükleniyor…'
              : enabled
              ? 'Açık — kullanıcılar oynayabilir'
              : 'Kapalı — girişler gizli, yeni oyun açılamaz',
        ),
      ),
    );
  }
}
