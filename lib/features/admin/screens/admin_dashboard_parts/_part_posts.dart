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
  // Gonderiler + hikayeler + dialoglar
  // ==========================================================================

  // --- _buildPostsContent ---
  Widget _buildPostsContent() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: Colors.purple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.purple,
              tabs: [
                Tab(icon: Icon(Icons.article), text: 'Gönderiler'),
                Tab(icon: Icon(Icons.auto_stories), text: 'Hikayeler'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [_buildPostsList(), _buildStoriesList()],
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildPostsList ---
  Widget _buildPostsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Gönderi bulunamadı'));
        }

        final posts = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tüm Gönderiler',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddPostDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Gönderi'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    final isPinned = post['is_pinned'] == true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: isPinned ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isPinned
                            ? BorderSide(color: Colors.amber.shade400, width: 2)
                            : BorderSide.none,
                      ),
                      child: Stack(
                        children: [
                          if (isPinned)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.push_pin,
                                      size: 12,
                                      color: Colors.amber.shade800,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'Sabitlendi',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.amber.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage:
                                  post['profiles']?['avatar_url'] != null
                                  ? NetworkImage(post['profiles']['avatar_url'])
                                  : null,
                              child: post['profiles']?['avatar_url'] == null
                                  ? Text(
                                      AdminUserHelpers.initialOf(
                                        post['profiles']?['username'] as String?,
                                        post['profiles']?['full_name'] as String?,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post['profiles']?['full_name'] ??
                                      post['profiles']?['username'] ??
                                      'Bilinmeyen Kullanıcı',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (post['content'] as String?)?.substring(
                                        0,
                                        (post['content'] as String?)!.length >
                                                80
                                            ? 80
                                            : (post['content'] as String?)!
                                                  .length,
                                      ) ??
                                      '-',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: 14,
                                    color: Colors.red,
                                  ),
                                  Text(
                                    ' ${post['likes_count'] ?? 0}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    Icons.comment,
                                    size: 14,
                                    color: Colors.blue,
                                  ),
                                  Text(
                                    ' ${post['comments_count'] ?? 0}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  Text(
                                    ' ${_formatDate(post['created_at'])}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: Colors.grey.shade700,
                              ),
                              onSelected: (value) {
                                switch (value) {
                                  case 'pin':
                                    _togglePin('posts', post['id'], !isPinned);
                                    break;
                                  case 'edit':
                                    _showEditPostDialog(post);
                                    break;
                                  case 'delete':
                                    _showDeletePostDialog(post);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'pin',
                                  child: Row(
                                    children: [
                                      Icon(
                                        isPinned
                                            ? Icons.push_pin_outlined
                                            : Icons.push_pin,
                                        size: 18,
                                        color: Colors.amber.shade700,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isPinned
                                            ? 'Sabitlemeyi Kaldır'
                                            : 'Sabitle',
                                      ),
                                    ],
                                  ),
                                ),
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
                        ],
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

  // --- _buildStoriesList ---
  Widget _buildStoriesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadStories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final stories = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tüm Hikayeler',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddStoryDialog(),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Bilgi'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (stories.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz hikaye yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hikayeler mobil uygulama üzerinden oluşturulur',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: stories.length,
                    itemBuilder: (context, index) {
                      final story = stories[index];
                      // Hikayeler için hem is_pinned hem admin_pinned kontrol et
                      final isStoryPinned =
                          story['is_pinned'] == true ||
                          story['admin_pinned'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isStoryPinned ? 3 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isStoryPinned
                              ? BorderSide(
                                  color: Colors.amber.shade400,
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                        child: Stack(
                          children: [
                            if (isStoryPinned)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.push_pin,
                                        size: 12,
                                        color: Colors.amber.shade800,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Sabitlendi',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.amber.shade800,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundImage: story['media_url'] != null
                                        ? NetworkImage(story['media_url'])
                                        : null,
                                    child: story['media_url'] == null
                                        ? const Icon(Icons.image, size: 24)
                                        : null,
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.purple,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.auto_stories,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    story['profiles']?['full_name'] ??
                                        story['profiles']?['username'] ??
                                        'Bilinmeyen Kullanıcı',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (story['caption'] != null &&
                                      (story['caption'] as String).isNotEmpty)
                                    Text(
                                      story['caption'],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.visibility,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    Text(
                                      ' ${story['views_count'] ?? 0}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    Text(
                                      ' ${_formatDate(story['created_at'])}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: Colors.grey.shade700,
                                ),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'pin':
                                      _togglePin(
                                        'stories',
                                        story['id'],
                                        !isStoryPinned,
                                      );
                                      break;
                                    case 'delete':
                                      _showDeleteStoryDialog(story);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'pin',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isStoryPinned
                                              ? Icons.push_pin_outlined
                                              : Icons.push_pin,
                                          size: 18,
                                          color: Colors.amber.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isStoryPinned
                                              ? 'Sabitlemeyi Kaldır'
                                              : 'Sabitle',
                                        ),
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
                          ],
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

  // --- _showAddPostDialog ---
  void _showAddPostDialog() {
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Gönderi Ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'İçerik',
                  border: OutlineInputBorder(),
                  hintText: 'Gönderi içeriği...',
                ),
                maxLines: 5,
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
              if (contentController.text.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('İçerik gerekli')));
                return;
              }

              try {
                await Supabase.instance.client.from('posts').insert({
                  'content': contentController.text.trim(),
                  'user_id': Supabase.instance.client.auth.currentUser?.id,
                });

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gönderi eklendi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gönderi eklenirken hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  // --- _showEditPostDialog ---
  void _showEditPostDialog(Map<String, dynamic> post) {
    final contentController = TextEditingController(text: post['content']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderi Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'İçerik',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
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
              if (contentController.text.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('İçerik gerekli')));
                return;
              }

              try {
                debugPrint('📝 Gönderi güncelleniyor: ${post['id']}');

                final response = await Supabase.instance.client
                    .from('posts')
                    .update({'content': contentController.text.trim()})
                    .eq('id', post['id'])
                    .select();

                debugPrint('✅ Gönderi güncelleme yanıtı: $response');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gönderi güncellendi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Gönderi güncellenirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gönderi güncellenirken hata: $e'),
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
    );
  }

  // --- _showDeletePostDialog ---
  void _showDeletePostDialog(Map<String, dynamic> post) {
    final content = post['content'] as String? ?? '';
    final preview = content.length > 50
        ? content.substring(0, 50)
        : content;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi Sil'),
        content: Text(
          'Bu gönderiyi silmek istediğinizden emin misiniz?\n\n"$preview..."\n\nBu işlem geri alınamaz.',
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
                debugPrint('🗑️ Gönderi siliniyor: ${post['id']}');
                debugPrint(
                  '📋 Kullanıcı ID: ${Supabase.instance.client.auth.currentUser?.id}',
                );
                debugPrint(
                  '📋 Kullanıcı rolü: ${Supabase.instance.client.auth.currentUser?.role}',
                );
                debugPrint(
                  '📋 Kullanıcı meta: ${Supabase.instance.client.auth.currentUser?.userMetadata}',
                );

                // Önce RPC ile dene (RLS bypass için)
                bool deleted = false;
                try {
                  await Supabase.instance.client.rpc(
                    'admin_delete_post',
                    params: {'post_id': post['id']},
                  );
                  debugPrint('✅ Gönderi RPC ile silindi');
                  deleted = true;
                } catch (rpcError) {
                  debugPrint(
                    '⚠️ RPC hatası (fonksiyon yok olabilir), doğrudan silme deneniyor: $rpcError',
                  );
                  // RPC başarısız olursa doğrudan sil
                  final response = await Supabase.instance.client
                      .from('posts')
                      .delete()
                      .eq('id', post['id'])
                      .select();

                  debugPrint('✅ Gönderi silme yanıtı: $response');
                  if (response.isNotEmpty) {
                    deleted = true;
                  }
                }

                if (mounted) {
                  if (deleted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Gönderi başarıyla silindi'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Gönderi silinemedi - RLS izni kontrol edin',
                        ),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Gönderi silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gönderi silinirken hata: ${e.toString()}'),
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

  // --- _showAddStoryDialog ---
  void _showAddStoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Hikaye Ekle'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Hikaye resimleri yüklemek için uygulamadaki hikaye özelliğini kullanınız',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // --- _showDeleteStoryDialog ---
  void _showDeleteStoryDialog(Map<String, dynamic> story) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hikayeyi Sil'),
        content: Text(
          'Bu hikayeyi silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz.',
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
                debugPrint('🗑️ Hikaye siliniyor: ${story['id']}');
                debugPrint(
                  '📋 Kullanıcı ID: ${Supabase.instance.client.auth.currentUser?.id}',
                );
                debugPrint(
                  '📋 Kullanıcı rolü: ${Supabase.instance.client.auth.currentUser?.role}',
                );
                debugPrint(
                  '📋 Kullanıcı meta: ${Supabase.instance.client.auth.currentUser?.userMetadata}',
                );

                // Önce RPC ile dene (RLS bypass için)
                bool deleted = false;
                try {
                  await Supabase.instance.client.rpc(
                    'admin_delete_story',
                    params: {'story_id': story['id']},
                  );
                  debugPrint('✅ Hikaye RPC ile silindi');
                  deleted = true;
                } catch (rpcError) {
                  debugPrint(
                    '⚠️ RPC hatası (fonksiyon yok olabilir), doğrudan silme deneniyor: $rpcError',
                  );
                  // RPC başarısız olursa doğrudan sil
                  final response = await Supabase.instance.client
                      .from('stories')
                      .delete()
                      .eq('id', story['id'])
                      .select();

                  debugPrint('✅ Hikaye silme yanıtı: $response');
                  if (response.isNotEmpty) {
                    deleted = true;
                  }
                }

                if (mounted) {
                  if (deleted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Hikaye başarıyla silindi'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Hikaye silinemedi - RLS izni kontrol edin',
                        ),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Hikaye silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hikaye silinirken hata: ${e.toString()}'),
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
}
