# CizreApp Authentication Features - Comprehensive Plan

## 📋 Overview
Üç temel feature'ı koordineli şekilde implementasyon yapacağız:
1. **Şifre Sıfırlama** - Email/Username ile
2. **Username ile Giriş** - Email/Username hybrid login
3. **Modern UI/UX** - Gradient, animations, improved design

---

## 1️⃣ ŞIFRE SIFIRLA (Password Reset) Feature

### Technical Architecture

**A. Database Layer**
- Supabase Auth'un built-in password reset flow'unu kullanacağız
- Trigger: `auth.resetPasswordForEmail(email: String)`
- Supabase otomatik olarak reset token ve email gönderir

**B. Service Layer - AuthService.dart (NEW)**
```
Metodlar:
├── requestPasswordReset(identifier: String) -> Future<bool>
│   ├── Input: email veya username
│   ├── Logic: Username ise email'e çevir, email'e reset linki gönder
│   └── Output: Success/error mesajı
│
└── resetPassword(newPassword: String) -> Future<bool>
    ├── Input: Yeni şifre
    ├── Logic: Deep link'ten gelen token ile şifre güncelle
    └── Output: Success/error
```

**C. UI Flow**
```
LoginScreen
    ↓
[Şifremi Unuttum?] → ResetPasswordScreen (NEW)
    ├─ Step 1: Email/Username Gir → Validate
    ├─ Step 2: Onay Mesajı Göster
    ├─ Step 3: Email'deki Link → ResetPasswordConfirmScreen (NEW)
    └─ Step 4: Yeni Şifre Gir → Login'e Dön
```

**D. Screens**
1. **ResetPasswordScreen** - Email/Username input + validation
2. **ResetPasswordConfirmScreen** - Reset token ile yeni şifre girişi
3. **ResetPasswordSuccessScreen** - Başarı mesajı

### Implementation Details

**ProfileService.dart - Username to Email Lookup**
```dart
Future<String?> getEmailByUsername(String username) async
  - profiles'den email çek
  - Not found: throw exception
```

**AuthService.dart - New Methods**
```dart
// Şifre sıfırlama linki talep et
Future<bool> requestPasswordReset(String identifier) async
  - if identifier contains '@' → email
  - else → username'den email al → resetPasswordForEmail(email)
  - Error handling + notifications

// Deep link handler
Future<bool> handleResetPasswordLink(String token, String newPassword) async
  - Supabase session'dan token al
  - updateUser() ile password güncelle
```

---

## 2️⃣ USERNAME İLE GİRİŞ (Username Login) Feature

### Technical Architecture

**A. Database Layer**
- profiles table'da username unique constraint var ✓
- Email lookup için optimized query ekle

**B. Service Layer - ProfileService Genişlet**
```
Yeni Metodlar:
├── getUserByUsername(username: String) -> Future<Map?>
│   ├── profiles.select('email').eq('username', username)
│   └── Return: {email, username, id} or null
│
└── getUserIdByIdentifier(identifier: String) -> Future<String?>
    ├── Input: email veya username
    ├── Logic: Email ise direkt, username ise lookup
    └── Output: user_id veya null
```

**C. Login Flow Upgrade**
```
LoginScreen (Redesigned)
    ├─ Input: "Email veya Kullanıcı Adı" (single field)
    ├─ Logic:
    │  ├─ Contains '@' → Email
    │  ├─ Else → Username lookup
    │  └─ Found → signin with email
    └─ Password → signInWithPassword()
```

**D. Validation**
- Email regex: `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`
- Username regex: `^[a-zA-Z0-9_]{3,20}$` (existing pattern)

### Implementation Details

**ProfileService Extension**
```dart
Future<Map<String, dynamic>?> getUserByUsername(String username) async
  - trim() + lowercase
  - profiles.select('id, email, username, full_name')
         .eq('username', username)
         .maybeSingle()
  - Handle null case

Future<String?> getEmailByIdentifier(String identifier) async
  - if '@' in identifier → identifier (is email)
  - else → await getUserByUsername() → extract email
  - Error handling
```

**LoginScreen Logic**
```dart
Future<void> _loginWithIdentifier() async
  - identifier = email/username field value
  - if identifier contains '@'
      → email = identifier
    else
      → email = await _getEmailByUsername(identifier)
  
  - await Supabase.auth.signInWithPassword(
      email: email,
      password: password
    )
  - Handle auth errors (user_not_found, invalid_credentials)
```

---

## 3️⃣ MODERN UI/UX DESIGN (Enhanced Screens)

### Design System Upgrades

**A. Visual Improvements**
1. **Gradient Background** - Material Design 3 uyumlu
   - Green theme: primaryGreen (#00C853) → lighter shade gradient
   - Blue theme: primaryBlue (#007AFF) → lighter shade gradient
   
2. **Card-Based Layout**
   - Input fields: Frosted glass effect (backdrop filter)
   - Buttons: Material Design 3 + shadows
   - Rounded corners: 16dp consistency

3. **Micro-Interactions**
   - Text field focus animation
   - Button scale animation on press
   - Success/error slide animations
   - Loading spinner smooth rotation

**B. LoginScreen Redesign**
```
┌─────────────────────────┐
│  [Gradient BG]          │
│  ┌─────────────────────┐│
│  │  CizreApp Logo      ││
│  └─────────────────────┘│
│                         │
│  ┌─────────────────────┐│
│  │ Hoş Geldiniz!       ││
│  │ Devam etmek için    ││
│  │ giriş yapın         ││
│  └─────────────────────┘│
│                         │
│  [Email/Username Field] │
│  [Password Field]       │
│  [Forgot Password Link] │
│                         │
│  [Sign In Button]       │
│  [Social Login Prep]    │
│                         │
│  [Sign Up Link]         │
└─────────────────────────┘
```

**C. RegisterScreen Redesign**
```
┌─────────────────────────┐
│  [Gradient BG]          │
│  ┌─────────────────────┐│
│  │ Step 1/2            ││
│  │ Hesap Oluştur       ││
│  └─────────────────────┘│
│                         │
│  [Full Name Field]      │
│  [Username Field]       │
│  [Info Icon - readonly] │
│                         │
│  [Next Button]          │
│  [Back Link]            │
└─────────────────────────┘

THEN:

┌─────────────────────────┐
│  [Gradient BG]          │
│  ┌─────────────────────┐│
│  │ Step 2/2            ││
│  │ İletişim Bilgileri  ││
│  └─────────────────────┘│
│                         │
│  [Email Field]          │
│  [Password Field]       │
│  [Password Requirements]│
│                         │
│  [Sign Up Button]       │
│  [Back Button]          │
└─────────────────────────┘
```

**D. ResetPasswordScreen Redesign**
```
┌─────────────────────────┐
│  [Gradient BG]          │
│  ┌─────────────────────┐│
│  │ Şifremi Unuttum     ││
│  │ Endişelenmeyin!     ││
│  │ Yeni şifre belirle. ││
│  └─────────────────────┘│
│                         │
│  Email/Username alan    │
│  [Identifier Field]     │
│  [Help Text]            │
│                         │
│  [Devam Et Button]      │
│  [Geri Button]          │
└─────────────────────────┘
```

---

## 🔄 INTEGRATION FLOW

### Cross-Feature Dependencies

```
┌─────────────────────────────────────────────┐
│ ProfileService Enhancements                 │
├─────────────────────────────────────────────┤
│ • getUserByUsername()                       │
│ • getEmailByIdentifier()                    │
│ • searchUsersForRecovery()                  │
└──────────────────────┬──────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   ┌─────────┐  ┌────────────┐  ┌────────────┐
   │ Login   │  │ Password   │  │ Register   │
   │ Screen  │  │ Reset Flow │  │ Screen     │
   └─────────┘  └────────────┘  └────────────┘
        │              │              │
        └──────────────┼──────────────┘
                       ▼
           ┌───────────────────────┐
           │ Modern UI Components  │
           │ • Gradients           │
           │ • Animations          │
           │ • Form Validation     │
           └───────────────────────┘
```

### Data Flow

**Login with Username**
```
Username Input
    ↓
ProfileService.getEmailByIdentifier()
    ↓
ProfileService.getUserByUsername() [if username]
    ↓
Extract email
    ↓
Supabase.auth.signInWithPassword(email, password)
    ↓
Navigate to /main
```

**Password Reset**
```
Identifier (email/username) Input
    ↓
AuthService.requestPasswordReset()
    ↓
ProfileService.getEmailByIdentifier() [if username]
    ↓
Supabase.auth.resetPasswordForEmail(email)
    ↓
User checks email
    ↓
Click deep link → ResetPasswordConfirmScreen
    ↓
Enter new password
    ↓
AuthService.resetPassword(newPassword)
    ↓
Redirect to Login
```

---

## 📁 FILE STRUCTURE

**New Files to Create:**
```
lib/features/auth/
├── screens/
│   ├── reset_password_screen.dart (NEW)
│   ├── reset_password_confirm_screen.dart (NEW)
│   └── reset_password_success_screen.dart (NEW)
│
└── services/
    └── auth_service.dart (NEW)
```

**Modified Files:**
```
lib/features/profile/services/profile_service.dart
  + getUserByUsername()
  + getEmailByIdentifier()

lib/features/auth/screens/login_screen.dart
  + Enhanced UI with gradient
  + Username/Email combo field
  + Enhanced password field
  + Modern styling

lib/features/auth/screens/register_screen.dart
  + Enhanced UI with gradient
  + Step-based form (2-step)
  + Modern styling
  + Smooth transitions
```

---

## ✅ VALIDATION & ERROR HANDLING

### Input Validation

**Email/Username Field**
- Min length: 3
- Max length: 50
- Pattern: email OR username regex
- Live validation feedback
- Error states with icons

**Password Field (Reset)**
- Min length: 6
- Complexity check: (Optional) uppercase + number
- Password strength indicator
- Match confirmation field

### Error Scenarios

| Scenario | Handling |
|----------|----------|
| User not found | "Email veya kullanıcı adı bulunamadı" |
| Multiple matches | Won't happen (username unique) |
| Invalid token | "Şifre sıfırlama süresi doldu. Tekrar deneyin." |
| Network error | "Bağlantı hatası. Tekrar deneyin." |
| Auth error | Display Supabase error message (TR) |

---

## 🎨 DESIGN TOKENS

### Colors (Existing AppTheme + Enhancements)
- Primary: `#00C853` (primaryGreen)
- Gradient Start: `#00C853`
- Gradient End: `#00a844` or lighter variant
- Background: `#F5F7FA` (bgLight)
- Input BG: `#FFFFFF` with transparency
- Text Primary: `#111827` (gray900)
- Text Secondary: `#4B5563` (gray600)

### Typography
- Headlines: Inter, weight 700, size 24-28
- Body: Inter, weight 400, size 14-16
- Labels: Inter, weight 600, size 12
- Captions: Inter, weight 400, size 12

### Spacing
- Padding: 16px, 24px, 32px
- Gap between elements: 16px
- Corner radius: 12-16px
- Button height: 48-56px

### Animations
- Duration: 200-400ms
- Curve: easeInOut, bounceOut
- Scale: 0.95 → 1.0 on press
- Opacity: 0 → 1 on load

---

## 📅 IMPLEMENTATION ORDER

### Phase 1 - Backend Services
- [ ] Create AuthService.dart (password reset methods)
- [ ] Enhance ProfileService (username lookup)
- [ ] Test database methods

### Phase 2 - Reset Password Flow
- [ ] Implement ResetPasswordScreen
- [ ] Implement ResetPasswordConfirmScreen
- [ ] Integration with AuthService
- [ ] Deep link handling

### Phase 3 - Username Login
- [ ] Enhance LoginScreen with username support
- [ ] Update login logic
- [ ] Form validation

### Phase 4 - Modern UI Design
- [ ] Add gradient backgrounds
- [ ] Implement animations
- [ ] Component refinement
- [ ] Cross-screen consistency

### Phase 5 - Polish & Testing
- [ ] Form validation improvements
- [ ] Error message refinement
- [ ] Loading states
- [ ] Full testing suite
