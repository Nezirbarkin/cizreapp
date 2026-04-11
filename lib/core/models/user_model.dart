enum UserRole { customer, seller, admin }

enum UserStatus { active, suspended, deleted }

class User {
  final String id;
  final String email;
  final String fullName;
  final String? username;
  final String? phone;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? bio;
  final UserRole role;
  final UserStatus status;
  final bool isOnline;
  final bool isGhostMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    this.username,
    this.phone,
    this.avatarUrl,
    this.bannerUrl,
    this.bio,
    this.role = UserRole.customer,
    this.status = UserStatus.active,
    this.isOnline = false,
    this.isGhostMode = false,
    required this.createdAt,
    required this.updatedAt,
  });

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    String? username,
    String? phone,
    String? avatarUrl,
    String? bannerUrl,
    String? bio,
    UserRole? role,
    UserStatus? status,
    bool? isOnline,
    bool? isGhostMode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      bio: bio ?? this.bio,
      role: role ?? this.role,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      isGhostMode: isGhostMode ?? this.isGhostMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'username': username,
      'phone': phone,
      'avatar_url': avatarUrl,
      'banner_url': bannerUrl,
      'bio': bio,
      'role': role.name,
      'status': status.name,
      'is_online': isOnline,
      'is_ghost_mode': isGhostMode,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      username: json['username'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bannerUrl: json['banner_url'] as String?,
      bio: json['bio'] as String?,
      role: UserRole.values.firstWhere(
        (e) => e.name == (json['role'] as String? ?? 'customer'),
        orElse: () => UserRole.customer,
      ),
      status: UserStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'active'),
        orElse: () => UserStatus.active,
      ),
      isOnline: json['is_online'] as bool? ?? false,
      isGhostMode: json['is_ghost_mode'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  String toString() => 'User(id: $id, email: $email, fullName: $fullName, role: $role)';
}
