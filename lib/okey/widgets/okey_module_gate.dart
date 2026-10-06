import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/okey_design_service.dart';
import '../services/okey_module_service.dart';

/// 101 Okey'e her giriş (menü, `/okey` rotası, davet bildirimi) bu kapıdan
/// geçer (Görev 4.1). Modül kapalıysa "şu anda kapalı" ekranı; yönetici test
/// için yine girebilir (sunucu da yöneticiyi engellemez).
class OkeyModuleGate extends StatefulWidget {
  const OkeyModuleGate({super.key, required this.child, this.isAdmin});

  final Widget child;

  /// Testler için; varsayılan sunucuya `auth_is_admin` sorar.
  final Future<bool> Function()? isAdmin;

  @override
  State<OkeyModuleGate> createState() => _OkeyModuleGateState();
}

class _OkeyModuleGateState extends State<OkeyModuleGate> {
  late final Future<bool> _open = _resolve();

  Future<bool> _resolve() async {
    // TASARIM AYARI modül anahtarıyla PARALEL okunur: lobi ilk karede doğru
    // tasarımla çizilsin (aksi halde varsayılan görünüp hemen değişirdi).
    // refresh() hata fırlatmaz ve kısa zaman aşımlıdır.
    final design = OkeyDesignService.refresh();
    final enabled = await OkeyModuleService.fetch(forceRefresh: true);
    await design;
    if (enabled) return true;
    try {
      final check = widget.isAdmin ??
          () async => await Supabase.instance.client.rpc('auth_is_admin') == true;
      return await check();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _open,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data!) return widget.child;
        return const OkeyClosedScreen();
      },
    );
  }
}

/// Modül kapalıyken gösterilen ekran.
class OkeyClosedScreen extends StatelessWidget {
  const OkeyClosedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('101 Okey')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.casino_outlined, size: 64, color: Colors.black26),
              SizedBox(height: 16),
              Text(
                '101 Okey şu anda kapalı',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Oyun yönetim tarafından geçici olarak kapatıldı. Açıldığında buradan yeniden girebilirsin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
