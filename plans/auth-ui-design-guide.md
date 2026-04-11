# Authentication UI/UX Design Guide

## 🎨 Visual Design System

### Color Palette

**Primary Colors**
- Primary Green: `#00C853`
- Secondary Green: `#00a844`
- Light Green: `#69F0AE` (for gradients)

**Gradient Combinations**
```
Login/Register Gradient:
- Start: #00C853 (top-left)
- Middle: #00a844 (center)
- End: #F5F7FA (bottom-right)
- Angle: 135deg (diagonal)

Button Gradient:
- Start: #00C853
- End: #00a844
- Angle: 90deg (vertical)
```

**Neutral Colors**
- White: `#FFFFFF`
- Background Light: `#F5F7FA`
- Gray 900: `#111827`
- Gray 600: `#4B5563`
- Gray 300: `#D1D5DB`

**Alert Colors**
- Success: `#10B981`
- Error: `#EF4444`
- Warning: `#FCD34D`
- Info: `#3B82F6`

---

## 📐 Layout Specifications

### Screen Dimensions
- Max content width: 400dp
- Min padding: 24dp
- Card max width: 360dp
- Button height: 56dp
- Input field height: 56dp

### Spacing System
- xs: 4dp
- sm: 8dp
- md: 16dp
- lg: 24dp
- xl: 32dp
- 2xl: 48dp

### Border Radius
- Small: 8dp (chips, tags)
- Medium: 12dp (inputs, buttons)
- Large: 20dp (cards)
- XLarge: 28dp (modals)

---

## 🖼️ Screen Layouts

### 1. LoginScreen Layout

```
┌────────────────────────────────────┐
│  [Gradient Background]             │
│                                    │
│  ┌──────────────────────────────┐ │
│  │                              │ │
│  │     [Logo - 80x80]           │ │
│  │                              │ │
│  └──────────────────────────────┘ │
│              (48dp gap)            │
│  ┌──────────────────────────────┐ │
│  │  Hoş Geldiniz!              │ │ <- Display Small (24sp, Bold)
│  │  Devam etmek için giriş     │ │ <- Body Large (16sp, Regular)
│  │  yapın                       │ │
│  └──────────────────────────────┘ │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Email veya Kullanıcı Adı    │ │ <- Text Field
│  │ [Input Field]                │ │
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Şifre                        │ │ <- Text Field
│  │ [Password Field] [Eye Icon]  │ │
│  └──────────────────────────────┘ │
│              (8dp gap)             │
│  [Şifremi Unuttum?] ────────────→ │ <- TextButton (right aligned)
│              (24dp gap)            │
│  ┌──────────────────────────────┐ │
│  │      GİRİŞ YAP              │ │ <- ElevatedButton (gradient)
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  ────────── veya ──────────       │ <- Divider with text
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │      HESAP OLUŞTUR          │ │ <- OutlinedButton
│  └──────────────────────────────┘ │
│                                    │
└────────────────────────────────────┘
```

### 2. RegisterScreen Layout - Step 1

```
┌────────────────────────────────────┐
│  [Gradient Background]             │
│                                    │
│  [← Geri]              [X Kapat]   │ <- AppBar alternative
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ ████──── 1/2 ────────       │ │ <- Step Indicator
│  └──────────────────────────────┘ │
│              (24dp gap)            │
│  ┌──────────────────────────────┐ │
│  │  Hesap Oluştur              │ │ <- Headline (20sp, Bold)
│  │  Bilgilerinizi girin         │ │ <- Body (14sp, Regular)
│  └──────────────────────────────┘ │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Ad Soyad                     │ │
│  │ [Input Field]                │ │
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Kullanıcı Adı               │ │
│  │ [Input Field] [✓ Available] │ │ <- Live validation
│  │ Daha sonra değiştirilemez   │ │ <- Helper text
│  └──────────────────────────────┘ │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │      DEVAM ET               │ │ <- Primary Button
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  Zaten üye misiniz? [Giriş Yap]  │ <- TextButton
│                                    │
└────────────────────────────────────┘
```

### 3. RegisterScreen Layout - Step 2

```
┌────────────────────────────────────┐
│  [Gradient Background]             │
│                                    │
│  [← Geri]              [X Kapat]   │
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ ████████── 2/2 ──            │ │ <- Step Indicator (filled)
│  └──────────────────────────────┘ │
│              (24dp gap)            │
│  ┌──────────────────────────────┐ │
│  │  İletişim Bilgileri          │ │
│  │  Son adım!                   │ │
│  └──────────────────────────────┘ │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ E-posta                      │ │
│  │ [Input Field]                │ │
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Şifre                        │ │
│  │ [Password Field] [Eye Icon]  │ │
│  │ ▓▓▓░░░░░ Orta                │ │ <- Strength indicator
│  └──────────────────────────────┘ │
│              (8dp gap)             │
│  • En az 6 karakter              │ <- Requirements list
│  • Bir büyük harf (önerilen)     │
│              (24dp gap)            │
│  ┌──────────────────────────────┐ │
│  │      HESAP OLUŞTUR          │ │ <- Primary Button
│  └──────────────────────────────┘ │
│                                    │
└────────────────────────────────────┘
```

### 4. ResetPasswordScreen Layout

```
┌────────────────────────────────────┐
│  [Gradient Background]             │
│                                    │
│  [← Geri]                          │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │  🔒                          │ │ <- Icon (48x48)
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │  Şifremi Unuttum            │ │ <- Headline (24sp, Bold)
│  │  Endişelenmeyin, yardımcı   │ │ <- Body (14sp)
│  │  oluyoruz!                   │ │
│  └──────────────────────────────┘ │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Email veya Kullanıcı Adı    │ │
│  │ [Input Field]                │ │
│  │ ℹ Şifre sıfırlama linkini   │ │ <- Info helper
│  │   email'inize göndereceğiz  │ │
│  └──────────────────────────────┘ │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │      DEVAM ET               │ │ <- Primary Button
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  [Giriş Sayfasına Dön]            │ <- TextButton
│                                    │
└────────────────────────────────────┘
```

### 5. ResetPasswordConfirmScreen Layout

```
┌────────────────────────────────────┐
│  [Gradient Background]             │
│                                    │
│  [X Kapat]                         │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │  🔑                          │ │ <- Icon (48x48)
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │  Yeni Şifre Belirle          │ │ <- Headline
│  │  Güçlü bir şifre seçin       │ │ <- Subtitle
│  └──────────────────────────────┘ │
│              (32dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Yeni Şifre                   │ │
│  │ [Password Field] [Eye Icon]  │ │
│  │ ▓▓▓▓▓░░░ Güçlü              │ │ <- Strength bar
│  └──────────────────────────────┘ │
│              (16dp gap)            │
│  ┌──────────────────────────────┐ │
│  │ Şifre Tekrar                 │ │
│  │ [Password Field] [Eye Icon]  │ │
│  │ ✓ Eşleşiyor                  │ │ <- Match indicator
│  └──────────────────────────────┘ │
│              (8dp gap)             │
│  Şifre Gereksinimleri:            │
│  ✓ En az 6 karakter              │
│  ✓ Bir büyük harf (önerilen)     │
│              (24dp gap)            │
│  ┌──────────────────────────────┐ │
│  │   ŞİFREYİ GÜNCELLE          │ │ <- Primary Button
│  └──────────────────────────────┘ │
│                                    │
└────────────────────────────────────┘
```

---

## 🎭 Component Specifications

### Input Fields

**Standard Text Field**
```
Height: 56dp
Border Radius: 12dp
Border Width: 1dp (normal), 2dp (focused)
Border Color: #D1D5DB (normal), #00C853 (focused), #EF4444 (error)
Background: #FFFFFF with 95% opacity
Padding: 16dp horizontal, 16dp vertical
Font Size: 16sp
Font Weight: 400 (Regular)
Icon Size: 24x24dp
Icon Padding: 12dp from edge
```

**Label Text**
```
Font Size: 14sp
Font Weight: 500 (Medium)
Color: #4B5563
Margin Bottom: 8dp
```

**Helper Text**
```
Font Size: 12sp
Font Weight: 400
Color: #6B7280 (info), #EF4444 (error), #10B981 (success)
Margin Top: 4dp
Icon: 16x16dp (optional)
```

**Error State**
```
Border: 2dp solid #EF4444
Icon: ⚠ (red)
Shake animation on error
Duration: 200ms
```

### Buttons

**Primary Button (Elevated)**
```
Height: 56dp
Border Radius: 12dp
Background: Gradient (#00C853 → #00a844)
Text Color: #FFFFFF
Font Size: 16sp
Font Weight: 600 (SemiBold)
Elevation: 4dp (normal), 8dp (pressed)
Ripple Color: White 20% opacity
Letter Spacing: 0.5sp

States:
- Normal: Full color
- Pressed: Scale 0.98, elevation 2dp
- Disabled: Gray, opacity 50%
- Loading: Spinner (white, 20x20dp)
```

**Secondary Button (Outlined)**
```
Height: 56dp
Border Radius: 12dp
Border: 2dp solid #00C853
Background: Transparent
Text Color: #00C853
Font Size: 16sp
Font Weight: 600

States:
- Hover: Background #00C853 10% opacity
- Pressed: Background #00C853 20% opacity
```

**Text Button**
```
Height: 44dp
Text Color: #00C853
Font Size: 14sp
Font Weight: 500
Underline: On hover
```

### Password Strength Indicator

```
Width: 100%
Height: 4dp
Border Radius: 2dp
Background: #E5E7EB

Levels:
- Weak: 25% filled, #EF4444 (red)
- Fair: 50% filled, #FCD34D (yellow)
- Good: 75% filled, #3B82F6 (blue)
- Strong: 100% filled, #10B981 (green)

Animation: Fill with transition, 300ms ease-in-out
```

### Step Indicator

```
Height: 4dp per step
Border Radius: 2dp
Gap: 8dp between steps

States:
- Inactive: #D1D5DB
- Active: #00C853
- Completed: #00C853

Label:
- Font Size: 12sp
- Font Weight: 600 (active), 400 (inactive)
- Color: #111827 (active), #6B7280 (inactive)
- Margin Top: 8dp
```

---

## ✨ Animations & Transitions

### Screen Transitions

**Page Route Animation**
```dart
PageRouteBuilder(
  transitionDuration: Duration(milliseconds: 300),
  pageBuilder: (context, animation, secondaryAnimation) => screen,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0.0, 0.1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      ),
    );
  },
)
```

### Focus Animation

```dart
AnimatedContainer(
  duration: Duration(milliseconds: 200),
  curve: Curves.easeInOut,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: isFocused ? AppTheme.primaryGreen : AppTheme.gray300,
      width: isFocused ? 2 : 1,
    ),
  ),
)
```

### Button Press Animation

```dart
GestureDetector(
  onTapDown: (_) => setState(() => _isPressed = true),
  onTapUp: (_) => setState(() => _isPressed = false),
  onTapCancel: () => setState(() => _isPressed = false),
  child: AnimatedScale(
    scale: _isPressed ? 0.98 : 1.0,
    duration: Duration(milliseconds: 100),
    curve: Curves.easeInOut,
    child: button,
  ),
)
```

### Loading Spinner

```dart
SizedBox(
  width: 20,
  height: 20,
  child: CircularProgressIndicator(
    strokeWidth: 2.5,
    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
  ),
)
```

### Success Checkmark Animation

```dart
TweenAnimationBuilder<double>(
  duration: Duration(milliseconds: 400),
  tween: Tween(begin: 0.0, end: 1.0),
  curve: Curves.elasticOut,
  builder: (context, value, child) {
    return Transform.scale(
      scale: value,
      child: Icon(
        Icons.check_circle,
        color: AppTheme.success,
        size: 48,
      ),
    );
  },
)
```

### Error Shake Animation

```dart
TweenAnimationBuilder<double>(
  duration: Duration(milliseconds: 400),
  tween: Tween(begin: 0.0, end: 1.0),
  builder: (context, value, child) {
    return Transform.translate(
      offset: Offset(
        sin(value * 3 * pi) * 10 * (1 - value),
        0,
      ),
      child: child,
    );
  },
  child: errorWidget,
)
```

---

## 🌐 Responsive Design

### Breakpoints

```
Mobile: < 600dp
Tablet: 600dp - 1024dp
Desktop: > 1024dp
```

### Layout Adjustments

**Mobile (< 600dp)**
- Single column layout
- Full width cards with 24dp margin
- Stack buttons vertically
- Hide decorative elements

**Tablet (600dp - 1024dp)**
- Center content, max width 480dp
- Side margins: 48dp
- Buttons side-by-side where appropriate
- Show decorative elements

**Desktop (> 1024dp)**
- Center content, max width 420dp
- Side panels with info/marketing
- Horizontal layout for some forms
- Rich animations and effects

---

## 🎯 Interaction States

### Input Field States

1. **Default**
   - Border: 1dp, #D1D5DB
   - Background: White 95%
   - Label: #4B5563

2. **Focused**
   - Border: 2dp, #00C853
   - Background: White 100%
   - Label: #00C853
   - Cursor: Blinking

3. **Filled (Valid)**
   - Border: 1dp, #D1D5DB
   - Icon: ✓ green (optional)

4. **Error**
   - Border: 2dp, #EF4444
   - Background: #FEE2E2 10%
   - Icon: ⚠ red
   - Helper text: Red
   - Shake animation

5. **Disabled**
   - Border: 1dp, #E5E7EB
   - Background: #F3F4F6
   - Text: #9CA3AF
   - Cursor: Not allowed

### Button States

1. **Normal**
   - Full color/border
   - Elevation: 4dp (elevated)

2. **Hover** (Desktop)
   - Slightly lighter background
   - Cursor: Pointer

3. **Pressed**
   - Scale: 0.98
   - Elevation: 2dp
   - Darker shade

4. **Loading**
   - Show spinner
   - Disable interaction
   - Semi-transparent text

5. **Disabled**
   - Gray background
   - 50% opacity
   - Cursor: Not allowed

---

## 📱 Platform-Specific Adjustments

### iOS
- Use Cupertino style for some elements
- Larger touch targets (44x44dp minimum)
- System font weights
- Bounce scroll physics

### Android
- Material Design ripple effects
- System navigation bar color
- Material elevation shadows
- Clamping scroll physics

### Web
- Keyboard navigation support
- Focus indicators
- Hover states
- Responsive breakpoints
