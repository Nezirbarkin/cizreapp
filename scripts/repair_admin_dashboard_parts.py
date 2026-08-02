#!/usr/bin/env python3
"""Repair truncated admin dashboard methods from the last committed source.

The split files use method markers.  Only explicitly listed, known-truncated
sections are replaced.  Data-loading methods accidentally omitted by the split
are extracted into a dedicated part.  Dart comments and strings are ignored
while matching method braces.
"""

from __future__ import annotations

import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_PATH = "lib/features/admin/screens/admin_dashboard_screen.dart"
SCREEN = ROOT / SOURCE_PATH
PARTS = SCREEN.parent / "admin_dashboard_parts"

TRUNCATED_METHODS = {
    "_buildDrawerItem": "_part_drawer.dart",
    "_buildStatCard": "_part_dashboard.dart",
    "_buildStatCardOld": "_part_dashboard.dart",
    "_buildShopStat": "_part_shops.dart",
    "_buildOrderStatChip": "_part_orders.dart",
    "_buildEarningsItem": "_part_orders.dart",
    "_buildOrderAmountItem": "_part_orders.dart",
    "_buildStatusOption": "_part_orders.dart",
    "_buildReportStatCard": "_part_reports.dart",
    "_buildReportStatusOption": "_part_reports.dart",
    "_buildPostReportStatCard": "_part_post_reports.dart",
    "_buildPeriodCard": "_part_reports_page.dart",
    "_buildCourierStatCard": "_part_courier.dart",
}

OMITTED_METHODS = [
    "_loadPosts",
    "_loadStories",
    "_loadProducts",
    "_loadShops",
    "_loadCategories",
    "_loadShopsWithDetails",
    "_loadOrders",
    "_loadShopsForFilter",
    "_loadReports",
    "_loadPostReports",
    "_loadSupportTickets",
    "_loadPaymentData",
    "_loadReportData",
    "_loadLogsData",
    "_loadOrderControlSettings",
    "_loadAPISettings",
    "_loadCouriers",
    "_loadCourierPayouts",
]


def committed_source() -> str:
    result = subprocess.run(
        ["git", "show", f"HEAD:{SOURCE_PATH}"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return result.stdout


def code_characters(text: str, start: int):
    """Yield (index, char) outside Dart strings and comments."""
    i = start
    state = "code"
    quote = ""
    triple = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "line_comment":
            if ch == "\n":
                state = "code"
            i += 1
            continue
        if state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue
        if state == "string":
            if ch == "\\":
                i += 2
                continue
            if triple and text.startswith(quote * 3, i):
                state = "code"
                i += 3
                continue
            if not triple and ch == quote:
                state = "code"
            i += 1
            continue

        if ch == "/" and nxt == "/":
            state = "line_comment"
            i += 2
            continue
        if ch == "/" and nxt == "*":
            state = "block_comment"
            i += 2
            continue
        if ch in ("'", '"'):
            quote = ch
            triple = text.startswith(ch * 3, i)
            state = "string"
            i += 3 if triple else 1
            continue
        yield i, ch
        i += 1


def extract_method(source: str, name: str) -> str:
    declaration = re.search(
        rf"(?m)^  (?!//)(?:static\s+)?[A-Za-z][A-Za-z0-9_<>, ?]*\s+"
        rf"{re.escape(name)}\s*\(",
        source,
    )
    if declaration is None:
        raise RuntimeError(f"HEAD içinde metot bulunamadı: {name}")

    body_start = None
    paren_depth = 0
    for index, char in code_characters(source, declaration.start()):
        if char == "(":
            paren_depth += 1
        elif char == ")":
            paren_depth -= 1
        elif char == "{" and paren_depth == 0:
            body_start = index
            break
        elif char == ";" and paren_depth == 0:
            raise RuntimeError(f"Blok gövdeli olmayan metot: {name}")
    if body_start is None:
        raise RuntimeError(f"Gövde başlangıcı bulunamadı: {name}")

    depth = 0
    for index, char in code_characters(source, body_start):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[declaration.start() : index + 1].rstrip() + "\n"
    raise RuntimeError(f"Gövde sonu bulunamadı: {name}")


def replace_marked_section(path: pathlib.Path, name: str, method: str) -> None:
    text = path.read_text(encoding="utf-8")
    marker = f"// --- {name} ---"
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"İşaret bulunamadı: {path.name} / {name}")
    next_marker = text.find("// --- ", start + len(marker))
    if next_marker < 0:
        extension_end = text.rfind("\n}")
        if extension_end < start:
            raise RuntimeError(f"Extension sonu bulunamadı: {path.name}")
        end = extension_end + 1
    else:
        end = next_marker
    replacement = f"{marker}\n{method}\n"
    path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


def main() -> None:
    source = committed_source()
    for name, filename in TRUNCATED_METHODS.items():
        replace_marked_section(PARTS / filename, name, extract_method(source, name))
        print(f"Onarıldı: {filename} / {name}")

    loader_methods = [extract_method(source, name) for name in OMITTED_METHODS]
    loaders = "part of '../admin_dashboard_screen.dart';\n\n"
    loaders += "extension on _AdminDashboardScreenState {\n\n"
    for name, method in zip(OMITTED_METHODS, loader_methods):
        loaders += f"// --- {name} ---\n{method}\n"
    loaders += "}\n"
    (PARTS / "_part_data_loaders.dart").write_text(loaders, encoding="utf-8")

    screen = SCREEN.read_text(encoding="utf-8")
    directive = "part 'admin_dashboard_parts/_part_data_loaders.dart';"
    if directive not in screen:
        anchor = "part 'admin_dashboard_parts/_part_helpers.dart';"
        screen = screen.replace(anchor, f"{anchor}\n{directive}")
        SCREEN.write_text(screen, encoding="utf-8")
    print(f"Eklendi: _part_data_loaders.dart / {len(loader_methods)} metot")


if __name__ == "__main__":
    main()
