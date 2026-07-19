#!/bin/bash
# ============================================================
# app-ads.txt dosyasını sunucuya yükleyen script
# ============================================================
# Kullanım:
#   ./scripts/deploy-app-ads-txt.sh
#
# Önkoşullar:
#   - Sunucuda SSH erişiminiz olmalı
#   - .env dosyasında SERVER_HOST, SERVER_USER, SERVER_PATH tanımlı olmalı
# ============================================================

set -euo pipefail

# Renkli çıktı
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Repo kökü
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
SOURCE_FILE="$REPO_ROOT/web/app-ads.txt"

echo -e "${YELLOW}🚀 app-ads.txt Deploy Script${NC}"
echo "================================================"

# Kaynak dosya kontrolü
if [ ! -f "$SOURCE_FILE" ]; then
  echo -e "${RED}❌ Hata: $SOURCE_FILE bulunamadı!${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Kaynak dosya bulundu:${NC} $SOURCE_FILE"
echo ""
echo "İçerik:"
echo "-----------------------------------"
cat "$SOURCE_FILE"
echo "-----------------------------------"
echo ""

# .env dosyasını yükle
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
  echo -e "${GREEN}✅ .env yüklendi${NC}"
else
  echo -e "${YELLOW}⚠️  .env bulunamadı, interaktif mod${NC}"
fi

# Parametreler (env veya interaktif)
read -p "Sunucu host (örn: cizreapp.com): " DEPLOY_HOST
read -p "Sunucu kullanıcı (örn: ubuntu): " DEPLOY_USER
read -p "Sunucu public dizini (örn: /var/www/cizreapp.com/public_html): " DEPLOY_PATH

if [ -z "$DEPLOY_HOST" ] || [ -z "$DEPLOY_USER" ] || [ -z "$DEPLOY_PATH" ]; then
  echo -e "${RED}❌ Tüm alanlar zorunludur!${NC}"
  exit 1
fi

# Doğrulama
echo ""
echo -e "${YELLOW}Hedef:${NC} ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/app-ads.txt"
read -p "Devam edilsin mi? (e/h): " CONFIRM

if [ "$CONFIRM" != "e" ] && [ "$CONFIRM" != "E" ]; then
  echo "İptal edildi."
  exit 0
fi

# Yükle (scp ile)
echo ""
echo -e "${YELLOW}📤 Yükleniyor...${NC}"
scp "$SOURCE_FILE" "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/app-ads.txt"

# Sunucuda izinleri ayarla
echo -e "${YELLOW}🔒 İzinler ayarlanıyor...${NC}"
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "chmod 644 ${DEPLOY_PATH}/app-ads.txt && chown \${APACHE_USER:-www-data}:\${APACHE_GROUP:-www-data} ${DEPLOY_PATH}/app-ads.txt 2>/dev/null || true"

echo ""
echo -e "${GREEN}✅ Yüklendi! Şimdi doğrulayın:${NC}"
echo ""
echo "  curl -I https://${DEPLOY_HOST}/app-ads.txt"
echo "  curl https://${DEPLOY_HOST}/app-ads.txt"
echo ""
echo -e "${YELLOW}Sonra AdMob panelinden 'Güncellemeleri kontrol et' butonuna basın.${NC}"
