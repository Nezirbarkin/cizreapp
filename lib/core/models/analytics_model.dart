/// Analytics ve İstatistik Modelleri
class MonthlyViewStats {
  final String month; // YYYY-MM formatında
  final int viewCount;
  final int uniqueViewers;

  MonthlyViewStats({
    required this.month,
    required this.viewCount,
    required this.uniqueViewers,
  });

  factory MonthlyViewStats.fromJson(Map<String, dynamic> json) {
    return MonthlyViewStats(
      month: json['month'] as String,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      uniqueViewers: (json['unique_viewers'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'month': month,
    'view_count': viewCount,
    'unique_viewers': uniqueViewers,
  };

  @override
  String toString() => 'MonthlyViewStats($month: $viewCount görüntüleme, $uniqueViewers benzersiz)';
}

/// Ayın görüntüleme özeti (şu an için)
class CurrentMonthViewStats {
  final int totalViews;
  final int uniqueViewers;

  CurrentMonthViewStats({
    required this.totalViews,
    required this.uniqueViewers,
  });

  factory CurrentMonthViewStats.fromJson(Map<String, dynamic> json) {
    return CurrentMonthViewStats(
      totalViews: (json['total_views'] as num?)?.toInt() ?? 0,
      uniqueViewers: (json['unique_viewers'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'total_views': totalViews,
    'unique_viewers': uniqueViewers,
  };

  @override
  String toString() => 'CurrentMonthViewStats($totalViews görüntüleme, $uniqueViewers benzersiz)';
}

/// Post görüntüleme istatistikleri (aylık)
class MonthlyPostViewStats extends MonthlyViewStats {
  final int postCount;

  MonthlyPostViewStats({
    required super.month,
    required super.viewCount,
    required super.uniqueViewers,
    required this.postCount,
  });

  factory MonthlyPostViewStats.fromJson(Map<String, dynamic> json) {
    return MonthlyPostViewStats(
      month: json['month'] as String,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      uniqueViewers: (json['unique_viewers'] as num?)?.toInt() ?? 0,
      postCount: (json['post_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'post_count': postCount,
  };

  @override
  String toString() => 'MonthlyPostViewStats($month: $viewCount görüntüleme, $uniqueViewers benzersiz, $postCount post)';
}

/// Analytics Özeti
class AnalyticsSummary {
  final String title; // "Profil Ziyaretleri" vs "Post Görüntülemeleri"
  final int currentMonthViews;
  final int currentMonthUniqueViewers;
  final List<MonthlyViewStats> monthlyHistory;
  final double averageViewsPerMonth;
  final int totalViews;

  AnalyticsSummary({
    required this.title,
    required this.currentMonthViews,
    required this.currentMonthUniqueViewers,
    required this.monthlyHistory,
    required this.averageViewsPerMonth,
    required this.totalViews,
  });

  /// Ay-ay karşılaştırma (yüzde olarak değişim)
  double getMonthlyGrowthPercentage() {
    if (monthlyHistory.length < 2) return 0;
    
    final currentMonth = monthlyHistory[0].viewCount;
    final previousMonth = monthlyHistory[1].viewCount;
    
    if (previousMonth == 0) return currentMonth > 0 ? 100 : 0;
    
    return ((currentMonth - previousMonth) / previousMonth * 100);
  }

  /// En çok görüntülenen ay
  MonthlyViewStats? getTopMonth() {
    if (monthlyHistory.isEmpty) return null;
    
    MonthlyViewStats top = monthlyHistory[0];
    for (final stat in monthlyHistory) {
      if (stat.viewCount > top.viewCount) {
        top = stat;
      }
    }
    return top;
  }

  @override
  String toString() => 'AnalyticsSummary($title: $currentMonthViews bu ay, ortalama $averageViewsPerMonth/ay)';
}
