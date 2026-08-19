// Bu dosya `part of admin_dashboard_screen.dart` oldugu icin ana dosyadaki
// ignore_for_file direktifleri buraya UYGULANMAZ; her part kendi listesini
// tasimak zorundadir.
//
// invalid_use_of_protected_member: bu part'lar `extension on
// _AdminDashboardScreenState` deseniyle yazildi; setState/mounted analiz
// acisindan sinif disindan cagrilmis gorunur ama calisma zamaninda
// State'in kendi uyesidir. Tek gercek false positive budur ve yalniz o
// susturulur - dosyalarin analizden komple cikarilmasi (analysis_options
// exclude) dead_code/tip hatalarini da gizliyordu.
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: use_build_context_synchronously, deprecated_member_use
part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Kullanicilar sekmesi + dialoglar
  // ==========================================================================

  // Kullanici listesini GERCEKTEN yeniden yukler.
  //
  // Bu ekran, diger admin sekmelerinden farkli olarak future'i build icinde
  // degil state alaninda (`_usersFuture`) tutuyor. Bu yuzden ciplak
  // `setState(() {})` cagrisi FutureBuilder'a AYNI tamamlanmis future'i
  // verir: rol degistirme / kullanici duzenleme / pull-to-refresh basarili
  // gorunur ama liste eski veriyi gostermeye devam eder. Yenileme, future'in
  // kendisinin degistirilmesini gerektirir.
  void _refreshUsers() {
    if (!mounted) return;
    setState(() {
      _usersFuture = _loadUsers();
    });
  }

  // --- _buildUsersContent ---
  Widget _buildUsersContent() {
    _usersFuture ??= _loadUsers();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Kullanıcı bulunamadı'));
        }

        final allUsers = snapshot.data!;

        // Arama + rol filtrelemesi
        final users = allUsers.where((user) {
          // Rol filtresi
          if (_roleFilter != null && user['role'] != _roleFilter) {
            return false;
          }
          // Arama filtresi
          if (_userSearchQuery.isNotEmpty) {
            final query = _userSearchQuery.toLowerCase();
            final username = (user['username'] as String?)?.toLowerCase() ?? '';
            final fullName =
                (user['full_name'] as String?)?.toLowerCase() ?? '';
            final email = (user['email'] as String?)?.toLowerCase() ?? '';
            final phone = (user['phone'] as String?)?.toLowerCase() ?? '';
            return username.contains(query) ||
                fullName.contains(query) ||
                email.contains(query) ||
                phone.contains(query);
          }
          return true;
        }).toList();

        // İstatistikler (tüm kullanıcılar üzerinden)
        final totalUsers = allUsers.length;
        final adminCount = allUsers.where((u) => u['role'] == 'admin').length;
        final sellerCount = allUsers.where((u) => u['role'] == 'seller').length;
        final courierCount = allUsers
            .where((u) => u['role'] == 'courier')
            .length;
        final driverCount = allUsers.where((u) => u['role'] == 'driver').length;
        final newsCount = allUsers.where((u) => u['role'] == 'news').length;
        // NOT: "Yasakli" karti yok - profiles tablosunda is_banned kolonu
        // bulunmuyor. Eklenirse burada sayilip bir _buildStatCard eklenmeli.

        return RefreshIndicator(
          onRefresh: () async {
            _refreshUsers();
            await _usersFuture;
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kullanıcı Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Arama TextField
                TextField(
                  controller: _userSearchController,
                  onChanged: (value) {
                    setState(() {
                      _userSearchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText:
                        'Kullanıcı ara (isim, email, kullanıcı adı, telefon)...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _userSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _userSearchController.clear();
                              setState(() {
                                _userSearchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 80) / 4,
                      child: _buildStatCard(
                        icon: Icons.people,
                        title: 'Toplam',
                        value: '$totalUsers',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                        onTap: () => setState(() => _roleFilter = null),
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 80) / 4,
                      child: _buildStatCard(
                        icon: Icons.admin_panel_settings,
                        title: 'Admin',
                        value: '$adminCount',
                        color: Colors.purple,
                        gradient: [
                          Colors.purple.shade400,
                          Colors.purple.shade600,
                        ],
                        onTap: () => setState(() => _roleFilter = 'admin'),
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 80) / 4,
                      child: _buildStatCard(
                        icon: Icons.store,
                        title: 'Satıcı',
                        value: '$sellerCount',
                        color: Colors.orange,
                        gradient: [
                          Colors.orange.shade400,
                          Colors.orange.shade600,
                        ],
                        onTap: () => setState(() => _roleFilter = 'seller'),
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 80) / 4,
                      child: _buildStatCard(
                        icon: Icons.delivery_dining,
                        title: 'Kurye',
                        value: '$courierCount',
                        color: Colors.teal,
                        gradient: [Colors.teal.shade400, Colors.teal.shade600],
                        onTap: () => setState(() => _roleFilter = 'courier'),
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 80) / 4,
                      child: _buildStatCard(
                        icon: Icons.directions_bus,
                        title: 'Şoför',
                        value: '$driverCount',
                        color: Colors.indigo,
                        gradient: [
                          Colors.indigo.shade400,
                          Colors.indigo.shade600,
                        ],
                        onTap: () => setState(() => _roleFilter = 'driver'),
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 80) / 4,
                      child: _buildStatCard(
                        icon: Icons.newspaper,
                        title: 'Haberci',
                        value: '$newsCount',
                        color: Colors.blueGrey,
                        gradient: [
                          Colors.blueGrey.shade400,
                          Colors.blueGrey.shade600,
                        ],
                        onTap: () => setState(() => _roleFilter = 'news'),
                      ),
                    ),
                  ],
                ),
                if (_roleFilter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Chip(
                          label: Text('Filtre: $_roleFilter'),
                          onDeleted: () => setState(() => _roleFilter = null),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),

                // Filtrelenmiş sonuç bilgisi
                if (_userSearchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      '${users.length} kullanıcı bulundu',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),

                // Kullanıcı Listesi
                if (users.isEmpty && _userSearchQuery.isNotEmpty)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Arama sonucu bulunamadı',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _userSearchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Aramayı Temizle'),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];

                      // --- Kart verisini güvenli şekilde çıkar ---
                      // Eski admin_list_users (fallback) veya yeni
                      // admin_user_list_with_stats'tan gelse de null-safe.
                      final email = (user['email'] as String?) ?? '';
                      final phone = (user['phone'] as String?) ?? '';
                      final username = (user['username'] as String?) ?? '';
                      final role = user['role'] as String?;
                      final fullName = (user['full_name'] as String?) ?? '';
                      final displayName = fullName.trim().isNotEmpty
                          ? fullName
                          : (username.trim().isNotEmpty ? username : '-');
                      final postsCount =
                          (user['posts_count'] as num?)?.toInt() ?? 0;
                      final followersCount =
                          (user['followers_count'] as num?)?.toInt() ?? 0;
                      final followingCount =
                          (user['following_count'] as num?)?.toInt() ?? 0;
                      final deliveredCount =
                          (user['delivered_count'] as num?)?.toInt() ?? 0;
                      final isOnline = (user['is_online'] as bool?) ?? false;
                      final isSuspicious =
                          (user['is_suspicious'] as bool?) ?? false;
                      final now = DateTime.now();
                      final lastSeen = _parseDateTime(user['last_seen']);
                      final createdAt = _parseDateTime(user['created_at']);
                      final lastSeenLabel = AdminUserHelpers.formatLastSeen(
                        lastSeen,
                        now: now,
                      );
                      final isNew =
                          AdminUserHelpers.isNewMember(createdAt, now: now);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showEditUserDialog(user),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Avatar + online göstergesi
                                _buildUserAvatar(
                                  user,
                                  online: isOnline,
                                ),
                                const SizedBox(width: 12),
                                // İçerik
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // İsim + rozetler
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          _buildRoleBadge(role),
                                          if (isSuspicious)
                                            _buildMiniBadge(
                                              'Şüpheli',
                                              Icons.warning_amber_rounded,
                                              Colors.red,
                                            ),
                                          if (isNew)
                                            _buildMiniBadge(
                                              'Yeni',
                                              Icons.fiber_new,
                                              Colors.green,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      // E-posta (mail ikonu yanında)
                                      _infoRow(
                                        Icons.email_outlined,
                                        email.isNotEmpty
                                            ? email
                                            : 'E-posta yok',
                                        dim: email.isEmpty,
                                      ),
                                      // Telefon (varsa)
                                      if (phone.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        _infoRow(
                                          Icons.phone_outlined,
                                          phone,
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      _infoRow(
                                        Icons.alternate_email,
                                        '@${username.isEmpty ? '-' : username}',
                                      ),
                                      // Sosyal istatistikler
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _statChip(
                                            Icons.article_outlined,
                                            AdminUserHelpers.formatStatCount(
                                              postsCount,
                                            ),
                                            'Gönderi',
                                            color: Colors.blue,
                                          ),
                                          _statChip(
                                            Icons.people_alt_outlined,
                                            AdminUserHelpers.formatStatCount(
                                              followersCount,
                                            ),
                                            'Takipçi',
                                            color: Colors.purple,
                                          ),
                                          _statChip(
                                            Icons.person_add_alt_outlined,
                                            AdminUserHelpers.formatStatCount(
                                              followingCount,
                                            ),
                                            'Takip',
                                            color: Colors.teal,
                                          ),
                                          if (role == 'courier' &&
                                              deliveredCount > 0)
                                            _statChip(
                                              Icons.local_shipping_outlined,
                                              AdminUserHelpers.formatStatCount(
                                                deliveredCount,
                                              ),
                                              'Teslim',
                                              color: Colors.orange,
                                            ),
                                        ],
                                      ),
                                      // Son görülme
                                      if (lastSeenLabel != '-') ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'Son görülme: $lastSeenLabel',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Aksiyon menüsü
                                PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_vert,
                                    color: Colors.grey.shade700,
                                  ),
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'edit':
                                        _showEditUserDialog(user);
                                        break;
                                      case 'change_role':
                                        _showChangeRoleDialog(user);
                                        break;
                                      case 'delete':
                                        _showDeleteUserDialog(user);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, size: 18),
                                          SizedBox(width: 8),
                                          Text('Düzenle'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'change_role',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.admin_panel_settings,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Rol Değiştir'),
                                        ],
                                      ),
                                    ),
                                    // Bu eylem hesabi silmez, "supheli"
                                    // isaretler (bkz. _showDeleteUserDialog).
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.gpp_bad,
                                            size: 18,
                                            color: Colors.orange,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Şüpheli İşaretle',
                                            style: TextStyle(
                                              color: Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _buildRoleBadge ---
  Widget _buildRoleBadge(String? role) {
    Color color;
    IconData icon;
    String label;

    switch (role) {
      case 'admin':
        color = Colors.purple;
        icon = Icons.admin_panel_settings;
        label = 'Admin';
        break;
      case 'seller':
        color = Colors.orange;
        icon = Icons.store;
        label = 'Satıcı';
        break;
      case 'courier':
        color = Colors.teal;
        icon = Icons.delivery_dining;
        label = 'Kurye';
        break;
      case 'driver':
        color = Colors.indigo;
        icon = Icons.directions_bus;
        label = 'Şoför';
        break;
      case 'news':
        color = Colors.blueGrey;
        icon = Icons.newspaper;
        label = 'Haberci';
        break;
      default:
        color = Colors.blue;
        icon = Icons.person;
        label = 'Müşteri';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildUserAvatar ---
  // CircleAvatar + online göstergesi. Ham NetworkImage yerine
  // CachedNetworkImage kullanılır: önbellek + yükleme yer tutucusu + hata
  // durumunda baş harfe düşüş. Böylece "geçerli URL ama yüklenemedi" (404,
  // imzalı-URL süresi dolmuş, ağ kesiği) durumunda kart boş kalmaz; baş harf
  // gösterilir. Bu, "güncel görsel çekilmiyor" şikâyetini (ham NetworkImage
  // sessizce başarısız olup boş daire bırakması) giderir.
  Widget _buildUserAvatar(Map<String, dynamic> user, {bool online = false}) {
    final url = user['avatar_url'] as String?;
    final initial = AdminUserHelpers.initialOf(
      user['username'] as String?,
      user['full_name'] as String?,
    );
    final valid = AdminUserHelpers.isValidAvatarUrl(url);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey.shade300,
          child: valid
              ? CachedNetworkImage(
                  imageUrl: url!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, _, __) => Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- _infoRow ---
  // Küçük ikon + tek satırlık gri bilgi (e-posta / telefon / @kullanıcı).
  Widget _infoRow(IconData icon, String text, {bool dim = false}) {
    final isEmpty = text.trim().isEmpty;
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: dim || isEmpty
                  ? Colors.grey.shade400
                  : Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }

  // --- _statChip ---
  // Kompakt istatistik etiketi (ör. "1.5B Gönderi").
  Widget _statChip(
    IconData icon,
    String value,
    String label, {
    Color color = Colors.blue,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // --- _buildMiniBadge ---
  // İsim satırında "Şüpheli" / "Yeni" gibi küçük rozet.
  Widget _buildMiniBadge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // --- _parseDateTime ---
  // RPC'den gelen ISO8601 dizesini güvenli şekilde DateTime'e çevirir.
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  // --- _showEditUserDialog ---
  void _showEditUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['full_name']);
    final usernameController = TextEditingController(text: user['username']);
    final userId = user['id'] as String;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcı Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Email alanı - read-only, admin_get_profile_email RPC'sinden çekiliyor
              FutureBuilder<String>(
                future: _fetchUserEmail(userId),
                builder: (context, snapshot) {
                  return TextField(
                    controller: TextEditingController(
                      text: snapshot.connectionState == ConnectionState.waiting
                          ? 'Yükleniyor...'
                          : (snapshot.data ?? '-'),
                    ),
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email, size: 18),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı Adı',
                  border: OutlineInputBorder(),
                  prefixText: '@',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // Doğrudan profiles UPDATE yasaklandı; admin_update_user_identity
                // RPC'sini kullanıyoruz. Bu RPC yalnız full_name/username
                // alanlarını günceller; role/email/phone/PII dokunmaz.
                await Supabase.instance.client.rpc(
                  'admin_update_user_identity',
                  params: {
                    'p_target_user_id': user['id'],
                    'p_full_name': nameController.text.trim(),
                    'p_username': usernameController.text.trim(),
                  },
                );

                if (mounted) {
                  Navigator.pop(context);
                  _refreshUsers();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kullanıcı güncellendi')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  // Kullanıcı email'ini admin_get_profile_email RPC ile çek
  Future<String> _fetchUserEmail(String userId) async {
    try {
      // rpc<String> (nullable olmayan) kullanilirsa `?? '-'` olu koda doner ve
      // e-postasi olmayan kullanicida SQL NULL -> String cast'i TypeError
      // firlatip catch'e duserdi. Dogru sozlesme rpc<String?>'dir
      // (bkz. _part_data_loaders.dart icindeki ayni cagri).
      final email = await Supabase.instance.client.rpc<String?>(
        'admin_get_profile_email',
        params: {'p_user_id': userId},
      );
      return (email == null || email.isEmpty) ? '-' : email;
    } catch (e) {
      debugPrint('❌ Email çekilirken hata: $e');
      return '-';
    }
  }

  // --- _showChangeRoleDialog ---
  void _showChangeRoleDialog(Map<String, dynamic> user) {
    String selectedRole = user['role'] ?? 'customer';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rol Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${user['full_name'] ?? user['username']} için yeni rol seçin:',
              ),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.person, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    const Text('Müşteri'),
                  ],
                ),
                value: 'customer',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.store, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    const Text('Satıcı'),
                  ],
                ),
                value: 'seller',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.delivery_dining, color: Colors.teal, size: 20),
                    const SizedBox(width: 8),
                    const Text('Kurye'),
                  ],
                ),
                value: 'courier',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.directions_bus, color: Colors.indigo, size: 20),
                    const SizedBox(width: 8),
                    const Text('Şoför'),
                  ],
                ),
                value: 'driver',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      color: Colors.purple,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Admin'),
                  ],
                ),
                value: 'admin',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.newspaper, color: Colors.blueGrey, size: 20),
                    const SizedBox(width: 8),
                    const Text('Haberci'),
                  ],
                ),
                value: 'news',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  // Doğrudan profiles UPDATE yasaklandı. admin_set_user_role
                  // RPC'si çağrılır; bu RPC:
                  //   * çağıranın gerçek admin olduğunu doğrular,
                  //   * target satırı FOR UPDATE kilitler,
                  //   * audit tablosuna yazar,
                  //   * son admin'in demote edilmesini engeller.
                  final newRole = await Supabase.instance.client.rpc<String>(
                    'admin_set_user_role',
                    params: {
                      'p_target_user_id': user['id'],
                      'p_new_role': selectedRole,
                      'p_reason': 'admin_dashboard_change',
                    },
                  );

                  // Önbelleği temizle - profil değiştiği için yeniden yüklenmeli
                  await _cacheService.clearCache();
                  debugPrint(
                    '🔄 Cache temizlendi - profiller yeniden yüklenecek',
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    // Kullanıcı listesini yeniden yükle
                    _refreshUsers();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Rol güncellendi: $newRole'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e, stackTrace) {
                  debugPrint('❌ Rol güncellenirken hata: $e');
                  debugPrint('📍 Stack trace: $stackTrace');

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Rol güncellenirken hata: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  // --- _showDeleteUserDialog ---
  //
  // ONEMLI: Bu akis kullaniciyi SILMEZ.
  // Veritabaninda `admin_delete_user` diye bir RPC yok (yalniz
  // admin_delete_post / admin_delete_story / admin_delete_group /
  // admin_delete_order var) ve profiles uzerinde dogrudan DELETE
  // 20260803000006 ile kapatildi. Cagrilan tek sey
  // admin_set_user_suspicious(flagged: true), yani hesabi "supheli" olarak
  // isaretlemek.
  //
  // Onceki surumde baslik "Kullaniciyi Sil", metin "Bu islem geri alinamaz ve
  // kullanicinin tum verileri silinecektir", sonuc bildirimi de "silme talebi
  // islendi" diyordu; admin geri donusu olmayan bir silme yaptigini sanip
  // hesabin durmaya devam ettigini gorunce panele guvenmiyordu. Metin, kodun
  // gercekte yaptigi ise esitlendi.
  void _showDeleteUserDialog(Map<String, dynamic> user) {
    final userLabel = user['full_name'] ?? user['username'] ?? 'Kullanıcı';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabı Şüpheli İşaretle'),
        content: Text(
          '$userLabel şüpheli olarak işaretlenecek ve "Şüpheli Kullanıcılar" '
          'listesine düşecek.\n\n'
          'Bu işlem hesabı SİLMEZ; gönderileri, siparişleri ve oturumu '
          'durmaya devam eder. İşaret "Şüpheli Kullanıcılar" ekranından geri '
          'alınabilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await Supabase.instance.client.rpc(
                  'admin_set_user_suspicious',
                  params: {
                    'target_user_id': user['id'],
                    'flagged': true,
                    'reason': 'admin_dashboard_flag',
                  },
                );

                if (mounted) {
                  Navigator.pop(context);
                  _refreshUsers();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kullanıcı şüpheli olarak işaretlendi'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Kullanıcı işaretlenirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('İşaretleme başarısız: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('Şüpheli İşaretle'),
          ),
        ],
      ),
    );
  }

  // Dükkanı olmayan kullanıcıları yükle (dükkan ekleme için)
  Future<List<Map<String, dynamic>>> _loadUsersWithoutShop() async {
    try {
      debugPrint('🔍 Dükkanı olmayan kullanıcılar yükleniyor...');

      // Önce tüm dükkan sahiplerini al
      final shopsResponse = await Supabase.instance.client
          .from('shops')
          .select('owner_id');

      // Null ve duplicate kontrolü ile owner ID'lerini al
      final shopOwnerIds = <String>{};
      for (final shop in shopsResponse) {
        final ownerId = shop['owner_id'] as String?;
        if (ownerId != null && ownerId.isNotEmpty) {
          shopOwnerIds.add(ownerId);
        }
      }

      // Tüm kullanıcıları al — profiles tablosuna authenticated SELECT
      // grant'i 20260803000006 ile kaldırıldı; doğrudan from('profiles')
      // çağrısı 42501 fırlatır. SECURITY DEFINER admin_list_users RPC
      // üzerinden, sayfalı/dar sütunlu liste çekilir.
      // NOT: Bu RPC `email` sütununu döndürmez (PII). Bu ekran yalnız
      // dükkan atamak için kullanıldığından email gerekmiyor.
      final usersResponse = await Supabase.instance.client.rpc<List<dynamic>>(
        'admin_list_users',
        params: {'p_limit': 100},
      );

      // Yinelenenleri filtrele ve dükkanı olmayanları al
      final seenIds = <String>{};
      final usersWithoutShop = List<Map<String, dynamic>>.from(usersResponse)
          .where((user) {
            final userId = user['id'] as String;
            // Yinelenen ID'leri atla
            if (seenIds.contains(userId)) return false;
            seenIds.add(userId);
            // Zaten dükkanı olanları atla
            return !shopOwnerIds.contains(userId);
          })
          .toList();

      debugPrint(
        '✅ Dükkanı olmayan ${usersWithoutShop.length} kullanıcı bulundu',
      );

      return usersWithoutShop;
    } catch (e) {
      debugPrint('❌ Dükkanı olmayan kullanıcılar yüklenirken hata: $e');
      return [];
    }
  }

  // Kullanıcıları yükle
  // Not: profiles tablosundan SELECT grant'i REVOKE edildiği için
  // doğrudan select('*') ile PII yüklemesi yapılamaz. Bunun yerine
  // SECURITY DEFINER admin_user_list_with_stats() RPC'si kullanılır; o hem
  // dar güvenli sütunları hem de e-posta/telefon (PII, yalnız admin'e) ve
  // sosyal istatistikleri (gönderi/takipçi/takip/teslim) tek sorguda döner.
  // Migration henüz uygulanmadıysa RPC yok olabilir; o durumda eski
  // admin_list_users()'a düşeriz (email/istatistik yok ama kart yine çalışır).
  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      debugPrint('🔍 Kullanıcılar yükleniyor (admin_user_list_with_stats RPC)');

      List<dynamic> response;
      try {
        response = await Supabase.instance.client.rpc<List<dynamic>>(
          'admin_user_list_with_stats',
          params: {'p_limit': 100},
        );
        debugPrint('✅ ${response.length} kullanıcı yüklendi (istatistikli)');
      } catch (e) {
        // Zengin RPC yok (migration uygulanmamış) — eski sözleşmeye düş.
        debugPrint(
          '⚠️ admin_user_list_with_stats kullanılamıyor, admin_list_users\'a düşülüyor: $e',
        );
        response = await Supabase.instance.client.rpc<List<dynamic>>(
          'admin_list_users',
          params: {'p_limit': 100},
        );
        debugPrint('✅ ${response.length} kullanıcı yüklendi (sade)');
      }

      // PII debugPrint KALDIRILDI: tüm kullanıcı listesi log'a yazılmaz.
      final users = List<Map<String, dynamic>>.from(response);

      return users;
    } catch (e, stackTrace) {
      debugPrint('❌ Kullanıcılar yüklenirken hata: $e');
      debugPrint('📍 Stack trace: $stackTrace');

      // Hata mesajını kullanıcıya göster
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Kullanıcılar yüklenirken hata oluştu: ${e.toString()}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Yeniden Dene',
                textColor: Colors.white,
                // setState(() {}) burada hicbir sey yapmiyordu: FutureBuilder
                // ayni (hatayla tamamlanmis) future'i tekrar kullanip yine bos
                // liste gosteriyordu. Future'in kendisi yenilenmeli.
                onPressed: _refreshUsers,
              ),
            ),
          );
        });
      }

      // Hata durumunda boş liste döndür
      return [];
    }
  }
}
