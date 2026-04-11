import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide constants
class AppConstants {
  // App Info
  static const String appName = 'CizreApp';
  static const String appVersion = '1.0.0';
  
  // Supabase Config - Web için doğrudan değerler
  static String get supabaseUrl {
    if (kIsWeb) return 'https://xsbukxkgtmdyickknqzf.supabase.co';
    return dotenv.env['SUPABASE_URL'] ?? 'https://xsbukxkgtmdyickknqzf.supabase.co';
  }
  
  static String get supabaseAnonKey {
    if (kIsWeb) return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';
    return dotenv.env['SUPABASE_ANON_KEY'] ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';
  }
  
  // API Endpoints
  static String get baseApiUrl {
    if (kIsWeb) return 'https://www.cizreapp.com/api';
    return dotenv.env['BASE_API_URL'] ?? 'https://www.cizreapp.com/api';
  }
  
  // Pagination
  static const int defaultPageSize = 20;
  static const int storiesExpireHours = 24;
  
  // Cart & Orders
  static const double defaultDeliveryFee = 15.0;
  static const double freeDeliveryThreshold = 100.0;
  static const double defaultCommissionRate = 10.0;
  
  // Image Sizes
  static const int maxImageUploadSizeMB = 5;
  static const int thumbnailSize = 300;
  static const int fullImageSize = 1080;
  
  // Social Media
  static const int maxPostImages = 10;
  static const int maxStoryDurationSeconds = 15;
  
  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration cacheExpiration = Duration(hours: 1);
}
