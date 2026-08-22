# CizreApp - admob Functions Deploy Sonrasi Test
# admob-reward-session ve admob-ssv-callback deploy basarili mi kontrol eder

$SupabaseUrl = "https://xsbukxkgtmdyickknqzf.supabase.co"
$SupabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc"

$headers = @{
    "apikey" = $SupabaseKey
    "Authorization" = "Bearer $SupabaseKey"
    "Content-Type" = "application/json"
}

Write-Host "admob Functions Deploy Test" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

# admob-reward-session testi
Write-Host "[1/2] admob-reward-session test ediliyor..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$SupabaseUrl/functions/v1/admob-reward-session" -Headers $headers -Method Post -Body "{}" -TimeoutSec 15
    Write-Host "[BASARILI] admob-reward-session CALISIYOR" -ForegroundColor Green
    Write-Host "  Yanit: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "[HATA] admob-reward-session DEPLOY EDILMEMIS (HTTP 404)" -ForegroundColor Red
        Write-Host "  Cozum: supabase functions deploy admob-reward-session" -ForegroundColor Yellow
    } elseif ($statusCode -eq 500) {
        $errorBody = $_.ErrorDetails.Message
        Write-Host "[HATA] admob-reward-session 500 hatasi (deploy edilmis ama runtime hatasi)" -ForegroundColor Red
        Write-Host "  Detay: $errorBody" -ForegroundColor Gray
    } else {
        Write-Host "[MEVCUT] admob-reward-session deploy edilmis (HTTP $statusCode)" -ForegroundColor Green
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $body = $reader.ReadToEnd()
            Write-Host "  Yanit: $body" -ForegroundColor Gray
        } catch {}
    }
}

Write-Host ""

# admob-ssv-callback testi (GET ister)
Write-Host "[2/2] admob-ssv-callback test ediliyor..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$SupabaseUrl/functions/v1/admob-ssv-callback" -Headers $headers -Method Get -TimeoutSec 15
    Write-Host "[BASARILI] admob-ssv-callback CALISIYOR" -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "[HATA] admob-ssv-callback DEPLOY EDILMEMIS (HTTP 404)" -ForegroundColor Red
        Write-Host "  Cozum: supabase functions deploy admob-ssv-callback" -ForegroundColor Yellow
    } elseif ($statusCode -eq 405) {
        Write-Host "[MEVCUT] admob-ssv-callback deploy edilmis (HTTP 405 - GET bekliyor)" -ForegroundColor Green
    } else {
        Write-Host "[DURUM] admob-ssv-callback (HTTP $statusCode)" -ForegroundColor Yellow
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $body = $reader.ReadToEnd()
            Write-Host "  Yanit: $body" -ForegroundColor Gray
        } catch {}
    }
}

Write-Host ""
Write-Host "============================" -ForegroundColor Cyan
Write-Host "Test tamamlandi." -ForegroundColor Cyan
