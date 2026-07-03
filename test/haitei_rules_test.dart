import 'package:flutter_test/flutter_test.dart';
import 'package:yacht_link/haitei_rules.dart';

// テスト用メンバー生成ヘルパー
Sailor sailor({
  required String id,
  String? name,
  String grade = '3年',
  String position = 'スキッパー',
  String yachtClass = '-',
  String teamRole = '',
  String? cert = '中級',
  bool license = false,
  String gender = '未設定',
}) {
  return Sailor.fromMap(id, {
    'name': name ?? id,
    'grade': grade,
    'position': position,
    'class': yachtClass,
    'teamRole': teamRole,
    'sailingCert': cert,
    'hasBoatLicense': license,
    'gender': gender,
  });
}

/// 指定風域で違反の出ない標準的なレスキュー艇（ハードボート・定員10）
RescueBoatPlan validRescue({
  String certForJumper = '上級',
  int capacity = 10,
  String idPrefix = 'r',
}) {
  return RescueBoatPlan(
    type: 'ハードボート',
    capacity: capacity,
    members: [
      RescueAssignment(
          sailor(id: '$idPrefix-leader', grade: '4年', cert: '中級'),
          RescueRole.leader),
      RescueAssignment(
          sailor(id: '$idPrefix-driver', license: true), RescueRole.driver),
      RescueAssignment(
          sailor(id: '$idPrefix-jumper', cert: certForJumper),
          RescueRole.jumper),
      RescueAssignment(sailor(id: '$idPrefix-a1'), RescueRole.assistant),
      RescueAssignment(sailor(id: '$idPrefix-a2'), RescueRole.assistant),
    ],
  );
}

YachtPlan yacht({required String skipperId, String cert = '上級', String crewId = 'crew1'}) {
  return YachtPlan(
    yachtClass: '470',
    skipper: sailor(id: skipperId, cert: cert),
    crews: [sailor(id: crewId, position: 'クルー')],
  );
}

bool has(List<Finding> findings, String code) =>
    findings.any((f) => f.code == code);

void main() {
  group('風域の判定', () {
    test('境界値', () {
      expect(windBand(0), 0);
      expect(windBand(2.9), 0);
      expect(windBand(3), 1);
      expect(windBand(4.9), 1);
      expect(windBand(5), 2);
      expect(windBand(6.9), 2);
      expect(windBand(7), 3);
      expect(windBand(9.9), 3);
      expect(windBand(10), 4);
    });
  });

  group('出艇中止基準（Ⅰ-4）', () {
    test('平均風速10m/s以上で出艇中止', () {
      final f = runHaiteiCheck(
          cond: const Conditions(aveWind: 10), yachts: [], rescues: []);
      expect(has(f, 'STOP_AVE_WIND'), isTrue);
      expect(verdictLabel(f), '出艇中止');
    });

    test('最大風速12.5m/s以上で出艇中止', () {
      final f = runHaiteiCheck(
          cond: const Conditions(aveWind: 5, maxWind: 12.5),
          yachts: [],
          rescues: []);
      expect(has(f, 'STOP_MAX_WIND'), isTrue);
    });

    test('波高1.5m以上で出艇中止', () {
      final f = runHaiteiCheck(
          cond: const Conditions(aveWind: 2, waveHeight: 1.5),
          yachts: [],
          rescues: []);
      expect(has(f, 'STOP_WAVE'), isTrue);
    });

    test('警報・雷・視界不良・ハーバー要請で出艇中止', () {
      final f = runHaiteiCheck(
          cond: const Conditions(
              aveWind: 2,
              poorVisibility: true,
              warningIssued: true,
              thunder: true,
              harborStopRequest: true),
          yachts: [],
          rescues: []);
      expect(has(f, 'STOP_VISIBILITY'), isTrue);
      expect(has(f, 'STOP_WARNING'), isTrue);
      expect(has(f, 'STOP_THUNDER'), isTrue);
      expect(has(f, 'STOP_HARBOR'), isTrue);
    });
  });

  group('スキッパーの部内帆走資格（Ⅰ-4 出艇基準）', () {
    test('無資格スキッパーはAve.4m/sでは資格不足。有資格の飛び込み要員がいれば条件付き出艇可', () {
      // validRescueの飛び込み要員は上級 → 資格が1つ下なので条件付き出艇可（注意扱い）
      final escorted = runHaiteiCheck(
        cond: const Conditions(aveWind: 4),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [validRescue()],
      );
      expect(has(escorted, 'SKIPPER_CERT'), isFalse);
      expect(has(escorted, 'SKIPPER_CERT_ESCORT'), isTrue);

      // 飛び込み要員が要求資格（初級）を満たさなければ特例は適用されず違反
      final ng = runHaiteiCheck(
        cond: const Conditions(aveWind: 4),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [validRescue(certForJumper: '無資格')],
      );
      expect(has(ng, 'SKIPPER_CERT'), isTrue);
      expect(has(ng, 'SKIPPER_CERT_ESCORT'), isFalse);
    });

    test('初級スキッパー: Ave.4m/sはOK、Ave.6m/sは中級飛び込み要員がいれば条件付き可、2階級上は違反', () {
      final ok = runHaiteiCheck(
        cond: const Conditions(aveWind: 4),
        yachts: [yacht(skipperId: 's1', cert: '初級')],
        rescues: [validRescue(certForJumper: '初級')],
      );
      expect(has(ok, 'SKIPPER_CERT'), isFalse);
      expect(has(ok, 'SKIPPER_CERT_ESCORT'), isFalse);

      // 1つ上の風域（Ave.5〜7）: 中級の飛び込み要員がいるので条件付き出艇可
      final escorted = runHaiteiCheck(
        cond: const Conditions(aveWind: 6),
        yachts: [yacht(skipperId: 's1', cert: '初級')],
        rescues: [validRescue(certForJumper: '中級')],
      );
      expect(has(escorted, 'SKIPPER_CERT'), isFalse);
      expect(has(escorted, 'SKIPPER_CERT_ESCORT'), isTrue);

      // 2つ上の風域相当（無資格でAve.6m/s）は飛び込み要員がいても違反
      final ng = runHaiteiCheck(
        cond: const Conditions(aveWind: 6),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [validRescue(certForJumper: '中級')],
      );
      expect(has(ng, 'SKIPPER_CERT'), isTrue);
    });

    test('上級スキッパーはAve.9m/sでもOK', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 9),
        yachts: [yacht(skipperId: 's1', cert: '上級')],
        rescues: [validRescue()],
      );
      expect(has(f, 'SKIPPER_CERT'), isFalse);
    });

    test('資格未設定は無資格扱い＋警告（上級飛び込み要員がいるため条件付き出艇可になる）', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 4),
        yachts: [
          YachtPlan(
              yachtClass: '470',
              skipper: sailor(id: 's1', cert: '未設定'),
              crews: [sailor(id: 'c1')]),
        ],
        rescues: [validRescue()],
      );
      expect(has(f, 'CERT_UNSET'), isTrue);
      expect(has(f, 'SKIPPER_CERT'), isFalse);
      expect(has(f, 'SKIPPER_CERT_ESCORT'), isTrue);
    });

    test('スキッパー経験のあるOB/OGは上級扱い（Ⅰ-4）', () {
      final ob = sailor(
          id: 'ob1', grade: 'OB/OG', position: 'スキッパー', cert: '未設定');
      expect(ob.effectiveCert, SailingCert.advanced);
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 8),
        yachts: [
          YachtPlan(yachtClass: '470', skipper: ob, crews: [sailor(id: 'c1')]),
        ],
        rescues: [validRescue()],
      );
      expect(has(f, 'SKIPPER_CERT'), isFalse);
    });
  });

  group('レスキュー艇（Ⅰ-6・出艇基準）', () {
    test('ヨットが出るのにレスキューがいなければ違反', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1')],
        rescues: [],
      );
      expect(has(f, 'RESCUE_REQUIRED'), isTrue);
    });

    test('Ave.5〜7m/sはレスキュー1艇につきヨット3艇まで', () {
      final yachts = [
        for (var i = 0; i < 4; i++)
          yacht(skipperId: 's$i', cert: '中級', crewId: 'c$i'),
      ];
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 6),
        yachts: yachts,
        rescues: [validRescue(certForJumper: '中級')],
      );
      expect(has(f, 'RESCUE_RATIO'), isTrue);

      final ok = runHaiteiCheck(
        cond: const Conditions(aveWind: 6),
        yachts: yachts.sublist(0, 3),
        rescues: [validRescue(certForJumper: '中級')],
      );
      expect(has(ok, 'RESCUE_RATIO'), isFalse);
    });

    test('Ave.7〜10m/sはレスキュー1艇につきヨット2艇まで', () {
      final yachts = [
        for (var i = 0; i < 3; i++)
          yacht(skipperId: 's$i', cert: '上級', crewId: 'c$i'),
      ];
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 8),
        yachts: yachts,
        rescues: [validRescue()],
      );
      expect(has(f, 'RESCUE_RATIO'), isTrue);
    });

    test('最少構成: ゴムボートAve.3m/s未満は2人（運転+飛び込み2回生以上）', () {
      final ok = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [
          RescueBoatPlan(type: 'ゴムボート', capacity: 6, members: [
            RescueAssignment(
                sailor(id: 'd1', license: true), RescueRole.driver),
            RescueAssignment(sailor(id: 'j1', grade: '2年'), RescueRole.jumper),
          ]),
        ],
      );
      expect(has(ok, 'RESCUE_TOTAL'), isFalse);
      expect(has(ok, 'RESCUE_JUMPER'), isFalse);

      // 1年生の飛び込み要員は違反
      final ng = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [
          RescueBoatPlan(type: 'ゴムボート', capacity: 6, members: [
            RescueAssignment(
                sailor(id: 'd1', license: true), RescueRole.driver),
            RescueAssignment(sailor(id: 'j1', grade: '1年'), RescueRole.jumper),
          ]),
        ],
      );
      expect(has(ng, 'RESCUE_JUMPER_QUAL'), isTrue);
    });

    test('最少構成: ハードボートAve.5〜7m/sは4人（補助2）', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 6),
        yachts: [yacht(skipperId: 's1', cert: '中級')],
        rescues: [
          RescueBoatPlan(type: 'ハードボート', capacity: 10, members: [
            RescueAssignment(
                sailor(id: 'd1', license: true), RescueRole.driver),
            RescueAssignment(sailor(id: 'j1', cert: '中級'), RescueRole.jumper),
            RescueAssignment(sailor(id: 'a1'), RescueRole.assistant),
          ]),
        ],
      );
      expect(has(f, 'RESCUE_TOTAL'), isTrue); // 3人 < 4人
      expect(has(f, 'RESCUE_ASSIST'), isTrue); // 補助1 < 2
    });

    test('飛び込み要員の資格不足は違反', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 6),
        yachts: [yacht(skipperId: 's1', cert: '中級')],
        rescues: [validRescue(certForJumper: '初級')],
      );
      expect(has(f, 'RESCUE_JUMPER_QUAL'), isTrue);
    });

    test('運転者の船舶免許なしは違反', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [
          RescueBoatPlan(type: 'ゴムボート', capacity: 6, members: [
            RescueAssignment(
                sailor(id: 'd1', license: false), RescueRole.driver),
            RescueAssignment(sailor(id: 'j1', grade: '2年'), RescueRole.jumper),
          ]),
        ],
      );
      expect(has(f, 'RESCUE_DRIVER_LICENSE'), isTrue);
    });

    test('定員: Ave.7m/s未満は定員より2名以上少なく', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 6),
        yachts: [yacht(skipperId: 's1', cert: '中級')],
        rescues: [validRescue(certForJumper: '中級', capacity: 6)], // 乗員5、定員6
      );
      expect(has(f, 'RESCUE_CAPACITY'), isTrue);
    });

    test('定員: Ave.7m/s以上は全員収容可能な空きが必要', () {
      // ヨット2艇=4人、レスキューは定員7で乗員5 → 空き2 < 4 で違反
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 8),
        yachts: [
          yacht(skipperId: 's1', cert: '上級', crewId: 'c1'),
          yacht(skipperId: 's2', cert: '上級', crewId: 'c2'),
        ],
        rescues: [validRescue(capacity: 7)],
      );
      expect(has(f, 'RESCUE_CAPACITY_TOTAL'), isTrue);

      final ok = runHaiteiCheck(
        cond: const Conditions(aveWind: 8),
        yachts: [
          yacht(skipperId: 's1', cert: '上級', crewId: 'c1'),
          yacht(skipperId: 's2', cert: '上級', crewId: 'c2'),
        ],
        rescues: [validRescue(capacity: 10)],
      );
      expect(has(ok, 'RESCUE_CAPACITY_TOTAL'), isFalse);
    });

    test('レスキュー長がいなければ違反', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [
          RescueBoatPlan(type: 'ゴムボート', capacity: 6, members: [
            RescueAssignment(
                sailor(id: 'd1', license: true), RescueRole.driver),
            RescueAssignment(sailor(id: 'j1', grade: '2年'), RescueRole.jumper),
          ]),
        ],
      );
      expect(has(f, 'RESCUE_LEADER_NONE'), isTrue);
    });

    test('継承順位上位（主将）が乗艇しているのに別人がレスキュー長なら警告', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [
          RescueBoatPlan(type: 'ハードボート', capacity: 10, members: [
            RescueAssignment(
                sailor(id: 'lead', grade: '2年'), RescueRole.leader),
            RescueAssignment(
                sailor(id: 'cap', grade: '4年', teamRole: '主将', license: true),
                RescueRole.driver),
            RescueAssignment(sailor(id: 'j1', grade: '2年'), RescueRole.jumper),
            RescueAssignment(sailor(id: 'a1'), RescueRole.assistant),
          ]),
        ],
      );
      expect(has(f, 'RESCUE_LEADER_ORDER'), isTrue);
    });

    test('女性のみのレスキュー艇は警告', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [
          RescueBoatPlan(type: 'ゴムボート', capacity: 6, members: [
            RescueAssignment(
                sailor(id: 'd1', license: true, gender: '女性'),
                RescueRole.driver),
            RescueAssignment(
                sailor(id: 'j1', grade: '2年', gender: '女性'),
                RescueRole.jumper),
          ]),
        ],
      );
      expect(has(f, 'RESCUE_FEMALE_ONLY'), isTrue);
    });
  });

  group('配艇の整合性', () {
    test('同じ人が2箇所に配置されていたら違反', () {
      final dup = sailor(id: 'dup', cert: '中級');
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [
          YachtPlan(yachtClass: '470', skipper: dup, crews: [sailor(id: 'c1')]),
        ],
        rescues: [
          RescueBoatPlan(type: 'ゴムボート', capacity: 6, members: [
            RescueAssignment(dup, RescueRole.driver),
            RescueAssignment(sailor(id: 'j1', grade: '2年'), RescueRole.jumper),
          ]),
        ],
      );
      expect(has(f, 'DUP_MEMBER'), isTrue);
    });

    test('スキッパー未選択は違反・クルー未選択は警告', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [
          const YachtPlan(yachtClass: '470'),
        ],
        rescues: [validRescue()],
      );
      expect(has(f, 'YACHT_NO_SKIPPER'), isTrue);
      expect(has(f, 'YACHT_NO_CREW'), isTrue);
    });
  });

  group('構内練習（Ⅰ-4）', () {
    test('構内は最大4艇まで', () {
      final yachts = [
        for (var i = 0; i < 5; i++)
          yacht(skipperId: 's$i', cert: '無資格', crewId: 'c$i'),
      ];
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2, insideHarbor: true),
        yachts: yachts,
        rescues: [validRescue()],
      );
      expect(has(f, 'HARBOR_MAX4'), isTrue);
      expect(has(f, 'HARBOR_PERMIT'), isTrue);
    });
  });

  group('リマインド', () {
    test('風速7m/s以上は海上での目視確認を要求', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 8),
        yachts: [yacht(skipperId: 's1', cert: '上級')],
        rescues: [validRescue()],
      );
      expect(has(f, 'SEA_CHECK'), isTrue);
    });

    test('11月〜3月はドライ/ウェットスーツの着用リマインド', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [validRescue()],
        date: DateTime(2026, 12, 1),
      );
      expect(has(f, 'REMIND_WEAR'), isTrue);

      final summer = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [validRescue()],
        date: DateTime(2026, 7, 1),
      );
      expect(has(summer, 'REMIND_WEAR'), isFalse);
    });
  });

  group('陸上要員（Ⅱ-1 対策3）', () {
    test('陸上要員がいないと違反、1人以上いればOK', () {
      final ng = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [validRescue()],
      );
      expect(has(ng, 'SHORE_REQUIRED'), isTrue);

      final ok = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [validRescue()],
        shoreStaff: [sailor(id: 'shore1', position: 'マネージャー')],
      );
      expect(has(ok, 'SHORE_REQUIRED'), isFalse);
    });

    test('陸上要員と海上の配置が重複していたら違反', () {
      final dup = sailor(id: 'dup', cert: '上級');
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [
          YachtPlan(yachtClass: '470', skipper: dup, crews: [sailor(id: 'c1')]),
        ],
        rescues: [validRescue()],
        shoreStaff: [dup],
      );
      expect(has(f, 'DUP_MEMBER'), isTrue);
    });
  });

  group('機材連携', () {
    test('修理中・故障中のレスキュー艇は警告', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 2),
        yachts: [yacht(skipperId: 's1', cert: '無資格')],
        rescues: [
          RescueBoatPlan(
            name: '阿尾Ⅱ',
            type: 'ハードボート',
            capacity: 10,
            status: '故障中',
            members: [
              RescueAssignment(sailor(id: 'lead', grade: '4年'), RescueRole.leader),
              RescueAssignment(sailor(id: 'd1', license: true), RescueRole.driver),
              RescueAssignment(sailor(id: 'j1', grade: '2年'), RescueRole.jumper),
              RescueAssignment(sailor(id: 'a1'), RescueRole.assistant),
            ],
          ),
        ],
      );
      expect(has(f, 'RESCUE_BOAT_STATUS'), isTrue);
      // メッセージには艇名が含まれる
      expect(
          f.firstWhere((x) => x.code == 'RESCUE_BOAT_STATUS').message,
          contains('阿尾Ⅱ'));
    });
  });

  group('乗員交代チェック', () {
    test('唯一の免許保持者（運転者）がヨットへ移る交代は注意', () {
      // ヨット: スキッパーX（免許なし）。レスキュー: 運転D（免許・スキッパー・470）と飛び込みJ。
      // X⇔D の交代後、レスキューに免許保持者がいなくなる。
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 4),
        yachts: [
          YachtPlan(
            yachtClass: '470',
            skipper: sailor(id: 'x', cert: '上級', yachtClass: '470'),
          ),
        ],
        rescues: [
          RescueBoatPlan(
            type: 'ゴムボート',
            capacity: 6,
            members: [
              RescueAssignment(
                  sailor(id: 'd', license: true, cert: '上級', yachtClass: '470'),
                  RescueRole.driver),
              RescueAssignment(
                  sailor(id: 'j', cert: '上級', position: 'クルー'),
                  RescueRole.jumper),
            ],
          ),
        ],
        shoreStaff: [sailor(id: 'shore1')],
      );
      expect(has(f, 'SWAP_RISK'), isTrue);
      expect(
          f.firstWhere((x) => x.code == 'SWAP_RISK').message, contains('運転者'));
    });

    test('交代後も基準を満たす場合は注意なし＋サマリー表示', () {
      // X も免許を持っていれば、D と交代しても運転者を確保できる
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 4),
        yachts: [
          YachtPlan(
            yachtClass: '470',
            skipper: sailor(id: 'x', cert: '上級', yachtClass: '470', license: true),
            crews: [sailor(id: 'c', cert: '中級', position: 'クルー', yachtClass: '470')],
          ),
        ],
        rescues: [
          RescueBoatPlan(
            type: 'ゴムボート',
            capacity: 6,
            members: [
              RescueAssignment(
                  sailor(id: 'd', license: true, cert: '上級', yachtClass: '470'),
                  RescueRole.driver),
              RescueAssignment(
                  sailor(id: 'j', cert: '上級', position: 'クルー', yachtClass: '470'),
                  RescueRole.jumper),
            ],
          ),
        ],
        shoreStaff: [sailor(id: 'shore1')],
      );
      expect(has(f, 'SWAP_RISK'), isFalse);
      expect(has(f, 'SWAP_SUMMARY'), isTrue);
    });

    test('資格不足のメンバーがスキッパーに入る交代は注意', () {
      // Ave.8m/s（上級域）。レスキューの D は中級なので、交代でスキッパーに入ると資格不足。
      // （中級＋上級飛び込み要員の特例は、飛び込み要員が確保できる場合のみ）
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 8),
        yachts: [
          YachtPlan(
            yachtClass: '470',
            skipper: sailor(id: 'x', cert: '上級', yachtClass: '470', license: true),
          ),
        ],
        rescues: [
          RescueBoatPlan(
            type: 'ゴムボート',
            capacity: 8,
            members: [
              RescueAssignment(
                  sailor(id: 'd', license: true, cert: '無資格', yachtClass: '470'),
                  RescueRole.driver),
              RescueAssignment(
                  sailor(id: 'j', cert: '上級', position: 'クルー'),
                  RescueRole.jumper),
              RescueAssignment(sailor(id: 'a1', position: 'マネージャー'),
                  RescueRole.assistant),
            ],
          ),
        ],
        shoreStaff: [sailor(id: 'shore1')],
      );
      // D（無資格）が上級域のスキッパーに入る交代は基準を満たさない
      expect(has(f, 'SWAP_RISK'), isTrue);
      expect(f.firstWhere((x) => x.code == 'SWAP_RISK').message,
          contains('資格基準を満たしません'));
    });
  });

  group('問題のない配艇', () {
    test('全条件を満たせば違反・中止なし', () {
      final f = runHaiteiCheck(
        cond: const Conditions(aveWind: 4, maxWind: 6, waveHeight: 0.3),
        yachts: [yacht(skipperId: 's1', cert: '初級')],
        rescues: [validRescue(certForJumper: '初級')],
        shoreStaff: [sailor(id: 'shore1', position: 'マネージャー')],
      );
      expect(f.any((x) => x.severity == Severity.stop), isFalse);
      expect(f.any((x) => x.severity == Severity.violation), isFalse);
      expect(verdictLabel(f), '出艇可（問題なし）');
    });
  });
}
