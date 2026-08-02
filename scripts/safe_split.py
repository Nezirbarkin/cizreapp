#!/usr/bin/env python3
"""
Güvenli parçalama: yedekten başla, her metodu teker teker bul ve sil,
her adımda doğrula.
"""

import re
import json
import os
from collections import defaultdict

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


def find_method_bounds(lines, method_name):
    pattern_prefix = method_name + "("
    for i in range(len(lines)):
        line = lines[i]
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if indent != 2:
            continue
        if pattern_prefix not in stripped:
            continue
        idx = stripped.index(pattern_prefix)
        if idx == 0:
            continue
        if stripped[idx-1] != ' ':
            continue
        paren_depth = 0
        sig_end_line = i
        for j in range(i, len(lines)):
            for ch in lines[j]:
                if ch == "(":
                    paren_depth += 1
                elif ch == ")":
                    paren_depth -= 1
            if paren_depth == 0:
                sig_end_line = j
                break
        brace_depth = 0
        started = False
        j = sig_end_line
        while j < len(lines):
            for ch in lines[j]:
                if ch == "{":
                    brace_depth += 1
                    started = True
                elif ch == "}":
                    brace_depth -= 1
            if started and brace_depth == 0:
                return i, j
            j += 1
    return None, None


def main():
    with open(SRC, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    print(f"Baslangic: {len(lines)} satir")

    # 1) Tüm bounds'ları hesapla
    bounds_list = []
    for name in set(METHOD_TO_PART.keys()):
        if name in KEEP:
            continue
        start, end = find_method_bounds(lines, name)
        if start is None:
            print(f"  BULUNAMADI: {name}")
            continue
        bounds_list.append((start, end, name, METHOD_TO_PART[name]))
    bounds_list.sort(key=lambda x: x[0])

    # 2) Part'lara ata
    part_methods = defaultdict(list)
    for start, end, name, part_key in bounds_list:
        part_methods[part_key].append((name, start, end))

    # 3) Part dosyalarını yaz
    for part_key, method_list in part_methods.items():
        filename = PART_TO_FILE.get(part_key)
        if not filename:
            print(f"  PART DOSYASI YOK: {part_key}")
            continue
        method_list.sort(key=lambda x: x[1])
        content_parts = [f"part of '../admin_dashboard_screen.dart';\n\n"]
        content_parts.append(f"// {'='*74}\n")
        content_parts.append(f"// {PART_DESC.get(part_key, part_key)}\n")
        content_parts.append(f"// {'='*74}\n\n")
        for method_name, start, end in method_list:
            content_parts.append(f"// --- {method_name} ---\n")
            content_parts.extend(lines[start:end+1])
            content_parts.append("\n\n")
        filepath = os.path.join(PARTS_DIR, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(content_parts)
        total_lines = sum(end - start + 1 for _, start, end in method_list)
        print(f"  {filename}: {len(method_list)} metot, {total_lines} satir")

    # 4) Ana dosyadan metotları sil - sıralı
    # Her silinen aralıktan sonra dosya kısalır, sonraki bounds'ları ayarla
    total_deleted = 0
    for start, end, name, part_key in bounds_list:
        new_start = start - total_deleted
        new_end = end - total_deleted
        if new_start < 0 or new_start >= len(lines):
            print(f"  ATLANDI: {name}")
            continue
        if new_end >= len(lines):
            new_end = len(lines) - 1
        # Önceki ve sonraki boş satırları sil
        delete_start = new_start
        if new_start > 0 and lines[new_start-1].strip() == "":
            delete_start = new_start - 1
        delete_end = new_end
        if new_end + 1 < len(lines) and lines[new_end+1].strip() == "":
            delete_end = new_end + 1
        del lines[delete_start:delete_end+1]
        total_deleted += (delete_end - delete_start + 1)

    # 5) Library direktifi ve part direktiflerini ekle
    # Zaten varsa üzerine yaz
    final_lines = []
    in_imports = False
    added = False
    for i, line in enumerate(lines):
        if not added and i > 5 and not in_imports and 'class AdminDashboardScreen' in line:
            # Part direktiflerini ekle
            for part_key in ["helpers", "drawer", "dashboard", "users", "posts",
                             "products", "categories", "shops", "orders",
                             "reports", "post_reports", "support_tickets",
                             "payments", "reports_page", "analytics", "logs",
                             "settings", "api_settings", "courier"]:
                final_lines.append(f"part 'admin_dashboard_parts/{PART_TO_FILE[part_key]}';\n")
            final_lines.append("\n")
            added = True
        if 'part \'admin_dashboard_parts/' in line:
            continue  # eski part direktiflerini atla
        final_lines.append(line)

    # Library; direktifi ekle (ilk non-comment, non-blank satırdan önce)
    # Veya en üste
    if "library;" not in "".join(final_lines[:20]):
        # İlk comment'ten sonra ekle
        for i, line in enumerate(final_lines):
            if not line.startswith("//") and line.strip():
                final_lines.insert(i, "library;\n\n")
                break

    with open(SRC, 'w', encoding='utf-8') as f:
        f.writelines(final_lines)
    print(f"\nSon: {len(final_lines)} satir")


if __name__ == "__main__":
    main()
