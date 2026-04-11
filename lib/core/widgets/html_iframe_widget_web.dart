// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

/// Web implementation for HTML iframe rendering
/// Web platformu için HTML iframe implementasyonu
Widget buildHtmlView(String htmlContent) {
  final viewId = htmlContent.hashCode;
  
  // IFrame oluştur
  final iframeElement = html.IFrameElement()
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.border = 'none'
    ..srcdoc = htmlContent;
  
  // Platform view'a kaydet
  ui_web.platformViewRegistry.registerViewFactory(
    'html-iframe-$viewId',
    (int viewId) => iframeElement,
  );
  
  return HtmlElementView(
    key: ValueKey('html-iframe-$viewId'),
    viewType: 'html-iframe-$viewId',
  );
}
