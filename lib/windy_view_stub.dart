import 'package:flutter/material.dart';

/// Windyマップ埋め込み（非対応プラットフォーム用スタブ）
Widget buildWindyView(String url) {
  return const Center(
    child: Text('この環境ではWindyマップを表示できません',
        style: TextStyle(color: Colors.grey)),
  );
}
