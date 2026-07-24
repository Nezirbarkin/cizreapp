// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CourierNoticesManagementContent extends StatefulWidget {
  const CourierNoticesManagementContent({super.key});

  @override
  State<CourierNoticesManagementContent> createState() =>
      _CourierNoticesManagementContentState();
}

class _CourierNoticesManagementContentState
    extends State<CourierNoticesManagementContent> {
  List<Map<String, dynamic>> _notices = [];
  bool _isLoading = true;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _selectedType = 'info';
  int _selectedPriority = 0;
  bool _showOnSendPackage = true;
  bool _showOnCourierPanel = true;

  @override
  void initState() {
    super.initState();
    _loadNotices();
  }

  Future<void> _loadNotices() async {
    setState(() => _isLoading = true);
    try {
      final notices = await Supabase.instance.client
          .from('courier_service_notices')
          .select()
          .order('created_at', ascending: false);
      setState(() => _notices = List<Map<String, dynamic>>.from(notices));
    } catch (e) {
      debugPrint('Uyarılar yükleme hatası: $e');
      _showError('Uyarılar yüklenemedi: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addNotice() async {
    if (_titleController.text.isEmpty || _messageController.text.isEmpty) {
      _showError('Başlık ve mesaj boş olamaz');
      return;
    }

    try {
      await Supabase.instance.client.from('courier_service_notices').insert({
        'title': _titleController.text,
        'message': _messageController.text,
        'notice_type': _selectedType,
        'priority': _selectedPriority,
        'show_on_send_package_screen': _showOnSendPackage,
        'show_on_courier_panel': _showOnCourierPanel,
        'is_active': true,
      });

      _titleController.clear();
      _messageController.clear();
      setState(() {
        _selectedType = 'info';
        _selectedPriority = 0;
        _showOnSendPackage = true;
        _showOnCourierPanel = true;
      });

      _loadNotices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uyarı eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Uyarı ekleme hatası: $e');
      _showError('Uyarı eklenemedi: $e');
    }
  }

  Future<void> _toggleActive(String id, bool currentState) async {
    try {
      await Supabase.instance.client
          .from('courier_service_notices')
          .update({'is_active': !currentState}).eq('id', id);
      _loadNotices();
    } catch (e) {
      debugPrint('Durum güncelleme hatası: $e');
      _showError('Durum güncellenemedi: $e');
    }
  }

  Future<void> _deleteNotice(String id) async {
    try {
      await Supabase.instance.client
          .from('courier_service_notices')
          .delete()
          .eq('id', id);
      _loadNotices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uyarı silindi'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Uyarı silme hatası: $e');
      _showError('Uyarı silinemedi: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'warning':
        return Colors.orange;
      case 'alert':
        return Colors.red;
      case 'success':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  String _getPriorityLabel(int priority) {
    switch (priority) {
      case 1:
        return 'ÖNEMLİ';
      case 2:
        return 'ACİL';
      default:
        return 'NORMAL';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Yeni Uyarı Ekleme Formu
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Yeni Uyarı Ekle',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Başlık',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Mesaj',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.message),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedType,
                          decoration: InputDecoration(
                            labelText: 'Tür',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: [
                            DropdownMenuItem(value: 'info', child: Text('ℹ️ Bilgi')),
                            DropdownMenuItem(value: 'warning', child: Text('⚠️ Uyarı')),
                            DropdownMenuItem(value: 'alert', child: Text('🚨 Acil')),
                            DropdownMenuItem(value: 'success', child: Text('✅ Başarı')),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedType = value ?? 'info');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedPriority,
                          decoration: InputDecoration(
                            labelText: 'Öncelik',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Normal')),
                            DropdownMenuItem(value: 1, child: Text('Önemli')),
                            DropdownMenuItem(value: 2, child: Text('Acil')),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedPriority = value ?? 0);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Paket Ekranında Göster'),
                          value: _showOnSendPackage,
                          onChanged: (value) {
                            setState(() => _showOnSendPackage = value ?? false);
                          },
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Kurye Panelinde Göster'),
                          value: _showOnCourierPanel,
                          onChanged: (value) {
                            setState(() => _showOnCourierPanel = value ?? false);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addNotice,
                      icon: const Icon(Icons.add),
                      label: const Text('Uyarı Ekle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Uyarılar Listesi
          const Text(
            'Mevcut Uyarılar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _notices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Henüz uyarı eklenmedi',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _notices.length,
                      itemBuilder: (context, index) {
                        final notice = _notices[index];
                        final typeColor = _getTypeColor(notice['notice_type']);
                        final isActive = notice['is_active'] as bool? ?? true;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: typeColor.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: typeColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: typeColor),
                                      ),
                                      child: Text(
                                        notice['notice_type'].toString().toUpperCase(),
                                        style: TextStyle(
                                          color: typeColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if ((notice['priority'] as int? ?? 0) > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (notice['priority'] as int? ?? 0) > 1
                                              ? Colors.red.shade100
                                              : Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _getPriorityLabel(
                                            notice['priority'] as int? ?? 0,
                                          ),
                                          style: TextStyle(
                                            color: (notice['priority'] as int? ?? 0) > 1
                                                ? Colors.red.shade700
                                                : Colors.orange.shade700,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    const Spacer(),
                                    IconButton(
                                      icon: Icon(
                                        isActive ? Icons.toggle_on : Icons.toggle_off,
                                        color: isActive ? Colors.green : Colors.grey,
                                        size: 24,
                                      ),
                                      onPressed: () => _toggleActive(
                                        notice['id'] as String,
                                        isActive,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteNotice(
                                        notice['id'] as String,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  notice['title'] as String? ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  notice['message'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (notice['show_on_send_package_screen'] as bool? ?? false)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '📦 Paket Ekranı',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    if (notice['show_on_courier_panel'] as bool? ?? false)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '🏍️ Kurye Paneli',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}
