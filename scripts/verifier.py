#!/usr/bin/env python3
"""
Dosyayı 19 part'a güvenli şekilde böl.

Yaklaşım:
1. Yedekten başla
2. Tüm metotların bounds'larını ORİJİNAL dosyada hesapla
3. Sıralı olarak sil, ama her silme sonrası:
   - Dosyayı kaydet
   - Sonraki metotu yeni dosyada yeniden bul
   - Eğer bulunamazsa, o metodun parça dosyasına yazılmış olduğunu varsay
4. Her parça dosyası kendi başına doğru
"""

import os
import re
import shutil
from collections import defaultdict

BACKUP = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart.bak"
SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"

PART_TO_FILE = {
    "drawer": "_part_drawer.dart",
    "dashboard": "_part_dashboard.dart",
    "users": "_part_users.dart",
    "posts": "_part_posts.dart",
    "products": "_part_products.dart",
    "categories": "_part_categories.dart",
    "shops": "_part_shops.dart",
    "orders": "_part_orders.dart",
    "reports": "_part_reports.dart",
    "post_reports": "_part_post_reports.dart",
    "support_tickets": "_part_support_tickets.dart",
    "payments": "_part_payments.dart",
    "reports_page": "_part_reports_page.dart",
    "analytics": "_part_analytics.dart",
    "logs": "_part_logs.dart",
    "settings": "_part_settings.dart",
    "api_settings": "_part_api_settings.dart",
    "courier": "_part_courier.dart",
    "helpers": "_part_helpers.dart",
}

PART_DESC = {
    "drawer": "Drawer widgets (menu)",
    "dashboard": "Dashboard ana sayfa + istatistik kartlari",
    "users": "Kullanicilar sekmesi + dialoglar",
    "posts": "Gonderiler + hikayeler + dialoglar",
    "products": "Urunler + ekleme/duzenleme/silme dialoglari",
    "categories": "Kategoriler + ekleme/duzenleme/silme dialoglari",
    "shops": "Dukkanlar + kart + ekleme/duzenleme/silme dialoglari",
    "orders": "Siparisler + kart + durum dialoglari",
    "reports": "Sikayetler + rapor kartlari + detay/silme",
    "post_reports": "Gonderi sikayetleri + detay/silme",
    "support_tickets": "Destek talepleri + detay dialog",
    "payments": "Odemeler + payout islemleri + dialoglar",
    "reports_page": "Raporlar sayfasi + grafik olusturucular",
    "analytics": "Analitik icerigi",
    "logs": "Loglar",
    "settings": "Ayarlar + siparis kontrol + duyuru",
    "api_settings": "API ayarlari + Iyzico + S3 + API key + webhooks",
    "courier": "Kurye yonetimi + bakiye/odeme dialoglari",
    "helpers": "Yardimci metotlar",
}

METHOD_TO_PART = {
    "_buildDrawer": "drawer",
    "_buildDrawerItem": "drawer",
    "_buildDashboardContent": "dashboard",
    "_buildWelcomeBanner": "dashboard",
    "_buildStatsGrid": "dashboard",
    "_buildStatCard": "dashboard",
    "_buildStatCardOld": "dashboard",
    "_buildNetworkStatusCard": "dashboard",
    "_buildCacheStatisticsCard": "dashboard",
    "_buildPerformanceCard": "dashboard",
    "_buildUsersContent": "users",
    "_buildRoleBadge": "users",
    "_showEditUserDialog": "users",
    "_showChangeRoleDialog": "users",
    "_showDeleteUserDialog": "users",
    "_buildPostsContent": "posts",
    "_buildPostsList": "posts",
    "_buildStoriesList": "posts",
    "_showAddPostDialog": "posts",
    "_showEditPostDialog": "posts",
    "_showDeletePostDialog": "posts",
    "_showAddStoryDialog": "posts",
    "_showDeleteStoryDialog": "posts",
    "_buildProductsContent": "products",
    "_showAddProductDialog": "products",
    "_showEditProductDialog": "products",
    "_showDeleteProductDialog": "products",
    "_buildCategoriesContent": "categories",
    "_buildCategoryCard": "categories",
    "_showAddCategoryDialog": "categories",
    "_showEditCategoryDialog": "categories",
    "_showDeleteCategoryDialog": "categories",
    "_buildShopsContent": "shops",
    "_loadAndSetShops": "shops",
    "_buildShopCard": "shops",
    "_buildShopStat": "shops",
    "_showAddShopDialog": "shops",
    "_toggleShopVerification": "shops",
    "_toggleShopApproval": "shops",
    "_toggleShopActive": "shops",
    "_showEditShopDialog": "shops",
    "_showDeleteShopDialog": "shops",
    "_showShopDetailDialog": "shops",
    "_buildOrdersContent": "orders",
    "_buildOrderStatChip": "orders",
    "_buildEarningsItem": "orders",
    "_buildOrderCard": "orders",
    "_buildOrderAmountItem": "orders",
    "_buildStatusBadge": "orders",
    "_showOrderDetailDialog": "orders",
    "_buildDetailRow": "orders",
    "_showEditOrderDialog": "orders",
    "_confirmAdminCancel": "orders",
    "_buildStatusOption": "orders",
    "_showDeleteOrderDialog": "orders",
    "_buildReportsContent": "reports",
    "_buildReportStatCard": "reports",
    "_togglePin": "reports",
    "_showReportDetailDialog": "reports",
    "_buildReportStatusOption": "reports",
    "_showDeleteReportDialog": "reports",
    "_getReportStatusText": "reports",
    "_callCustomerFromAdmin": "reports",
    "_openAddressInMap": "reports",
    "_buildPostReportsContent": "post_reports",
    "_buildPostReportStatCard": "post_reports",
    "_showPostReportDetailDialog": "post_reports",
    "_buildReportDetailRow": "post_reports",
    "_showDeletePostReportDialog": "post_reports",
    "_loadPostReports": "post_reports",
    "_getPostReportStatusText": "post_reports",
    "_buildSupportTicketsContent": "support_tickets",
    "_showSupportTicketDetailDialog": "support_tickets",
    "_getSupportTicketStatusText": "support_tickets",
    "_buildPaymentsContent": "payments",
    "_markPayoutAsPaid": "payments",
    "_showPaymentDetailDialog": "payments",
    "_processPayoutRequest": "payments",
    "_showRejectPayoutDialog": "payments",
    "_getPaymentStatusText": "payments",
    "_getAddressPhoneForAdmin": "payments",
    "_buildReportsPageContent": "reports_page",
    "_buildPeriodCard": "reports_page",
    "_buildRevenueChart": "reports_page",
    "_buildOrdersChart": "reports_page",
    "_buildCategoryDistribution": "reports_page",
    "_buildAnalyticsContent": "analytics",
    "_buildLogsContent": "logs",
    "_buildSettingsContent": "settings",
    "_buildOrderControlCard": "settings",
    "_buildStartupAnnouncementCard": "settings",
    "_showEditAnnouncementDialog": "settings",
    "_buildTypeChip": "settings",
    "_showSendNotificationDialog": "settings",
    "_buildAPISettingsContent": "api_settings",
    "_buildIyzicoPaymentSettingsCard": "api_settings",
    "_showEditIyzicoDialog": "api_settings",
    "_showCreateAPIKeyDialog": "api_settings",
    "_showDeleteAPIKeyDialog": "api_settings",
    "_toggleAPIKey": "api_settings",
    "_regenerateAPIKey": "api_settings",
    "_updateAPISetting": "api_settings",
    "_showWebhooksDialog": "api_settings",
    "_buildWebhookItem": "api_settings",
    "_buildS3StorageSettingsCard": "api_settings",
    "_showS3SettingsDialog": "api_settings",
    "_buildCourierManagementContent": "courier",
    "_buildCourierStatCard": "courier",
    "_buildCourierCard": "courier",
    "_buildCourierInfoItem": "courier",
    "_resetCourierBalance": "courier",
    "_markCourierPaid": "courier",
    "_showCourierFeeDialog": "courier",
    "_approveCourierPayout": "courier",
    "_getCourierFee": "courier",
    "_formatDate": "helpers",
    "_formatDateTime": "helpers",
    "_isValidImageUrl": "helpers",
}

KEEP = {
    "build", "_setupRealtimeSubscription", "_loadRealData", "_buildBody",
    "_buildComingSoon", "_buildInfoRow",
}


def find_method_bounds(content, method_name):
    """content: string. method_name: string. Returns (start, end) byte/string index or None."""
    # Find method definition line
    pattern = re.compile(
        r'^  (?:static\s+)?(?:Widget|Future<[^>]*>|void|bool|int|double|String|List<[^>]*>|Map<[^>]*>)\s+'
        + re.escape(method_name) + r'\s*\(',
        re.MULTILINE
    )
    m = pattern.search(content)
    if not m:
        return None, None
    start = m.start()
    # Find matching closing brace
    # Walk through content from start
    brace_depth = 0
    started = False
    paren_depth = 0
    sig_end = -1
    i = start
    while i < len(content):
        ch = content[i]
        if not started:
            if ch == '(':
                paren_depth += 1
            elif ch == ')':
                paren_depth -= 1
            elif ch == '{':
                brace_depth = 1
                started = True
        else:
            if ch == '{':
                brace_depth += 1
            elif ch == '}':
                brace_depth -= 1
                if brace_depth == 0:
                    # Include the newline after } if present
                    end = i + 1
                    if end < len(content) and content[end] == '\n':
                        end += 1
                    return start, end
        i += 1
    return None, None


def main():
    # Yedekten geri yükle
    shutil.copy(BACKUP, SRC)
    with open(SRC, 'r', encoding='utf-8') as f:
        content = f.read()

    print(f"Baslangic: {len(content.splitlines())} satir, {len(content)} karakter")

    # Part dosyalarını temizle (helpers ve drawer'ı koru)
    preserve = {"_part_helpers.dart", "_part_drawer.dart"}
    for fn in os.listdir(PARTS_DIR):
        if fn.endswith(".dart") and fn not in preserve:
            os.remove(os.path.join(PARTS_DIR, fn))

    # Her metodu bul ve parça dosyasına yaz
    part_contents = defaultdict(list)
    for name, part_key in METHOD_TO_PART.items():
        if name in KEEP:
            continue
        start, end = find_method_bounds(content, name)
        if start is None:
            print(f"  BULUNAMADI: {name}")
            continue
        method_text = content[start:end]
        part_contents[part_key].append((name, method_text))
        # Ana içerikten kaldır
        content = content[:start] + content[end:]

    # Part dosyalarını yaz
    for part_key, methods in part_contents.items():
        filename = PART_TO_FILE.get(part_key)
        if not filename:
            continue
        text = f"part of '../admin_dashboard_screen.dart';\n\n"
        text += f"// {'='*74}\n"
        text += f"// {PART_DESC.get(part_key, part_key)}\n"
        text += f"// {'='*74}\n\n"
        for name, mtext in methods:
            text += f"// --- {name} ---\n"
            text += mtext
            if not mtext.endswith('\n'):
                text += '\n'
            text += '\n'
        with open(os.path.join(PARTS_DIR, filename), 'w', encoding='utf-8') as f:
            f.write(text)
        total_lines = sum(m.count('\n') for _, m in methods)
        print(f"  {filename}: {len(methods)} metot, ~{total_lines} satir")

    # Library direktifi ve part direktiflerini ekle
    # Önce import'ları koru, sonra class'tan önce part direktifleri
    lines = content.split('\n')
    # class AdminDashboardScreen satırını bul
    class_idx = None
    for i, line in enumerate(lines):
        if 'class AdminDashboardScreen' in line:
            class_idx = i
            break

    if class_idx:
        # part direktiflerini ekle (import'lardan sonra, class'tan önce)
        new_lines = lines[:class_idx]
        # Boş satır ekle
        if new_lines and new_lines[-1].strip():
            new_lines.append("")
        for part_key in ["helpers", "drawer", "dashboard", "users", "posts",
                         "products", "categories", "shops", "orders",
                         "reports", "post_reports", "support_tickets",
                         "payments", "reports_page", "analytics", "logs",
                         "settings", "api_settings", "courier"]:
            new_lines.append(f"part 'admin_dashboard_parts/{PART_TO_FILE[part_key]}';")
        new_lines.append("")
        new_lines.extend(lines[class_idx:])
        content = '\n'.join(new_lines)

    # library; direktifi ekle (en başa, yorumlardan sonra)
    if "library;" not in content:
        # İlk boş olmayan satırdan önce ekle
        # Basitçe ilk 10 satıra ekle
        lines = content.split('\n')
        # İlk yorum olmayan satırı bul
        for i, line in enumerate(lines):
            if not line.startswith('//') and line.strip():
                lines.insert(i, 'library;')
                lines.insert(i+1, '')
                break
        content = '\n'.join(lines)

    with open(SRC, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"\nSon: {len(content.splitlines())} satir")


if __name__ == "__main__":
    main()
