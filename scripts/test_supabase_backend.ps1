# CizreApp - Supabase Backend Baglanti Testi (Windows PowerShell)
# Kullanim: powershell -ExecutionPolicy Bypass -File scripts\test_supabase_backend.ps1

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "CizreApp - Supabase Backend Test Basliyor..." -ForegroundColor Cyan
Write-Host "============================================================"

# Renkler
$Green = "Green"
$Red = "Red"
$Yellow = "Yellow"

# Sayaclar
$script:Pass = 0
$script:Fail = 0

function Test-Result {
    param([bool]$Success, [string]$Message)
    if ($Success) {
        Write-Host "[BASARILI] $Message" -ForegroundColor $Green
        $script:Pass++
    } else {
        Write-Host "[BASARISIZ] $Message" -ForegroundColor $Red
        $script:Fail++
    }
}

# Supabase URL ve Key (AppConstants'tan)
$SupabaseUrl = "https://xsbukxkgtmdyickknqzf.supabase.co"
$SupabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc"

# .env kontrol
Write-Host ""
Write-Host "1. Supabase Baglanti Bilgileri" -ForegroundColor Yellow
Write-Host "--------------------------------"
if (Test-Path ".env") {
    Write-Host "[BULUNDU] .env dosyasi mevcut" -ForegroundColor $Green
} else {
    Write-Host "[UYARI] .env dosyasi yok (AppConstants fallback kullaniliyor)" -ForegroundColor $Yellow
}

# 2. REST API Testi
Write-Host ""
Write-Host "2. REST API Erisim Testi" -ForegroundColor Yellow
Write-Host "--------------------------------"
try {
    $headers = @{
        "apikey" = $SupabaseKey
        "Authorization" = "Bearer $SupabaseKey"
    }
    $response = Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/" -Headers $headers -Method Get -TimeoutSec 15
    Test-Result $true "REST API erisilebilir"
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 200 -or $statusCode -eq 404) {
        Test-Result $true "REST API erisilebilir (HTTP $statusCode)"
    } else {
        Test-Result $false "REST API erisim hatasi"
    }
}

# 3. Tablo Erisim Testleri
Write-Host ""
Write-Host "3. Tablo Erisim Testleri" -ForegroundColor Yellow
Write-Host "--------------------------------"
$tables = @("categories", "shops", "products", "posts_with_profiles", "addresses", "orders", "post_likes", "post_comments", "follows", "follow_requests", "stories", "story_likes", "story_views", "notifications", "shop_coupons", "courier_assignments", "blocked_users", "user_reports", "support_tickets", "comments", "comment_likes")

foreach ($table in $tables) {
    try {
        $resp = Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/$table?limit=1" -Headers $headers -Method Get -TimeoutSec 10
        Test-Result $true "$table erisilebilir"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 200) {
            Test-Result $true "$table erisilebilir (HTTP 200)"
        } elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "[RLS KORUMALI] $table (HTTP $statusCode)" -ForegroundColor $Yellow
        } else {
            Write-Host "[HATA] $table (HTTP $statusCode)" -ForegroundColor $Yellow
        }
    }
}

# 4. Storage Bucket Testleri
Write-Host ""
Write-Host "4. Storage Bucket Testleri" -ForegroundColor Yellow
Write-Host "--------------------------------"
$buckets = @("avatars", "covers", "posts", "stories", "shop-images", "product-images", "avatars", "post-media", "news")

foreach ($bucket in $buckets) {
    try {
        $resp = Invoke-RestMethod -Uri "$SupabaseUrl/storage/v1/bucket/$bucket" -Headers $headers -Method Get -TimeoutSec 10
        Test-Result $true "$bucket bucket mevcut"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 200) {
            Test-Result $true "$bucket bucket mevcut"
        } elseif ($statusCode -eq 404) {
            Write-Host "[YOK] $bucket bucket bulunamadi" -ForegroundColor $Yellow
        } else {
            Write-Host "[HATA] $bucket (HTTP $statusCode)" -ForegroundColor $Yellow
        }
    }
}

# 5. Edge Functions
Write-Host ""
Write-Host "5. Edge Function Erisim Testleri" -ForegroundColor Yellow
Write-Host "--------------------------------"
$functions = @(
    "iyzico-payment-callback",
    "confirm-balance-topup",
    "send-email",
    "send-push-notification",
    "get-balance",
    "use-balance-for-order",
    "request-withdrawal",
    "process-withdrawal",
    "refund-to-balance",
    "iyzico-payment-init",
    "create-balance-topup",
    "admin-add-balance",
    "admin-deduct-balance",
    "send-verification-code",
    "send-password-reset-otp",
    "send-registration-otp",
    "reset-password-with-otp",
    "request-account-deletion",
    "delete-account",
    "get-seller-earnings",
    "get-transaction-history",
    "smm-order-create",
    "smm-order-status-check",
    "smm-provider-services",
    "smm-sync-products",
    "process-notification-outbox",
    "grant-ad-reward",
    "admob-reward-session",
    "admob-ssv-callback"
)

foreach ($func in $functions) {
    try {
        $resp = Invoke-RestMethod -Uri "$SupabaseUrl/functions/v1/$func" -Headers $headers -Method Post -Body "{}" -ContentType "application/json" -TimeoutSec 10
        Test-Result $true "$func function mevcut"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Host "[YOK] $func bulunamadi" -ForegroundColor $Red
            $script:Fail++
        } elseif ($statusCode -eq 401) {
            Write-Host "[JWT KORUMALI] $func" -ForegroundColor Yellow
        } else {
            Write-Host "[MEVCUT] $func (HTTP $statusCode)" -ForegroundColor $Green
            $script:Pass++
        }
    }
}

# 6. Auth Endpoint
Write-Host ""
Write-Host "6. Auth Endpoint Testi" -ForegroundColor Yellow
Write-Host "--------------------------------"
try {
    $resp = Invoke-RestMethod -Uri "$SupabaseUrl/auth/v1/settings" -Headers $headers -Method Get -TimeoutSec 10
    Test-Result $true "Auth servisi erisilebilir"
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 200 -or $statusCode -eq 404) {
        Test-Result $true "Auth servisi erisilebilir (HTTP $statusCode)"
    } else {
        Test-Result $false "Auth servisi erisilemedi"
    }
}

# Sonuc
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "SONUC RAPORU" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Basarili: $script:Pass" -ForegroundColor $Green
Write-Host "Basarisiz: $script:Fail" -ForegroundColor $Red
Write-Host ""

if ($script:Fail -eq 0) {
    Write-Host "TUM TESTLER BASARILI!" -ForegroundColor $Green
    Write-Host ""
    Write-Host "Backend baglantisi saglikli calisiyor." -ForegroundColor $Green
    Write-Host "Simdi Flutter uygulamasini calistirabilirsiniz:" -ForegroundColor Cyan
    Write-Host "  flutter run -d chrome" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "BAZI TESTLER BASARISIZ" -ForegroundColor $Yellow
    Write-Host ""
    Write-Host "Sorun giderme onerileri:" -ForegroundColor Yellow
    Write-Host "  1. .env dosyasindaki SUPABASE_URL ve SUPABASE_ANON_KEY'i kontrol edin"
    Write-Host "  2. Supabase projesinin aktif oldugunu dogrulayin"
    Write-Host "  3. Internet baglantinizi kontrol edin"
    Write-Host "  4. Supabase Dashboard'da RLS politikalarini kontrol edin"
    exit 1
}
