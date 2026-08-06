#!/bin/bash
# =============================================================================
# CizreApp - Supabase Backend Bağlantı ve Fonksiyon Testi
# =============================================================================
# Bu script Supabase bağlantısını ve temel fonksiyonları test eder.
# Kullanım: bash scripts/test_supabase_backend.sh
# =============================================================================

set -e

echo "🚀 CizreApp - Supabase Backend Test Başlıyor..."
echo "=" * 60

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test sayacı
PASS=0
FAIL=0

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ BAŞARILI${NC}: $2"
        ((PASS++))
    else
        echo -e "${RED}❌ BAŞARISIZ${NC}: $2"
        ((FAIL++))
    fi
}

# 1. Supabase URL tanımlı mı kontrol
echo ""
echo "📡 1. Supabase Bağlantı Bilgileri"
echo "--------------------------------"

# .env dosyasını kontrol et
if [ -f .env ]; then
    echo -e "${GREEN}✅ .env dosyası bulundu${NC}"
    SUPABASE_URL=$(grep SUPABASE_URL .env | cut -d '=' -f2)
    SUPABASE_KEY=$(grep SUPABASE_ANON_KEY .env | cut -d '=' -f2)
    
    if [ -n "$SUPABASE_URL" ]; then
        echo -e "${GREEN}✅ SUPABASE_URL tanımlı: ${SUPABASE_URL:0:30}...${NC}"
        ((PASS++))
    else
        echo -e "${YELLOW}⚠️ SUPABASE_URL .env'de tanımlı değil (fallback kullanılacak)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ .env dosyası yok (AppConstants fallback kullanılıyor)${NC}"
    SUPABASE_URL="https://xsbukxkgtmdyickknqzf.supabase.co"
    SUPABASE_KEY="fallback"
fi

# 2. Supabase REST API'ye istek at
echo ""
echo "🌐 2. REST API Erişim Testi"
echo "--------------------------------"

# /rest/v1/ endpoint'ine basit GET
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "apikey: $SUPABASE_KEY" \
    -H "Authorization: Bearer $SUPABASE_KEY" \
    "$SUPABASE_URL/rest/v1/")

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ REST API erişilebilir (HTTP $HTTP_CODE)${NC}"
    ((PASS++))
else
    echo -e "${RED}❌ REST API erişim hatası (HTTP $HTTP_CODE)${NC}"
    ((FAIL++))
fi

# 3. categories tablosunu test et
echo ""
echo "📊 3. Tablo Erişim Testleri"
echo "--------------------------------"

for TABLE in "categories" "shops" "products" "posts_with_profiles"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "apikey: $SUPABASE_KEY" \
        -H "Authorization: Bearer $SUPABASE_KEY" \
        "$SUPABASE_URL/rest/v1/$TABLE?limit=1")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ Tablo erişimi: $TABLE (HTTP $HTTP_CODE)${NC}"
        ((PASS++))
    else
        echo -e "${RED}❌ Tablo erişim hatası: $TABLE (HTTP $HTTP_CODE)${NC}"
        ((FAIL++))
    fi
done

# 4. Storage bucket testi
echo ""
echo "📁 4. Storage Bucket Testleri"
echo "--------------------------------"

for BUCKET in "avatars" "posts" "shop-images" "covers" "stories"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "apikey: $SUPABASE_KEY" \
        -H "Authorization: Bearer $SUPABASE_KEY" \
        "$SUPABASE_URL/storage/v1/bucket/$BUCKET")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ Bucket erişimi: $BUCKET${NC}"
        ((PASS++))
    else
        echo -e "${YELLOW}⚠️ Bucket erişim hatası: $BUCKET (HTTP $HTTP_CODE)${NC}"
    fi
done

# 5. Edge Functions testi
echo ""
echo "⚙️ 5. Edge Function Testleri"
echo "--------------------------------"

# Auth gerektirmeyen fonksiyonları test et
for FUNC in "iyzico-payment-callback" "confirm-balance-topup" "send-email"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -X POST \
        "$SUPABASE_URL/functions/v1/$FUNC" \
        -d '{}')
    
    # 401, 400, 500 hata kodları fonksiyonun var olduğunu gösterir
    if [ "$HTTP_CODE" != "404" ]; then
        echo -e "${GREEN}✅ Function mevcut: $FUNC (HTTP $HTTP_CODE)${NC}"
        ((PASS++))
    else
        echo -e "${RED}❌ Function bulunamadı: $FUNC${NC}"
        ((FAIL++))
    fi
done

# Sonuç
echo ""
echo "=" * 60
echo "📋 SONUÇ RAPORU"
echo "=" * 60
echo -e "${GREEN}✅ Başarılı: $PASS${NC}"
echo -e "${RED}❌ Başarısız: $FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}🎉 TÜM TESTLER BAŞARILI!${NC}"
    echo ""
    echo "Backend bağlantısı sağlıklı çalışıyor."
    echo "Şimdi Flutter uygulamasını çalıştırabilirsiniz:"
    echo "  flutter run -d chrome"
    exit 0
else
    echo -e "${RED}⚠️ BAZI TESTLER BAŞARISIZ${NC}"
    echo ""
    echo "Sorun giderme önerileri:"
    echo "  1. .env dosyasındaki SUPABASE_URL ve SUPABASE_ANON_KEY'i kontrol edin"
    echo "  2. Supabase projesinin aktif olduğunu doğrulayın"
    echo "  3. İnternet bağlantınızı kontrol edin"
    echo "  4. Supabase Dashboard'da RLS politikalarını kontrol edin"
    exit 1
fi
