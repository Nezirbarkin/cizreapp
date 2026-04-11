/// Web platform implementasyonu
/// dart:html ile iframe oluşturur

// ignore_for_file: deprecated_member_use, dangling_library_doc_comments, avoid_web_libraries_in_flutter

import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

// Kayıtlı viewId'lerin takibi - aynı iframe'i tekrar kaydetmeyi önler
final Set<String> _registeredViewIds = {};

Widget buildHtmlView({
  required String htmlContent,
  required double width,
  required double height,
  String? viewId,
}) {
  final actualViewId = viewId ?? 'html-iframe-${htmlContent.hashCode}';
  
  // Sadece ilk kez kaydet - yanıp sönmeyi önler
  if (!_registeredViewIds.contains(actualViewId)) {
    _registeredViewIds.add(actualViewId);
    
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      actualViewId,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.overflow = 'hidden'
          ..srcdoc = htmlContent;
        
        return iframe;
      },
    );
  }

  return SizedBox(
    width: width,
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: HtmlElementView(viewType: actualViewId),
    ),
  );
}

void registerWebView(String viewId, String htmlContent) {
  // Sadece ilk kez kaydet
  if (!_registeredViewIds.contains(viewId)) {
    _registeredViewIds.add(viewId);
    
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int id) {
        final iframe = html.IFrameElement()
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.overflow = 'hidden'
          ..srcdoc = htmlContent;
        
        return iframe;
      },
    );
  }
}
