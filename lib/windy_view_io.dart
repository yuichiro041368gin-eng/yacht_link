import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Windyマップ埋め込み（モバイル版：WebViewで表示）
/// webview_flutterが対応していないデスクトップでは外部ブラウザで開くボタンを出す。
Widget buildWindyView(String url) {
  if (Platform.isAndroid || Platform.isIOS) {
    return _WindyWebView(url: url);
  }
  return Center(
    child: FilledButton.icon(
      icon: const Icon(Icons.open_in_new),
      label: const Text('Windyをブラウザで開く'),
      onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    ),
  );
}

class _WindyWebView extends StatefulWidget {
  final String url;
  const _WindyWebView({required this.url});

  @override
  State<_WindyWebView> createState() => _WindyWebViewState();
}

class _WindyWebViewState extends State<_WindyWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
