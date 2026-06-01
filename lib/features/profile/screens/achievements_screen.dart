// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/achievement_model.dart';
import '../../../core/services/achievement_service.dart';

/// Başarımlar ve rozetler ekranı
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> with SingleTickerProviderStateMixin {
  final AchievementService _achievementService = AchievementService();
  late TabController _tabController;
  
  UserAchievements? _userAchievements;
  bool _isLoading = true;
  // ignore: unused_field
  List<Achievement> _newlyUnlocked = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAchievements();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAchievements() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Başarımları kontrol et ve yeni açılan varsa getir
      final newlyUnlocked = await _achievementService.checkAndUnlockAchievements(userId);
      
      // Kullanıcı başarımlarını getir
      final userAchievements = await _achievementService.getUserAchievements(userId);

      if (mounted) {
        setState(() {
          _userAchievements = userAchievements;
          _newlyUnlocked = newlyUnlocked;
          _isLoading = false;
        });

        // Yeni açılan başarımlar varsa göster
        if (newlyUnlocked.isNotEmpty) {
          _showUnlockedDialog(newlyUnlocked);
        }
      }
    } catch (e) {
      debugPrint('❌ Başarımlar yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showUnlockedDialog(List<Achievement> achievements) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events,
              size: 64,
              color: Colors.amber,
            ),
            const SizedBox(height: 16),
            const Text(
              '🎉 Yeni Başarı!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...achievements.map((a) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    AchievementIcons.getIcon(a.iconName),
                    color: AchievementIcons.getColor(a.type),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '+${a.xpReward} XP',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Harika!'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Başarımlar'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Aktif'),
            Tab(text: 'Kilitli'),
            Tab(text: 'Seviye'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userAchievements == null
              ? _buildEmptyState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildUnlockedTab(),
                    _buildLockedTab(),
                    _buildLevelTab(),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 24),
          Text(
            'Başarımlar yüklenemedi',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadAchievements,
            child: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockedTab() {
    final unlocked = _userAchievements!.unlockedAchievements;
    
    if (unlocked.isEmpty) {
      return _buildNoAchievementsState(
        'Henüz açılmış başarım yok',
        'Sipariş ver, değerlendirme yap, arkadaşlarını davet et!',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAchievements,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: unlocked.length,
        itemBuilder: (context, index) {
          return _buildAchievementCard(unlocked[index], isUnlocked: true);
        },
      ),
    );
  }

  Widget _buildLockedTab() {
    final upcoming = _userAchievements!.upcomingAchievements;
    final locked = _userAchievements!.achievements
        .where((a) => !a.isUnlocked && a.currentCount == 0)
        .toList();

    if (upcoming.isEmpty && locked.isEmpty) {
      return _buildNoAchievementsState(
        'Tüm başarımlar açıldı!',
        'Harika! Tüm başarımları tamamladın 🎉',
      );
    }

    final allLocked = [...upcoming, ...locked];

    return RefreshIndicator(
      onRefresh: _loadAchievements,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: allLocked.length,
        itemBuilder: (context, index) {
          return _buildAchievementCard(allLocked[index], isUnlocked: false);
        },
      ),
    );
  }

  Widget _buildLevelTab() {
    final level = _userAchievements!.level;
    final totalXp = _userAchievements!.totalXp;
    final progress = _userAchievements!.levelProgress;
    final xpToNext = _userAchievements!.xpToNextLevel;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Seviye kartı
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Seviye rozeti
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.workspace_premium,
                          size: 40,
                          color: Colors.amber,
                        ),
                        Text(
                          'Lv.$level',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Seviye $level',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$totalXp XP Toplam',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 20),
                // İlerleme çubuğu
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$xpToNext XP sonra seviye ${level + 1}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // İstatistikler
          _buildStatsSection(),
          const SizedBox(height: 24),
          // Rozet koleksiyonu
          _buildBadgeCollection(),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    final stats = _userAchievements!.stats;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 İstatistiklerin',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem(
                Icons.shopping_bag,
                '${stats['orders'] ?? 0}',
                'Sipariş',
                Colors.blue,
              ),
              _buildStatItem(
                Icons.star,
                '${stats['reviews'] ?? 0}',
                'Değerlendirme',
                Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatItem(
                Icons.people,
                '${stats['followers'] ?? 0}',
                'Takipçi',
                Colors.purple,
              ),
              _buildStatItem(
                Icons.store,
                '${stats['distinct_shops'] ?? 0}',
                'Mağaza',
                Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeCollection() {
    final unlocked = _userAchievements!.unlockedAchievements;
    final total = _userAchievements!.achievements.length;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🏅 Rozet Koleksiyonu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${unlocked.length}/$total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mini rozetler
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _userAchievements!.achievements.map((a) {
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: a.isUnlocked
                      ? AchievementIcons.getColor(a.type).withOpacity(0.2)
                      : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AchievementIcons.getIcon(a.iconName),
                  size: 20,
                  color: a.isUnlocked
                      ? AchievementIcons.getColor(a.type)
                      : Colors.grey.shade400,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAchievementsState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementCard(Achievement achievement, {required bool isUnlocked}) {
    final color = AchievementIcons.getColor(achievement.type);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // İkon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isUnlocked ? color.withOpacity(0.2) : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              AchievementIcons.getIcon(achievement.iconName),
              size: 32,
              color: isUnlocked ? color : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 12),
          // Başlık
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              achievement.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isUnlocked ? Colors.black87 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          // Açıklama
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              achievement.description,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          // İlerleme
          if (!isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: achievement.progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              achievement.remainingText,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '+${achievement.xpReward} XP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}