/// 配艇チェッカーの判定ロジック。
///
/// 富山大学体育会ヨット部「安全対策マニュアル（令和8年7月改訂）」の
/// Ⅰ-4（出艇判断・部内帆走資格・出艇基準・出艇中止基準）、
/// Ⅰ-6（レスキュー艇の最少構成・定員・レスキュー長）などをコード化したもの。
/// UI・Firebaseに依存しない純Dartなので単体テストで検証できる。
library;

// ---------------------------------------------------------------------------
// 部内帆走資格
// ---------------------------------------------------------------------------

enum SailingCert { none, beginner, intermediate, advanced }

const Map<SailingCert, String> _certLabels = {
  SailingCert.none: '無資格',
  SailingCert.beginner: '初級',
  SailingCert.intermediate: '中級',
  SailingCert.advanced: '上級',
};

String sailingCertLabel(SailingCert cert) => _certLabels[cert]!;

SailingCert sailingCertFromLabel(String? label) {
  switch (label) {
    case '初級':
      return SailingCert.beginner;
    case '中級':
      return SailingCert.intermediate;
    case '上級':
      return SailingCert.advanced;
    default:
      return SailingCert.none;
  }
}

// ---------------------------------------------------------------------------
// 風域（出艇基準の区分）
// ---------------------------------------------------------------------------

/// 出艇基準の風域区分。0: Ave.3m/s未満, 1: 3〜5m/s未満, 2: 5〜7m/s未満,
/// 3: 7〜10m/s未満, 4: 出艇中止域（Ave.10m/s以上）
int windBand(double aveWind) {
  if (aveWind < 3) return 0;
  if (aveWind < 5) return 1;
  if (aveWind < 7) return 2;
  if (aveWind < 10) return 3;
  return 4;
}

const List<String> _bandLabels = [
  'Ave.3m/s未満',
  'Ave.3〜5m/s未満',
  'Ave.5〜7m/s未満',
  'Ave.7〜10m/s未満',
  '出艇中止域（Ave.10m/s以上）',
];

String windBandLabel(int band) => _bandLabels[band];

/// 各風域でスキッパーに要求される最低資格（出艇基準表）
SailingCert requiredSkipperCert(int band) {
  switch (band) {
    case 0:
      return SailingCert.none; // 制限なし
    case 1:
      return SailingCert.beginner;
    case 2:
      return SailingCert.intermediate;
    default:
      return SailingCert.advanced;
  }
}

// ---------------------------------------------------------------------------
// 部員（メンバー）
// ---------------------------------------------------------------------------

class Sailor {
  final String id;
  final String name;
  final String grade; // '1年'〜'4年', '院生', 'OB/OG', 'コーチ'
  final String position; // 'スキッパー', 'クルー', '両方' など
  final String yachtClass; // '470', 'Snipe', '両方' など（乗艇クラス）
  final String teamRole; // '主将 / 会計' のような自由記述
  final SailingCert cert;
  final bool certSet; // プロフィールで資格が設定済みか
  final bool hasBoatLicense; // 小型船舶操縦免許
  final String gender; // '男性', '女性', '未設定'

  const Sailor({
    required this.id,
    required this.name,
    this.grade = '-',
    this.position = '-',
    this.yachtClass = '-',
    this.teamRole = '',
    this.cert = SailingCert.none,
    this.certSet = false,
    this.hasBoatLicense = false,
    this.gender = '未設定',
  });

  factory Sailor.fromMap(String id, Map<String, dynamic> data) {
    final rawCert = data['sailingCert'] as String?;
    final certSet = rawCert != null && rawCert != '未設定';
    return Sailor(
      id: id,
      name: data['name'] ?? '名前未設定',
      grade: data['grade'] ?? '-',
      position: data['position'] ?? '-',
      yachtClass: data['class'] ?? '-',
      teamRole: data['teamRole'] ?? '',
      cert: sailingCertFromLabel(rawCert),
      certSet: certSet,
      hasBoatLicense: data['hasBoatLicense'] == true,
      gender: data['gender'] ?? '未設定',
    );
  }

  /// マニュアルⅠ-4: スキッパー経験のあるOB・OGは上級帆走者として扱う
  SailingCert get effectiveCert {
    if (!certSet && grade == 'OB/OG' && position.contains('スキッパー')) {
      return SailingCert.advanced;
    }
    return cert;
  }

  /// 飛び込み要員の「2回生以上」判定（1年生のみ対象外）
  bool get isSecondYearOrAbove => grade != '1年';

  /// レスキュー長の継承順位（Ⅰ-6の表）。数値が小さいほど優先。
  /// 1:主将 2:クラス長 3:4年 4:3年 5:2年 6:その他
  int get leaderPriority {
    if (teamRole.contains('主将')) return 1;
    if (teamRole.contains('クラス長') || teamRole.contains('クラスリーダー')) {
      return 2;
    }
    switch (grade) {
      case '4年':
        return 3;
      case '3年':
        return 4;
      case '2年':
        return 5;
    }
    return 6;
  }
}

// ---------------------------------------------------------------------------
// 配艇プラン
// ---------------------------------------------------------------------------

class YachtPlan {
  final String yachtClass; // '470' or 'スナイプ'
  final Sailor? skipper;
  final List<Sailor> crews;

  const YachtPlan({
    required this.yachtClass,
    this.skipper,
    this.crews = const [],
  });

  int get crewCount => (skipper != null ? 1 : 0) + crews.length;
}

enum RescueRole { leader, driver, jumper, assistant }

const Map<RescueRole, String> rescueRoleLabels = {
  RescueRole.leader: 'レスキュー長',
  RescueRole.driver: '運転',
  RescueRole.jumper: '飛び込み要員',
  RescueRole.assistant: '補助・見張り',
};

class RescueAssignment {
  final Sailor sailor;
  final RescueRole role;
  const RescueAssignment(this.sailor, this.role);
}

class RescueBoatPlan {
  final String name; // 機材に登録された艇名（例: 'VSR', '阿尾Ⅱ'）
  final String type; // 'ゴムボート' or 'ハードボート'
  final int capacity; // 定員
  final String? status; // 機材管理上の状態（'使用可' / '修理中' / '故障中'）
  final List<RescueAssignment> members;

  const RescueBoatPlan({
    this.name = '',
    required this.type,
    required this.capacity,
    this.status,
    this.members = const [],
  });

  bool get isRubberBoat => type == 'ゴムボート';
}

class Conditions {
  final double aveWind; // 平均風速 m/s
  final double maxWind; // 最大風速 m/s
  final double waveHeight; // 波高 m
  final bool poorVisibility; // 視界2000m以下
  final bool warningIssued; // 警報・注意報の発令
  final bool thunder; // 雷注意報・雷鳴
  final bool harborStopRequest; // ハーバーからの中止要請
  final bool insideHarbor; // 構内練習

  const Conditions({
    required this.aveWind,
    this.maxWind = 0,
    this.waveHeight = 0,
    this.poorVisibility = false,
    this.warningIssued = false,
    this.thunder = false,
    this.harborStopRequest = false,
    this.insideHarbor = false,
  });
}

// ---------------------------------------------------------------------------
// チェック結果
// ---------------------------------------------------------------------------

enum Severity { stop, violation, warning, info }

class Finding {
  final Severity severity;
  final String code; // テスト・集計用の安定した識別子
  final String rule; // マニュアルの該当箇所
  final String message;

  const Finding({
    required this.severity,
    required this.code,
    required this.rule,
    required this.message,
  });
}

String verdictLabel(List<Finding> findings) {
  if (findings.any((f) => f.severity == Severity.stop)) return '出艇中止';
  if (findings.any((f) => f.severity == Severity.violation)) {
    return '違反あり（配艇の見直しが必要）';
  }
  if (findings.any((f) => f.severity == Severity.warning)) {
    return '出艇可（注意事項あり）';
  }
  return '出艇可（問題なし）';
}

// ---------------------------------------------------------------------------
// 交代チェック用の適合判定ヘルパー
// ---------------------------------------------------------------------------

String _normalizedClass(String c) {
  final lower = c.toLowerCase();
  if (lower.contains('470')) return '470';
  if (lower.contains('snipe') || c.contains('スナイプ')) return 'snipe';
  return c;
}

/// メンバーが指定クラスのヨットに乗れるか（プロフィールの艇種で判定）
bool _canSailClass(Sailor s, String yachtClass) {
  if (s.yachtClass == '両方') return true;
  return _normalizedClass(s.yachtClass) == _normalizedClass(yachtClass);
}

/// メンバーが指定ポジション（スキッパー/クルー）に就けるか
bool _canTakePosition(Sailor s, bool skipperSlot) {
  if (s.position == '両方') return true;
  return skipperSlot ? s.position == 'スキッパー' : s.position == 'クルー';
}

/// 指定風域の要求資格を満たす飛び込み要員がレスキュー艇団にいるか
bool _fleetHasQualifiedJumper(List<RescueBoatPlan> rescues, int band) {
  if (band < 1) return false;
  final req = requiredSkipperCert(band);
  for (final r in rescues) {
    for (final m in r.members) {
      if (m.role == RescueRole.jumper &&
          m.sailor.effectiveCert.index >= req.index) {
        return true;
      }
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// チェック本体
// ---------------------------------------------------------------------------

List<Finding> runHaiteiCheck({
  required Conditions cond,
  required List<YachtPlan> yachts,
  required List<RescueBoatPlan> rescues,
  List<Sailor> shoreStaff = const [],
  DateTime? date,
}) {
  final findings = <Finding>[];
  void add(Severity severity, String code, String rule, String message) {
    findings.add(
        Finding(severity: severity, code: code, rule: rule, message: message));
  }

  String num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  // 艇名が登録されていれば艇名で表示する
  String rescueLabel(int i, RescueBoatPlan r) =>
      'レスキュー${i + 1}（${r.name.isNotEmpty ? r.name : r.type}）';

  // --- 1. 出艇中止基準（Ⅰ-4） ---
  if (cond.aveWind >= 10) {
    add(Severity.stop, 'STOP_AVE_WIND', 'Ⅰ-4 出艇中止基準',
        '平均風速 ${num(cond.aveWind)}m/s は Ave.10m/s 以上のため出艇中止');
  }
  if (cond.maxWind >= 12.5) {
    add(Severity.stop, 'STOP_MAX_WIND', 'Ⅰ-4 出艇中止基準',
        '最大風速 ${num(cond.maxWind)}m/s は Max12.5m/s 以上のため出艇中止');
  }
  if (cond.waveHeight >= 1.5) {
    add(Severity.stop, 'STOP_WAVE', 'Ⅰ-4 出艇中止基準',
        '波高 ${num(cond.waveHeight)}m は 1.5m 以上のため出艇中止');
  }
  if (cond.poorVisibility) {
    add(Severity.stop, 'STOP_VISIBILITY', 'Ⅰ-4 出艇中止基準',
        '海上の視界が2000m以下のため出艇中止');
  }
  if (cond.warningIssued) {
    add(Severity.stop, 'STOP_WARNING', 'Ⅰ-4 出艇中止基準',
        '射水市の警報・注意報（大雨、高潮、大雪、強風、波浪など）発令中のため出艇中止');
  }
  if (cond.thunder) {
    add(Severity.stop, 'STOP_THUNDER', 'Ⅰ-4 出艇中止基準',
        '雷注意報の発令中または雷鳴確認のため出艇中止（富山市・高岡市・氷見市の情報も参照）');
  }
  if (cond.harborStopRequest) {
    add(Severity.stop, 'STOP_HARBOR', 'Ⅰ-4 出艇中止基準',
        'ハーバーから出艇中止の要請があるため出艇中止');
  }

  final band = windBand(cond.aveWind);

  // --- 2. メンバー重複チェック ---
  final seen = <String, String>{};
  void checkDup(Sailor sailor, String place) {
    final prev = seen[sailor.id];
    if (prev != null) {
      add(Severity.violation, 'DUP_MEMBER', '配艇の整合性',
          '${sailor.name} が「$prev」と「$place」に重複して配置されています');
    } else {
      seen[sailor.id] = place;
    }
  }

  for (var i = 0; i < yachts.length; i++) {
    final y = yachts[i];
    final label = 'ヨット${i + 1}（${y.yachtClass}）';
    if (y.skipper != null) checkDup(y.skipper!, label);
    for (final c in y.crews) {
      checkDup(c, label);
    }
  }
  for (var i = 0; i < rescues.length; i++) {
    final r = rescues[i];
    final label = rescueLabel(i, r);
    for (final m in r.members) {
      checkDup(m.sailor, label);
    }
  }
  for (final s in shoreStaff) {
    checkDup(s, '陸上要員');
  }

  // --- 3. ヨット側のチェック ---
  if (yachts.isEmpty) {
    add(Severity.warning, 'NO_YACHT', '配艇', 'ヨットが1艇も登録されていません');
  }
  for (var i = 0; i < yachts.length; i++) {
    final y = yachts[i];
    final label = 'ヨット${i + 1}（${y.yachtClass}）';
    final skipper = y.skipper;
    if (skipper == null) {
      add(Severity.violation, 'YACHT_NO_SKIPPER', '配艇', '$label: スキッパーが未選択です');
    } else {
      if (!skipper.certSet && skipper.effectiveCert == SailingCert.none) {
        add(Severity.warning, 'CERT_UNSET', 'Ⅰ-4 部内帆走資格',
            '$label: ${skipper.name} の帆走資格が未設定のため「無資格」として判定します（プロフィールで設定してください）');
      }
      if (band <= 3) {
        final required = requiredSkipperCert(band);
        final eff = skipper.effectiveCert;
        if (eff.index < required.index) {
          // 特例: 資格が基準の1つ下でも、その風域の要求資格を満たす
          // 飛び込み要員がレスキューに配置されていれば条件付きで出艇可とする
          if (eff.index == required.index - 1 &&
              _fleetHasQualifiedJumper(rescues, band)) {
            add(Severity.warning, 'SKIPPER_CERT_ESCORT', 'Ⅰ-4 出艇基準（条件付き）',
                '$label: ${skipper.name}（${sailingCertLabel(eff)}）は${windBandLabel(band)}の基準'
                '「${sailingCertLabel(required)}」の1つ下の資格ですが、'
                '${sailingCertLabel(required)}以上の飛び込み要員がレスキューにいるため条件付きで出艇可とします');
          } else {
            add(Severity.violation, 'SKIPPER_CERT', 'Ⅰ-4 出艇基準（部内帆走資格）',
                '$label: ${windBandLabel(band)}では「${sailingCertLabel(required)}」以上のスキッパーが必要です'
                '（${skipper.name}: ${sailingCertLabel(eff)}）');
          }
        }
      }
      if (skipper.position == 'クルー') {
        add(Severity.warning, 'SKIPPER_POSITION', '配艇',
            '$label: ${skipper.name} のポジションは「クルー」です。スキッパー配置が正しいか確認してください');
      }
    }
    if (y.crews.isEmpty) {
      add(Severity.warning, 'YACHT_NO_CREW', '配艇',
          '$label: クルーが未選択です（470・スナイプは2人乗り）');
    }
  }

  // --- 4. レスキュー艇のチェック（Ⅰ-6） ---
  final yachtCount = yachts.length;
  final sailorCount = yachts.fold<int>(0, (p, y) => p + y.crewCount);

  if (yachtCount > 0 && rescues.isEmpty) {
    add(Severity.violation, 'RESCUE_REQUIRED', 'Ⅰ-6 レスキュー艇',
        '練習を行う際はレスキュー艇を必ず出艇させること（天候・風の強弱に関わらず）');
  }

  // レスキュー1艇あたりのヨット数の上限
  if (rescues.isNotEmpty && band <= 3) {
    if (band == 2 && yachtCount > rescues.length * 3) {
      add(Severity.violation, 'RESCUE_RATIO', 'Ⅰ-4 出艇基準',
          'Ave.5〜7m/s ではレスキュー1艇につきヨットは3艇まで'
          '（現在: レスキュー${rescues.length}艇に対しヨット$yachtCount艇）');
    }
    if (band == 3 && yachtCount > rescues.length * 2) {
      add(Severity.violation, 'RESCUE_RATIO', 'Ⅰ-4 出艇基準',
          'Ave.7〜10m/s ではレスキュー1艇につきヨットは2艇まで'
          '（現在: レスキュー${rescues.length}艇に対しヨット$yachtCount艇）');
    }
  }

  // 各艇の最少構成
  if (band <= 3) {
    for (var i = 0; i < rescues.length; i++) {
      final r = rescues[i];
      final label = rescueLabel(i, r);
      final members = r.members;

      // 機材管理上の状態チェック
      if (r.status != null && r.status != '使用可') {
        add(Severity.warning, 'RESCUE_BOAT_STATUS', '機材管理',
            '$label: 機材管理で「${r.status}」と登録されています。使用できる状態か確認してください');
      }
      final drivers = members.where((m) => m.role == RescueRole.driver).toList();
      final jumpers = members.where((m) => m.role == RescueRole.jumper).toList();
      final assistants =
          members.where((m) => m.role == RescueRole.assistant).toList();

      final isGom = r.isRubberBoat;
      final minTotal = (isGom ? const [2, 2, 3, 3] : const [3, 3, 4, 4])[band];
      final minAssist = (isGom ? const [0, 0, 1, 1] : const [1, 1, 2, 2])[band];

      if (members.length < minTotal) {
        add(Severity.violation, 'RESCUE_TOTAL', 'Ⅰ-4 出艇基準（レスキュー最少構成）',
            '$label: 乗員${members.length}人は${windBandLabel(band)}の最少構成 $minTotal人 を下回っています');
      }
      if (drivers.isEmpty) {
        add(Severity.violation, 'RESCUE_DRIVER', 'Ⅰ-4 出艇基準（レスキュー最少構成）',
            '$label: 運転者が割り当てられていません');
      }
      for (final d in drivers) {
        if (!d.sailor.hasBoatLicense) {
          add(Severity.violation, 'RESCUE_DRIVER_LICENSE', 'Ⅰ-6 レスキュー艇（運転者）',
              '$label: 運転者 ${d.sailor.name} の小型船舶免許が確認できません（運転者は免許携帯必須）');
        }
      }
      if (band == 0) {
        if (jumpers.isEmpty) {
          add(Severity.violation, 'RESCUE_JUMPER', 'Ⅰ-4 出艇基準（レスキュー最少構成）',
              '$label: 飛び込み要員（2回生以上）が割り当てられていません');
        } else if (!jumpers.any((j) => j.sailor.isSecondYearOrAbove)) {
          add(Severity.violation, 'RESCUE_JUMPER_QUAL', 'Ⅰ-4 出艇基準（レスキュー最少構成）',
              '$label: 飛び込み要員は2回生以上である必要があります');
        }
      } else {
        final req = requiredSkipperCert(band);
        if (jumpers.isEmpty) {
          add(Severity.violation, 'RESCUE_JUMPER', 'Ⅰ-4 出艇基準（レスキュー最少構成）',
              '$label: 飛び込み要員（${sailingCertLabel(req)}以上）が割り当てられていません');
        } else if (!jumpers
            .any((j) => j.sailor.effectiveCert.index >= req.index)) {
          add(Severity.violation, 'RESCUE_JUMPER_QUAL', 'Ⅰ-4 出艇基準（レスキュー最少構成）',
              '$label: ${windBandLabel(band)}の飛び込み要員は「${sailingCertLabel(req)}」以上が必要です');
        }
      }
      if (assistants.length < minAssist) {
        add(Severity.violation, 'RESCUE_ASSIST', 'Ⅰ-4 出艇基準（レスキュー最少構成）',
            '$label: 補助が$minAssist人必要です（現在${assistants.length}人）');
      }

      // 定員（Ⅰ-6）
      if (r.capacity <= 0) {
        add(Severity.warning, 'RESCUE_CAPACITY_UNSET', 'Ⅰ-6 レスキュー艇（定員）',
            '$label: 定員が未入力のため定員チェックができません');
      } else if (cond.aveWind < 7 && members.length > r.capacity - 2) {
        add(Severity.violation, 'RESCUE_CAPACITY', 'Ⅰ-6 レスキュー艇（定員）',
            '$label: Ave.7m/s未満ではレスキュー乗員は定員より2名以上少なくすること'
            '（定員${r.capacity}人に対し乗員${members.length}人）');
      }

      // 男女比（Ⅰ-6: 特に女性のみにならないようにする）
      if (members.isNotEmpty &&
          members.every((m) => m.sailor.gender == '女性')) {
        add(Severity.warning, 'RESCUE_FEMALE_ONLY', 'Ⅰ-6 レスキュー艇',
            '$label: 乗員が女性のみになっています（男女比を考慮すること）');
      }
    }

    // Ave.7m/s以上: 事故時に全員を一度に収容できる救助艇数を確保
    if (band == 3 && rescues.isNotEmpty) {
      final spare = rescues.fold<int>(
          0, (p, r) => p + (r.capacity - r.members.length));
      if (spare < sailorCount) {
        add(Severity.violation, 'RESCUE_CAPACITY_TOTAL', 'Ⅰ-6 レスキュー艇（定員）',
            'Ave.7m/s以上では事故発生時にヨット乗員全員（$sailorCount人）を一度に収容できる救助艇数が必要です'
            '（現在の空き: $spare人分）');
      }
    }

    // レスキュー長（Ⅰ-6）
    if (rescues.isNotEmpty) {
      final allRescueMembers = [for (final r in rescues) ...r.members];
      final leaders =
          allRescueMembers.where((m) => m.role == RescueRole.leader).toList();
      if (leaders.isEmpty) {
        add(Severity.violation, 'RESCUE_LEADER_NONE', 'Ⅰ-6 レスキュー艇（レスキュー長）',
            'レスキュー長が割り当てられていません（運転者・飛び込み要員との兼任は不可）');
      } else if (leaders.length > 1) {
        add(Severity.warning, 'RESCUE_LEADER_MULTI', 'Ⅰ-6 レスキュー艇（レスキュー長）',
            'レスキュー長が${leaders.length}人割り当てられています。指揮系統を明確にするため通常は1人にしてください');
      } else {
        final leader = leaders.first.sailor;
        Sailor best = leader;
        for (final m in allRescueMembers) {
          if (m.sailor.leaderPriority < best.leaderPriority) best = m.sailor;
        }
        if (best.id != leader.id &&
            best.leaderPriority < leader.leaderPriority) {
          add(Severity.warning, 'RESCUE_LEADER_ORDER', 'Ⅰ-6 レスキュー艇（継承順位）',
              '継承順位（主将→クラス長→4年→3年→2年）上位の ${best.name} がレスキューに乗艇しています。'
              'レスキュー長を ${leader.name} とする配置で正しいか確認してください');
        }
      }
    }
  }

  // --- 5. 陸上要員（Ⅱ-1 対策3） ---
  if (yachts.isNotEmpty && shoreStaff.isEmpty) {
    add(Severity.violation, 'SHORE_REQUIRED', 'Ⅱ-1 対策3 陸上からの情報共有',
        '陸上要員が設定されていません。陸上に1名以上待機させ、気象情報を10分に1度確認して海上へ伝達すること');
  }

  // --- 6. 構内練習（Ⅰ-4） ---
  if (cond.insideHarbor) {
    if (yachtCount > 4) {
      add(Severity.violation, 'HARBOR_MAX4', 'Ⅰ-4 出艇判断',
          '構内で練習する際は最大4艇までです（現在$yachtCount艇）');
    }
    add(Severity.warning, 'HARBOR_PERMIT', 'Ⅰ-4 出艇判断',
        '構内練習はハーバーマスターの許可を必ず取り、レスキュー艇も出して救助できるようにしておくこと');
  }

  // --- 7. 乗員交代チェック ---
  // 練習中にヨットとレスキュー艇の乗員を交代する場合を想定し、
  // 「同じポジション・同じ艇種同士でのみ交代する」前提で全組み合わせを検証する。
  // 交代後に運転者（船舶免許）・飛び込み要員・レスキュー長・スキッパー資格が
  // 維持できない組み合わせを注意として列挙する。
  if (band <= 3 && yachts.isNotEmpty && rescues.isNotEmpty) {
    var eligiblePairs = 0;
    var riskyPairs = 0;

    for (var yi = 0; yi < yachts.length; yi++) {
      final y = yachts[yi];
      final yLabel = 'ヨット${yi + 1}（${y.yachtClass}）';
      final slots = <(Sailor, bool)>[
        if (y.skipper != null) (y.skipper!, true),
        for (final c in y.crews) (c, false),
      ];

      for (final (x, isSkipperSlot) in slots) {
        for (var ri = 0; ri < rescues.length; ri++) {
          final r = rescues[ri];
          final rLabel = rescueLabel(ri, r);

          for (final m in r.members) {
            final swapIn = m.sailor; // ヨットに乗り込む側（レスキューから）
            if (!_canTakePosition(swapIn, isSkipperSlot)) continue;
            if (!_canSailClass(swapIn, y.yachtClass)) continue;
            eligiblePairs++;

            final problems = <String>[];

            // 交代後のレスキュー乗員（運転・飛び込み候補のプール。
            // レスキュー長は兼任不可のため候補から除く）
            final pool = <Sailor>[
              for (final mm in r.members)
                if (mm.sailor.id != swapIn.id && mm.role != RescueRole.leader)
                  mm.sailor,
              x, // ヨットから降りてレスキューに乗る側
            ];
            final licensed = pool.where((s) => s.hasBoatLicense).toList();
            final jumperReqLabel =
                band == 0 ? '2回生以上' : '${sailingCertLabel(requiredSkipperCert(band))}以上';
            bool jumperOk(Sailor s) => band == 0
                ? s.isSecondYearOrAbove
                : s.effectiveCert.index >= requiredSkipperCert(band).index;
            final jumperCandidates = pool.where(jumperOk).toList();

            if (licensed.isEmpty) {
              problems.add('船舶免許保持者がいなくなり運転者を確保できません');
            }
            if (jumperCandidates.isEmpty) {
              problems.add('飛び込み要員（$jumperReqLabel）を確保できません');
            }
            if (problems.isEmpty &&
                licensed.length == 1 &&
                jumperCandidates.length == 1 &&
                licensed.first.id == jumperCandidates.first.id) {
              problems.add('運転者と飛び込み要員を1人で兼ねることになります');
            }

            // レスキュー長がヨットへ移ってしまう場合
            if (m.role == RescueRole.leader) {
              final otherLeaders = [
                for (final rr in rescues) ...rr.members
              ].where((mm) =>
                  mm.role == RescueRole.leader && mm.sailor.id != swapIn.id);
              if (otherLeaders.isEmpty) {
                problems.add('レスキュー長が海上のレスキューから不在になります（継承順位に従い再選任が必要）');
              }
            }

            // 交代後の新しいスキッパーの資格
            if (isSkipperSlot) {
              final required = requiredSkipperCert(band);
              final eff = swapIn.effectiveCert;
              if (eff.index < required.index) {
                // 特例（1つ下の資格＋有資格飛び込み要員）も交代後の構成で判定する
                final jumperAfterSwap = jumperCandidates.isNotEmpty ||
                    [
                      for (var oi = 0; oi < rescues.length; oi++)
                        if (oi != ri) ...rescues[oi].members
                    ].any((mm) => mm.role == RescueRole.jumper && jumperOk(mm.sailor));
                final canEscort =
                    band >= 1 && eff.index == required.index - 1 && jumperAfterSwap;
                if (!canEscort) {
                  problems.add(
                      '交代後のスキッパー ${swapIn.name}（${sailingCertLabel(eff)}）が${windBandLabel(band)}の資格基準を満たしません');
                }
              }
            }

            if (problems.isNotEmpty) {
              riskyPairs++;
              add(Severity.warning, 'SWAP_RISK', '乗員交代チェック',
                  '交代注意: $yLabel ${x.name}（${isSkipperSlot ? 'スキッパー' : 'クルー'}）⇔ $rLabel ${swapIn.name}: ${problems.join('。')}');
            }
          }
        }
      }
    }

    if (eligiblePairs > 0) {
      add(Severity.info, 'SWAP_SUMMARY', '乗員交代チェック',
          '同ポジション・同艇種で交代し得る組み合わせは$eligiblePairs通りです'
          '${riskyPairs == 0 ? '（すべて交代後も基準を満たします）' : '（うち$riskyPairs通りは交代注意）'}');
    }
  }

  // --- 8. 手順のリマインド ---
  if (band <= 3 && (cond.aveWind >= 7 || cond.waveHeight >= 1.0)) {
    add(Severity.warning, 'SEA_CHECK', 'Ⅱ-1 対策1',
        '風速7m/s以上または波高1.0m以上が予想される場合は、出艇前にレスキュー艇で直接海上にて目視確認を行うこと');
  }
  add(Severity.info, 'REMIND_GEAR', 'Ⅰ-5 装備',
      'ライフジャケット・笛・シーナイフ・シャックルキーの携帯を出艇前ミーティングで全員分確認する');
  add(Severity.info, 'REMIND_REPORT', 'Ⅰ-1 出艇・着艇の報告',
      '気象係は「ヨット部OB会現役支援チーム＋現役」へ気象情報を送り出艇許可を得る。マリーナへ出艇・着艇を申告する');
  if (date != null && (date.month >= 11 || date.month <= 3)) {
    add(Severity.info, 'REMIND_WEAR', 'Ⅰ-5 装備',
        '11月〜3月はドライスーツまたはウエットスーツを着用する');
  }

  return findings;
}
