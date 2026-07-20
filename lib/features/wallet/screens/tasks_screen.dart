import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/task_earning_model.dart';
import '../../../core/services/task_earning_service.dart';
import '../../../shared/widgets/fullscreen_image_viewer.dart';

/// Görev Yaparak Kazan - Ana Liste Ekranı
/// Reklam kartının altına eklenen "Görevler" butonundan açılır
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TaskEarningService _service = TaskEarningService.instance;

  List<Task> _tasks = [];
  List<TaskCategory> _categories = [];
  String? _selectedCategoryId;
  bool _isLoading = true;
  String? _error;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    final count = await _service.getUserPendingCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getActiveTasks(categoryId: _selectedCategoryId),
        _service.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _tasks = results[0] as List<Task>;
        _categories = results[1] as List<TaskCategory>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Görevler'),
        centerTitle: false,
        actions: [
          if (_pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_pendingCount bekleyen',
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 11),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 22),
            tooltip: 'Geçmişim',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TaskHistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          // Kategori filtreleri
          if (_categories.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildCategoryChips(),
            ),

          // Görev listesi
          if (_tasks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Şu an aktif görev yok',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Daha sonra tekrar kontrol edin',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TaskCard(
                      task: _tasks[index],
                      onClaimed: () => _loadData(),
                    ),
                  ),
                  childCount: _tasks.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _CategoryChip(
              label: 'Tümü',
              icon: '🎯',
              isSelected: _selectedCategoryId == null,
              onTap: () {
                setState(() => _selectedCategoryId = null);
                _loadData();
              },
            ),
            const SizedBox(width: 8),
            ..._categories.map((cat) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CategoryChip(
                    label: cat.name,
                    icon: cat.icon ?? '📋',
                    isSelected: _selectedCategoryId == cat.id,
                    onTap: () {
                      setState(() => _selectedCategoryId = cat.id);
                      _loadData();
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? Colors.purple : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Görev Kartı
class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onClaimed;

  const _TaskCard({required this.task, required this.onClaimed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(taskId: task.id),
          ),
        ).then((_) => onClaimed()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Görsel önizleme (varsa — üst kısımda, tıklanabilir)
            if (task.imageUrl != null && task.imageUrl!.isNotEmpty)
              GestureDetector(
                onTap: () => FullscreenImageViewer.open(
                  context,
                  imageUrl: task.imageUrl!,
                  heroTag: 'task_list_${task.id}',
                  caption: task.title,
                ),
                child: Hero(
                  tag: 'task_list_${task.id}',
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: Image.network(
                      task.imageUrl!,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: kategori + ödül
              Row(
                children: [
                  if (task.categoryIcon != null) ...[
                    Text(task.categoryIcon!, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                  ],
                  if (task.categoryName != null)
                    Flexible(
                      child: Text(
                        task.categoryName!,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade600, Colors.green.shade400],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '₺${task.rewardAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Başlık
              Text(
                task.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Açıklama
              Text(
                task.description,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Uyarı varsa
              if (task.warningText != null && task.warningText!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          task.warningText!,
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Alt: katılımcı + durum
              Row(
                children: [
                  Icon(Icons.people_outline, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${task.remainingSlots} / ${task.maxParticipants} yer kaldı',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(),
                ],
              ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    if (task.userAlreadyClaimed) {
      final status = task.userSubmissionStatus;
      Color color;
      String label;
      IconData icon;

      if (status == TaskSubmissionStatus.approved) {
        color = Colors.green;
        label = 'Onaylandı ✓';
        icon = Icons.check_circle;
      } else if (status == TaskSubmissionStatus.rejected) {
        color = Colors.red;
        label = 'Reddedildi';
        icon = Icons.cancel;
      } else {
        color = Colors.orange;
        label = 'Onay Bekliyor';
        icon = Icons.hourglass_empty;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    if (!task.isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          task.remainingSlots > 0 ? 'Yakında' : 'Dolu',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade600, Colors.purple.shade400],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'Göreve Git',
            style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Görev Detay + Katılım Ekranı
class TaskDetailScreen extends StatefulWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final TaskEarningService _service = TaskEarningService.instance;
  final ImagePicker _picker = ImagePicker();

  Task? _task;
  bool _isLoading = true;
  bool _isClaiming = false;
  bool _isUploading = false;
  String? _error;
  String? _mySubmissionId;
  TaskSubmissionStatus? _myStatus;
  XFile? _selectedImage;
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  Future<void> _loadTask() async {
    setState(() => _isLoading = true);
    try {
      final tasks = await _service.getActiveTasks();
      final task = tasks.where((t) => t.id == widget.taskId).firstOrNull;
      if (!mounted) return;
      setState(() {
        _task = task;
        _mySubmissionId = task?.userSubmissionId;
        _myStatus = task?.userSubmissionStatus;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _claimTask() async {
    if (_task == null) return;
    setState(() => _isClaiming = true);
    try {
      final submissionId = await _service.claimTask(widget.taskId);
      if (!mounted) return;
      setState(() {
        _mySubmissionId = submissionId;
        _myStatus = TaskSubmissionStatus.pending;
        _isClaiming = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Göreve katıldınız! Ekran görüntüsü yükleyin.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClaiming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() => _selectedImage = image);
    }
  }

  Future<void> _submitProof() async {
    if (_selectedImage == null || _mySubmissionId == null) return;
    setState(() => _isUploading = true);
    try {
      // 1. Yükle
      final url = await _service.uploadTaskScreenshot(
        submissionId: _mySubmissionId!,
        file: _selectedImage!,
      );
      // 2. Bağla
      await _service.submitTaskWithProof(
        submissionId: _mySubmissionId!,
        screenshotUrl: url,
        userNote: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _myStatus = TaskSubmissionStatus.pending;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ekran görüntüsü gönderildi! Admin onayını bekleyin.'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Widget _previewFallback() => Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Icon(Icons.image, size: 48)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_task?.title ?? 'Görev Detayı'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _task == null
              ? Center(child: Text(_error ?? 'Görev bulunamadı'))
              : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final task = _task!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ödül kartı
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade600, Colors.green.shade400],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.monetization_on, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kazanacağınız Ödül',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      '₺${task.rewardAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Açıklama
          Text(task.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(task.description, style: TextStyle(color: Colors.grey.shade700, height: 1.5)),

          // Görsel (varsa — tam ekran için tıklanabilir)
          if (task.imageUrl != null && task.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => FullscreenImageViewer.open(
                context,
                imageUrl: task.imageUrl!,
                heroTag: 'task_${task.id}',
                caption: task.title,
              ),
              child: Hero(
                tag: 'task_${task.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    task.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Uyarı
          if (task.warningText != null && task.warningText!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  Expanded(child: Text(task.warningText!, style: TextStyle(color: Colors.orange.shade900))),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Link varsa
          if (task.taskLink != null && task.taskLink!.isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(task.taskLink!);
                if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Link açılamadı: ${task.taskLink}')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Görev Linkini Aç'),
            ),
            const SizedBox(height: 16),
          ],

          // Katılımcı durumu
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.people, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text('${task.remainingSlots} / ${task.maxParticipants} yer kaldı'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Görev durumuna göre içerik
          if (task.userAlreadyClaimed) ...[
            _buildClaimedContent(theme),
          ] else if (task.canClaim) ...[
            _buildClaimButton(),
          ] else ...[
            _buildNotAvailable(),
          ],
        ],
      ),
    );
  }

  Widget _buildClaimedContent(ThemeData theme) {
    if (_myStatus == TaskSubmissionStatus.approved) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ödülünüz onaylandı! 🎉', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Bakiyenize ₺${_task?.rewardAmount.toStringAsFixed(2)} eklendi.', style: TextStyle(color: Colors.green.shade700)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_myStatus == TaskSubmissionStatus.rejected) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel, color: Colors.red.shade700, size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Başvurunuz reddedildi. Tekrar göreve katılabilirsiniz.', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
    }

    // Pending — ekran görüntüsü yükleme
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_empty, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Ekran Görüntüsü Yükleyin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Görevi tamamladıktan sonra ekran görüntüsü yükleyerek gönderin.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Seçilen görsel önizleme
            if (_selectedImage != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb
                        ? Image.network(
                            _selectedImage!.path,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _previewFallback(),
                          )
                        : Image.file(
                            File(_selectedImage!.path),
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _previewFallback(),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      onPressed: () => setState(() => _selectedImage = null),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    ),
                  ),
                ],
              )
            else
              InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey.shade500),
                      const SizedBox(height: 8),
                      Text('Ekran Görüntüsü Seç', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('Galeriden Seç veya Fotoğraf Çek'),
            ),
            const SizedBox(height: 12),

            // Not alanı
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Not (opsiyonel)',
                hintText: 'Örn: Takip ettim, beğendim...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Gönder butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedImage == null || _isUploading ? null : _submitProof,
                icon: _isUploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_isUploading ? 'Gönderiliyor...' : 'Gönder ve Onayla'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClaimButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isClaiming ? null : _claimTask,
        icon: _isClaiming
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.play_arrow),
        label: Text(_isClaiming ? 'Katılınıyor...' : 'Göreve Katıl'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildNotAvailable() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _task!.remainingSlots > 0
                  ? 'Bu görev henüz başlamadı'
                  : 'Bu görev için yer kalmadı',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kullanıcı Görev Geçmişi
class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({super.key});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  final TaskEarningService _service = TaskEarningService.instance;

  List<TaskSubmission> _history = [];
  bool _isLoading = true;
  TaskSubmissionStatus? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final history = await _service.getUserTaskHistory(status: _filter);
      if (!mounted) return;
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Görev Geçmişim'),
        actions: [
          PopupMenuButton<TaskSubmissionStatus?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (status) {
              setState(() => _filter = status);
              _load();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('Tümü')),
              const PopupMenuItem(value: TaskSubmissionStatus.pending, child: Text('Beklemede')),
              const PopupMenuItem(value: TaskSubmissionStatus.approved, child: Text('Onaylandı')),
              const PopupMenuItem(value: TaskSubmissionStatus.rejected, child: Text('Reddedildi')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('Henüz görev geçmişiniz yok'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    itemBuilder: (context, index) => _buildHistoryCard(_history[index]),
                  ),
                ),
    );
  }

  Widget _buildHistoryCard(TaskSubmission s) {
    Color statusColor;
    IconData statusIcon;
    if (s.status == TaskSubmissionStatus.approved) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (s.status == TaskSubmissionStatus.rejected) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.taskTitle ?? 'Görev',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        s.status.label,
                        style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (s.screenshotUrl != null && s.screenshotUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => FullscreenImageViewer.open(
                  context,
                  imageUrl: s.screenshotUrl!,
                  heroTag: 'history_shot_${s.id}',
                  caption: s.taskTitle,
                ),
                child: Hero(
                  tag: 'history_shot_${s.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      s.screenshotUrl!,
                      height: 80,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  _formatDate(s.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (s.rewardAmount != null) ...[
                  const Spacer(),
                  Text(
                    '+₺${s.rewardAmount!.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
            if (s.rejectionReason != null && s.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Red gerekçesi: ${s.rejectionReason}',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
