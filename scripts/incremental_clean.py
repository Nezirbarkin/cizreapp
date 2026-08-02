#!/usr/bin/env python3
"""
Her seferinde bir metodu bul, sil, kaydet, sonrakine geç.
Bu şekilde bounds kayması sorun olmaz.
"""

import re
import json

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
OUT = r"C:\Users\lenovo\cizreapp\scripts\_method_bounds.json"

# Hangi metot hangi part'a ait
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

    initial_count = len(lines)
    print(f"Baslangic: {initial_count} satir")

    prev_end = -1

    # Her metodu teker teker bul ve sil
    # Önce tüm bounds'ları bul, sonra satır sırasına göre sil
    bounds_list = []
    for name in set(METHOD_TO_PART.keys()):
        if name in KEEP:
            continue
        start, end = find_method_bounds(lines, name)
        if start is None:
            print(f"  BULUNAMADI: {name}")
            continue
        bounds_list.append((start, end, name))
    bounds_list.sort(key=lambda x: x[0])

    # İkinci aşama: bounds'ları sırala, satır numaralarını güncelle
    # Sıralı silme yap, kaç satır silindiğini takip et
    bounds_list.sort(key=lambda x: x[0])

    removed = []
    total_deleted = 0  # Şimdiye kadar silinen toplam satır
    for start, end, name in bounds_list:
        # start ve end'i mevcut dosyaya göre ayarla
        new_start = start - total_deleted
        new_end = end - total_deleted
        if new_start < 0 or new_start >= len(lines):
            print(f"  ATLANDI: {name} (yeni start gecersiz: {new_start})")
            continue
        if new_end >= len(lines):
            new_end = len(lines) - 1
        # Önceki ve sonraki boş satırları da sil
        delete_start = new_start
        if new_start > 0 and lines[new_start-1].strip() == "":
            delete_start = new_start - 1
        delete_end = new_end
        if new_end + 1 < len(lines) and lines[new_end+1].strip() == "":
            delete_end = new_end + 1
        del lines[delete_start:delete_end+1]
        removed.append(name)
        total_deleted += (delete_end - delete_start + 1)

    with open(SRC, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print(f"Son: {len(lines)} satir ({len(removed)} metot silindi)")


if __name__ == "__main__":
    main()
