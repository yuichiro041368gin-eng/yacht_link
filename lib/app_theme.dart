import 'package:flutter/material.dart';

/// YachtLink デザインシステム「Deep Ocean」
///
/// - 基調色: ディープネイビー〜マリンブルーのグラデーション
/// - アクセント: シアン（海面の反射光をイメージ）
/// - 各ページは AppColors.primary（MaterialColor）を参照する。
///   Colors.indigo と同様に .shade50〜.shade900 が使える。
class AppColors {
  AppColors._();

  /// メインカラー（ディープオーシャンブルー）
  static const MaterialColor primary = MaterialColor(0xFF0F4C81, <int, Color>{
    50: Color(0xFFE7EFF6),
    100: Color(0xFFC4D8E9),
    200: Color(0xFF9DBFDB),
    300: Color(0xFF74A5CC),
    400: Color(0xFF4A8ABC),
    500: Color(0xFF0F4C81),
    600: Color(0xFF0D4374),
    700: Color(0xFF0B3961),
    800: Color(0xFF082C4C),
    900: Color(0xFF061F36),
  });

  /// 最も深い紺（ナビゲーションバー・夜の海）
  static const Color deepNavy = Color(0xFF081A30);

  /// 濃紺（ヒーローヘッダーの始点）
  static const Color navy = Color(0xFF0A2540);

  /// 沖合の青
  static const Color ocean = Color(0xFF1B6FAE);

  /// アクセントシアン
  static const Color cyan = Color(0xFF2BC8E8);

  /// 淡いアクア（選択状態・グロー）
  static const Color aqua = Color(0xFF8FE8F7);

  /// 画面背景（ごく淡いブルーグレー）
  static const Color scaffoldBg = Color(0xFFF2F6FB);

  /// カード上の細い境界線
  static const Color hairline = Color(0xFFE3EAF3);
}

/// アプリ共通のグラデーション定義
class AppGradients {
  AppGradients._();

  /// ヒーローヘッダー（夜の海 → 沖合）
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.navy, Color(0xFF0F4C81), AppColors.ocean],
  );

  /// シアン系CTA（ボタン・強調）
  static const LinearGradient cyanCta = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.cyan, AppColors.ocean],
  );

  /// バナー: エメラルド〜ティール（配艇チェッカー）
  static const LinearGradient teal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF12B886), Color(0xFF0B7285)],
  );

  /// バナー: スカイブルー（アメダス風況）
  static const LinearGradient sky = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF339AF0), Color(0xFF1B6FAE)],
  );

  /// バナー: スレート（天気図）
  static const LinearGradient slate = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF546E8B), Color(0xFF2C4258)],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.cyan,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.scaffoldBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.deepNavy,
        indicatorColor: AppColors.cyan.withValues(alpha: 0.22),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.aqua);
          }
          return const IconThemeData(color: Colors.white54);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                color: AppColors.aqua, fontSize: 11, fontWeight: FontWeight.bold);
          }
          return const TextStyle(color: Colors.white54, fontSize: 11);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 68,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        indicatorColor: AppColors.aqua,
        dividerColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppColors.primary.withValues(alpha: 0.4),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.deepNavy,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primary),
      dividerTheme: const DividerThemeData(color: AppColors.hairline),
    );
  }
}

/// ホーム画面などで使う、グラデーション背景のバナーカード。
class GradientBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const GradientBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.last.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              height: 1.3)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    color: Colors.white.withValues(alpha: 0.7), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
