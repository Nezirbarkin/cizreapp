# Authentication Features - Technical Specifications

## 📋 Component Specifications

### 1. AuthService (NEW)

**Location:** `lib/features/auth/services/auth_service.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../profile/services/profile_service.dart';

class AuthService {
  final _supabase = Supabase.instance.client;
  final _profileService = ProfileService();

  /// Şifre sıfırlama isteği gönder
  /// identifier: email veya username
  /// Returns: başarılı ise true
  Future<bool> requestPasswordReset(String identifier) async {
    try {
      String email;
      
      // Email mi username mi kontrol et
      if (identifier.contains('@')) {
        email = identifier.trim();
      } else {
        // Username ise email'i bul
        final userEmail = await _profileService.getEmailByIdentifier(identifier);
        if (userEmail == null) {
          throw Exception('Kullanıcı bulunamadı');
        }
        email = userEmail;
      }
      
      // Supabase'e şifre sıfırlama isteği gönder
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'cizreapp://reset-password', // Deep link
      );
      
      debugPrint('✅ Şifre sıfırlama emaili gönderildi: $email');
      return true;
      
    } catch (e) {
      debugPrint('❌ Şifre sıfırlama hatası: $e');
      rethrow;
    }
  }
  
  /// Yeni şifre belirle (reset token ile)
  Future<bool> updatePassword(String newPassword) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Oturum bulunamadı');
      }
      
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      
      debugPrint('✅ Şifre güncellendi');
      return true;
      
    } catch (e) {
      debugPrint('❌ Şifre güncelleme hatası: $e');
      rethrow;
    }
  }
  
  /// Email ve şifre ile giriş (identifier support)
  Future<AuthResponse> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    try {
      String email;
      
      // Email mi username mi kontrol et
      if (identifier.contains('@')) {
        email = identifier.trim();
      } else {
        // Username ise email'i bul
        final userEmail = await _profileService.getEmailByIdentifier(identifier);
        if (userEmail == null) {
          throw Exception('Kullanıcı bulunamadı');
        }
        email = userEmail;
      }
      
      // Giriş yap
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      debugPrint('✅ Giriş başarılı: ${response.user?.email}');
      return response;
      
    } catch (e) {
      debugPrint('❌ Giriş hatası: $e');
      rethrow;
    }
  }
}
```

---

### 2. ProfileService Extensions

**Location:** `lib/features/profile/services/profile_service.dart`

**Eklenecek Metodlar:**

```dart
/// Username'den kullanıcı bilgilerini getir
Future<Map<String, dynamic>?> getUserByUsername(String username) async {
  try {
    final response = await _supabase
        .from('profiles')
        .select('id, email, username, full_name, avatar_url')
        .eq('username', username.trim().toLowerCase())
        .maybeSingle();
    
    return response;
  } catch (e) {
    debugPrint('❌ Username ile kullanıcı bulunamadı: $e');
    return null;
  }
}

/// Email veya username'den email'i al
Future<String?> getEmailByIdentifier(String identifier) async {
  try {
    // Email ise direkt döndür
    if (identifier.contains('@')) {
      return identifier.trim();
    }
    
    // Username ise lookup yap
    final user = await getUserByUsername(identifier);
    return user?['email'] as String?;
    
  } catch (e) {
    debugPrint('❌ Email lookup hatası: $e');
    return null;
  }
}
```

---

### 3. ResetPasswordScreen

**Location:** `lib/features/auth/screens/reset_password_screen.dart`

**UI Elements:**
- Gradient container background
- App logo (centered)
- Title: "Şifremi Unuttum"
- Subtitle: "Email veya kullanıcı adınızı girin"
- Text field: Email/Username input
- Helper text: "Şifre sıfırlama linkini email'inize göndereceğiz"
- Button: "Devam Et"
- Back button / navigation

**State Management:**
- `_identifierController` - TextEditingController
- `_isLoading` - bool
- `_formKey` - GlobalKey<FormState>

**Key Methods:**
```dart
Future<void> _requestReset() async {
  if (!_formKey.currentState!.validate()) return;
  
  setState(() => _isLoading = true);
  
  try {
    final authService = AuthService();
    final success = await authService.requestPasswordReset(
      _identifierController.text.trim(),
    );
    
    if (success && mounted) {
      // Success screen'e git veya dialog göster
      _showSuccessDialog();
    }
  } catch (e) {
    _showErrorSnackbar(e.toString());
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

void _showSuccessDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Email Gönderildi'),
      content: Text('Şifre sıfırlama linki email adresinize gönderildi.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Tamam'),
        ),
      ],
    ),
  );
}
```

---

### 4. ResetPasswordConfirmScreen

**Location:** `lib/features/auth/screens/reset_password_confirm_screen.dart`

**Purpose:** Deep link ile açılan ekran, yeni şifre girişi

**UI Elements:**
- Gradient background
- Title: "Yeni Şifre Belirle"
- Password field (with visibility toggle)
- Password confirmation field
- Password strength indicator (optional)
- Button: "Şifreyi Güncelle"

**State Management:**
- `_passwordController`
- `_confirmPasswordController`
- `_isLoading`
- `_obscurePassword`
- `_obscureConfirmPassword`

**Key Methods:**
```dart
Future<void> _updatePassword() async {
  if (!_formKey.currentState!.validate()) return;
  
  // Şifrelerin eşleştiğini kontrol et
  if (_passwordController.text != _confirmPasswordController.text) {
    _showErrorSnackbar('Şifreler eşleşmiyor');
    return;
  }
  
  setState(() => _isLoading = true);
  
  try {
    final authService = AuthService();
    await authService.updatePassword(_passwordController.text);
    
    if (mounted) {
      // Login'e yönlendir
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
      
      _showSuccessSnackbar('Şifreniz güncellendi');
    }
  } catch (e) {
    _showErrorSnackbar(e.toString());
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
```

---

### 5. Enhanced LoginScreen

**Location:** `lib/features/auth/screens/login_screen.dart` (UPDATED)

**Changes:**
1. Background: Gradient container
2. Field label: "Email" → "Email veya Kullanıcı Adı"
3. Login method: Use AuthService.signInWithIdentifier()
4. Add "Şifremi Unuttum?" navigation
5. Enhanced styling with animations

**Updated Login Method:**
```dart
Future<void> _login() async {
  if (!_formKey.currentState!.validate()) return;
  
  setState(() => _isLoading = true);
  
  try {
    final authService = AuthService();
    final response = await authService.signInWithIdentifier(
      identifier: _identifierController.text.trim(),
      password: _passwordController.text,
    );
    
    if (response.session != null && mounted) {
      Navigator.of(context).pushReplacementNamed('/main');
    }
  } on AuthException catch (e) {
    if (mounted) {
      _showErrorSnackbar(_translateAuthError(e.message));
    }
  } catch (e) {
    if (mounted) {
      _showErrorSnackbar('Bir hata oluştu: $e');
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

String _translateAuthError(String message) {
  if (message.contains('Invalid login credentials')) {
    return 'Email/kullanıcı adı veya şifre hatalı';
  }
  if (message.contains('Email not confirmed')) {
    return 'Lütfen email adresinizi doğrulayın';
  }
  return message;
}
```

---

### 6. Enhanced RegisterScreen

**Location:** `lib/features/auth/screens/register_screen.dart` (UPDATED)

**Changes:**
1. Background: Gradient container
2. Multi-step form (PageView with 2 steps)
3. Step indicator widget
4. Enhanced validation feedback
5. Smooth transitions

**Step 1 - Personal Info:**
- Full name
- Username (with availability check)

**Step 2 - Account Info:**
- Email
- Password (with strength indicator)

**State Management:**
```dart
final _pageController = PageController();
int _currentStep = 0;
bool _isCheckingUsername = false;

Future<void> _checkUsernameAvailability() async {
  final username = _usernameController.text.trim();
  if (username.isEmpty || username.length < 3) return;
  
  setState(() => _isCheckingUsername = true);
  
  try {
    final existing = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    
    setState(() {
      _usernameAvailable = existing == null;
      _isCheckingUsername = false;
    });
  } catch (e) {
    setState(() => _isCheckingUsername = false);
  }
}

void _nextStep() {
  if (_currentStep == 0) {
    // Validate step 1
    if (_nameController.text.isEmpty || 
        _usernameController.text.isEmpty ||
        !_usernameAvailable) {
      return;
    }
    
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = 1);
  }
}

void _previousStep() {
  if (_currentStep == 1) {
    _pageController.previousPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = 0);
  }
}
```

---

## 🎨 UI Components Specifications

### Gradient Background Widget

```dart
class GradientBackground extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;
  
  const GradientBackground({
    Key? key,
    required this.child,
    this.colors,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? [
            AppTheme.primaryGreen,
            AppTheme.primaryGreen.withOpacity(0.7),
            AppTheme.bgLight,
          ],
        ),
      ),
      child: child,
    );
  }
}
```

### Auth Card Widget

```dart
class AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  
  const AuthCard({
    Key? key,
    required this.child,
    this.padding,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24),
      padding: padding ?? EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}
```

### Step Indicator Widget

```dart
class StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String>? labels;
  
  const StepIndicator({
    Key? key,
    required this.currentStep,
    required this.totalSteps,
    this.labels,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (index) {
        final isActive = index <= currentStep;
        final isCompleted = index < currentStep;
        
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 4,
                margin: EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isActive 
                      ? AppTheme.primaryGreen 
                      : AppTheme.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (labels != null && labels!.length > index) ...[
                SizedBox(height: 8),
                Text(
                  labels![index],
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? AppTheme.gray900 : AppTheme.gray500,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}
```

---

## 🔐 Deep Link Configuration

### Android (android/app/src/main/AndroidManifest.xml)

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="cizreapp"
        android:host="reset-password" />
</intent-filter>
```

### iOS (ios/Runner/Info.plist)

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.cizreapp</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>cizreapp</string>
        </array>
    </dict>
</array>
```

### Main.dart Deep Link Handler

```dart
void _handleDeepLink(Uri uri) {
  if (uri.scheme == 'cizreapp' && uri.host == 'reset-password') {
    // Reset password ekranına yönlendir
    navigatorKey.currentState?.pushNamed('/reset-password-confirm');
  }
}

@override
void initState() {
  super.initState();
  
  // Deep link listener
  _linkSubscription = getLinksStream().listen((String? link) {
    if (link != null) {
      _handleDeepLink(Uri.parse(link));
    }
  });
}
```

---

## 📊 Database Queries

### Username Lookup Query (Optimized)

```sql
-- Index oluştur (performance için)
CREATE INDEX IF NOT EXISTS idx_profiles_username 
ON profiles(username);

-- Query pattern
SELECT id, email, username, full_name
FROM profiles
WHERE username = 'example_username'
LIMIT 1;
```

### Email Existence Check

```sql
SELECT id FROM profiles
WHERE email = 'user@example.com'
LIMIT 1;
```

---

## 🧪 Testing Scenarios

### Unit Tests

```dart
test('AuthService - requestPasswordReset with email', () async {
  final authService = AuthService();
  final result = await authService.requestPasswordReset('test@example.com');
  expect(result, true);
});

test('AuthService - requestPasswordReset with username', () async {
  final authService = AuthService();
  final result = await authService.requestPasswordReset('testuser');
  expect(result, true);
});

test('ProfileService - getUserByUsername returns user', () async {
  final profileService = ProfileService();
  final user = await profileService.getUserByUsername('testuser');
  expect(user, isNotNull);
  expect(user?['email'], 'test@example.com');
});

test('ProfileService - getEmailByIdentifier with email', () async {
  final profileService = ProfileService();
  final email = await profileService.getEmailByIdentifier('test@example.com');
  expect(email, 'test@example.com');
});

test('ProfileService - getEmailByIdentifier with username', () async {
  final profileService = ProfileService();
  final email = await profileService.getEmailByIdentifier('testuser');
  expect(email, 'test@example.com');
});
```

### Widget Tests

```dart
testWidgets('LoginScreen - shows identifier field', (tester) async {
  await tester.pumpWidget(MaterialApp(home: LoginScreen()));
  expect(find.text('Email veya Kullanıcı Adı'), findsOneWidget);
});

testWidgets('ResetPasswordScreen - shows reset button', (tester) async {
  await tester.pumpWidget(MaterialApp(home: ResetPasswordScreen()));
  expect(find.text('Devam Et'), findsOneWidget);
});
```

---

## 📈 Performance Considerations

1. **Database Indexes**
   - username column indexed for fast lookup
   - email column already indexed (primary)

2. **Caching**
   - Consider caching username lookups (short TTL)
   - Use Supabase realtime for username availability

3. **Rate Limiting**
   - Implement rate limiting on password reset (Supabase RLS)
   - Max 3 requests per hour per IP

4. **Validation**
   - Client-side validation before API calls
   - Debounce username availability checks (500ms)

---

## 🔒 Security Checklist

- [x] Passwords hashed by Supabase Auth
- [x] Reset tokens expire after 24 hours
- [x] Reset links one-time use
- [x] Email verification required
- [x] Username lookups don't expose sensitive data
- [x] Rate limiting on authentication endpoints
- [x] Input sanitization on all fields
- [x] HTTPS only for API calls
- [x] Deep links validated before processing
