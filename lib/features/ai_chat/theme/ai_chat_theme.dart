import 'package:flutter/material.dart';

/// Modern AI Chat Tema - Gemini Tarzı
/// Koyu tema, mor/violet gradyanlar, modern tipografi
class AIChatTheme {
  AIChatTheme._();

  // =====================================================
  // ARKA PLAN RENKLERİ
  // =====================================================
  
  /// Ana arka plan gradient başlangıcı
  static const Color backgroundStart = Color(0xFF1A1A2E);
  
  /// Ana arka plan gradient bitişi
  static const Color backgroundEnd = Color(0xFF16213E);
  
  /// Gradient arka plan
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [backgroundStart, backgroundEnd],
  );

  // =====================================================
  // GRADYAN RENKLER
  // =====================================================
  
  /// Mor/violet gradient başlangıcı
  static const Color primaryGradientStart = Color(0xFF7B2CBF);
  
  /// Mor/violet gradient bitişi
  static const Color primaryGradientEnd = Color(0xFF9D4EDD);
  
  /// Ana gradient
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGradientStart, primaryGradientEnd],
  );
  
  /// Açık mor gradient (vurgular için)
  static const LinearGradient lightPurpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9D4EDD), Color(0xFFCB77FF)],
  );
  
  /// Mesaj gönder butonu gradient
  static const LinearGradient sendButtonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primaryGradientStart, primaryGradientEnd],
  );

  // =====================================================
  // KART RENKLERİ
  // =====================================================
  
  /// Ana kart arka planı (yarı saydam)
  static const Color cardBackground = Color(0xFF252542);
  
  /// Açık kart arka planı
  static const Color cardBackgroundLight = Color(0xFF2D2D4A);
  
  /// Kart hover efekti
  static const Color cardHover = Color(0xFF353555);
  
  /// Kart kenarlık rengi
  static const Color cardBorder = Color(0xFF3D3D5C);

  // =====================================================
  // METİN RENKLERİ
  // =====================================================
  
  /// Ana metin rengi (beyaz)
  static const Color textPrimary = Color(0xFFFFFFFF);
  
  /// İkincil metin rengi (açık gri)
  static const Color textSecondary = Color(0xFFB8B8D1);
  
  /// Soluk metin rengi
  static const Color textMuted = Color(0xFF6B6B8D);
  
  /// Link metin rengi
  static const Color textLink = Color(0xFF9D4EDD);

  // =====================================================
  // MESAJ BALONU RENKLERİ
  // =====================================================
  
  /// Kullanıcı mesajı arka planı
  static const Color userBubbleColor = Color(0xFF7B2CBF);
  
  /// Kullanıcı mesajı gradyanı
  static const LinearGradient userBubbleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGradientStart, Color(0xFF6B21A8)],
  );
  
  /// AI mesajı arka planı
  static const Color aiBubbleColor = Color(0xFF2D2D4A);
  
  /// AI mesajı kenarlık rengi
  static const Color aiBubbleBorder = Color(0xFF3D3D5C);

  // =====================================================
  // ÖZEL DURUM RENKLERİ
  // =====================================================
  
  static const Color success = Color(0xFF4ADE80);
  static const Color successDark = Color(0xFF22C55E);
  static const Color error = Color(0xFFF87171);
  static const Color errorDark = Color(0xFFEF4444);
  static const Color warning = Color(0xFFFBBF24);
  static const Color warningDark = Color(0xFFF59E0B);
  static const Color info = Color(0xFF60A5FA);
  static const Color infoDark = Color(0xFF3B82F6);

  // =====================================================
  // BORDER RADIUS
  // =====================================================
  
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;
  static const double radiusRound = 24.0;
  static const double radiusCircle = 100.0;

  // =====================================================
  // PADDING & MARGIN
  // =====================================================
  
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 12.0;
  static const double paddingL = 16.0;
  static const double paddingXL = 24.0;
  static const double paddingXXL = 32.0;

  // =====================================================
  // BOYUTLAR
  // =====================================================
  
  /// Mesaj balonu maksimum genişlik
  static const double messageMaxWidth = 320.0;
  
  /// Prompt kartı genişliği
  static const double promptCardWidth = 140.0;
  
  /// Prompt kartı yüksekliği
  static const double promptCardHeight = 120.0;
  
  /// Prompt görsel yüksekliği
  static const double promptImageHeight = 70.0;
  
  /// Avatar boyutu (AI)
  static const double aiAvatarSize = 36.0;
  
  /// Kullanıcı avatar boyutu
  static const double userAvatarSize = 32.0;
  
  /// İkon boyutu
  static const double iconSizeSmall = 18.0;
  static const double iconSizeMedium = 24.0;
  static const double iconSizeLarge = 32.0;

  // =====================================================
  // GÖLGE
  // =====================================================
  
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.2),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
  
  static List<BoxShadow> messageShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.15),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
  
  static List<BoxShadow> glowShadow(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.4),
      blurRadius: 12,
      spreadRadius: 2,
    ),
  ];

  // =====================================================
  // ANİMASYON SÜRELERİ
  // =====================================================
  
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
  static const Duration typingAnimation = Duration(milliseconds: 800);

  // =====================================================
  // YAZI TİPLERİ
  // =====================================================
  
  static const String fontFamily = 'Roboto';
  
  static TextStyle get headlineLarge => const TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    letterSpacing: -0.5,
  );
  
  static TextStyle get headlineMedium => const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  
  static TextStyle get titleLarge => const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  
  static TextStyle get titleMedium => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );
  
  static TextStyle get bodyLarge => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );
  
  static TextStyle get bodyMedium => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: textSecondary,
  );
  
  static TextStyle get bodySmall => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: textMuted,
  );
  
  static TextStyle get labelMedium => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    letterSpacing: 0.5,
  );

  // =====================================================
  // DEKORASYONLAR
  // =====================================================
  
  /// Kart dekorasyonu
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: cardBackground.withOpacity(0.8),
    borderRadius: BorderRadius.circular(radiusXLarge),
    border: Border.all(color: cardBorder.withOpacity(0.3), width: 1),
    boxShadow: cardShadow,
  );
  
  /// Hoşgeldin kartı dekorasyonu
  static BoxDecoration get welcomeCardDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        cardBackground.withOpacity(0.9),
        cardBackgroundLight.withOpacity(0.7),
      ],
    ),
    borderRadius: BorderRadius.circular(radiusXLarge),
    border: Border.all(color: primaryGradientStart.withOpacity(0.3), width: 1),
  );
  
  /// Kullanıcı mesaj balonu dekorasyonu
  static BoxDecoration get userBubbleDecoration => BoxDecoration(
    gradient: userBubbleGradient,
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(radiusLarge),
      topRight: Radius.circular(radiusLarge),
      bottomLeft: Radius.circular(radiusLarge),
      bottomRight: Radius.circular(radiusSmall),
    ),
    boxShadow: messageShadow,
  );
  
  /// AI mesaj balonu dekorasyonu
  static BoxDecoration get aiBubbleDecoration => BoxDecoration(
    color: aiBubbleColor,
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(radiusSmall),
      topRight: Radius.circular(radiusLarge),
      bottomLeft: Radius.circular(radiusLarge),
      bottomRight: Radius.circular(radiusLarge),
    ),
    border: Border.all(color: aiBubbleBorder, width: 1),
  );
  
  /// Prompt kartı dekorasyonu (görsel varsa)
  static BoxDecoration promptCardDecorationWithImage(String imageUrl) => BoxDecoration(
    color: cardBackground,
    borderRadius: BorderRadius.circular(radiusLarge),
    border: Border.all(color: cardBorder, width: 1),
    boxShadow: cardShadow,
    image: imageUrl.isNotEmpty
      ? DecorationImage(
          image: NetworkImage(imageUrl),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.4),
            BlendMode.darken,
          ),
        )
      : null,
  );
  
  /// Prompt kartı dekorasyonu (görsel yoksa, renkli)
  static BoxDecoration promptCardDecorationWithColor(Color color) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        color,
        color.withOpacity(0.7),
      ],
    ),
    borderRadius: BorderRadius.circular(radiusLarge),
    boxShadow: glowShadow(color),
  );
  
  /// Mesaj giriş alanı dekorasyonu
  static BoxDecoration get inputDecoration => BoxDecoration(
    color: cardBackground,
    borderRadius: BorderRadius.circular(radiusRound),
    border: Border.all(color: cardBorder, width: 1),
  );
  
  /// Gönder butonu dekorasyonu
  static BoxDecoration get sendButtonDecoration => BoxDecoration(
    gradient: sendButtonGradient,
    borderRadius: BorderRadius.circular(radiusMedium),
    boxShadow: glowShadow(primaryGradientStart),
  );

  // =====================================================
  // THEME DATA
  // =====================================================
  
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundStart,
    primaryColor: primaryGradientStart,
    colorScheme: const ColorScheme.dark(
      primary: primaryGradientStart,
      secondary: primaryGradientEnd,
      surface: cardBackground,
      error: error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: textPrimary),
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusRound),
        borderSide: const BorderSide(color: cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusRound),
        borderSide: const BorderSide(color: cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusRound),
        borderSide: const BorderSide(color: primaryGradientStart, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: const TextStyle(color: textMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGradientStart,
        foregroundColor: textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryGradientEnd,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cardBackground,
      contentTextStyle: const TextStyle(color: textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// =====================================================
// KATEGORİ RENKLERİ
// =====================================================

class AICategoryColors {
  AICategoryColors._();
  
  static const Map<String, Color> categoryColors = {
    'general': Color(0xFF7B2CBF),
    'shopping': Color(0xFF3B82F6),
    'food': Color(0xFFF97316),
    'creative': Color(0xFFEC4899),
    'productivity': Color(0xFF22C55E),
    'social': Color(0xFF8B5CF6),
    'travel': Color(0xFF06B6D4),
  };
  
  static Color getColorForCategory(String category) {
    return categoryColors[category] ?? const Color(0xFF7B2CBF);
  }
  
  static List<Color> gradientForCategory(String category) {
    final baseColor = getColorForCategory(category);
    return [
      baseColor,
      baseColor.withOpacity(0.7),
    ];
  }
}
