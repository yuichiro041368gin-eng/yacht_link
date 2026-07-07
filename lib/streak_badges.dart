import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 練習日誌の記録状況から算出するストリーク・バッジ統計。
/// practice_reports の既存データのみで計算するため、
/// スキーマ変更もセキュリティルール変更も不要。
class PracticeStats {
  /// 連続記録週数（今週まだ書いていなくてもストリークは切れない）
  final int weekStreak;

  /// 今週記録した日数（ユニーク日付）
  final int thisWeekDays;

  /// 集計期間内の累計記録日数（ユニーク日付）
  final int totalDays;

  /// 今週の曜日ごとの記録有無（月〜日）
  final List<bool> thisWeekDots;

  final List<PracticeBadge> badges;

  const PracticeStats({
    required this.weekStreak,
    required this.thisWeekDays,
    required this.totalDays,
    required this.thisWeekDots,
    required this.badges,
  });

  int get earnedCount => badges.where((b) => b.earned).length;
}

/// バッジ1個分の定義と獲得状況
class PracticeBadge {
  final String title;
  final String description;
  final IconData icon;
  final bool earned;
  final double progress; // 0.0〜1.0
  final String progressLabel;

  const PracticeBadge({
    required this.title,
    required this.description,
    required this.icon,
    required this.earned,
    required this.progress,
    required this.progressLabel,
  });
}

/// practice_reports のドキュメント（data map のリスト）から統計を計算する。
/// [reports] は各ドキュメントの data。必要フィールド:
/// date('yyyy-MM-dd'), timeSlot('AM'/'PM'),
/// 任意: windSpeedMin/Max, comment_動作 等, scores
PracticeStats computePracticeStats(
  List<Map<String, dynamic>> reports, {
  DateTime? now,
}) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  DateTime mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  // 日付のパースと基本集計
  final Set<DateTime> uniqueDates = {};
  final Map<DateTime, Set<String>> slotsByDate = {};
  int heavyWindLogs = 0; // 平均風速7m/s以上
  int lightWindLogs = 0; // 平均風速4m/s未満
  bool hasPerfectLog = false;

  const commentKeys = [
    'comment_動作',
    'comment_セーリング',
    'comment_スタート',
    'comment_コース',
  ];

  for (final r in reports) {
    final dateStr = r['date'];
    if (dateStr is! String) continue;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) continue;
    final date = DateTime(parsed.year, parsed.month, parsed.day);

    uniqueDates.add(date);
    final slot = r['timeSlot'];
    if (slot is String) {
      (slotsByDate[date] ??= {}).add(slot);
    }

    final min = double.tryParse('${r['windSpeedMin']}');
    final max = double.tryParse('${r['windSpeedMax']}');
    if (min != null && max != null) {
      final avg = (min + max) / 2;
      if (avg >= 7.0) heavyWindLogs++;
      if (avg < 4.0) lightWindLogs++;
    }

    if (!hasPerfectLog) {
      hasPerfectLog = commentKeys.every((k) {
        final v = r[k];
        return v is String && v.trim().isNotEmpty;
      });
    }
  }

  // 週ストリーク: 記録のある週（月曜起点）が何週連続しているか。
  // 今週まだ書いていなくても、先週まで続いていればストリーク継続扱い。
  final weekStarts = uniqueDates.map(mondayOf).toSet();
  final thisMonday = mondayOf(today);
  DateTime cursor = thisMonday;
  if (!weekStarts.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 7));
  }
  int weekStreak = 0;
  while (weekStarts.contains(cursor)) {
    weekStreak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }

  // 今週のドット（月〜日）
  final thisWeekDots = List<bool>.generate(7, (i) {
    return uniqueDates.contains(thisMonday.add(Duration(days: i)));
  });
  final thisWeekDays = thisWeekDots.where((d) => d).length;

  // 午前も午後も記録した日数
  final fullDays =
      slotsByDate.values.where((s) => s.contains('AM') && s.contains('PM')).length;

  PracticeBadge makeBadge(String title, String desc, IconData icon, int value, int target) {
    return PracticeBadge(
      title: title,
      description: desc,
      icon: icon,
      earned: value >= target,
      progress: (value / target).clamp(0.0, 1.0),
      progressLabel: '$value / $target',
    );
  }

  final badges = <PracticeBadge>[
    makeBadge('継続の炎', '4週連続で日誌を記録する', Icons.local_fire_department, weekStreak, 4),
    makeBadge('記録の鉄人', '累計30日分の日誌を記録する', Icons.edit_calendar, uniqueDates.length, 30),
    makeBadge('ストームライダー', '強風(平均7m/s以上)の日誌を3回記録する', Icons.storm, heavyWindLogs, 3),
    makeBadge('微風の職人', '微風(平均4m/s未満)の日誌を10回記録する', Icons.air, lightWindLogs, 10),
    makeBadge('フルデイセーラー', '午前も午後も記録した日を10日つくる', Icons.wb_twilight, fullDays, 10),
    makeBadge('パーフェクトログ', '1つの日誌で全カテゴリのコメントを記入する', Icons.checklist, hasPerfectLog ? 1 : 0, 1),
  ];

  return PracticeStats(
    weekStreak: weekStreak,
    thisWeekDays: thisWeekDays,
    totalDays: uniqueDates.length,
    thisWeekDots: thisWeekDots,
    badges: badges,
  );
}

/// ホーム画面に置くストリーク+バッジのカード
class StreakBadgesCard extends StatelessWidget {
  final PracticeStats stats;

  const StreakBadgesCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final bool onFire = stats.weekStreak > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 炎アイコン: ストリーク中はオレンジグラデ、ゼロならグレー
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: onFire
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFFB03A), Color(0xFFFF6B35)],
                        )
                      : null,
                  color: onFire ? null : AppColors.hairline,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: onFire
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF6B35).withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.local_fire_department,
                  color: onFire ? Colors.white : Colors.grey,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      onFire ? '${stats.weekStreak}週連続 記録中！' : '日誌を書いてストリークを始めよう',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '今週 ${stats.thisWeekDays}日 ・ 累計 ${stats.totalDays}日 ・ バッジ ${stats.earnedCount}/${stats.badges.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              _WeekDots(dots: stats.thisWeekDots),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stats.badges.length,
              separatorBuilder: (_, i) => const SizedBox(width: 14),
              itemBuilder: (context, index) =>
                  _BadgeChip(badge: stats.badges[index]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 今週の記録を月〜日の7つのドットで表示
class _WeekDots extends StatelessWidget {
  final List<bool> dots;
  const _WeekDots({required this.dots});

  @override
  Widget build(BuildContext context) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(7, (i) {
        return Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dots[i] ? AppColors.cyan : AppColors.hairline,
                ),
              ),
              const SizedBox(height: 2),
              Text(labels[i],
                  style: TextStyle(
                      fontSize: 8,
                      color: dots[i] ? AppColors.primary : Colors.grey)),
            ],
          ),
        );
      }),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final PracticeBadge badge;
  const _BadgeChip({required this.badge});

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(badge.icon,
                color: badge.earned ? AppColors.primary : Colors.grey, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(badge.title, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(badge.description),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: badge.progress,
                minHeight: 8,
                backgroundColor: AppColors.hairline,
                color: badge.earned ? const Color(0xFF12B886) : AppColors.cyan,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              badge.earned ? '獲得済み！' : 'あと少し: ${badge.progressLabel}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: badge.earned ? const Color(0xFF12B886) : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showDetail(context),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: badge.earned ? AppGradients.cyanCta : null,
                color: badge.earned ? null : AppColors.scaffoldBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: badge.earned
                      ? Colors.transparent
                      : AppColors.hairline,
                  width: 1.5,
                ),
                boxShadow: badge.earned
                    ? [
                        BoxShadow(
                          color: AppColors.cyan.withValues(alpha: 0.35),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                badge.icon,
                size: 24,
                color: badge.earned ? Colors.white : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              badge.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: badge.earned ? AppColors.navy : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
