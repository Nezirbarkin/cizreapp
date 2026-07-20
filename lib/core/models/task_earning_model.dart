/// Görev Kategorisi Modeli
class TaskCategory {
  final String id;
  final String name;
  final String? icon;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;

  TaskCategory({
    required this.id,
    required this.name,
    this.icon,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
  });

  factory TaskCategory.fromJson(Map<String, dynamic> json) {
    return TaskCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'sort_order': sortOrder,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Görev durumu
enum TaskStatus {
  draft,
  active,
  paused,
  completed,
  archived;

  String get label {
    switch (this) {
      case TaskStatus.draft:
        return 'Taslak';
      case TaskStatus.active:
        return 'Aktif';
      case TaskStatus.paused:
        return 'Duraklatıldı';
      case TaskStatus.completed:
        return 'Tamamlandı';
      case TaskStatus.archived:
        return 'Arşivlendi';
    }
  }

  static TaskStatus fromString(String value) {
    switch (value) {
      case 'draft':
        return TaskStatus.draft;
      case 'active':
        return TaskStatus.active;
      case 'paused':
        return TaskStatus.paused;
      case 'completed':
        return TaskStatus.completed;
      case 'archived':
        return TaskStatus.archived;
      default:
        return TaskStatus.draft;
    }
  }
}

/// Görev Başvuru Durumu
enum TaskSubmissionStatus {
  pending,
  approved,
  rejected;

  String get label {
    switch (this) {
      case TaskSubmissionStatus.pending:
        return 'Beklemede';
      case TaskSubmissionStatus.approved:
        return 'Onaylandı';
      case TaskSubmissionStatus.rejected:
        return 'Reddedildi';
    }
  }

  static TaskSubmissionStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return TaskSubmissionStatus.pending;
      case 'approved':
        return TaskSubmissionStatus.approved;
      case 'rejected':
        return TaskSubmissionStatus.rejected;
      default:
        return TaskSubmissionStatus.pending;
    }
  }
}

/// Görev Modeli (Kullanıcı görünümü)
class Task {
  final String id;
  final String? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String title;
  final String description;
  final String? warningText;
  final String? taskLink;
  final String? imageUrl;
  final List<String> imageUrls;
  final double rewardAmount;
  final int maxParticipants;
  final int currentParticipants;
  final int remainingSlots;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final TaskStatus status;
  final bool userAlreadyClaimed;
  final String? userSubmissionId;
  final TaskSubmissionStatus? userSubmissionStatus;
  final DateTime createdAt;

  Task({
    required this.id,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    required this.title,
    required this.description,
    this.warningText,
    this.taskLink,
    this.imageUrl,
    this.imageUrls = const [],
    required this.rewardAmount,
    required this.maxParticipants,
    this.currentParticipants = 0,
    this.remainingSlots = 0,
    required this.startsAt,
    this.expiresAt,
    this.status = TaskStatus.active,
    this.userAlreadyClaimed = false,
    this.userSubmissionId,
    this.userSubmissionStatus,
    required this.createdAt,
  });

  bool get isActive => status == TaskStatus.active && remainingSlots > 0;
  bool get hasStarted => startsAt.isBefore(DateTime.now());
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get canClaim => isActive && hasStarted && !isExpired && !userAlreadyClaimed && remainingSlots > 0;

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['task_id'] ?? json['id']) as String? ?? '',
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      categoryIcon: json['category_icon'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      warningText: json['warning_text'] as String?,
      taskLink: json['task_link'] as String?,
      imageUrl: json['image_url'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? const [],
      rewardAmount: (json['reward_amount'] as num?)?.toDouble() ?? 0,
      maxParticipants: json['max_participants'] as int? ?? 0,
      currentParticipants: json['current_participants'] as int? ?? 0,
      remainingSlots: json['remaining_slots'] as int? ?? 0,
      startsAt: json['starts_at'] != null
          ? DateTime.parse(json['starts_at'] as String)
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      status: TaskStatus.fromString(json['status'] as String? ?? 'active'),
      userAlreadyClaimed: json['user_already_claimed'] as bool? ?? false,
      userSubmissionId: json['user_submission_id'] as String?,
      userSubmissionStatus: json['user_submission_status'] != null
          ? TaskSubmissionStatus.fromString(json['user_submission_status'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Görev Başvurusu Modeli (Admin görünümü dahil)
class TaskSubmission {
  final String id;
  final String taskId;
  final String userId;
  final String? userFullName;
  final String? userAvatarUrl;
  final String? userPhone;
  final String? taskTitle;
  final String? taskDescription;
  final double? taskReward;
  final String? screenshotUrl;
  final String? userNote;
  final TaskSubmissionStatus status;
  final double? rewardAmount;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double totalEarned;

  TaskSubmission({
    required this.id,
    required this.taskId,
    required this.userId,
    this.userFullName,
    this.userAvatarUrl,
    this.userPhone,
    this.taskTitle,
    this.taskDescription,
    this.taskReward,
    this.screenshotUrl,
    this.userNote,
    required this.status,
    this.rewardAmount,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.totalEarned = 0,
  });

  factory TaskSubmission.fromJson(Map<String, dynamic> json) {
    return TaskSubmission(
      id: json['id'] as String? ?? '',
      taskId: json['task_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      userFullName: json['user_full_name'] as String?,
      userAvatarUrl: json['user_avatar_url'] as String?,
      userPhone: json['user_phone'] as String?,
      taskTitle: json['task_title'] as String?,
      taskDescription: json['task_description'] as String?,
      taskReward: (json['task_reward'] as num?)?.toDouble(),
      screenshotUrl: json['screenshot_url'] as String?,
      userNote: json['user_note'] as String?,
      status: TaskSubmissionStatus.fromString(json['status'] as String? ?? 'pending'),
      rewardAmount: (json['reward_amount'] as num?)?.toDouble(),
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Görev İstatistikleri (Admin)
class TaskStats {
  final int totalTasks;
  final int activeTasks;
  final int completedTasks;
  final int pausedTasks;
  final int pendingSubmissions;
  final int approvedSubmissions;
  final int rejectedSubmissions;
  final double totalPaidToday;
  final double totalPaidAllTime;

  TaskStats({
    this.totalTasks = 0,
    this.activeTasks = 0,
    this.completedTasks = 0,
    this.pausedTasks = 0,
    this.pendingSubmissions = 0,
    this.approvedSubmissions = 0,
    this.rejectedSubmissions = 0,
    this.totalPaidToday = 0,
    this.totalPaidAllTime = 0,
  });

  factory TaskStats.fromJson(Map<String, dynamic> json) {
    return TaskStats(
      totalTasks: json['total_tasks'] as int? ?? 0,
      activeTasks: json['active_tasks'] as int? ?? 0,
      completedTasks: json['completed_tasks'] as int? ?? 0,
      pausedTasks: json['paused_tasks'] as int? ?? 0,
      pendingSubmissions: json['pending_submissions'] as int? ?? 0,
      approvedSubmissions: json['approved_submissions'] as int? ?? 0,
      rejectedSubmissions: json['rejected_submissions'] as int? ?? 0,
      totalPaidToday: (json['total_paid_today'] as num?)?.toDouble() ?? 0,
      totalPaidAllTime: (json['total_paid_all_time'] as num?)?.toDouble() ?? 0,
    );
  }
}
