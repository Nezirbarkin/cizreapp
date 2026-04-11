// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/theme_provider.dart';
import '../models/user_model.dart';
import '../../features/market/screens/address_management_screen.dart';
import '../../features/market/screens/cart_screen.dart';
import '../../features/market/screens/order_history_screen.dart';
import '../../features/favorites/screens/favorites_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/notification_settings_screen.dart';
import '../../features/profile/screens/account_settings_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/seller/screens/seller_dashboard_screen.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  UserRole? _userRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _userRole = null;
          _isLoading = false;
        });
        return;
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        final roleStr = response['role'] as String?;
        setState(() {
          _userRole = UserRole.values.firstWhere(
            (e) => e.name == (roleStr ?? 'customer'),
            orElse: () => UserRole.customer,
          );
          _isLoading = false;
        });
      } else {
        setState(() {
          _userRole = UserRole.customer;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Kullanıcı rolü yüklenirken hata: $e');
      setState(() {
        _userRole = UserRole.customer;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: themeProvider.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ayarlar',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            
            // Menu Items
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  // Admin veya Satıcı Panel Butonu
                  if (_userRole == UserRole.admin)
                    _buildPanelButton(
                      context: context,
                      icon: Icons.admin_panel_settings,
                      title: 'Admin Paneli',
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
                    const SizedBox(height: 8),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.person_outline,
                    title: 'Profil',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
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
                  _buildMenuItem(
                    context: context,
                    icon: Icons.shopping_cart_outlined,
                    title: 'Sepetim',
                     onTap: () {
                       Navigator.pop(context);
                       Navigator.push(
                         context,
                         MaterialPageRoute(
                           builder: (context) => const CartScreen(),
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
                     icon: Icons.receipt_long_outlined,
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
                    icon: Icons.palette_outlined,
                    title: 'Tema',
                    onTap: () => _showThemeDialog(context),
                  ),
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
                  _buildMenuItem(
                    context: context,
                    icon: Icons.settings_outlined,
                    title: 'Uygulama Ayarı',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Uygulama ayarlarına gidildi')),
                      );
                    },
                  ),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.help_outline,
                    title: 'Destek Merkezi',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Destek merkezi açıldı')),
                      );
                    },
                  ),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.info_outline,
                    title: 'Hakkında',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Hakkında sayfasına gidildi')),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Giriş Yap veya Çıkış Yap butonu
                  _buildAuthButton(
                    context: context,
                    isGuest: Supabase.instance.client.auth.currentUser == null,
                    onTap: () async {
                      final isGuest = Supabase.instance.client.auth.currentUser == null;
                      
                      if (isGuest) {
                         // Misafir kullanıcı - Giriş ekranına yönlendir
                         Navigator.of(context).pop();
                         Navigator.of(context).pushNamed('/login');
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

                        if (confirm == true) {
                          try {
                            await Supabase.instance.client.auth.signOut();
                            // Ana ekrana yönlendir (misafir modu)
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/',
                              (route) => false,
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Çıkış yapılırken hata: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              color: themeProvider.primaryColor,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey.shade400,
              size: 16,
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
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    'Yönetim Paneli',
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: color.withOpacity(0.6),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeDialog(BuildContext parentContext) {
    final themeProvider = Provider.of<ThemeProvider>(parentContext, listen: false);
    
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
                        Navigator.pop(parentContext);
                      },
                    ),
                    _buildThemeOption(
                      themeProvider: themeProvider,
                      color: Colors.blue.shade600,
                      label: 'Mavi',
                      onTap: () {
                        themeProvider.setTheme(Colors.blue.shade600);
                        Navigator.pop(context);
                        Navigator.pop(parentContext);
                      },
                    ),
                    _buildThemeOption(
                      themeProvider: themeProvider,
                      color: Colors.pink.shade600,
                      label: 'Pembe',
                      onTap: () {
                        themeProvider.setTheme(Colors.pink.shade600);
                        Navigator.pop(context);
                        Navigator.pop(parentContext);
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
       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
       decoration: BoxDecoration(
         color: color.shade50,
         borderRadius: BorderRadius.circular(12),
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
               fontSize: 16,
               fontWeight: FontWeight.w700,
               color: color.shade600,
             ),
           ),
         ],
       ),
     ),
   );
 }
}
