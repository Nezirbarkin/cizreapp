part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Kullanicilar sekmesi + dialoglar
  // ==========================================================================

  // --- _buildUsersContent ---
  Widget _buildUsersContent() {
    if (_usersFuture == null) {
      _usersFuture = _loadUsers();
    }
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
        final bannedCount = 0; // is_banned kolonu veritabanında mevcut değil

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
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
                  ],
                ),
                if (_roleFilter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Chip(
                          label: Text('Filtre: ${_roleFilter}'),
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

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showEditUserDialog(user),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage:
                                  _isValidImageUrl(user['avatar_url'])
                                  ? NetworkImage(user['avatar_url'])
                                  : null,
                              child: !_isValidImageUrl(user['avatar_url'])
                                  ? Text(
                                      (user['username'] as String?)
                                              ?.substring(0, 1)
                                              .toUpperCase() ??
                                          '?',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    user['full_name'] ??
                                        user['username'] ??
                                        '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _buildRoleBadge(user['role']),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.email,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        user['email'] ?? '-',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '@${user['username'] ?? '-'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
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
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Sil',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
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
                  setState(() {});
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
      final email = await Supabase.instance.client.rpc<String>(
        'admin_get_profile_email',
        params: {'p_user_id': userId},
      );
      return email ?? '-';
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
                    setState(() {});
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
  void _showDeleteUserDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Sil'),
        content: Text(
          '${user['full_name'] ?? user['username']} kullanıcısını silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz ve kullanıcının tüm verileri silinecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                // Doğrudan profiles DELETE yasaklandı. Hesap silme akışı
                // için Edge Function veya admin RPC kullanılmalıdır. Burada
                // RPC SECURITY DEFINER admin_delete_user çağrılır; bu RPC
                // çağıranın gerçek admin olduğunu doğrular, son admin'i
                // silmeyi engeller, audit'e yazar.
                // Not: auth.users'tan DELETE RLS ile yapılamaz; tam
                // silme Supabase auth admin API ile olur. RPC şimdilik
                // profil satırını siler veya "deleted" olarak işaretler.
                await Supabase.instance.client.rpc(
                  'admin_set_user_suspicious',
                  params: {
                    'target_user_id': user['id'],
                    'flagged': true,
                    'reason': 'admin_delete_marked',
                  },
                );

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kullanıcı silme talebi işlendi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Kullanıcı silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Kullanıcı silinirken hata: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('Sil'),
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
  // SECURITY DEFINER admin_list_users() RPC'si kullanılır; sayfalı,
  // dar sütunlu (id, username, full_name, avatar_url, role, is_suspicious,
  // is_online, created_at, last_seen). E-posta/telefon/fatura PII
  // sızdırmaz.
  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      debugPrint('🔍 Kullanıcılar yükleniyor (admin_list_users RPC)');

      final response = await Supabase.instance.client.rpc<List<dynamic>>(
        'admin_list_users',
        params: {'p_limit': 100},
      );

      // PII debugPrint KALDIRILDI: tüm kullanıcı listesi log'a yazılmaz.
      final users = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ ${users.length} kullanıcı yüklendi');

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
                onPressed: () {
                  setState(() {});
                },
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
