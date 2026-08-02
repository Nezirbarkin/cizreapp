#!/usr/bin/env python3
"""
admin_dashboard_screen.dart dosyasını part dosyalarına böler.

Yaklaşım: Her metodu parantez sayımı ile bul, part dosyasına yaz,
ardından ana dosyadan kaldır.
"""

import os
import re
import json
from collections import defaultdict

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
PARTS_DIR = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_parts"

# Metot -> Part adı
METHOD_TO_PART = {
    # drawer
    "_buildDrawer": "drawer",
    "_buildDrawerItem": "drawer",
    # dashboard
    "_buildDashboardContent": "dashboard",
    "_buildWelcomeBanner": "dashboard",
    "_buildStatsGrid": "dashboard",
    "_buildStatCard": "dashboard",
    "_buildStatCardOld": "dashboard",
    "_buildNetworkStatusCard": "dashboard",
    "_buildCacheStatisticsCard": "dashboard",
    "_buildPerformanceCard": "dashboard",
    # users
    "_buildUsersContent": "users",
    "_buildRoleBadge": "users",
    "_showEditUserDialog": "users",
    "_showChangeRoleDialog": "users",
    "_showDeleteUserDialog": "users",
    # posts
    "_buildPostsContent": "posts",
    "_buildPostsList": "posts",
    "_buildStoriesList": "posts",
    "_showAddPostDialog": "posts",
    "_showEditPostDialog": "posts",
    "_showDeletePostDialog": "posts",
    "_showAddStoryDialog": "posts",
    "_showDeleteStoryDialog": "posts",
    # products
    "_buildProductsContent": "products",
    "_showAddProductDialog": "products",
    "_showEditProductDialog": "products",
    "_showDeleteProductDialog": "products",
    # categories
    "_buildCategoriesContent": "categories",
    "_buildCategoryCard": "categories",
    "_showAddCategoryDialog": "categories",
    "_showEditCategoryDialog": "categories",
    "_showDeleteCategoryDialog": "categories",
    # shops
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
    # orders
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
    # reports
    "_buildReportsContent": "reports",
    "_buildReportStatCard": "reports",
    "_togglePin": "reports",
    "_showReportDetailDialog": "reports",
    "_buildReportStatusOption": "reports",
    "_showDeleteReportDialog": "reports",
    # post_reports
    "_buildPostReportsContent": "post_reports",
    "_buildPostReportStatCard": "post_reports",
    "_showPostReportDetailDialog": "post_reports",
    "_buildReportDetailRow": "post_reports",
    "_showDeletePostReportDialog": "post_reports",
    # support_tickets
    "_buildSupportTicketsContent": "support_tickets",
    "_showSupportTicketDetailDialog": "support_tickets",
    # payments
    "_buildPaymentsContent": "payments",
    "_markPayoutAsPaid": "payments",
    "_showPaymentDetailDialog": "payments",
    "_processPayoutRequest": "payments",
    "_showRejectPayoutDialog": "payments",
    # reports_page
    "_buildReportsPageContent": "reports_page",
    "_buildPeriodCard": "reports_page",
    "_buildRevenueChart": "reports_page",
    "_buildOrdersChart": "reports_page",
    "_buildCategoryDistribution": "reports_page",
    # analytics
    "_buildAnalyticsContent": "analytics",
    # logs
    "_buildLogsContent": "logs",
    # settings
    "_buildSettingsContent": "settings",
    "_buildOrderControlCard": "settings",
    "_buildStartupAnnouncementCard": "settings",
    "_showEditAnnouncementDialog": "settings",
    "_buildTypeChip": "settings",
    "_showSendNotificationDialog": "settings",
    # api_settings
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
    # courier
    "_buildCourierManagementContent": "courier",
    "_buildCourierStatCard": "courier",
    "_buildCourierCard": "courier",
    "_buildCourierInfoItem": "courier",
    "_resetCourierBalance": "courier",
    "_markCourierPaid": "courier",
    "_showCourierFeeDialog": "courier",
    "_approveCourierPayout": "courier",
}

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
}


def find_method_bounds(lines, method_name):
    """Bir metodun (start, end) 0-based indekslerini bul."""
    pattern_prefix = method_name + "("
    for i in range(len(lines)):
        line = lines[i]
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        # Sınıf içi metot: 2-boşluk indentation, return type olmalı
        if indent != 2:
            continue
        if pattern_prefix not in stripped:
            continue
        # Method adından sonra gelen kısım (boşluk, parametreler vs.)
        idx = stripped.index(pattern_prefix)
        # Öncesinde geçerli bir identifier/return type olmalı
        if idx == 0:
            # Method adı satırın başında -> return type yok
            continue
        # Önceki karakter boşluk olmalı (return type'tan ayrılmış)
        if stripped[idx-1] != ' ':
            continue
        # Bu bir metot tanımı olmalı
        # Return type: stripped'den method_name'den önceki kısım
        # Örnek: "  Widget _buildDrawer(" veya "  Future<void> _showS3SettingsDialog("
        before = stripped[:stripped.index(pattern_prefix)]
        if not before.strip():
            continue  # return type yok
        return_type_words = before.strip().split()
        if not return_type_words:
            continue
        # Return type bilinen Dart tiplerinden biri olmalı
        valid_types = {'Widget', 'void', 'bool', 'int', 'double', 'String',
                       'Future', 'List', 'Map', 'Set', 'dynamic', 'var', 'final',
                       'static', 'late'}
        if return_type_words[-1] not in valid_types and \
           not any(w in valid_types for w in return_type_words):
            # Belki tanım değil
            continue
        # Şimdi gövdeyi bul
        # İmza parantezlerini eşleştir
        # Satırda ( ve ) say
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
        # Şimdi { bulmamız gerek sig_end_line sonrasında
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

    print(f"Toplam satir: {len(lines)}")

    # Her metodu bul
    methods = {}  # method_name -> (start, end) 0-based
    not_found = []
    for method_name in sorted(set(METHOD_TO_PART.keys())):
        start, end = find_method_bounds(lines, method_name)
        if start is None:
            not_found.append(method_name)
            continue
        methods[method_name] = (start, end)

    print(f"Bulunan metot: {len(methods)}/{len(METHOD_TO_PART)}")
    if not_found:
        print(f"Bulunamayan metotlar: {not_found}")

    # Her metodu part'a ata
    part_methods = defaultdict(list)
    for method_name, (start, end) in methods.items():
        part_key = METHOD_TO_PART[method_name]
        part_methods[part_key].append((method_name, start, end))

    # Part dosyalarını oluştur
    os.makedirs(PARTS_DIR, exist_ok=True)

    for part_key, method_list in part_methods.items():
        filename = PART_TO_FILE.get(part_key)
        if not filename:
            print(f"  PART DOSYASI YOK: {part_key}")
            continue

        # Metotları satır sırasına göre sırala
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

    # Method bounds'ları sakla
    out = {name: list(bounds) for name, bounds in methods.items()}
    with open(r"C:\Users\lenovo\cizreapp\scripts\_method_bounds.json", "w") as f:
        json.dump(out, f, indent=2)
    print(f"\n{len(methods)} metodun bounds bilgisi _method_bounds.json dosyasina yazildi.")


if __name__ == "__main__":
    main()
