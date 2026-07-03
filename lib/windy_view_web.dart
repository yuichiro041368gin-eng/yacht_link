import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// 同じURLのiframeファクトリを二重登録しないための記録
final Set<String> _registeredViewTypes = {};

/// Windyマップ埋め込み（Web版：iframeで表示）
Widget buildWindyView(String url) {
  final viewType = 'windy-embed-${url.hashCode}';
  if (!_registeredViewTypes.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = url
        ..allow = 'fullscreen'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
    _registeredViewTypes.add(viewType);
  }
  return HtmlElementView(viewType: viewType);
}
