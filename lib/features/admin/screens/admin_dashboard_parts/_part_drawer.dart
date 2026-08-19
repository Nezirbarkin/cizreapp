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
  // Drawer widgets (menu)
  // ==========================================================================

  // --- _buildDrawer ---
  Widget _buildDrawer(BuildContext context, User? currentUser) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple.shade700, Colors.purple.shade900],
          ),
        ),
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: 40,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Admin Panel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // ignore: deprecated_member_use
                    currentUser?.email ?? 'admin@cizreapp.com',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, thickness: 1),

            // Menu Items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    isSelected: _selectedMenu == 'Dashboard',
                    onTap: () {
                      setState(() => _selectedMenu = 'Dashboard');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.people_rounded,
                    title: 'Kullanıcılar',
                    isSelected: _selectedMenu == 'Kullanıcılar',
                    badgeCount: _newUsersCount,
                    onTap: () {
                      setState(() {
                        _selectedMenu = 'Kullanıcılar';
                        _newUsersCount = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Kullanıcı Özellikleri',
                    isSelected: _selectedMenu == 'Kullanıcı Özellikleri',
                    onTap: () {
                      setState(() => _selectedMenu = 'Kullanıcı Özellikleri');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.post_add_rounded,
                    title: 'Gönderiler',
                    isSelected: _selectedMenu == 'Gönderiler',
                    badgeCount: _newPostsCount,
                    onTap: () {
                      setState(() {
                        _selectedMenu = 'Gönderiler';
                        _newPostsCount = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.campaign_rounded,
                    title: 'İlanlar & Kategoriler',
                    isSelected: _selectedMenu == 'İlanlar & Kategoriler',
                    onTap: () {
                      setState(() => _selectedMenu = 'İlanlar & Kategoriler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.newspaper_rounded,
                    title: 'Haberler',
                    isSelected: _selectedMenu == 'Haberler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Haberler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.shopping_bag_rounded,
                    title: 'Ürünler',
                    isSelected: _selectedMenu == 'Ürünler',
                    badgeCount: _newProductsCount,
                    onTap: () {
                      setState(() {
                        _selectedMenu = 'Ürünler';
                        _newProductsCount = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.smart_toy_rounded,
                    title: 'SMM Sağlayıcıları',
                    isSelected: _selectedMenu == 'SMM Sağlayıcıları',
                    onTap: () {
                      setState(() => _selectedMenu = 'SMM Sağlayıcıları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.category_rounded,
                    title: 'Kategoriler',
                    isSelected: _selectedMenu == 'Kategoriler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Kategoriler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.store_rounded,
                    title: 'Dükkanlar',
                    isSelected: _selectedMenu == 'Dükkanlar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Dükkanlar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.receipt_long_rounded,
                    title: 'Siparişler',
                    isSelected: _selectedMenu == 'Siparişler',
                    badgeCount: _newOrdersCount,
                    onTap: () {
                      setState(() {
                        _selectedMenu = 'Siparişler';
                        _newOrdersCount = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.delivery_dining,
                    title: 'Kurye Yönetimi',
                    isSelected: _selectedMenu == 'Kurye Yönetimi',
                    onTap: () {
                      setState(() => _selectedMenu = 'Kurye Yönetimi');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.notifications_active_rounded,
                    title: 'Bildirimler',
                    isSelected: _selectedMenu == 'Bildirimler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Bildirimler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.groups_rounded,
                    title: 'Gruplar',
                    isSelected: _selectedMenu == 'Gruplar',
                    badgeCount: _newGroupsCount,
                    onTap: () {
                      setState(() {
                        _selectedMenu = 'Gruplar';
                        _newGroupsCount = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.flag_rounded,
                    title: 'Şikayetler',
                    isSelected: _selectedMenu == 'Şikayetler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Şikayetler');
                      Navigator.pop(context);
                    },
                    badgeCount: _unansweredComplaintCount,
                  ),
                  _buildDrawerItem(
                    icon: Icons.support_agent_rounded,
                    title: 'Destek Talepleri',
                    isSelected: _selectedMenu == 'Destek Talepleri',
                    badgeCount: _unansweredTicketCount,
                    onTap: () {
                      setState(() => _selectedMenu = 'Destek Talepleri');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.payment_rounded,
                    title: 'Ödemeler',
                    isSelected: _selectedMenu == 'Ödemeler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Ödemeler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.assessment_rounded,
                    title: 'Raporlar',
                    isSelected: _selectedMenu == 'Raporlar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Raporlar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.local_fire_department_rounded,
                    title: 'Günün Fırsatları',
                    isSelected: _selectedMenu == 'Günün Fırsatları',
                    onTap: () {
                      setState(() => _selectedMenu = 'Günün Fırsatları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.analytics_rounded,
                    title: 'Analitik',
                    isSelected: _selectedMenu == 'Analitik',
                    onTap: () {
                      setState(() => _selectedMenu = 'Analitik');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.history_rounded,
                    title: 'Loglar',
                    isSelected: _selectedMenu == 'Loglar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Loglar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.api_rounded,
                    title: 'API Ayarları',
                    isSelected: _selectedMenu == 'API Ayarları',
                    onTap: () {
                      setState(() => _selectedMenu = 'API Ayarları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.settings_rounded,
                    title: 'Ayarlar',
                    isSelected: _selectedMenu == 'Ayarlar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Ayarlar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.info_outline_rounded,
                    title: 'Hakkında Ayarları',
                    isSelected: _selectedMenu == 'Hakkında Ayarları',
                    onTap: () {
                      setState(() => _selectedMenu = 'Hakkında Ayarları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.play_circle_fill_rounded,
                    title: 'Reklam Ayarları',
                    isSelected: _selectedMenu == 'Reklam Ayarları',
                    onTap: () {
                      setState(() => _selectedMenu = 'Reklam Ayarları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.directions_bus_rounded,
                    title: 'Şehiriçi Yönetimi',
                    isSelected: _selectedMenu == 'Şehiriçi Yönetimi',
                    onTap: () {
                      setState(() => _selectedMenu = 'Şehiriçi Yönetimi');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.account_balance_wallet,
                    title: 'Cüzdan Yönetimi',
                    isSelected: _selectedMenu == 'Cüzdan Yönetimi',
                    onTap: () {
                      setState(() => _selectedMenu = 'Cüzdan Yönetimi');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.assignment_turned_in_rounded,
                    title: 'Görev Yönetimi',
                    isSelected: _selectedMenu == 'Görev Yönetimi',
                    onTap: () {
                      setState(() => _selectedMenu = 'Görev Yönetimi');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.notification_important,
                    title: 'Kurye Uyarıları',
                    isSelected: _selectedMenu == 'Kurye Uyarıları',
                    onTap: () {
                      setState(() => _selectedMenu = 'Kurye Uyarıları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.gpp_bad_rounded,
                    title: 'Şüpheli Kullanıcılar',
                    isSelected: _selectedMenu == 'Şüpheli Kullanıcılar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Şüpheli Kullanıcılar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.radar_rounded,
                    title: 'Dolandırıcılık Sinyalleri',
                    isSelected: _selectedMenu == 'Dolandırıcılık Sinyalleri',
                    onTap: () {
                      setState(
                        () => _selectedMenu = 'Dolandırıcılık Sinyalleri',
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white24, thickness: 1),

            // Ana Sayfaya Git
            ListTile(
              leading: const Icon(Icons.home, color: Colors.white),
              title: const Text(
                'Ana Sayfaya Dön',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/',
                  (route) => false,
                );
              },
            ),

            // Çıkış Yap
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text(
                'Çıkış Yap',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                // Root navigator key ile güvenli çıkış → login ekranı.
                await AppNavigator.signOutAndReset('/login');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // --- _buildDrawerItem ---
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: badgeCount != null && badgeCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
