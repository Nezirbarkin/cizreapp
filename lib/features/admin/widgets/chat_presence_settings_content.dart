import 'package:flutter/material.dart';

import '../../chat/models/chat_presence.dart';
import '../services/chat_presence_admin_service.dart';
import 'admin_ui.dart';

/// Admin > Sohbet Durumu.
///
/// Sohbet ekranı ve profildeki üç özelliği yönetir: SON GÖRÜLME (kaç günden
/// eskiyse hiç gösterilmeyeceği dahil), ÇEVRİMİÇİ durumu ve "YAZIYOR…" göstergesi.
/// En üstte, mevcut ayarlarla kullanıcıların ne göreceğinin canlı önizlemesi var;
/// örneğin "9 gün önce" senaryosu süre sınırının etkisini gösterir.
///
/// Anahtarlar sunucuda da uygulanır (kapalı özelliğin bilgisi sunucudan hiç
/// dönmez); buradaki değişiklik istemciyi kurcalayan biri için de geçerlidir.
/// Kullanıcının kendi gizlilik seçimi (hayalet modu, "son görülmemi gizle"...)
/// bunların ÜSTÜNE eklenir: bir bilgi ancak ikisi de izin veriyorsa görünür.
class ChatPresenceSettingsContent extends StatefulWidget {
  const ChatPresenceSettingsContent({super.key});

  @override
  State<ChatPresenceSettingsContent> createState() =>
      _ChatPresenceSettingsContentState();
}

enum PresencePreviewScenario { online, recent, old, typing }

/// Önizlemedeki "eski" senaryo: varsayılan 7 günlük sınırın dışında kalsın.
const int kPresencePreviewOldDays = 9;

/// Bu senaryoda, mevcut ayarlarla, bu ekranda görünecek satır (yoksa null).
///
/// Sunucudaki `presence_resolve` kurallarının ayar katmanını yansıtır (kullanıcının
/// kendi gizlilik seçimi hariç); admin bir anahtarı çevirmeden önce sonucu görsün.
@visibleForTesting
String? presencePreviewLine(
  ChatPresenceSettings settings,
  PresenceContext context,
  PresencePreviewScenario scenario, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  switch (scenario) {
    case PresencePreviewScenario.online:
      return settings.online ? PresenceLabels.online : null;
    case PresencePreviewScenario.typing:
      // "Yazıyor…" yalnız sohbet ekranında gösterilir.
      return context != PresenceContext.profile && settings.typing
          ? '${PresenceLabels.typing}…'
          : null;
    case PresencePreviewScenario.recent:
      return _previewSeenLine(settings, context, 1, clock);
    case PresencePreviewScenario.old:
      return _previewSeenLine(settings, context, kPresencePreviewOldDays, clock);
  }
}

String? _previewSeenLine(
  ChatPresenceSettings settings,
  PresenceContext context,
  int daysAgo,
  DateTime now,
) {
  if (!settings.showsLastSeen(context)) return null;
  if (daysAgo > settings.lastSeenMaxDays) return null;
  return PresenceLabels.lastSeen(now.subtract(Duration(days: daysAgo)), now: now);
}

class _ChatPresenceSettingsContentState
    extends State<ChatPresenceSettingsContent> {
  static const List<int> _dayPresets = [1, 3, 7, 14, 30, 90];

  ChatPresenceSettings? _settings;
  ChatPresenceStats? _stats;
  Object? _loadError;
  String? _busyKey;
  PresencePreviewScenario _scenario = PresencePreviewScenario.online;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final settings = await ChatPresenceAdminService.loadSettings();
      if (!mounted) return;
      setState(() => _settings = settings);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
      return;
    }
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ChatPresenceAdminService.loadStats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (_) {
      // Özet kutuları olmadan da ayarlar çalışır.
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  /// Tek bir yazımı çalıştırır; sunucunun döndürdüğü güncel ayarı gösterir.
  Future<void> _apply(
    String busyKey,
    Future<ChatPresenceSettings> Function() write,
  ) async {
    setState(() => _busyKey = busyKey);
    try {
      final next = await write();
      if (!mounted) return;
      setState(() => _settings = next);
    } catch (e) {
      if (!mounted) return;
      _snack('Kaydedilemedi: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      if (_loadError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: AdminUi.muted),
              const SizedBox(height: 8),
              const Text('Ayarlar okunamadı'),
              TextButton(onPressed: _load, child: const Text('Yeniden dene')),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: AdminUi.page,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _sectionTitle('Kullanıcılar böyle görür'),
            _previewCard(settings),
            const SizedBox(height: 18),
            _sectionTitle('Son görülme'),
            _switchTile(
              busyKey: ChatPresenceAdminService.keyLastSeen,
              icon: Icons.schedule_rounded,
              color: const Color(0xFF7C3AED),
              title: 'Son görülme',
              subtitle:
                  'Sohbet ekranında ve profilde "son görülme dün 21:10" gibi '
                  'görünür. Kapalıyken hiçbir yerde gösterilmez ve sunucu da '
                  'bu bilgiyi hiç döndürmez.',
              value: settings.lastSeen,
              onChanged: (v) => _apply(
                ChatPresenceAdminService.keyLastSeen,
                () => ChatPresenceAdminService.setFlag(
                  ChatPresenceAdminService.keyLastSeen,
                  v,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _switchTile(
              busyKey: ChatPresenceAdminService.keyLastSeenInChat,
              icon: Icons.chat_bubble_outline_rounded,
              color: const Color(0xFF0EA5E9),
              title: 'Sohbet ekranında göster',
              subtitle: 'Sohbet başlığında adın altında.',
              value: settings.lastSeenInChat,
              enabled: settings.lastSeen,
              indent: true,
              onChanged: (v) => _apply(
                ChatPresenceAdminService.keyLastSeenInChat,
                () => ChatPresenceAdminService.setFlag(
                  ChatPresenceAdminService.keyLastSeenInChat,
                  v,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _switchTile(
              busyKey: ChatPresenceAdminService.keyLastSeenInProfile,
              icon: Icons.person_outline_rounded,
              color: const Color(0xFF14B8A6),
              title: 'Profilde göster',
              subtitle: 'Profil sayfasında adın altında.',
              value: settings.lastSeenInProfile,
              enabled: settings.lastSeen,
              indent: true,
              onChanged: (v) => _apply(
                ChatPresenceAdminService.keyLastSeenInProfile,
                () => ChatPresenceAdminService.setFlag(
                  ChatPresenceAdminService.keyLastSeenInProfile,
                  v,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _daysCard(settings),
            const SizedBox(height: 18),
            _sectionTitle('Çevrimiçi durumu'),
            _switchTile(
              busyKey: ChatPresenceAdminService.keyOnline,
              icon: Icons.circle,
              color: const Color(0xFF16A34A),
              title: 'Çevrimiçi durumu',
              subtitle:
                  'Yeşil nokta, "çevrimiçi" yazısı ve sohbet listesindeki aktif '
                  'kullanıcılar şeridi. Kapalıyken kimse kimsenin çevrimiçi '
                  'olduğunu göremez.',
              value: settings.online,
              onChanged: (v) => _apply(
                ChatPresenceAdminService.keyOnline,
                () => ChatPresenceAdminService.setFlag(
                  ChatPresenceAdminService.keyOnline,
                  v,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle('Yazıyor… göstergesi'),
            _switchTile(
              busyKey: ChatPresenceAdminService.keyTyping,
              icon: Icons.edit_note_rounded,
              color: const Color(0xFFF59E0B),
              title: 'Yazıyor… göstergesi',
              subtitle:
                  'Karşı taraf yazarken sohbet başlığında "yazıyor…" görünür. '
                  'Kapalıyken sunucu kanalı hiç açmaz.',
              value: settings.typing,
              onChanged: (v) => _apply(
                ChatPresenceAdminService.keyTyping,
                () => ChatPresenceAdminService.setFlag(
                  ChatPresenceAdminService.keyTyping,
                  v,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _switchTile(
              busyKey: ChatPresenceAdminService.keyTypingInGroups,
              icon: Icons.groups_rounded,
              color: const Color(0xFFEC4899),
              title: 'Grup sohbetlerinde de',
              subtitle: 'Grup başlığında "Ali yazıyor…", "3 kişi yazıyor…".',
              value: settings.typingInGroups,
              enabled: settings.typing,
              indent: true,
              onChanged: (v) => _apply(
                ChatPresenceAdminService.keyTypingInGroups,
                () => ChatPresenceAdminService.setFlag(
                  ChatPresenceAdminService.keyTypingInGroups,
                  v,
                ),
              ),
            ),
            if (_stats != null) ...[
              const SizedBox(height: 18),
              _sectionTitle('Kullanıcılar bu özellikleri nasıl kullanıyor'),
              _statsGrid(_stats!),
            ],
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Kullanıcılar kendi gizliliklerini Mesajlar › Gizlilik & Durum '
                'ekranından seçer: son görülmeyi herkese, yalnız arkadaşlara '
                '(karşılıklı takip) ya da hiç kimseye açabilir, "yazıyor…" '
                'bilgisini kapatabilir. Bir bilgi ancak buradaki anahtar VE '
                'kullanıcının seçimi izin veriyorsa görünür. Engellenen kişiler '
                've takip edilmeyen gizli hesaplar hiçbir durumu göremez.',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminUi.muted,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Parçalar
  // ---------------------------------------------------------------------------

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AdminUi.muted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _switchTile({
    required String busyKey,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    bool indent = false,
  }) {
    final busy = _busyKey == busyKey;
    final locked = _busyKey != null || !enabled;
    final tile = AdminCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          _iconBox(icon, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminUi.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch(
              value: value,
              onChanged: locked ? null : onChanged,
              activeThumbColor: AdminUi.brand,
            ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(left: indent ? 18 : 0),
      child: Opacity(opacity: enabled ? 1 : 0.55, child: tile),
    );
  }

  Widget _daysCard(ChatPresenceSettings settings) {
    final days = settings.lastSeenMaxDays;
    final locked = _busyKey != null || !settings.lastSeen;
    final canStep = !locked;
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Opacity(
        opacity: settings.lastSeen ? 1 : 0.55,
        child: AdminCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconBox(Icons.hourglass_bottom_rounded, Colors.deepOrange),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Süre sınırı',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Son görülmesi bu günden eskiyse hiçbir yerde '
                          'gösterilmez.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AdminUi.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Bir gün azalt',
                    onPressed: canStep &&
                            days > ChatPresenceAdminService.minDays
                        ? () => _apply(
                            'days',
                            () => ChatPresenceAdminService.setMaxDays(days - 1),
                          )
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: _busyKey == 'days'
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '$days gün',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AdminUi.ink,
                              ),
                            ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Bir gün artır',
                    onPressed: canStep &&
                            days < ChatPresenceAdminService.maxDays
                        ? () => _apply(
                            'days',
                            () => ChatPresenceAdminService.setMaxDays(days + 1),
                          )
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final preset in _dayPresets)
                    ChoiceChip(
                      label: Text('$preset gün'),
                      selected: days == preset,
                      showCheckmark: false,
                      selectedColor: AdminUi.brandSoft,
                      side: BorderSide(
                        color: days == preset ? AdminUi.brand : AdminUi.line,
                      ),
                      onSelected: locked
                          ? null
                          : (_) => _apply(
                              'days',
                              () => ChatPresenceAdminService.setMaxDays(preset),
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Önizleme --------------------------------------------------------------

  Widget _previewCard(ChatPresenceSettings settings) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kaydırmalı çubuk yerine sarmalı satır: telefon genişliğinde dört
          // senaryonun hepsi görünür (biri ekran dışında kalıp gözden kaçmasın).
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _scenarioChip(
                PresencePreviewScenario.online,
                'Çevrimiçi',
                Icons.circle,
              ),
              _scenarioChip(
                PresencePreviewScenario.recent,
                'Dün çıktı',
                Icons.schedule_rounded,
              ),
              _scenarioChip(
                PresencePreviewScenario.old,
                '$kPresencePreviewOldDays gün önce',
                Icons.history_rounded,
              ),
              _scenarioChip(
                PresencePreviewScenario.typing,
                'Yazıyor',
                Icons.edit_note_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _caption('Sohbet ekranı'),
          _MockChatHeader(
            line: presencePreviewLine(settings, PresenceContext.chat, _scenario),
          ),
          const SizedBox(height: 10),
          _caption('Profil'),
          _MockProfile(
            line: presencePreviewLine(settings, PresenceContext.profile, _scenario),
            online: _scenario == PresencePreviewScenario.online,
          ),
        ],
      ),
    );
  }

  Widget _scenarioChip(
    PresencePreviewScenario value,
    String label,
    IconData icon,
  ) {
    final selected = _scenario == value;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _scenario = value),
      selectedColor: AdminUi.brand,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AdminUi.brand : AdminUi.line),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : AdminUi.muted,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AdminUi.ink,
        ),
      ),
    );
  }

  Widget _caption(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AdminUi.muted,
      ),
    ),
  );

  // --- Özet ------------------------------------------------------------------

  Widget _statsGrid(ChatPresenceStats stats) {
    Widget cell(IconData icon, String label, int value, Color color) => Expanded(
      child: AdminMiniStat(
        icon: icon,
        label: label,
        value: adminCompact(value),
        color: color,
      ),
    );

    return Column(
      children: [
        Row(
          children: [
            cell(Icons.circle, 'Şu an çevrimiçi', stats.onlineNow, Colors.green),
            const SizedBox(width: 8),
            cell(
              Icons.visibility_off_outlined,
              'Son görülme gizli',
              stats.lastSeenHidden,
              Colors.deepPurple,
            ),
            const SizedBox(width: 8),
            cell(
              Icons.people_alt_outlined,
              'Yalnız arkadaşlara',
              stats.lastSeenFriends,
              Colors.blue,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            cell(
              Icons.nights_stay_outlined,
              'Hayalet modu',
              stats.ghost,
              Colors.indigo,
            ),
            const SizedBox(width: 8),
            cell(
              Icons.circle_outlined,
              'Çevrimdışı görünen',
              stats.onlineOff,
              Colors.blueGrey,
            ),
            const SizedBox(width: 8),
            cell(
              Icons.edit_off_outlined,
              'Yazıyor kapalı',
              stats.typingOff,
              Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${adminCompact(stats.total)} kullanıcı üzerinden (botlar hariç)',
            style: const TextStyle(fontSize: 11, color: AdminUi.muted),
          ),
        ),
      ],
    );
  }
}

/// Sohbet başlığının küçük taklidi.
class _MockChatHeader extends StatelessWidget {
  const _MockChatHeader({required this.line});

  final String? line;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdminUi.brand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white24,
            child: const Text(
              'A',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ayşe Yılmaz',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  line ?? 'hiçbir durum gösterilmez',
                  key: const ValueKey('preview-chat-line'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: line == null ? 0.45 : 0.9),
                    fontStyle: line == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Profil başlığının küçük taklidi.
class _MockProfile extends StatelessWidget {
  const _MockProfile({required this.line, required this.online});

  final String? line;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final showDot = line != null && online;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdminUi.page,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ayşe Yılmaz',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AdminUi.ink,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (showDot) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  line ?? 'hiçbir durum gösterilmez',
                  key: const ValueKey('preview-profile-line'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: line == null
                        ? AdminUi.muted.withValues(alpha: 0.7)
                        : (showDot
                              ? const Color(0xFF16A34A)
                              : AdminUi.muted),
                    fontWeight: showDot ? FontWeight.w600 : FontWeight.normal,
                    fontStyle: line == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
