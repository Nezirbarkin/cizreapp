// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/theme_provider.dart';
import '../models/user_model.dart';
import '../services/privacy_service.dart';
import '../../features/favorites/screens/favorites_screen.dart';
import '../../features/market/screens/address_management_screen.dart';
import '../../features/market/screens/order_history_screen.dart';
import '../../features/profile/screens/support_center_screen.dart';
import '../../features/profile/screens/notification_settings_screen.dart';
import '../../features/profile/screens/account_settings_screen.dart';
import '../../features/profile/screens/about_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/seller/screens/seller_dashboard_screen.dart';

class SettingsSidebar extends StatefulWidget {
  const SettingsSidebar({super.key});

  @override
  State<SettingsSidebar> createState() => _SettingsSidebarState();
}

class _SettingsSidebarState extends State<SettingsSidebar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  // Profil verileri
  String _username = '';
  String _fullName = '';
  String? _avatarUrl;
  bool _isLoading = true;
  UserRole? _userRole;

  // Gizlilik & Durum
  final PrivacyService _privacyService = PrivacyService();
  bool _isOnline = true;
  bool _isGhostMode = false;
  bool _isLoadingPrivacy = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    
    _controller.forward();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    // Misafir kullanıcı kontrolü
    if (userId == null) {
      if (mounted) {
        setState(() {
          _username = 'Misafir';
          _fullName = 'Misafir Kullanıcı';
          _avatarUrl = null;
          _userRole = null;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        if (response != null) {
          final roleStr = response['role'] as String?;
          setState(() {
            _username = response['username'] ?? '';
            _fullName = response['full_name'] ?? response['username'] ?? 'Kullanıcı';
            _avatarUrl = response['avatar_url'];
            _userRole = UserRole.values.firstWhere(
              (e) => e.name == (roleStr ?? 'customer'),
              orElse: () => UserRole.customer,
            );
            _isLoading = false;
          });
        } else {
          // Profil bulunamadı
          setState(() {
            _username = 'Kullanıcı';
            _fullName = 'Profil Bulunamadı';
            _userRole = UserRole.customer;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');
      if (mounted) {
        setState(() {
          _username = 'Kullanıcı';
          _fullName = 'Hata';
          _userRole = UserRole.customer;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPrivacySettings() async {
    try {
      final isOnline = await _privacyService.getOnlineStatus();
      final isGhostMode = await _privacyService.getGhostMode();
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
          _isGhostMode = isGhostMode;
        });
      }
    } catch (e) {
      debugPrint('Gizlilik ayarları yüklenirken hata: $e');
    }
  }

  Future<void> _setOnlineStatus(bool value) async {
    if (_isLoadingPrivacy) return;
    setState(() => _isLoadingPrivacy = true);
    try {
      final success = await _privacyService.updateOnlineStatus(value);
      if (success && mounted) {
        setState(() => _isOnline = value);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPrivacy = false);
      }
    }
  }

  Future<void> _setGhostMode(bool value) async {
    if (_isLoadingPrivacy) return;
    setState(() => _isLoadingPrivacy = true);
    try {
      final success = await _privacyService.updateGhostMode(value);
      if (success && mounted) {
        setState(() => _isGhostMode = value);
        // Hayalet mod açılırsa çevrimiçi durumu kapat
        if (value) {
          setState(() => _isOnline = false);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPrivacy = false);
      }
    }
  }

  void _close() async {
    await _controller.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        await _controller.reverse();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Overlay (arka plan)
            GestureDetector(
              onTap: _close,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  // ignore: deprecated_member_use
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
            ),
            
            // Sidebar Panel
            Align(
              alignment: Alignment.centerRight,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FA),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        offset: Offset(-2, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header (Yeşil üst bölüm)
                      Container(
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + 20,
                          left: 24,
                          right: 24,
                          bottom: 24,
                        ),
                        decoration: BoxDecoration(
                          color: themeProvider.primaryColor,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(40),
                          ),
                          boxShadow: [
                            BoxShadow(
                              // ignore: deprecated_member_use
                              color: themeProvider.primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Kapat butonu
                            Align(
                              alignment: Alignment.topRight,
                              child: GestureDetector(
                                onTap: _close,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    // ignore: deprecated_member_use
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Profil bilgileri - Gerçek verilerle
                            Row(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      // ignore: deprecated_member_use
                                      color: Colors.white.withOpacity(0.3),
                                      width: 4,
                                    ),
                                    color: Colors.white,
                                  ),
                                  child: ClipOval(
                                    child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                                        ? Image.network(
                                            _avatarUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return const Icon(Icons.person, size: 32, color: Colors.grey);
                                            },
                                          )
                                        : Icon(
                                            Icons.person,
                                            size: 32,
                                            color: themeProvider.primaryColor,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isLoading ? 'Yükleniyor...' : _fullName,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          height: 1.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _isLoading ? '...' : '@$_username',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // Menü içerikleri
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(
                            left: 24,
                            right: 24,
                            top: 24,
                            bottom: 24 + bottomPadding, // Bottom padding eklendi
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Admin veya Satıcı Panel Butonu
                              if (_userRole == UserRole.admin)
                                _buildPanelButton(
                                  context: context,
                                  icon: Icons.admin_panel_settings,
                                  title: 'Admin Paneli',
                                  subtitle: 'Yönetim Merkezi',
                                  color: Colors.purple,
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const AdminDashboardScreen(),
                                      ),
                                    );
                                  },
                                ),
                              if (_userRole == UserRole.seller)
                                _buildPanelButton(
                                  context: context,
                                  icon: Icons.store,
                                  title: 'Satıcı Paneli',
                                  subtitle: 'Mağaza Yönetimi',
                                  color: Colors.orange,
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const SellerDashboardScreen(),
                                      ),
                                    );
                                  },
                                ),
                              if (_userRole == UserRole.admin || _userRole == UserRole.seller)
                                const SizedBox(height: 24),
                              
                              // Hesabım bölümü
                              const Text(
                                'HESABIM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              _buildMenuItem(
                                context: context,
                                icon: Icons.favorite_outline,
                                title: 'Favorilerim',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const FavoritesScreen(),
                                    ),
                                  );
                                },
                              ),
                              
                              _buildMenuItem(
                                context: context,
                                icon: Icons.location_on_outlined,
                                title: 'Adreslerim',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const AddressManagementScreen(),
                                    ),
                                  );
                                },
                              ),
                              
                              _buildMenuItem(
                                context: context,
                                icon: Icons.shopping_cart_outlined,
                                title: 'Siparişlerim',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const OrderHistoryScreen(),
                                    ),
                                  );
                                },
                              ),
                              
                              _buildMenuItem(
                                context: context,
                                icon: Icons.security_outlined,
                                title: 'Hesap Ayarları',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const AccountSettingsScreen(),
                                    ),
                                  );
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Gizlilik & Durum
                              const Text(
                                'GİZLİLİK & DURUM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              Opacity(
                                opacity: _isGhostMode ? 0.5 : 1.0,
                                child: _buildToggleItem(
                                  context: context,
                                  icon: _isOnline ? Icons.circle : Icons.circle_outlined,
                                  title: _isOnline ? 'Çevrimiçi Durumum: Açık' : 'Çevrimiçi Durumum: Kapalı',
                                  value: _isOnline,
                                  activeColor: themeProvider.primaryColor,
                                  onChanged: (value) {
                                    if (!_isGhostMode) {
                                      _setOnlineStatus(value);
                                    }
                                  },
                                ),
                              ),
                              
                              _buildToggleItem(
                                context: context,
                                icon: _isGhostMode ? Icons.visibility_off : Icons.visibility,
                                title: 'Hayalet Modu${_isGhostMode ? ' (Aktif)' : ''}',
                                value: _isGhostMode,
                                activeColor: Colors.indigo,
                                onChanged: (value) {
                                  _setGhostMode(value);
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Bildirimler
                              const Text(
                                'BİLDİRİMLER',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              _buildMenuItem(
                                context: context,
                                icon: Icons.notifications_outlined,
                                title: 'Bildirim Ayarları',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const NotificationSettingsScreen(),
                                    ),
                                  );
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Destek & Yardım
                              const Text(
                                'DESTEK & YARDIM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              _buildMenuItem(
                                context: context,
                                icon: Icons.help_outline,
                                title: 'Destek Merkezi',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const SupportCenterScreen(),
                                    ),
                                  );
                                },
                              ),

                              _buildMenuItem(
                                context: context,
                                icon: Icons.info_outline,
                                title: 'Hakkında',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const AboutScreen(),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 24),

                              // Görünüm
                              const Text(
                                'GÖRÜNÜM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              _buildMenuItem(
                                context: context,
                                icon: Icons.palette_outlined,
                                title: 'Tema',
                                onTap: () {
                                  _showThemeDialog(context, themeProvider);
                                },
                              ),

                              const SizedBox(height: 32),

                              // Giriş Yap veya Çıkış Yap butonu
                              _buildAuthButton(
                                context: context,
                                isGuest: Supabase.instance.client.auth.currentUser == null,
                                onTap: () async {
                                  final isGuest = Supabase.instance.client.auth.currentUser == null;
                                  
                                  if (isGuest) {
                                    // Misafir kullanıcı - Giriş ekranına yönlendir
                                    if (mounted) {
                                      Navigator.of(context).pushNamedAndRemoveUntil(
                                        '/login',
                                        (route) => false,
                                      );
                                    }
                                  } else {
                                    // Giriş yapmış kullanıcı - Çıkış yap onayı
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        title: const Text('Çıkış Yap'),
                                        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('İptal'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                            ),
                                            child: const Text('Çıkış'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true && mounted) {
                                      try {
                                        await Supabase.instance.client.auth.signOut();
                                        // Ana ekrana yönlendir (misafir modu)
                                        if (mounted) {
                                          // ignore: use_build_context_synchronously
                                          Navigator.of(context).pushNamedAndRemoveUntil(
                                            '/',
                                            (route) => false,
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          // ignore: use_build_context_synchronously
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Çıkış yapılırken hata: $e')),
                                          );
                                        }
                                      }
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.grey.shade500,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withOpacity(0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: value ? activeColor.withOpacity(0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: value ? activeColor : Colors.grey.shade500,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? activeColor : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext parentContext, ThemeProvider themeProvider) {
    showDialog(
      context: parentContext,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tema Seç',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildThemeOption(
                      themeProvider: themeProvider,
                      color: Colors.green.shade600,
                      label: 'Yeşil',
                      onTap: () {
                        themeProvider.setTheme(Colors.green.shade600);
                        Navigator.pop(context);
                      },
                    ),
                    _buildThemeOption(
                      themeProvider: themeProvider,
                      color: Colors.blue.shade600,
                      label: 'Mavi',
                      onTap: () {
                        themeProvider.setTheme(Colors.blue.shade600);
                        Navigator.pop(context);
                      },
                    ),
                    _buildThemeOption(
                      themeProvider: themeProvider,
                      color: Colors.pink.shade600,
                      label: 'Pembe',
                      onTap: () {
                        themeProvider.setTheme(Colors.pink.shade600);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeOption({
    required ThemeProvider themeProvider,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    final isSelected = themeProvider.primaryColor == color;
    
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: Colors.black,
                      width: 3,
                    )
                  : null,
            ),
            child: isSelected
                ? const Center(
                    child: Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 24,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isSelected ? color : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthButton({
    required BuildContext context,
    required bool isGuest,
    required VoidCallback onTap,
  }) {
    final color = isGuest ? Colors.green : Colors.red;
    final icon = isGuest ? Icons.login : Icons.logout;
    final text = isGuest ? 'Giriş Yap' : 'Çıkış Yap';
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color.shade600,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Yardımcı fonksiyon - sağdan açılış için
void showSettingsSidebar(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SettingsSidebar();
      },
    ),
  );
}
