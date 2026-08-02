#!/usr/bin/env python3
"""Tüm metotların bounds bilgisini hesapla."""

import os
import json

SRC = r"C:\Users\lenovo\cizreapp\lib\features\admin\screens\admin_dashboard_screen.dart"
OUT = r"C:\Users\lenovo\cizreapp\scripts\_method_bounds.json"

# ANA DOSYADA KALACAK metotlar
KEEP = {
    "build", "_setupRealtimeSubscription", "_loadRealData", "_buildBody",
    "_buildComingSoon", "_buildInfoRow",
}

# Hangi metot hangi part'a ait
METHOD_TO_PART = {
    # drawer (zaten part'larda)
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
    "_getReportStatusText": "reports",
    "_callCustomerFromAdmin": "reports",
    "_openAddressInMap": "reports",
    # post_reports
    "_buildPostReportsContent": "post_reports",
    "_buildPostReportStatCard": "post_reports",
    "_showPostReportDetailDialog": "post_reports",
    "_buildReportDetailRow": "post_reports",
    "_showDeletePostReportDialog": "post_reports",
    "_loadPostReports": "post_reports",
    "_getPostReportStatusText": "post_reports",
    # support_tickets
    "_buildSupportTicketsContent": "support_tickets",
    "_showSupportTicketDetailDialog": "support_tickets",
    "_getSupportTicketStatusText": "support_tickets",
    # payments
    "_buildPaymentsContent": "payments",
    "_markPayoutAsPaid": "payments",
    "_showPaymentDetailDialog": "payments",
    "_processPayoutRequest": "payments",
    "_showRejectPayoutDialog": "payments",
    "_getPaymentStatusText": "payments",
    "_getAddressPhoneForAdmin": "payments",
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
    "_getCourierFee": "courier",
    # helpers
    "_formatDate": "helpers",
    "_formatDateTime": "helpers",
    "_isValidImageUrl": "helpers",
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
    methods = {}
    not_found = []
    for method_name in sorted(set(METHOD_TO_PART.keys())):
        start, end = find_method_bounds(lines, method_name)
        if start is None:
            not_found.append(method_name)
            continue
        methods[method_name] = [start, end]
    print(f"Bulunan: {len(methods)}/{len(METHOD_TO_PART)}")
    if not_found:
        print(f"Bulunamayan: {not_found}")
    out = {name: {"bounds": bounds, "part": METHOD_TO_PART[name]} for name, bounds in methods.items()}
    with open(OUT, "w") as f:
        json.dump(out, f, indent=2)
    print(f"Bounds: {OUT}")


if __name__ == "__main__":
    main()
