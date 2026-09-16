import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/social_access_service.dart';
import '../services/bot_service.dart';

/// Admin panelinin "Bot Hesapları" bölümü.
///
/// Üç sekme:
///  1. Botlar        — profil düzenleme, avatar yükleme, aktif/pasif
///  2. Gönderiler    — bot adına metin/görsel gönderi kuyruğu
///  3. Ayarlar       — otomatik takip aralığı + Keşfet erişimi
class BotManagementContent extends StatefulWidget {
  const BotManagementContent({super.key});

  @override
  State<BotManagementContent> createState() => _BotManagementContentState();
}

class _BotManagementContentState extends State<BotManagementContent>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF6C5CE7);

  late final TabController _tabController;
  final BotService _service = BotService();

  List<BotAccount> _bots = const [];
  BotStats _stats = const BotStats();
  bool _loadingBots = true;
  String? _botsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadBots();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBots() async {
    setState(() {
      _loadingBots = true;
      _botsError = null;
    });
    try {
      final bots = await _service.listBots();
      final stats = await _service.loadStats();
      if (!mounted) return;
      setState(() {
        _bots = bots;
        _stats = stats;
        _loadingBots = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _botsError = e.toString();
        _loadingBots = false;
      });
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: _accent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _accent,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Botlar'),
              Tab(icon: Icon(Icons.post_add), text: 'Gönderiler'),
              Tab(icon: Icon(Icons.auto_stories_outlined), text: 'Kitaplık'),
              Tab(icon: Icon(Icons.tune), text: 'Ayarlar'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBotsTab(),
              _BotQueueTab(service: _service, bots: _bots),
              _BotLibraryTab(service: _service, onChanged: _loadBots),
              _BotSettingsTab(service: _service, onChanged: _loadBots),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Sekme 1 — Botlar
  // ===========================================================================
  Widget _buildBotsTab() {
    if (_loadingBots) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_botsError != null) {
      return _ErrorBox(message: _botsError!, onRetry: _loadBots);
    }

    return RefreshIndicator(
      onRefresh: _loadBots,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatsCard(),
          const SizedBox(height: 16),
          _buildActionsRow(),
          const SizedBox(height: 16),
          if (_bots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'Henüz bot hesabı yok.\n"Hazır 20 botu oluştur" ile başlayabilirsin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._bots.map(_buildBotTile),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      elevation: 0,
      color: _accent.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, color: _accent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Özet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Yenile',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadBots,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatChip(
                  label: 'Bot',
                  value: '${_stats.botCount}',
                  icon: Icons.smart_toy,
                ),
                _StatChip(
                  label: 'Aktif bot',
                  value: '${_stats.activeBotCount}',
                  icon: Icons.check_circle_outline,
                ),
                _StatChip(
                  label: 'Gerçek üye',
                  value: '${_stats.realUserCount}',
                  icon: Icons.people_outline,
                ),
                _StatChip(
                  label: 'Bekleyen takip',
                  value: '${_stats.pendingFollowJobs}',
                  icon: Icons.schedule,
                ),
                _StatChip(
                  label: 'Yapılan takip',
                  value: '${_stats.doneFollowJobs}',
                  icon: Icons.person_add_alt,
                ),
                _StatChip(
                  label: 'Bot gönderisi',
                  value: '${_stats.botPostCount}',
                  icon: Icons.image_outlined,
                ),
                _StatChip(
                  label: 'Bekleyen beğeni',
                  value: '${_stats.pendingLikeJobs}',
                  icon: Icons.favorite_border,
                ),
                _StatChip(
                  label: 'Yapılan beğeni',
                  value: '${_stats.doneLikeJobs}',
                  icon: Icons.favorite,
                ),
                _StatChip(
                  label: 'Kitaplık metin',
                  value: '${_stats.libraryTextCount}',
                  icon: Icons.notes,
                ),
                _StatChip(
                  label: 'Kitaplık görsel',
                  value: '${_stats.libraryImageCount}',
                  icon: Icons.photo_library_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Not: Admin panelindeki üye sayaçları botları saymaz — '
              '"Gerçek üye" rakamı gerçek kayıtları gösterir.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: () => _openBotEditor(null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Yeni bot'),
        ),
        OutlinedButton.icon(
          onPressed: _seedDefaults,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Hazır 20 botu oluştur'),
        ),
        OutlinedButton.icon(
          onPressed: _runQueuesNow,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Kuyrukları şimdi işle'),
        ),
        OutlinedButton.icon(
          onPressed: _backfillFollows,
          icon: const Icon(Icons.group_add_outlined, size: 18),
          label: const Text('Mevcut üyelere takip planla'),
        ),
      ],
    );
  }

  Future<void> _seedDefaults() async {
    try {
      final created = await _service.seedDefaultBots();
      _toast(created > 0
          ? '$created bot oluşturuldu.'
          : 'Hazır botların hepsi zaten mevcut.');
      await _loadBots();
    } catch (e) {
      _toast('Botlar oluşturulamadı: $e', error: true);
    }
  }

  Future<void> _runQueuesNow() async {
    try {
      final result = await _service.runQueuesNow();
      _toast('${result.follows} takip, ${result.posts} gönderi, '
          '${result.likes} beğeni işlendi '
          '(${result.likesScheduled} gönderiye beğeni planlandı).');
      await _loadBots();
    } catch (e) {
      _toast('Kuyruklar işlenemedi: $e', error: true);
    }
  }

  Future<void> _backfillFollows() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mevcut üyelere takip planla'),
        content: const Text(
          'Şimdiye kadar hiç bot takibi planlanmamış üyeler için, '
          'önümüzdeki 72 saate yayılmış takip işleri oluşturulacak. '
          'Bu işlem tekrar çalıştırılabilir; aynı üye için ikinci kez iş açmaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Planla'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final count = await _service.backfillFollows();
      _toast('$count üye için takip planlandı.');
      await _loadBots();
    } catch (e) {
      _toast('Planlama başarısız: $e', error: true);
    }
  }

  Widget _buildBotTile(BotAccount bot) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: _BotAvatar(url: bot.avatarUrl, name: bot.displayName, size: 48),
        title: Row(
          children: [
            Flexible(
              child: Text(
                bot.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            if (!bot.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Pasif', style: TextStyle(fontSize: 10)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('@${bot.username ?? '-'}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if ((bot.bio ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  bot.bio!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: [
                _MiniStat(icon: Icons.people_outline, value: bot.followersCount),
                _MiniStat(icon: Icons.grid_on, value: bot.postsCount),
                _MiniStat(icon: Icons.schedule, value: bot.pendingJobs),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                _openBotEditor(bot);
                break;
              case 'toggle':
                await _toggleActive(bot);
                break;
              case 'post':
                _tabController.animateTo(1);
                break;
              case 'delete':
                await _confirmDelete(bot);
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(bot.isActive ? 'Pasifleştir' : 'Aktifleştir'),
            ),
            const PopupMenuItem(value: 'post', child: Text('Gönderi ekle')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: () => _openBotEditor(bot),
      ),
    );
  }

  Future<void> _toggleActive(BotAccount bot) async {
    try {
      await _service.updateBot(id: bot.id, isActive: !bot.isActive);
      await _loadBots();
    } catch (e) {
      _toast('Güncellenemedi: $e', error: true);
    }
  }

  Future<void> _confirmDelete(BotAccount bot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${bot.displayName} silinsin mi?'),
        content: const Text(
          'Bot hesabı ve ona ait TÜM gönderiler, takipler kalıcı olarak silinir. '
          'Bu işlem geri alınamaz. Sadece görünürlüğünü kapatmak istiyorsan '
          '"Pasifleştir" seçeneğini kullan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteBot(bot.id);
      _toast('Bot silindi.');
      await _loadBots();
    } catch (e) {
      _toast('Silinemedi: $e', error: true);
    }
  }

  Future<void> _openBotEditor(BotAccount? bot) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BotEditorSheet(service: _service, bot: bot),
    );
    if (saved == true) await _loadBots();
  }
}

// =============================================================================
// Bot düzenleme formu
// =============================================================================
class _BotEditorSheet extends StatefulWidget {
  final BotService service;
  final BotAccount? bot;

  const _BotEditorSheet({required this.service, this.bot});

  @override
  State<_BotEditorSheet> createState() => _BotEditorSheetState();
}

class _BotEditorSheetState extends State<_BotEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _location;
  late final TextEditingController _website;
  late final TextEditingController _persona;

  bool _isActive = true;
  bool _autoFollow = true;
  bool _saving = false;
  String? _avatarUrl;
  XFile? _pickedAvatar;

  bool get _isNew => widget.bot == null;

  @override
  void initState() {
    super.initState();
    final b = widget.bot;
    _fullName = TextEditingController(text: b?.fullName ?? '');
    _username = TextEditingController(text: b?.username ?? '');
    _bio = TextEditingController(text: b?.bio ?? '');
    _location = TextEditingController(text: b?.location ?? 'Cizre, Şırnak');
    _website = TextEditingController(text: b?.website ?? '');
    _persona = TextEditingController(text: b?.persona ?? '');
    _isActive = b?.isActive ?? true;
    _autoFollow = b?.autoFollowEnabled ?? true;
    _avatarUrl = b?.avatarUrl;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _bio.dispose();
    _location.dispose();
    _website.dispose();
    _persona.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (file == null) return;
    setState(() => _pickedAvatar = file);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      String botId;
      if (_isNew) {
        botId = await widget.service.createBot(
          fullName: _fullName.text.trim(),
          username: _username.text.trim(),
          bio: _bio.text.trim(),
          location: _location.text.trim(),
          website: _website.text.trim(),
          persona: _persona.text.trim(),
        );
      } else {
        botId = widget.bot!.id;
      }

      // Avatar, botun kimliği belli olduktan sonra yüklenir (dosya adı bot
      // id'sini taşır, böylece storage'da hangi bota ait olduğu belli olur).
      String? newAvatarUrl;
      if (_pickedAvatar != null) {
        newAvatarUrl = await widget.service.uploadBotAvatar(botId, _pickedAvatar!);
      }

      await widget.service.updateBot(
        id: botId,
        fullName: _fullName.text.trim(),
        username: _isNew ? null : _username.text.trim(),
        bio: _bio.text.trim(),
        avatarUrl: newAvatarUrl,
        location: _location.text.trim(),
        website: _website.text.trim(),
        persona: _persona.text.trim(),
        isActive: _isActive,
        autoFollowEnabled: _autoFollow,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kaydedilemedi: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isNew ? 'Yeni bot hesabı' : 'Botu düzenle',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Stack(
                    children: [
                      _pickedAvatar != null
                          ? ClipOval(
                              child: _LocalImageThumb(
                                file: _pickedAvatar!,
                                size: 88,
                              ),
                            )
                          : _BotAvatar(
                              url: _avatarUrl,
                              name: _fullName.text.isEmpty
                                  ? 'Bot'
                                  : _fullName.text,
                              size: 88,
                            ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: const Color(0xFF6C5CE7),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _pickAvatar,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.camera_alt,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_pickedAvatar != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: Text(
                        'Yeni fotoğraf seçildi, kaydedince yüklenecek.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                _field(_fullName, 'Ad Soyad', required: true),
                const SizedBox(height: 12),
                _field(
                  _username,
                  'Kullanıcı adı',
                  required: true,
                  enabled: true,
                  hint: 'ornek.kullanici',
                  validator: (v) {
                    final value = (v ?? '').trim().toLowerCase();
                    if (value.isEmpty) return 'Zorunlu alan';
                    if (!RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(value)) {
                      return 'Yalnız a-z, 0-9, nokta ve alt çizgi (3-30 karakter)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _field(_bio, 'Biyografi', maxLines: 3),
                const SizedBox(height: 12),
                _field(_location, 'Konum'),
                const SizedBox(height: 12),
                _field(_website, 'Web sitesi'),
                const SizedBox(height: 12),
                _field(_persona, 'Persona notu (yalnız admin görür)'),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('Aktif'),
                  subtitle: const Text(
                    'Pasif bot yeni takip yapmaz ve gönderi yayınlamaz.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoFollow,
                  onChanged: (v) => setState(() => _autoFollow = v),
                  title: const Text('Yeni üyeleri otomatik takip et'),
                  subtitle: const Text(
                    'Kapalıysa bu bot yeni kayıt olanları takip etmez.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isNew ? 'Oluştur' : 'Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool enabled = true,
    int maxLines = 1,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
      validator: validator ??
          (required
              ? (v) => (v ?? '').trim().isEmpty ? 'Zorunlu alan' : null
              : null),
    );
  }
}

// =============================================================================
// Sekme 2 — Gönderi kuyruğu
// =============================================================================
class _BotQueueTab extends StatefulWidget {
  final BotService service;
  final List<BotAccount> bots;

  const _BotQueueTab({required this.service, required this.bots});

  @override
  State<_BotQueueTab> createState() => _BotQueueTabState();
}

class _BotQueueTabState extends State<_BotQueueTab> {
  List<BotQueuedPost> _items = const [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.listQueue(status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Tümü', null),
                      _filterChip('Bekleyen', 'pending'),
                      _filterChip('Yayınlanan', 'published'),
                      _filterChip('Hatalı', 'failed'),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Yenile',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
              ),
              onPressed: widget.bots.isEmpty ? null : () => _openEditor(null),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Bot gönderisi oluştur'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorBox(message: _error!, onRetry: _load)
                  : _items.isEmpty
                      ? const Center(
                          child: Text(
                            'Kuyrukta gönderi yok.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _items.length,
                            itemBuilder: (_, i) => _queueTile(_items[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _statusFilter = value);
          _load();
        },
      ),
    );
  }

  Widget _queueTile(BotQueuedPost item) {
    final statusColor = switch (item.status) {
      'published' => Colors.green,
      'failed' => Colors.red,
      'cancelled' => Colors.grey,
      _ => Colors.orange,
    };
    final statusLabel = switch (item.status) {
      'published' => 'Yayınlandı',
      'failed' => 'Hata',
      'cancelled' => 'İptal',
      _ => 'Bekliyor',
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BotAvatar(
                  url: item.botAvatarUrl,
                  name: item.botFullName ?? 'Rastgele bot',
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.botFullName ?? 'Rastgele bot (yayında seçilir)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _formatDate(item.scheduledAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if ((item.content ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(item.content!.trim(), style: const TextStyle(fontSize: 13)),
            ],
            if (item.images.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: item.images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: item.images[i],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if ((item.errorMessage ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.errorMessage!,
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (item.isPending)
                  TextButton.icon(
                    onPressed: () => _openEditor(item),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Düzenle'),
                  ),
                TextButton.icon(
                  onPressed: () => _delete(item),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.red),
                  label: const Text('Sil',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BotQueuedPost item) async {
    try {
      await widget.service.deleteQueuedPost(item.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    }
  }

  Future<void> _openEditor(BotQueuedPost? item) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QueuePostEditorSheet(
        service: widget.service,
        bots: widget.bots,
        item: item,
      ),
    );
    if (saved == true) await _load();
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

// =============================================================================
// Gönderi oluşturma / düzenleme
// =============================================================================
class _QueuePostEditorSheet extends StatefulWidget {
  final BotService service;
  final List<BotAccount> bots;
  final BotQueuedPost? item;

  const _QueuePostEditorSheet({
    required this.service,
    required this.bots,
    this.item,
  });

  @override
  State<_QueuePostEditorSheet> createState() => _QueuePostEditorSheetState();
}

class _QueuePostEditorSheetState extends State<_QueuePostEditorSheet> {
  final _content = TextEditingController();
  final _location = TextEditingController();

  String? _botId;
  List<String> _existingImages = [];
  final List<XFile> _newImages = [];
  DateTime _scheduledAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _content.text = item.content ?? '';
      _location.text = item.location ?? '';
      _botId = item.botId;
      _existingImages = List.of(item.images);
      _scheduledAt = item.scheduledAt;
    }
  }

  @override
  void dispose() {
    _content.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(
      maxWidth: 1440,
      maxHeight: 1440,
      imageQuality: 88,
    );
    if (files.isEmpty) return;
    setState(() => _newImages.addAll(files));
  }

  Future<void> _pickSchedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null) return;

    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final text = _content.text.trim();
    if (text.isEmpty && _existingImages.isEmpty && _newImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Metin veya en az bir görsel gerekli.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // Görseller storage'a botun (veya seçili değilse ilk botun) kimliğiyle
      // yüklenir; dosya adı yalnız izlenebilirlik içindir, gönderinin sahibi
      // yayın anında `bot_id` alanından belirlenir.
      final uploadOwner = _botId ?? widget.bots.first.id;
      final uploaded = _newImages.isEmpty
          ? const <String>[]
          : await widget.service.uploadPostImages(uploadOwner, _newImages);

      await widget.service.upsertQueuedPost(
        id: widget.item?.id,
        botId: _botId,
        content: text,
        images: [..._existingImages, ...uploaded],
        location: _location.text.trim(),
        scheduledAt: _scheduledAt,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kaydedilemedi: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.item == null ? 'Bot gönderisi' : 'Gönderiyi düzenle',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _botId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Yayınlayacak bot',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Rastgele aktif bot'),
                  ),
                  ...widget.bots.map(
                    (b) => DropdownMenuItem<String?>(
                      value: b.id,
                      child: Text('${b.displayName}  ·  @${b.username ?? '-'}'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _botId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _content,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Gönderi metni',
                  alignLabelWithHint: true,
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                decoration: InputDecoration(
                  labelText: 'Konum (isteğe bağlı)',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Görseller',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 18),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
              if (_existingImages.isEmpty && _newImages.isEmpty)
                Text(
                  'Henüz görsel yok — sadece metin de paylaşılabilir.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._existingImages.map(
                      (url) => _thumb(
                        child: CachedNetworkImage(
                          imageUrl: url,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                        ),
                        onRemove: () =>
                            setState(() => _existingImages.remove(url)),
                      ),
                    ),
                    ..._newImages.map(
                      (file) => _thumb(
                        child: _LocalImageThumb(file: file, size: 76),
                        onRemove: () => setState(() => _newImages.remove(file)),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Yayın zamanı'),
                subtitle: Text(_formatDate(_scheduledAt)),
                trailing: TextButton(
                  onPressed: _pickSchedule,
                  child: const Text('Değiştir'),
                ),
              ),
              Text(
                'Geçmiş bir saat seçersen kuyruk taraması (5 dakikada bir) '
                'ilk turda yayınlar.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Kuyruğa ekle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb({required Widget child, required VoidCallback onRemove}) {
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

// =============================================================================
// Sekme 3 — İçerik kitaplığı
// =============================================================================
// Hazır gönderi metinleri ve görselleri burada durur. "Gönderi üret" bu
// kitaplıktan beslenir; dağıtım sunucuda DÜZENSİZ yapılır (bir bot çok, bir
// bot az paylaşır; tarihler kümelenir) — böylece akış otomatik üretilmiş gibi
// görünmez.
class _BotLibraryTab extends StatefulWidget {
  final BotService service;
  final Future<void> Function() onChanged;

  const _BotLibraryTab({required this.service, required this.onChanged});

  @override
  State<_BotLibraryTab> createState() => _BotLibraryTabState();
}

class _BotLibraryTabState extends State<_BotLibraryTab> {
  static const Color _accent = Color(0xFF6C5CE7);

  List<BotLibraryText> _texts = const [];
  List<BotLibraryImage> _images = const [];
  bool _loading = true;
  String? _error;
  String? _toneFilter;
  bool _showImages = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final texts = await widget.service.listLibraryTexts(tone: _toneFilter);
      final images = await widget.service.listLibraryImages();
      if (!mounted) return;
      setState(() {
        _texts = texts;
        _images = images;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorBox(message: _error!, onRetry: _load);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text('Metin (${_texts.length})'),
                      icon: const Icon(Icons.notes, size: 16),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Görsel (${_images.length})'),
                      icon: const Icon(Icons.photo_library_outlined, size: 16),
                    ),
                  ],
                  selected: {_showImages},
                  onSelectionChanged: (v) =>
                      setState(() => _showImages = v.first),
                ),
              ),
              IconButton(
                tooltip: 'Yenile',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  onPressed: _showImages ? _addImage : () => _editText(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_showImages ? 'Görsel yükle' : 'Metin ekle'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openPublishDialog,
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('Gönderi üret'),
                ),
              ),
            ],
          ),
        ),
        if (!_showImages) _toneFilterRow(),
        const SizedBox(height: 4),
        Expanded(child: _showImages ? _imageGrid() : _textList()),
      ],
    );
  }

  Widget _toneFilterRow() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Tümü'),
              selected: _toneFilter == null,
              onSelected: (_) {
                setState(() => _toneFilter = null);
                _load();
              },
            ),
          ),
          ...kBotContentTones.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _toneFilter == e.key,
                onSelected: (_) {
                  setState(() => _toneFilter = e.key);
                  _load();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textList() {
    if (_texts.isEmpty) {
      return const Center(
        child: Text('Bu tonda metin yok.', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _texts.length,
        itemBuilder: (_, i) {
          final t = _texts[i];
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              title: Text(
                t.body,
                style: TextStyle(
                  fontSize: 13,
                  color: t.isActive ? Colors.black87 : Colors.grey,
                  decoration: t.isActive ? null : TextDecoration.lineThrough,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        kBotContentTones[t.tone] ?? t.tone,
                        style: const TextStyle(fontSize: 10.5, color: _accent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${t.usedCount} kez kullanıldı',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    _editText(t);
                  } else if (v == 'toggle') {
                    await _toggleText(t);
                  } else if (v == 'delete') {
                    await _deleteEntry('text', t.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(t.isActive ? 'Pasifleştir' : 'Aktifleştir'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Sil', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
              onTap: () => _editText(t),
            ),
          );
        },
      ),
    );
  }

  Widget _imageGrid() {
    if (_images.isEmpty) {
      return const Center(
        child:
            Text('Kitaplıkta görsel yok.', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _images.length,
        itemBuilder: (_, i) {
          final img = _images[i];
          return GestureDetector(
            onLongPress: () => _deleteEntry('image', img.id),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: img.url,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image, size: 18),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Text(
                        '${kBotContentTones[img.tone] ?? img.tone} · ${img.usedCount}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleText(BotLibraryText t) async {
    try {
      await widget.service.upsertLibraryText(
        id: t.id,
        body: t.body,
        tone: t.tone,
        isActive: !t.isActive,
      );
      await _load();
    } catch (e) {
      _toast('Güncellenemedi: $e', error: true);
    }
  }

  Future<void> _deleteEntry(String kind, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: Text(
          kind == 'text'
              ? 'Bu metin kitaplıktan kalıcı olarak silinecek. Daha önce bu '
                  'metinle üretilmiş gönderiler silinmez.'
              : 'Bu görsel kitaplıktan silinecek. Daha önce bu görselle '
                  'üretilmiş gönderiler silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.service.deleteLibraryEntry(kind: kind, id: id);
      await _load();
      await widget.onChanged();
    } catch (e) {
      _toast('Silinemedi: $e', error: true);
    }
  }

  Future<void> _addImage() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(
      maxWidth: 1440,
      maxHeight: 1440,
      imageQuality: 88,
    );
    if (files.isEmpty || !mounted) return;

    final tone = await _pickTone();
    if (tone == null) return;

    try {
      for (final f in files) {
        await widget.service.addLibraryImage(f, tone: tone);
      }
      _toast('${files.length} görsel kitaplığa eklendi.');
      await _load();
      await widget.onChanged();
    } catch (e) {
      _toast('Yüklenemedi: $e', error: true);
    }
  }

  Future<String?> _pickTone({String initial = 'gunluk'}) async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ton seç',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            ...kBotContentTones.entries.map(
              (e) => ListTile(
                dense: true,
                title: Text(e.value),
                trailing: e.key == initial
                    ? const Icon(Icons.check, size: 18, color: _accent)
                    : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editText(BotLibraryText? t) async {
    final controller = TextEditingController(text: t?.body ?? '');
    String tone = t?.tone ?? 'gunluk';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t == null ? 'Metin ekle' : 'Metni düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Gönderi metni',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tone,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Ton',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: kBotContentTones.entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setLocal(() => tone = v ?? tone),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final body = controller.text.trim();
    if (body.isEmpty) {
      _toast('Metin boş olamaz.', error: true);
      return;
    }

    try {
      await widget.service.upsertLibraryText(
        id: t?.id,
        body: body,
        tone: tone,
        isActive: t?.isActive ?? true,
      );
      await _load();
      await widget.onChanged();
    } catch (e) {
      _toast('Kaydedilemedi: $e', error: true);
    }
  }

  Future<void> _openPublishDialog() async {
    int total = 30;
    int spreadDays = 180;
    int imagePercent = 35;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Kitaplıktan gönderi üret'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Metinler botlara düzensiz dağıtılır: bazı botlar çok, bazıları '
                'az paylaşır ve tarihler kümelenir. En az kullanılmış metinler '
                'önce seçilir.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              _slider('Gönderi sayısı', total, 5, 140,
                  (v) => setLocal(() => total = v)),
              _slider('Kaç güne yayılsın', spreadDays, 7, 365,
                  (v) => setLocal(() => spreadDays = v)),
              _slider('Görselli oranı (%)', imagePercent, 0, 100,
                  (v) => setLocal(() => imagePercent = v)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Üret'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      final created = await widget.service.publishFromLibrary(
        total: total,
        spreadDays: spreadDays,
        imagePercent: imagePercent,
      );
      _toast('$created gönderi üretildi.');
      await _load();
      await widget.onChanged();
    } catch (e) {
      _toast('Üretilemedi: $e', error: true);
    }
  }

  Widget _slider(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

// =============================================================================
// Sekme 4 — Ayarlar
// =============================================================================
class _BotSettingsTab extends StatefulWidget {
  final BotService service;
  final Future<void> Function() onChanged;

  const _BotSettingsTab({required this.service, required this.onChanged});

  @override
  State<_BotSettingsTab> createState() => _BotSettingsTabState();
}

class _BotSettingsTabState extends State<_BotSettingsTab> {
  BotFollowSettings _settings = const BotFollowSettings();
  BotLikeSettings _likeSettings = const BotLikeSettings();
  bool _explorePublic = SocialAccessService.defaultIsPublic;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await widget.service.loadFollowSettings();
    final likeSettings = await widget.service.loadLikeSettings();
    final explorePublic =
        await SocialAccessService.fetchIsPublic(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _likeSettings = likeSettings;
      _explorePublic = explorePublic;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.saveFollowSettings(_settings);
      await widget.service.saveLikeSettings(_likeSettings);
      await SocialAccessService.setIsPublic(_explorePublic);
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ayarlar kaydedildi.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kaydedilemedi: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionCard(
          icon: Icons.explore_outlined,
          title: 'Keşfet erişimi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: false,
                // ignore: deprecated_member_use
                groupValue: _explorePublic,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _explorePublic = v ?? false),
                title: const Text('Sadece üyelere açık'),
                subtitle: const Text(
                  'Misafirler Keşfet sekmesine girmek isteyince giriş ekranına yönlendirilir.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: true,
                // ignore: deprecated_member_use
                groupValue: _explorePublic,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _explorePublic = v ?? false),
                title: const Text('Herkese açık (salt okunur)'),
                subtitle: const Text(
                  'Misafir gönderileri görebilir; beğeni, yorum, paylaşım ve '
                  'hikâye için giriş istenir. Gizli hesapların gönderileri '
                  'misafire gösterilmez.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Yeni üyeyi otomatik takip',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _settings.enabled,
                onChanged: (v) =>
                    setState(() => _settings = _settings.copyWith(enabled: v)),
                title: const Text('Etkin'),
              ),
              const SizedBox(height: 4),
              _numberRow(
                label: 'Gecikme aralığı (saat)',
                first: _settings.minHours,
                second: _settings.maxHours,
                max: 336,
                onChanged: (a, b) => setState(
                  () => _settings = _settings.copyWith(minHours: a, maxHours: b),
                ),
              ),
              const SizedBox(height: 12),
              _numberRow(
                label: 'Üye başına bot sayısı',
                first: _settings.minCount,
                second: _settings.maxCount,
                max: 50,
                onChanged: (a, b) => setState(
                  () => _settings = _settings.copyWith(minCount: a, maxCount: b),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Yeni üye kaydolduğunda, seçilen aralıkta rastgele sayıda bot, '
                'rastgele zamanlarda takip eder. Takipler 10 dakikada bir '
                'çalışan sunucu görevi ile işlenir.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          icon: Icons.favorite_border,
          title: 'Gönderi beğenme',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _likeSettings.enabled,
                onChanged: (v) => setState(
                  () => _likeSettings = _likeSettings.copyWith(enabled: v),
                ),
                title: const Text('Etkin'),
                subtitle: const Text(
                  'Botlar yeni gönderileri beğenir; gönderi sahibi normal '
                  '"beğendi" bildirimini alır.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 4),
              _numberRow(
                label: 'Beğeni gecikmesi (saat)',
                first: _likeSettings.minHours,
                second: _likeSettings.maxHours,
                max: 168,
                onChanged: (a, b) => setState(
                  () => _likeSettings =
                      _likeSettings.copyWith(minHours: a, maxHours: b),
                ),
              ),
              const SizedBox(height: 12),
              _numberRow(
                label: 'Gönderi başına beğeni',
                first: _likeSettings.minCount,
                second: _likeSettings.maxCount,
                max: 20,
                onChanged: (a, b) => setState(
                  () => _likeSettings =
                      _likeSettings.copyWith(minCount: a, maxCount: b),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Kaç günlük gönderiler değerlendirilsin',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: _stepper(
                      value: _likeSettings.lookbackDays,
                      min: 1,
                      max: 60,
                      caption: 'Gün',
                      onChanged: (v) => setState(
                        () => _likeSettings =
                            _likeSettings.copyWith(lookbackDays: v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Beğeniler tek anda değil, gönderi başına seçilen aralığa '
                'yayılarak gelir. Birikmiş eski gönderilerin beğenileri de '
                'şimdiden itibaren dağıtılır — hepsi aynı dakikada düşmez.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save, size: 18),
            label: const Text('Ayarları kaydet'),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF6C5CE7)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _numberRow({
    required String label,
    required int first,
    required int second,
    required int max,
    required void Function(int, int) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _stepper(
                value: first,
                min: 0,
                max: second,
                onChanged: (v) => onChanged(v, second),
                caption: 'En az',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _stepper(
                value: second,
                min: first,
                max: max,
                onChanged: (v) => onChanged(first, v),
                caption: 'En çok',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepper({
    required int value,
    required int min,
    required int max,
    required String caption,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 16),
          ),
          Expanded(
            child: Column(
              children: [
                Text(caption,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                Text('$value',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add, size: 16),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Küçük parçalar
// =============================================================================
class _BotAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;

  const _BotAvatar({required this.url, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join();

    if ((url ?? '').trim().isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontSize: size / 3,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF6C5CE7),
          ),
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: size / 2,
          backgroundColor: Colors.grey.shade200,
          child: Icon(Icons.person, size: size / 2, color: Colors.grey),
        ),
      ),
    );
  }
}

/// Henüz yüklenmemiş, yerel olarak seçilmiş bir görselin önizlemesi.
///
/// `XFile.path` mobilde bir dosya sistemi yoludur, web'de ise blob URL'i —
/// ikisini de tek koddan çizmenin taşınabilir yolu baytları okumaktır.
class _LocalImageThumb extends StatelessWidget {
  final XFile file;
  final double size;

  const _LocalImageThumb({required this.file, required this.size});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
          );
        }
        return Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.grey.shade400,
            ),
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final int value;

  const _MiniStat({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text('$value',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
