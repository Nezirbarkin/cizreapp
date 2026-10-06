import 'package:flutter/material.dart';

import '../services/okey_design_service.dart';
import '../theme/okey_design.dart';
import '../widgets/okey_design_preview.dart';
import 'okey_admin_service.dart';

/// Admin › 101 Okey › TASARIM — modülün tüm görünümünü (lobi, masa, ıstaka,
/// düğmeler, alt sayfalar) tek yerden seçer.
///
/// Üç ayar (hepsi `app_settings`, bkz. 20261005000020_okey_design_settings):
///
///  * **Aktif tasarım** (`okey_design`) — yedi hazır paketten biri; herkes
///    bunu görür.
///  * **Lobi düzeni** (`okey_lobby_layout`) — UX: Salon / Arena / Kompakt ya
///    da "tasarıma göre" (her tasarım kendi düzeniyle gelir).
///  * **Oyuncu seçimi** (`okey_design_user_choice`) — açıksa oyuncu kendi
///    cihazında başka tasarım/masa/ıstaka seçebilir; kapalıysa herkes
///    yöneticinin seçimini görür.
///
/// Değişiklik anında kaydedilir; oyuncular Okey'e bir sonraki girişlerinde
/// (modül kapısı ayarı okur) yeni görünümü görür.
class OkeyAdminDesignTab extends StatefulWidget {
  const OkeyAdminDesignTab({super.key, this.load, this.save});

  /// Testler için.
  final Future<OkeyDesignConfig> Function()? load;
  final Future<void> Function(OkeyDesignConfig config)? save;

  @override
  State<OkeyAdminDesignTab> createState() => _OkeyAdminDesignTabState();
}

class _OkeyAdminDesignTabState extends State<OkeyAdminDesignTab> {
  OkeyDesignConfig? _config;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await (widget.load ?? OkeyDesignService.fetchForAdmin)();
      if (mounted) setState(() => _config = c);
    } catch (e) {
      if (mounted) {
        setState(() => _error = OkeyAdminService.describeError(e));
      }
    }
  }

  Future<void> _save(OkeyDesignConfig next, String message) async {
    setState(() => _saving = true);
    try {
      await (widget.save ?? OkeyDesignService.saveAdmin)(next);
      if (!mounted) return;
      setState(() => _config = next);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kaydedilemedi: ${OkeyAdminService.describeError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyDesign(OkeyDesign design) async {
    final c = _config;
    if (c == null || c.designKey == design.key) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${design.label}" uygulansın mı?'),
        content: Text(
          'Tüm oyuncuların Okey lobisi, masası ve ıstakası bu tasarıma '
          'geçer${c.userChoice ? ' (kendi tasarımını seçmiş oyuncular hariç)' : ''}. '
          'Oyuncular yeni görünümü Okey\'e bir sonraki girişlerinde görür.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save(
      OkeyDesignConfig(
        designKey: design.key,
        layout: c.layout,
        userChoice: c.userChoice,
      ),
      '"${design.label}" tasarımı uygulandı',
    );
  }

  Future<void> _setLayout(OkeyLobbyLayout? layout) async {
    final c = _config;
    if (c == null || c.layout == layout) return;
    await _save(
      OkeyDesignConfig(
        designKey: c.designKey,
        layout: layout,
        userChoice: c.userChoice,
      ),
      layout == null
          ? 'Lobi düzeni tasarıma bağlandı'
          : 'Lobi düzeni: ${layout.label}',
    );
  }

  Future<void> _setUserChoice(bool value) async {
    final c = _config;
    if (c == null) return;
    await _save(
      OkeyDesignConfig(
        designKey: c.designKey,
        layout: c.layout,
        userChoice: value,
      ),
      value
          ? 'Oyuncular kendi görünümünü seçebilir'
          : 'Herkes yöneticinin seçtiği görünümü görür',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _config == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.black38),
              const SizedBox(height: 12),
              Text(
                'Tasarım ayarı alınamadı: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    final c = _config;
    if (c == null) return const Center(child: CircularProgressIndicator());

    final active = OkeyDesign.byKey(c.designKey);
    final effectiveLayout = c.layout ?? active.layout;

    return AbsorbPointer(
      absorbing: _saving,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActiveDesignCard(
            design: active,
            layout: effectiveLayout,
            saving: _saving,
          ),
          const SizedBox(height: 16),
          _SectionTitle(
            icon: Icons.view_quilt_outlined,
            title: 'Lobi düzeni (UX)',
            subtitle:
                'Ana sayfanın yerleşimi. "Tasarıma göre" seçiliyken her '
                'tasarım kendi düzeniyle gelir.',
          ),
          const SizedBox(height: 8),
          _LayoutPicker(
            selected: c.layout,
            designDefault: active.layout,
            onSelect: _setLayout,
          ),
          const SizedBox(height: 12),
          Material(
            color: const Color(0xFFF5F3FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.purple.shade100),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              value: c.userChoice,
              onChanged: _saving ? null : _setUserChoice,
              secondary: Icon(
                c.userChoice ? Icons.palette_outlined : Icons.lock_outline,
                color: Colors.purple,
              ),
              title: const Text(
                'Oyuncular kendi görünümünü seçebilsin',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                c.userChoice
                    ? 'Açık — oyuncu lobideki Görünüm düğmesinden tasarım, '
                          'masa ve ıstaka seçebilir'
                    : 'Kapalı — herkes yukarıdaki tasarımı görür',
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.style_outlined,
            title: 'Tasarımlar (${OkeyDesign.all.length})',
            subtitle:
                'Her tasarım lobi renklerini, düğme ve kart biçimini, arka '
                'plan dekorunu, masa temasını ve ıstakayı birlikte değiştirir.',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = (w / 190).floor().clamp(2, 5);
              const gap = 10.0;
              final cardW = (w - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final d in OkeyDesign.all)
                    SizedBox(
                      width: cardW,
                      child: _DesignCard(
                        design: d,
                        layout: c.layout ?? d.layout,
                        active: d.key == active.key,
                        onApply: () => _applyDesign(d),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.purple.shade700, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aktif tasarımın büyük önizlemesi + özeti.
class _ActiveDesignCard extends StatelessWidget {
  final OkeyDesign design;
  final OkeyLobbyLayout layout;
  final bool saving;

  const _ActiveDesignCard({
    required this.design,
    required this.layout,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade700, Colors.purple.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            height: 172,
            child: OkeyDesignPreview(design: design, layout: layout),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'ŞU AN AKTİF',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (saving) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  design.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  design.tagline,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InfoChip(icon: Icons.view_quilt, text: layout.label),
                    _InfoChip(
                      icon: Icons.table_restaurant,
                      text: design.tableTheme.label,
                    ),
                    _InfoChip(
                      icon: Icons.view_agenda,
                      text: design.rackStyle.label,
                    ),
                    _InfoChip(
                      icon: design.isLight ? Icons.light_mode : Icons.dark_mode,
                      text: design.isLight ? 'Açık' : 'Koyu',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lobi düzeni seçimi: "Tasarıma göre" + üç düzen. Dar ekranda alt satıra
/// iner (Wrap) — dört seçenek 320 px'e yan yana sığmaz.
class _LayoutPicker extends StatelessWidget {
  final OkeyLobbyLayout? selected;
  final OkeyLobbyLayout designDefault;
  final ValueChanged<OkeyLobbyLayout?> onSelect;

  const _LayoutPicker({
    required this.selected,
    required this.designDefault,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    Widget option(OkeyLobbyLayout? value, String title, String sub) {
      final on = selected == value;
      return ChoiceChip(
        selected: on,
        onSelected: (_) => onSelect(value),
        showCheckmark: false,
        avatar: Icon(
          on ? Icons.radio_button_checked : Icons.radio_button_off,
          size: 18,
          color: on ? Colors.purple.shade700 : Colors.black45,
        ),
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              sub,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        selectedColor: Colors.purple.shade50,
        side: BorderSide(color: on ? Colors.purple.shade300 : Colors.black12),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        option(null, 'Tasarıma göre', 'Şu an: ${designDefault.label}'),
        for (final l in OkeyLobbyLayout.values)
          option(l, l.label, l.description),
      ],
    );
  }
}

/// Izgaradaki tasarım kartı.
class _DesignCard extends StatelessWidget {
  final OkeyDesign design;
  final OkeyLobbyLayout layout;
  final bool active;
  final VoidCallback onApply;

  const _DesignCard({
    required this.design,
    required this.layout,
    required this.active,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: active ? 4 : 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active ? Colors.purple.shade400 : Colors.black12,
          width: active ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active ? null : onApply,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 0.56,
                child: OkeyDesignPreview(design: design, layout: layout),
              ),
              const SizedBox(height: 8),
              Text(
                design.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                design.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                '${layout.label} · ${design.tableTheme.label} · '
                '${design.rackStyle.label}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.purple.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (active)
                Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.purple.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Aktif',
                        style: TextStyle(
                          color: Colors.purple.shade700,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: 34,
                  child: FilledButton(
                    onPressed: onApply,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      padding: EdgeInsets.zero,
                    ),
                    child: const FittedBox(child: Text('Uygula')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
