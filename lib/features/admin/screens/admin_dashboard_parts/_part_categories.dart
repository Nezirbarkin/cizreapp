part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Kategoriler + ekleme/duzenleme/silme dialoglari
  // ==========================================================================

  // --- _buildCategoriesContent ---
  Widget _buildCategoriesContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadCategories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final categories = snapshot.data ?? [];

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
                      'Kategori Yönetimi',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddCategoryDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Kategori'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (categories.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz kategori yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _buildCategoryCard(category);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _buildCategoryCard ---
  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final iconData = Icons.category; // Varsayılan icon
    final color = Colors.purple; // Varsayılan renk
    final shopCount = category['shop_count'] ?? 0;
    final imageUrl = category['image_url'] as String?;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: IntrinsicHeight(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Resim varsa göster, yoksa ikon göster
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: imageUrl == null
                          ? color.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) {
                                return Icon(iconData, color: color, size: 24);
                              },
                            ),
                          )
                        : Icon(iconData, color: color, size: 24),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditCategoryDialog(category);
                      } else if (value == 'delete') {
                        _showDeleteCategoryDialog(category);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Düzenle'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Sil', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                category['name'] ?? '-',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Dükkan sayısı gösterimi
              Row(
                children: [
                  Icon(Icons.store, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    '$shopCount dükkan',
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  category['description'] ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.sort, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    'Sıra: ${category['display_order'] ?? 0}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  if (category['is_active'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Aktif',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Pasif',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
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

  // --- _showAddCategoryDialog ---
  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final sortOrderController = TextEditingController(text: '0');
    bool isActive = true;
    XFile? selectedImage;
    String? previewUrl;
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Yeni Kategori Ekle'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Görsel Yükleme Alanı
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 800,
                        maxHeight: 800,
                        imageQuality: 85,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedImage = picked;
                          previewUrl = picked.path;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedImage != null
                              ? Colors.purple.shade300
                              : Colors.grey.shade300,
                          width: selectedImage != null ? 2 : 1,
                        ),
                        image: previewUrl != null
                            ? DecorationImage(
                                image: previewUrl!.startsWith('http')
                                    ? NetworkImage(previewUrl!) as ImageProvider
                                    : AssetImage(previewUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: selectedImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 40,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Görsel Yükle',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Dokunarak galeriden seçin',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : Stack(
                              children: [
                                // Seçili resmi göster
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: Image.asset(
                                      previewUrl!,
                                      fit: BoxFit.cover,
                                      // ignore: unnecessary_underscores
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                            child: Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                              size: 40,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                                // Sil butonu
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        selectedImage = null;
                                        previewUrl = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Kategori Adı *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sortOrderController,
                    decoration: const InputDecoration(
                      labelText: 'Sıralama *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sort),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Aktif'),
                    subtitle: const Text('Kategori kullanıcıya gösterilsin'),
                    value: isActive,
                    onChanged: (value) {
                      setDialogState(() => isActive = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      if (nameController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Kategori adı gerekli')),
                        );
                        return;
                      }

                      try {
                        setDialogState(() => isUploading = true);
                        debugPrint('📝 Yeni kategori ekleniyor...');

                        String? imageUrl;

                        // Görsel yükle
                        if (selectedImage != null) {
                          final bytes = await selectedImage!.readAsBytes();
                          final fileName =
                              'category_${DateTime.now().millisecondsSinceEpoch}.jpg';
                          final path = 'categories/$fileName';

                          await Supabase.instance.client.storage
                              .from('category-images')
                              .uploadBinary(
                                path,
                                bytes,
                                fileOptions: const FileOptions(
                                  contentType: 'image/jpeg',
                                ),
                              );

                          imageUrl = Supabase.instance.client.storage
                              .from('category-images')
                              .getPublicUrl(path);
                        }

                        // Doğrudan Supabase ile ekle
                        final insertData = {
                          'name': nameController.text.trim(),
                          'slug': nameController.text
                              .trim()
                              .toLowerCase()
                              .replaceAll(' ', '-')
                              .replaceAll(RegExp(r'[^a-z0-9-]'), ''),
                          'description': descriptionController.text.trim(),
                          'display_order':
                              int.tryParse(sortOrderController.text) ?? 0,
                          'is_active': isActive,
                        };

                        // Resim URL varsa ekle
                        if (imageUrl != null) {
                          insertData['image_url'] = imageUrl;
                        }

                        await Supabase.instance.client
                            .from('categories')
                            .insert(insertData);

                        debugPrint('✅ Kategori başarıyla eklendi');

                        if (mounted) {
                          Navigator.pop(context);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Kategori başarıyla eklendi'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('❌ Kategori eklenirken hata: $e');
                        setDialogState(() => isUploading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Kategori eklenirken hata: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  // --- _showEditCategoryDialog ---
  void _showEditCategoryDialog(Map<String, dynamic> category) {
    final nameController = TextEditingController(text: category['name']);
    final descriptionController = TextEditingController(
      text: category['description'] ?? '',
    );
    final sortOrderController = TextEditingController(
      text: category['display_order']?.toString() ?? '0',
    );
    bool isActive = category['is_active'] ?? true;
    XFile? selectedImage;
    String? previewUrl = category['image_url'];
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kategoriyi Düzenle'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Kategori Adı *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sortOrderController,
                    decoration: const InputDecoration(
                      labelText: 'Sıralama *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sort),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  // Resim seçimi
                  GestureDetector(
                    onTap: isUploading
                        ? null
                        : () async {
                            final ImagePicker picker = ImagePicker();
                            final XFile? image = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1024,
                              maxHeight: 1024,
                              imageQuality: 85,
                            );

                            if (image != null) {
                              setDialogState(() {
                                selectedImage = image;
                                previewUrl = null; // Eski URL'yi temizle
                              });
                            }
                          },
                    child: Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[100],
                      ),
                      child: selectedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: selectedImage!.path,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorWidget: (context, url, error) {
                                  return const Center(
                                    child: Icon(
                                      Icons.error,
                                      size: 48,
                                      color: Colors.red,
                                    ),
                                  );
                                },
                              ),
                            )
                          : previewUrl != null && previewUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: previewUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorWidget: (context, url, error) {
                                  return const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Resim Seç',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Resim Seç (İsteğe Bağlı)',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Aktif'),
                    subtitle: const Text('Kategori kullanıcıya gösterilsin'),
                    value: isActive,
                    onChanged: (value) {
                      setDialogState(() => isActive = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      if (nameController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Kategori adı gerekli')),
                        );
                        return;
                      }

                      try {
                        setDialogState(() => isUploading = true);

                        debugPrint(
                          '📝 Kategori güncelleniyor: ${category['id']}',
                        );

                        String? imageUrl = category['image_url'];

                        // Yeni resim seçildiyse yükle
                        if (selectedImage != null) {
                          debugPrint('📤 Resim yükleniyor...');

                          final bytes = await selectedImage!.readAsBytes();
                          final fileExt = selectedImage!.path
                              .split('.')
                              .last
                              .toLowerCase();
                          // Dosya adındaki geçersiz karakterleri temizle (& ş ğ ü ö ç ı vb)
                          final safeName = nameController.text
                              .trim()
                              .toLowerCase()
                              .replaceAll(' ', '_')
                              .replaceAll('&', 've')
                              .replaceAll('ş', 's')
                              .replaceAll('ğ', 'g')
                              .replaceAll('ü', 'u')
                              .replaceAll('ö', 'o')
                              .replaceAll('ç', 'c')
                              .replaceAll('ı', 'i')
                              .replaceAll('İ', 'i')
                              .replaceAll('Ş', 's')
                              .replaceAll('Ğ', 'g')
                              .replaceAll('Ü', 'u')
                              .replaceAll('Ö', 'o')
                              .replaceAll('Ç', 'c')
                              .replaceAll(RegExp(r'[^a-z0-9_]'), '');
                          final fileName =
                              '${DateTime.now().millisecondsSinceEpoch}_$safeName.$fileExt';
                          final filePath = 'category-images/$fileName';

                          // MIME type düzeltmesi: jpg -> jpeg
                          String contentType = 'image/$fileExt';
                          if (fileExt == 'jpg') {
                            contentType = 'image/jpeg';
                          }

                          await Supabase.instance.client.storage
                              .from('category-images')
                              .uploadBinary(
                                filePath,
                                bytes,
                                fileOptions: FileOptions(
                                  contentType: contentType,
                                  upsert: false,
                                ),
                              );

                          imageUrl = Supabase.instance.client.storage
                              .from('category-images')
                              .getPublicUrl(filePath);

                          debugPrint('✅ Resim yüklendi: $imageUrl');
                        }

                        // Kategoriyi güncelle
                        final updateData = {
                          'name': nameController.text.trim(),
                          'slug': nameController.text
                              .trim()
                              .toLowerCase()
                              .replaceAll(' ', '-')
                              .replaceAll(RegExp(r'[^a-z0-9-]'), ''),
                          'description': descriptionController.text.trim(),
                          'display_order':
                              int.tryParse(sortOrderController.text) ?? 0,
                          'is_active': isActive,
                        };

                        if (imageUrl != null && imageUrl.isNotEmpty) {
                          updateData['image_url'] = imageUrl;
                        }

                        await Supabase.instance.client
                            .from('categories')
                            .update(updateData)
                            .eq('id', category['id']);

                        debugPrint('✅ Kategori başarıyla güncellendi');

                        if (mounted) {
                          Navigator.pop(context);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Kategori başarıyla güncellendi'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('❌ Kategori güncellenirken hata: $e');
                        setDialogState(() => isUploading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Kategori güncellenirken hata: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  // --- _showDeleteCategoryDialog ---
  void _showDeleteCategoryDialog(Map<String, dynamic> category) {
    final shopCount = category['shop_count'] ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategoriyi Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${category['name']} kategorisini silmek istediğinizden emin misiniz?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (shopCount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu kategoriye ait $shopCount dükkan var. Kategoriyi silebilmek için önce bu dükkanları başka bir kategoriye taşımalısınız.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Bu işlem geri alınamaz.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          if (shopCount == 0)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  debugPrint(
                    '🗑️ Kategori siliniyor: ${category['id']} (${category['name']})',
                  );

                  // Doğrudan Supabase ile sil (RLS sorunlarını önlemek için)
                  final response = await Supabase.instance.client
                      .from('categories')
                      .delete()
                      .eq('id', category['id'])
                      .select();

                  debugPrint('✅ Kategori silme yanıtı: $response');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kategori başarıyla silindi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Kategori silinirken hata: $e');

                  String errorMessage = 'Kategori silinirken hata oluştu';
                  if (e.toString().contains('foreign key constraint')) {
                    errorMessage =
                        'Bu kategoriye ait dükkanlar var. Önce dükkanları başka bir kategoriye taşıyın.';
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorMessage),
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
