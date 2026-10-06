import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bot_comment_service.dart';
import '../services/bot_service.dart';
import 'admin_ui.dart';

/// Admin > Bot Hesapları > Yorumlar (Görev 4.7).
///
/// * Manuel yorum: bot + gönderi + metin (ya da kitaplıktan), hemen ya da
///   zamanlı.
/// * Otomatik yorum: son gönderileri bir kez değerlendiren zamanlayıcının
///   ayarları (varsayılan KAPALI) ve "kuyruğu şimdi çalıştır".
/// * Kuyruk: bekleyen/yazılan/hatalı işler; bekleyeni iptal, yazılanı sil.
/// * Yorum kitaplığı: hazır metinler (ton, kullanım sayısı, etkin/pasif).
class BotCommentsTab extends StatefulWidget {
  const BotCommentsTab({super.key, required this.bots, this.service});

  /// Bot Hesapları ekranının yüklediği botlar (pasifler seçilemez).
  final List<BotAccount> bots;

  /// Testlerde sahte servis vermek için.
  final BotCommentService? service;

  @override
  State<BotCommentsTab> createState() => _BotCommentsTabState();
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

String _botLabel(BotAccount bot) {
  final name = bot.fullName?.trim().isNotEmpty == true ? bot.fullName!.trim() : (bot.username ?? 'Bot');
  return bot.username == null ? name : '$name · @${bot.username}';
}

class _BotCommentsTabState extends State<BotCommentsTab> with AutomaticKeepAliveClientMixin {
  late final BotCommentService _service = widget.service ?? BotCommentService();

  // Manuel yorum
  String? _botId;
  BotPostOption? _post;
  final _body = TextEditingController();
  final _postSearch = TextEditingController();
  Timer? _postDebounce;
  List<BotPostOption> _posts = const [];
  bool _postsLoading = true;
  int _delayMinutes = 0;
  bool _sending = false;

  // Otomatik ayarlar
  BotCommentSettings? _settings;
  bool _savingSettings = false;
  bool _runningQueue = false;

  // Kuyruk
  String _jobStatus = 'pending';
  BotCommentJobsPage? _jobs;
  bool _jobsLoading = true;
  final Set<String> _busyJobs = {};

  // Kitaplık
  List<BotCommentTemplate>? _library;

  @override
  bool get wantKeepAlive => true;

  List<BotAccount> get _activeBots => [for (final b in widget.bots) if (b.isActive) b];

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadSettings();
    _loadJobs();
    _loadLibrary();
  }

  @override
  void dispose() {
    _postDebounce?.cancel();
    _body.dispose();
    _postSearch.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- yükleme

  Future<void> _loadPosts() async {
    setState(() => _postsLoading = true);
    try {
      final list = await _service.recentPosts(search: _postSearch.text, limit: 20);
      if (!mounted) return;
      setState(() {
        _posts = list;
        _postsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _postsLoading = false);
      _snack(context, BotCommentService.errorMessage(e), error: true);
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _service.loadSettings();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _loadJobs() async {
    setState(() => _jobsLoading = true);
    try {
      final page = await _service.jobs(status: _jobStatus, limit: 30);
      if (!mounted) return;
      setState(() {
        _jobs = page;
        _jobsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _jobsLoading = false);
      _snack(context, BotCommentService.errorMessage(e), error: true);
    }
  }

  Future<void> _loadLibrary() async {
    try {
      final list = await _service.library();
      if (mounted) setState(() => _library = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _library = const []);
      _snack(context, BotCommentService.errorMessage(e), error: true);
    }
  }

  // ---------------------------------------------------------------- işlemler

  Future<void> _send() async {
    final botId = _botId;
    final post = _post;
    final body = _body.text.trim();
    if (botId == null || post == null || body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final result = await _service.comment(
        botId: botId,
        postId: post.id,
        body: body,
        dueAt: _delayMinutes == 0 ? null : DateTime.now().add(Duration(minutes: _delayMinutes)),
      );
      if (!mounted) return;
      _snack(context, result.status == 'done' ? 'Yorum yazıldı' : 'Yorum zamanlandı');
      _body.clear();
      await Future.wait([_loadJobs(), _loadPosts()]);
    } catch (e) {
      if (!mounted) return;
      _snack(context, BotCommentService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickTemplate() async {
    final templates = [for (final t in _library ?? const <BotCommentTemplate>[]) if (t.isActive) t];
    final picked = await showModalBottomSheet<BotCommentTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: templates.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('Kitaplıkta etkin yorum yok.'))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final t in templates)
                    ListTile(
                      key: ValueKey('pick-template-${t.id}'),
                      title: Text(t.body),
                      subtitle: Text(BotCommentService.toneLabel(t.tone)),
                      onTap: () => Navigator.pop(context, t),
                    ),
                ],
              ),
      ),
    );
    if (picked != null && mounted) setState(() => _body.text = picked.body);
  }

  Future<void> _saveSettings(BotCommentSettings settings) async {
    setState(() => _savingSettings = true);
    try {
      await _service.saveSettings(settings);
      if (!mounted) return;
      setState(() => _settings = settings);
      _snack(context, settings.enabled ? 'Otomatik yorum ayarları kaydedildi (açık)' : 'Otomatik yorum kapalı');
    } catch (e) {
      if (!mounted) return;
      _snack(context, BotCommentService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _runQueue() async {
    setState(() => _runningQueue = true);
    try {
      final result = await _service.runQueue();
      if (!mounted) return;
      _snack(context, '${result.scheduled} yorum zamanlandı · ${result.processed} yorum yazıldı');
      await _loadJobs();
    } catch (e) {
      if (!mounted) return;
      _snack(context, BotCommentService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _runningQueue = false);
    }
  }

  Future<void> _cancelJob(BotCommentJob job) async {
    if (job.isDone) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yorum silinsin mi?'),
          content: Text('"${job.body}" yorumu gönderiden kaldırılır.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busyJobs.add(job.id);
    });
    try {
      final status = await _service.cancel(job.id);
      if (!mounted) return;
      _snack(context, status == 'deleted' ? 'Yorum silindi' : 'Zamanlanmış yorum iptal edildi');
    } catch (e) {
      if (!mounted) return;
      _snack(context, BotCommentService.errorMessage(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyJobs.remove(job.id);
        });
      }
    }
    await _loadJobs();
  }

  Future<void> _editTemplate([BotCommentTemplate? template]) async {
    final result = await showDialog<({String body, String tone, bool active})>(
      context: context,
      builder: (_) => _TemplateDialog(template: template),
    );
    if (result == null || !mounted) return;
    try {
      await _service.upsertTemplate(
        id: template?.id,
        body: result.body,
        tone: result.tone,
        isActive: result.active,
      );
      if (!mounted) return;
      _snack(context, template == null ? 'Yorum kitaplığa eklendi' : 'Yorum güncellendi');
    } catch (e) {
      if (!mounted) return;
      _snack(context, BotCommentService.errorMessage(e), error: true);
    }
    await _loadLibrary();
  }

  Future<void> _toggleTemplate(BotCommentTemplate template, bool active) async {
    try {
      await _service.upsertTemplate(id: template.id, body: template.body, tone: template.tone, isActive: active);
    } catch (e) {
      if (!mounted) return;
      _snack(context, BotCommentService.errorMessage(e), error: true);
    }
    await _loadLibrary();
  }

  Future<void> _deleteTemplate(BotCommentTemplate template) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kitaplıktan silinsin mi?'),
        content: Text('"${template.body}" silinir; yazılmış yorumlar etkilenmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteTemplate(template.id);
    } catch (e) {
      if (!mounted) return;
      _snack(context, BotCommentService.errorMessage(e), error: true);
    }
    await _loadLibrary();
  }

  // ---------------------------------------------------------------- görünüm

  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminUi.ink)),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );

  Widget _summary() {
    final jobs = _jobs;
    String n(int? v) => jobs == null ? '–' : '${v ?? 0}';
    return Row(
      children: [
        Expanded(
          child: AdminMiniStat(
            icon: Icons.schedule,
            label: 'Bekleyen',
            value: n(jobs?.pending),
            color: Colors.orange.shade800,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AdminMiniStat(
            icon: Icons.mode_comment_outlined,
            label: '24 saatte',
            value: n(jobs?.done24h),
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AdminMiniStat(
            icon: Icons.error_outline,
            label: 'Hatalı (24s)',
            value: n(jobs?.failed24h),
            color: Colors.red.shade700,
          ),
        ),
      ],
    );
  }

  Widget _manualCard() {
    final bots = _activeBots;
    final canSend = !_sending && _botId != null && _post != null && _body.text.trim().isNotEmpty;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('bot-comment-bot'),
            initialValue: _botId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bot', border: OutlineInputBorder(), isDense: true),
            items: [
              for (final bot in bots)
                DropdownMenuItem(value: bot.id, child: Text(_botLabel(bot), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _sending ? null : (value) => setState(() => _botId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('bot-comment-post-search'),
            controller: _postSearch,
            onChanged: (_) {
              _postDebounce?.cancel();
              _postDebounce = Timer(const Duration(milliseconds: 350), _loadPosts);
            },
            decoration: const InputDecoration(
              labelText: 'Gönderi ara (metin ya da yazar)',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (_postsLoading)
            const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
          else if (_posts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Gönderi bulunamadı', style: TextStyle(color: AdminUi.muted)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final post in _posts)
                    _PostOptionTile(
                      post: post,
                      selected: _post?.id == post.id,
                      onTap: () => setState(() => _post = post),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('bot-comment-body'),
            controller: _body,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Yorum', border: OutlineInputBorder()),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('bot-comment-template'),
                onPressed: _sending ? null : _pickTemplate,
                icon: const Icon(Icons.auto_stories_outlined, size: 18),
                label: const Text('Kitaplıktan'),
              ),
              DropdownButton<int>(
                key: const ValueKey('bot-comment-delay'),
                value: _delayMinutes,
                onChanged: _sending ? null : (value) => setState(() => _delayMinutes = value ?? 0),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Hemen')),
                  DropdownMenuItem(value: 15, child: Text('15 dk sonra')),
                  DropdownMenuItem(value: 60, child: Text('1 saat sonra')),
                  DropdownMenuItem(value: 180, child: Text('3 saat sonra')),
                  DropdownMenuItem(value: 1440, child: Text('Yarın bu saatte')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('bot-comment-send'),
              onPressed: canSend ? _send : null,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_delayMinutes == 0 ? Icons.send_rounded : Icons.schedule_send_rounded, size: 18),
              label: Text(_delayMinutes == 0 ? 'Yorum yap' : 'Zamanla'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobsCard() {
    final jobs = _jobs;
    return AdminCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in const [
                  (value: 'pending', label: 'Bekleyen'),
                  (value: 'done', label: 'Yazılan'),
                  (value: 'failed', label: 'Hatalı'),
                  (value: 'all', label: 'Tümü'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('bot-jobs-${item.value}'),
                      label: Text(item.label),
                      selected: _jobStatus == item.value,
                      onSelected: (_) {
                        if (_jobStatus == item.value) return;
                        setState(() => _jobStatus = item.value);
                        _loadJobs();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_jobsLoading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (jobs == null || jobs.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Kayıt yok', style: TextStyle(color: AdminUi.muted)),
            )
          else
            for (final job in jobs.rows)
              _JobTile(job: job, busy: _busyJobs.contains(job.id), onCancel: () => _cancelJob(job)),
          if (jobs != null && jobs.total > jobs.rows.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'İlk ${jobs.rows.length} kayıt gösteriliyor (toplam ${jobs.total}).',
                style: const TextStyle(fontSize: 12, color: AdminUi.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _libraryCard() {
    final library = _library;
    return AdminCard(
      padding: const EdgeInsets.all(12),
      child: library == null
          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (library.isEmpty)
                  const Text('Kitaplık boş', style: TextStyle(color: AdminUi.muted)),
                for (final t in library)
                  Padding(
                    key: ValueKey('template-${t.id}'),
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.body,
                                style: TextStyle(color: t.isActive ? AdminUi.ink : AdminUi.muted, fontSize: 13.5),
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 6,
                                children: [
                                  AdminPill(label: BotCommentService.toneLabel(t.tone), color: Colors.indigo),
                                  AdminPill(label: '${t.useCount} kez', color: Colors.blueGrey),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Switch(value: t.isActive, onChanged: (v) => _toggleTemplate(t, v)),
                        PopupMenuButton<String>(
                          tooltip: 'Yorum işlemleri',
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editTemplate(t);
                            } else {
                              _deleteTemplate(t);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                            PopupMenuItem(value: 'delete', child: Text('Sil')),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = _settings;
    return RefreshIndicator(
      onRefresh: () => Future.wait([_loadJobs(), _loadPosts(), _loadLibrary(), _loadSettings()]),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          _summary(),
          _sectionTitle('Manuel yorum'),
          _manualCard(),
          _sectionTitle(
            'Otomatik yorum',
            trailing: TextButton.icon(
              key: const ValueKey('bot-comment-run'),
              onPressed: _runningQueue ? null : _runQueue,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Şimdi çalıştır'),
            ),
          ),
          if (settings == null)
            const AdminCard(child: Center(child: CircularProgressIndicator()))
          else
            _AutoSettingsCard(
              key: ValueKey('auto-settings-${settings.hashCode}'),
              settings: settings,
              saving: _savingSettings,
              onSave: _saveSettings,
            ),
          _sectionTitle('Kuyruk'),
          _jobsCard(),
          _sectionTitle(
            'Yorum kitaplığı',
            trailing: TextButton.icon(
              key: const ValueKey('bot-template-add'),
              onPressed: () => _editTemplate(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ekle'),
            ),
          ),
          _libraryCard(),
        ],
      ),
    );
  }
}

class _PostOptionTile extends StatelessWidget {
  const _PostOptionTile({required this.post, required this.selected, required this.onTap});

  final BotPostOption post;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('bot-post-${post.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? AdminUi.brandSoft : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AdminUi.brand : AdminUi.line),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AdminUi.brand : AdminUi.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  Text(
                    [
                      post.authorName ?? 'Bilinmiyor',
                      if (post.authorIsBot) 'bot',
                      '${post.commentsCount} yorum',
                      if (post.createdAt != null) adminTimeAgo(post.createdAt),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.busy, required this.onCancel});

  final BotCommentJob job;
  final bool busy;
  final VoidCallback onCancel;

  Color get _color => switch (job.status) {
    'pending' => Colors.orange.shade800,
    'done' => Colors.green.shade700,
    'failed' => Colors.red.shade700,
    _ => Colors.grey.shade700,
  };

  @override
  Widget build(BuildContext context) {
    final when = job.isPending ? job.dueAt : (job.processedAt ?? job.createdAt);
    return Container(
      key: ValueKey('bot-job-${job.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminUi.page,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminUi.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AdminPill(label: job.statusLabel, color: _color),
              AdminPill(label: job.source == 'manual' ? 'Manuel' : 'Otomatik', color: Colors.blueGrey),
              if (job.botName != null) AdminPill(label: job.botName!, color: AdminUi.brand, icon: Icons.smart_toy_outlined),
            ],
          ),
          const SizedBox(height: 6),
          Text('"${job.body}"', style: const TextStyle(fontSize: 13.5, color: AdminUi.ink)),
          if (job.postPreview != null)
            Text(
              'Gönderi: ${job.postPreview}${job.postAuthorName == null ? '' : ' (${job.postAuthorName})'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AdminUi.muted),
            ),
          Text(
            job.isPending ? 'Vade: ${adminDateTime(when)}' : adminDateTime(when),
            style: const TextStyle(fontSize: 12, color: AdminUi.muted),
          ),
          if (job.errorMessage != null)
            Text(job.errorMessage!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
          if (job.isPending || job.isDone)
            Align(
              alignment: Alignment.centerRight,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                      child: Text(job.isPending ? 'İptal et' : 'Yorumu sil'),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Otomatik yorum ayarları; alanlar sayısal ve sınırlı (sunucu da sınırlar).
class _AutoSettingsCard extends StatefulWidget {
  const _AutoSettingsCard({super.key, required this.settings, required this.saving, required this.onSave});

  final BotCommentSettings settings;
  final bool saving;
  final ValueChanged<BotCommentSettings> onSave;

  @override
  State<_AutoSettingsCard> createState() => _AutoSettingsCardState();
}

class _AutoSettingsCardState extends State<_AutoSettingsCard> {
  final _formKey = GlobalKey<FormState>();
  late bool _enabled = widget.settings.enabled;
  late final _probability = TextEditingController(text: '${widget.settings.probability}');
  late final _minCount = TextEditingController(text: '${widget.settings.minCount}');
  late final _maxCount = TextEditingController(text: '${widget.settings.maxCount}');
  late final _minHours = TextEditingController(text: '${widget.settings.minHours}');
  late final _maxHours = TextEditingController(text: '${widget.settings.maxHours}');
  late final _lookback = TextEditingController(text: '${widget.settings.lookbackDays}');

  @override
  void dispose() {
    for (final c in [_probability, _minCount, _maxCount, _minHours, _maxHours, _lookback]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _number(TextEditingController controller, String label, int min, int max, String key) {
    return SizedBox(
      width: 150,
      child: TextFormField(
        key: ValueKey(key),
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, helperText: '$min–$max', isDense: true),
        validator: (value) {
          final n = int.tryParse(value ?? '');
          if (n == null || n < min || n > max) return '$min–$max arası';
          return null;
        },
      ),
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    int v(TextEditingController c) => int.parse(c.text);
    final minCount = v(_minCount);
    final minHours = v(_minHours);
    widget.onSave(
      BotCommentSettings(
        enabled: _enabled,
        probability: v(_probability),
        minCount: minCount,
        maxCount: v(_maxCount) < minCount ? minCount : v(_maxCount),
        minHours: minHours,
        maxHours: v(_maxHours) < minHours ? minHours : v(_maxHours),
        lookbackDays: v(_lookback),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('bot-comment-auto-enabled'),
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: widget.saving ? null : (value) => setState(() => _enabled = value),
              title: const Text('Botlar otomatik yorum yapsın', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Son gönderiler BİR KEZ değerlendirilir; olasılığa göre seçilen gönderiye kitaplıktan '
                'yorumlar, belirlenen saat aralığına yayılarak yazılır. Bot sahibine bildirim gitmez.',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _number(_probability, 'Olasılık (%)', 0, 100, 'bot-set-probability'),
                _number(_minCount, 'En az yorum', 0, 10, 'bot-set-min-count'),
                _number(_maxCount, 'En çok yorum', 0, 10, 'bot-set-max-count'),
                _number(_minHours, 'En erken (saat)', 0, 168, 'bot-set-min-hours'),
                _number(_maxHours, 'En geç (saat)', 0, 168, 'bot-set-max-hours'),
                _number(_lookback, 'Geriye bakış (gün)', 1, 30, 'bot-set-lookback'),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('bot-comment-settings-save'),
                onPressed: widget.saving ? null : _save,
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kitaplık yorumu ekle/düzenle.
class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({this.template});

  final BotCommentTemplate? template;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _body = TextEditingController(text: widget.template?.body ?? '');
  late String _tone = widget.template?.tone ?? 'genel';
  late bool _active = widget.template?.isActive ?? true;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.template == null ? 'Yorum ekle' : 'Yorumu düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('template-body'),
              controller: _body,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Yorum', errorText: _error, border: const OutlineInputBorder()),
            ),
            DropdownButtonFormField<String>(
              key: const ValueKey('template-tone'),
              initialValue: _tone,
              decoration: const InputDecoration(labelText: 'Ton'),
              items: [
                for (final tone in BotCommentService.tones)
                  DropdownMenuItem(value: tone, child: Text(BotCommentService.toneLabel(tone))),
              ],
              onChanged: (value) => setState(() => _tone = value ?? _tone),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (value) => setState(() => _active = value),
              title: const Text('Otomatik yorumlarda kullanılsın'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final body = _body.text.trim();
            if (body.isEmpty) {
              setState(() => _error = 'Yorum boş olamaz');
              return;
            }
            Navigator.pop(context, (body: body, tone: _tone, active: _active));
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
