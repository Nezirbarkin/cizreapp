// =============================================================================
// Görev Yönetimi Admin Widget
// AdminDashboardScreen'den _selectedMenu = 'Görev Yönetimi' ile çağrılır.
// =============================================================================

// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/task_earning_model.dart';
import '../../../core/services/task_earning_service.dart';
import '../../../shared/widgets/fullscreen_image_viewer.dart';
import 'dart:io';

/// Admin Görev Yönetimi Widget
class TaskManagementContent extends StatefulWidget {
  const TaskManagementContent({super.key});

  @override
  State<TaskManagementContent> createState() => _TaskManagementContentState();
}

class _TaskManagementContentState extends State<TaskManagementContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.purple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.purple,
            tabs: const [
              Tab(icon: Icon(Icons.assignment), text: 'Görevler'),
              Tab(icon: Icon(Icons.pending_actions), text: 'Başvurular'),
              Tab(icon: Icon(Icons.bar_chart), text: 'İstatistikler'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _TasksTab(),
              _SubmissionsTab(),
              _StatsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TAB 1: Görevler
// =============================================================================
class _TasksTab extends StatefulWidget {
  const _TasksTab();

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> {
  final TaskEarningService _service = TaskEarningService.instance;
  List<Task> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final tasks = await _service.getAllTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Henüz görev yok'),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showTaskForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('İlk Görevi Oluştur'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _tasks.length,
                itemBuilder: (context, index) => _TaskAdminCard(
                  task: _tasks[index],
                  onEdit: () => _showTaskForm(context, task: _tasks[index]),
                  onStatusChange: (status) => _changeStatus(_tasks[index].id, status),
                  onDelete: () => _deleteTask(_tasks[index].id),
                  onRefresh: _load,
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTaskForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Görev'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
    );
  }

  Future<void> _changeStatus(String taskId, TaskStatus status) async {
    try {
      await _service.updateTaskStatus(taskId, status);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteTask(String taskId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Görevi Sil'),
        content: const Text('Bu görevi silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteTask(taskId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showTaskForm(BuildContext context, {Task? task}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TaskFormSheet(
        task: task,
        onSaved: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }
}

class _TaskAdminCard extends StatelessWidget {
  final Task task;
  final VoidCallback onEdit;
  final void Function(TaskStatus) onStatusChange;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  const _TaskAdminCard({
    required this.task,
    required this.onEdit,
    required this.onStatusChange,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (task.categoryIcon != null) ...[
                    Text(task.categoryIcon!, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusDropdown(
                    currentStatus: task.status,
                    onChanged: onStatusChange,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.description,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.monetization_on, size: 14, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '₺${task.rewardAmount.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.people_outline, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${task.currentParticipants}/${task.maxParticipants}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.red,
                    onPressed: onDelete,
                    tooltip: 'Sil',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  final TaskStatus currentStatus;
  final void Function(TaskStatus) onChanged;

  const _StatusDropdown({required this.currentStatus, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (currentStatus) {
      case TaskStatus.active:
        color = Colors.green;
        break;
      case TaskStatus.completed:
        color = Colors.blue;
        break;
      case TaskStatus.paused:
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }

    return PopupMenuButton<TaskStatus>(
      initialValue: currentStatus,
      onSelected: onChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentStatus.label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 14, color: color),
          ],
        ),
      ),
      itemBuilder: (context) => TaskStatus.values.map((s) {
        return PopupMenuItem(
          value: s,
          child: Row(
            children: [
              if (s == currentStatus) const Icon(Icons.check, size: 16),
              if (s != currentStatus) const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text(s.label),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// =============================================================================
// TAB 2: Başvurular
// =============================================================================
class _SubmissionsTab extends StatefulWidget {
  const _SubmissionsTab();

  @override
  State<_SubmissionsTab> createState() => _SubmissionsTabState();
}

class _SubmissionsTabState extends State<_SubmissionsTab> {
  final TaskEarningService _service = TaskEarningService.instance;
  List<TaskSubmission> _submissions = [];
  bool _isLoading = true;
  TaskSubmissionStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
    _setupRealtime();
  }

  RealtimeChannel? _channel;

  void _setupRealtime() {
    _channel = _service.subscribeAllSubmissions(onChange: _load);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final subs = await _service.adminGetSubmissions(status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _submissions = subs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // İstatistik
    final pending = _submissions.where((s) => s.status == TaskSubmissionStatus.pending).length;
    final approved = _submissions.where((s) => s.status == TaskSubmissionStatus.approved).length;
    final rejected = _submissions.where((s) => s.status == TaskSubmissionStatus.rejected).length;

    return Column(
      children: [
        // Filtre + istatistik
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'Tümü',
                        count: _submissions.length,
                        isSelected: _statusFilter == null,
                        onTap: () {
                          setState(() => _statusFilter = null);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Bekleyen',
                        count: pending,
                        isSelected: _statusFilter == TaskSubmissionStatus.pending,
                        color: Colors.orange,
                        onTap: () {
                          setState(() => _statusFilter = TaskSubmissionStatus.pending);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Onaylandı',
                        count: approved,
                        isSelected: _statusFilter == TaskSubmissionStatus.approved,
                        color: Colors.green,
                        onTap: () {
                          setState(() => _statusFilter = TaskSubmissionStatus.approved);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Reddedildi',
                        count: rejected,
                        isSelected: _statusFilter == TaskSubmissionStatus.rejected,
                        color: Colors.red,
                        onTap: () {
                          setState(() => _statusFilter = TaskSubmissionStatus.rejected);
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
        ),

        // Liste
        Expanded(
          child: _submissions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('Başvuru yok'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _submissions.length,
                    itemBuilder: (context, index) =>
                        _SubmissionCard(
                          submission: _submissions[index],
                          onApprove: () => _approve(_submissions[index]),
                          onReject: () => _reject(_submissions[index]),
                        ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _approve(TaskSubmission submission) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başvuruyu Onayla'),
        content: Text(
          '${submission.userFullName ?? 'Kullanıcı'} — ${submission.taskTitle ?? 'Görev'}\n'
          'Ödenecek: ₺${submission.taskReward?.toStringAsFixed(2) ?? '-'}\n\n'
          'Onaylandığında bakiyeye otomatik eklenecek.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _service.approveSubmission(submissionId: submission.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Onaylandı! ₺${submission.taskReward?.toStringAsFixed(2)} eklendi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reject(TaskSubmission submission) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başvuruyu Reddet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${submission.userFullName ?? 'Kullanıcı'} — ${submission.taskTitle ?? 'Görev'}'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Red Gerekçesi',
                hintText: 'Kullanıcıya gösterilecek',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, reasonController.text.trim()),
            child: const Text('Reddet'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;

    try {
      await _service.rejectSubmission(submissionId: submission.id, rejectionReason: reason);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reddedildi.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.purple;
    return Material(
      color: isSelected ? c : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.3) : c.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : c,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final TaskSubmission submission;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _SubmissionCard({
    required this.submission,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = submission.status == TaskSubmissionStatus.approved
        ? Colors.green
        : submission.status == TaskSubmissionStatus.rejected
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: submission.userAvatarUrl != null
                      ? NetworkImage(submission.userAvatarUrl!)
                      : null,
                  child: submission.userAvatarUrl == null
                      ? Text(
                          (submission.userFullName ?? '?').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        submission.userFullName ?? 'Bilinmeyen',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        submission.taskTitle ?? 'Görev',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    submission.status.label,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Ekran görüntüsü — tıklanabilir (tam ekran)
            if (submission.screenshotUrl != null && submission.screenshotUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => FullscreenImageViewer.open(
                  context,
                  imageUrl: submission.screenshotUrl!,
                  heroTag: 'admin_submission_${submission.id}',
                  caption: submission.taskTitle,
                ),
                child: Hero(
                  tag: 'admin_submission_${submission.id}',
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          submission.screenshotUrl!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fullscreen, color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('Tam ekran', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Kullanıcı notu
            if (submission.userNote != null && submission.userNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        submission.userNote!,
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Red gerekçesi
            if (submission.rejectionReason != null && submission.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Red: ${submission.rejectionReason}',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  _formatDate(submission.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const Spacer(),
                if (submission.taskReward != null)
                  Text(
                    '₺${submission.taskReward!.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),

            // Onay/Red butonları
            if (submission.status == TaskSubmissionStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reddet'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Onayla'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// TAB 3: İstatistikler
// =============================================================================
class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  final TaskEarningService _service = TaskEarningService.instance;
  TaskStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _service.getTaskStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_stats == null) return const Center(child: Text('Veri yok'));

    final stats = _stats!;
    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Görev İstatistikleri', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Görev durumları
            Row(
              children: [
                _StatCard(
                  icon: Icons.assignment,
                  color: Colors.purple,
                  label: 'Toplam Görev',
                  value: '${stats.totalTasks}',
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.play_circle,
                  color: Colors.green,
                  label: 'Aktif',
                  value: '${stats.activeTasks}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                  icon: Icons.check_circle,
                  color: Colors.blue,
                  label: 'Tamamlandı',
                  value: '${stats.completedTasks}',
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.pause_circle,
                  color: Colors.orange,
                  label: 'Duraklatıldı',
                  value: '${stats.pausedTasks}',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Başvuru durumları
            const Text('Başvurular', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                  icon: Icons.pending,
                  color: Colors.orange,
                  label: 'Bekleyen',
                  value: '${stats.pendingSubmissions}',
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.thumb_up,
                  color: Colors.green,
                  label: 'Onaylandı',
                  value: '${stats.approvedSubmissions}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                  icon: Icons.thumb_down,
                  color: Colors.red,
                  label: 'Reddedildi',
                  value: '${stats.rejectedSubmissions}',
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 24),

            // Ödeme özeti
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade600, Colors.green.shade400],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.payments, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Ödeme Özeti',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Bugünkü Ödeme', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            Text(fmt.format(stats.totalPaidToday), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 50, color: Colors.white24),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Toplam Ödeme', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(fmt.format(stats.totalPaidAllTime), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Görev Oluşturma/Düzenleme Form Sheet
// =============================================================================
class _TaskFormSheet extends StatefulWidget {
  final Task? task;
  final VoidCallback onSaved;

  const _TaskFormSheet({this.task, required this.onSaved});

  @override
  State<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<_TaskFormSheet> {
  final TaskEarningService _service = TaskEarningService.instance;
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _warningCtrl = TextEditingController();
  final _rewardCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  String? _selectedCategoryId;
  List<TaskCategory> _categories = [];
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isUploadingImage = false;
  TaskStatus _status = TaskStatus.active;
  DateTime _startsAt = DateTime.now();
  DateTime? _expiresAt;

  // Görsel state (çoklu)
  final List<String> _existingImageUrls = []; // Mevcut görseller (edit modunda gelir)
  final List<XFile> _newImageFiles = [];      // Yeni seçilen henüz yüklenmemiş görseller

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (widget.task != null) {
      final t = widget.task!;
      _titleCtrl.text = t.title;
      _descCtrl.text = t.description;
      _linkCtrl.text = t.taskLink ?? '';
      _warningCtrl.text = t.warningText ?? '';
      _rewardCtrl.text = t.rewardAmount.toStringAsFixed(2);
      _maxCtrl.text = t.maxParticipants.toString();
      _selectedCategoryId = t.categoryId;
      _status = t.status;
      _startsAt = t.startsAt;
      _expiresAt = t.expiresAt;
      _existingImageUrls.addAll(
        t.imageUrls.isNotEmpty ? t.imageUrls : [if (t.imageUrl != null) t.imageUrl!],
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (images.isNotEmpty) {
        setState(() {
          _newImageFiles.addAll(images);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Görsel seçilemedi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _removeNewImage(int index) {
    setState(() => _newImageFiles.removeAt(index));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  Future<void> _loadCategories() async {
    final cats = await _service.getCategories();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final reward = double.parse(_rewardCtrl.text.replaceAll(',', '.'));
      final max = int.parse(_maxCtrl.text);

      // Yeni seçilen görselleri storage'a yükle
      final uploadedUrls = <String>[];
      if (_newImageFiles.isNotEmpty) {
        setState(() => _isUploadingImage = true);
        for (final file in _newImageFiles) {
          uploadedUrls.add(await _service.uploadTaskImage(file: file));
        }
      }
      final finalImageUrls = [..._existingImageUrls, ...uploadedUrls];
      final finalImageUrl = finalImageUrls.isNotEmpty ? finalImageUrls.first : null;

      if (_isEditing) {
        await _service.updateTask(
          taskId: widget.task!.id,
          categoryId: _selectedCategoryId,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          warningText: _warningCtrl.text.trim().isNotEmpty ? _warningCtrl.text.trim() : null,
          taskLink: _linkCtrl.text.trim().isNotEmpty ? _linkCtrl.text.trim() : null,
          imageUrl: finalImageUrl,
          clearImageUrl: finalImageUrl == null && widget.task!.imageUrl != null,
          imageUrls: finalImageUrls,
          rewardAmount: reward,
          maxParticipants: max,
          startsAt: _startsAt,
          expiresAt: _expiresAt,
          clearExpiresAt: _expiresAt == null,
          status: _status,
        );
      } else {
        await _service.createTask(
          categoryId: _selectedCategoryId,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          warningText: _warningCtrl.text.trim().isNotEmpty ? _warningCtrl.text.trim() : null,
          taskLink: _linkCtrl.text.trim().isNotEmpty ? _linkCtrl.text.trim() : null,
          imageUrl: finalImageUrl,
          imageUrls: finalImageUrls,
          rewardAmount: reward,
          maxParticipants: max,
          startsAt: _startsAt,
          expiresAt: _expiresAt,
          status: _status,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Görev güncellendi' : 'Görev oluşturuldu'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _linkCtrl.dispose();
    _warningCtrl.dispose();
    _rewardCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
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
                      _isEditing ? 'Görevi Düzenle' : 'Yeni Görev Oluştur',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    // Kategori
                    DropdownButtonFormField<String>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                        ..._categories.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Row(
                                children: [
                                  if (c.icon != null) Text(c.icon!, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Text(c.name),
                                ],
                              ),
                            )),
                      ],
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    ),
                    const SizedBox(height: 12),

                    // Başlık
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: 'Başlık *', border: OutlineInputBorder()),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Zorunlu' : null,
                    ),
                    const SizedBox(height: 12),

                    // Açıklama
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Açıklama *', border: OutlineInputBorder()),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Zorunlu' : null,
                    ),
                    const SizedBox(height: 12),

                    // Link + Uyarı
                    TextFormField(
                      controller: _linkCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Görev Linki',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _warningCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Uyarı Metni',
                        hintText: 'Örn: Sadece Türkiye\'den katılım geçerli',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Görev Görseli
                    _buildImagePicker(),
                    const SizedBox(height: 12),

                    // Fiyat + Katılımcı
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _rewardCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Ödül (₺) *',
                              hintText: '10.00',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Zorunlu';
                              final n = double.tryParse(v.replaceAll(',', '.'));
                              if (n == null || n <= 0) return 'Geçersiz';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _maxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Katılımcı Limiti *',
                              hintText: '100',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Zorunlu';
                              final n = int.tryParse(v);
                              if (n == null || n <= 0) return 'Geçersiz';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Durum
                    DropdownButtonFormField<TaskStatus>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Durum', border: OutlineInputBorder()),
                      items: TaskStatus.values
                          .where((s) => s != TaskStatus.archived)
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                          .toList(),
                      onChanged: (v) => setState(() => _status = v ?? TaskStatus.active),
                    ),
                    const SizedBox(height: 16),

                    // Kaydet butonu
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_isEditing ? 'Güncelle' : 'Oluştur'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _thumbnail({required Widget image, required VoidCallback onRemove, String? badge}) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 100, height: 100, child: image),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
          ),
      ],
    );
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _existingImageUrls.length; i++)
              _thumbnail(
                image: GestureDetector(
                  onTap: () => FullscreenImageViewer.open(
                    context,
                    imageUrl: _existingImageUrls[i],
                    heroTag: 'form_existing_${widget.task?.id ?? "new"}_$i',
                    caption: _titleCtrl.text,
                  ),
                  child: Image.network(
                    _existingImageUrls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
                onRemove: () => _removeExistingImage(i),
              ),
            for (var i = 0; i < _newImageFiles.length; i++)
              _thumbnail(
                image: kIsWeb
                    ? Image.network(_newImageFiles[i].path, fit: BoxFit.cover)
                    : Image.file(File(_newImageFiles[i].path), fit: BoxFit.cover),
                onRemove: () => _removeNewImage(i),
                badge: 'Yeni',
              ),
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade600, size: 28),
                    const SizedBox(height: 2),
                    Text('Görsel Ekle', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_isUploadingImage)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Görseller yükleniyor...',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }
}
