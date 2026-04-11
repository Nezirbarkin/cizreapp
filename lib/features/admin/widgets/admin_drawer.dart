import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDrawer extends StatelessWidget {
  final String selectedSection;
  final Function(String) onSectionChanged;
  final User? currentUser;

  const AdminDrawer({
    super.key,
    required this.selectedSection,
    required this.onSectionChanged,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primaryContainer,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: 35,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Admin Panel',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (currentUser?.email != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      currentUser!.email!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildDrawerItem(
              context: context,
              icon: Icons.dashboard_rounded,
              title: 'Dashboard',
              section: 'dashboard',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.people_rounded,
              title: 'Kullanıcılar',
              section: 'users',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.post_add_rounded,
              title: 'Gönderiler',
              section: 'posts',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.shopping_bag_rounded,
              title: 'Ürünler',
              section: 'products',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.category_rounded,
              title: 'Kategoriler',
              section: 'categories',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.store_rounded,
              title: 'Dükkanlar',
              section: 'shops',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.receipt_long_rounded,
              title: 'Siparişler',
              section: 'orders',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.groups_rounded,
              title: 'Gruplar',
              section: 'groups',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.notifications_active_rounded,
              title: 'Bildirimler',
              section: 'notifications',
            ),
            const Divider(height: 24, thickness: 1),
            _buildDrawerItem(
              context: context,
              icon: Icons.flag_rounded,
              title: 'Raporlar',
              section: 'reports',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.support_agent_rounded,
              title: 'Destek Talepleri',
              section: 'support',
            ),
            const Divider(height: 24, thickness: 1),
            _buildDrawerItem(
              context: context,
              icon: Icons.payment_rounded,
              title: 'Ödemeler',
              section: 'payments',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.assessment_rounded,
              title: 'Kampanyalar',
              section: 'campaigns',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.local_fire_department_rounded,
              title: 'Günün Fırsatları',
              section: 'daily_deals',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.analytics_rounded,
              title: 'Analizler',
              section: 'analytics',
            ),
            const Divider(height: 24, thickness: 1),
            _buildDrawerItem(
              context: context,
              icon: Icons.api_rounded,
              title: 'API Ayarları',
              section: 'api',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.settings_rounded,
              title: 'Sistem Ayarları',
              section: 'settings',
            ),
            _buildDrawerItem(
              context: context,
              icon: Icons.info_outline_rounded,
              title: 'Hakkında Ayarları',
              section: 'about_settings',
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış Yap'),
                      content: const Text(
                        'Admin panelinden çıkış yapmak istediğinize emin misiniz?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('İptal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Çıkış Yap'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true && context.mounted) {
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushReplacementNamed('/login');
                    }
                  }
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Çıkış Yap'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String section,
  }) {
    final isSelected = selectedSection == section;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              // ignore: deprecated_member_use
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        selected: isSelected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onTap: () {
          onSectionChanged(section);
          Navigator.pop(context);
        },
      ),
    );
  }
}
