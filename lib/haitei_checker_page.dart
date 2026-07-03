import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'haitei_rules.dart';

/// 配艇チェッカー
/// 出艇前に、その日の配艇案が安全マニュアル（Ⅰ-4 出艇基準、Ⅰ-6 レスキュー艇 等）
/// を満たしているかをチェックするページ。
class HaiteiCheckerPage extends StatefulWidget {
  const HaiteiCheckerPage({super.key});

  @override
  State<HaiteiCheckerPage> createState() => _HaiteiCheckerPageState();
}

class _YachtForm {
  String yachtClass = '470';
  Sailor? skipper;
  List<Sailor?> crews = [null];
}

class _RescueSlot {
  Sailor? sailor;
  RescueRole role;
  _RescueSlot(this.role);
}

// 機材ページで登録されたレスキュー艇
class _RescueBoatOption {
  final String id;
  final String name;
  final String? rescueType; // 'ゴムボート' / 'ハードボート'（未設定ならnull）
  final int? capacity;
  final String status; // '使用可' / '修理中' / '故障中'

  _RescueBoatOption.fromMap(this.id, Map<String, dynamic> data)
      : name = data['name'] ?? '名称なし',
        rescueType = data['rescueType'],
        capacity = (data['capacity'] as num?)?.toInt(),
        status = data['status'] ?? '使用可';
}

class _RescueForm {
  String name = ''; // 機材から選択した艇名（未選択なら空）
  String? equipmentStatus; // 機材管理上の状態
  String type = 'ゴムボート';
  final TextEditingController capacityCtrl = TextEditingController(text: '6');
  List<_RescueSlot> slots = [
    _RescueSlot(RescueRole.leader),
    _RescueSlot(RescueRole.driver),
    _RescueSlot(RescueRole.jumper),
  ];

  void dispose() => capacityCtrl.dispose();
}

class _HaiteiCheckerPageState extends State<HaiteiCheckerPage> {
  bool _loading = true;
  String? _teamId;
  String _teamName = '';
  List<Sailor> _members = [];
  List<_RescueBoatOption> _boatOptions = []; // 機材登録済みのレスキュー艇
  final List<Sailor?> _shoreStaff = [null]; // 陸上要員

  final _aveCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _waveCtrl = TextEditingController(text: '0');
  bool _poorVisibility = false;
  bool _warningIssued = false;
  bool _thunder = false;
  bool _harborStop = false;
  bool _insideHarbor = false;

  final List<_YachtForm> _yachts = [_YachtForm()];
  final List<_RescueForm> _rescues = [_RescueForm()];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _aveCtrl.dispose();
    _maxCtrl.dispose();
    _waveCtrl.dispose();
    for (final r in _rescues) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final teamId = userDoc.data()?['teamId'];
      final teamName = userDoc.data()?['teamName'] ?? '';
      if (teamId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('teamId', isEqualTo: teamId)
          .where('status', isEqualTo: 'approved')
          .get();
      final members = snap.docs
          .map((d) => Sailor.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      // 機材ページで登録されたレスキュー艇を読み込む
      List<_RescueBoatOption> boats = [];
      try {
        final eqSnap = await FirebaseFirestore.instance
            .collection('equipment')
            .where('teamId', isEqualTo: teamId)
            .where('category', isEqualTo: 'レスキュー')
            .get();
        boats = eqSnap.docs
            .map((d) => _RescueBoatOption.fromMap(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      } catch (e) {
        debugPrint('配艇チェッカー: レスキュー艇の取得エラー: $e');
      }

      if (mounted) {
        setState(() {
          _teamId = teamId;
          _teamName = teamName;
          _members = members;
          _boatOptions = boats;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('配艇チェッカー: メンバー取得エラー: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- メンバー選択 ---

  Set<String> _assignedIds() {
    final ids = <String>{};
    for (final y in _yachts) {
      if (y.skipper != null) ids.add(y.skipper!.id);
      for (final c in y.crews) {
        if (c != null) ids.add(c.id);
      }
    }
    for (final r in _rescues) {
      for (final s in r.slots) {
        if (s.sailor != null) ids.add(s.sailor!.id);
      }
    }
    for (final s in _shoreStaff) {
      if (s != null) ids.add(s.id);
    }
    return ids;
  }

  String _memberInfo(Sailor s) {
    final parts = <String>[s.grade, s.yachtClass, s.position];
    if (s.certSet || s.effectiveCert != SailingCert.none) {
      parts.add('帆走資格:${sailingCertLabel(s.effectiveCert)}');
    }
    if (s.hasBoatLicense) parts.add('船舶免許');
    return parts.join(' / ');
  }

  Future<Sailor?> _pickMember(String title) {
    final assigned = _assignedIds();
    return showModalBottomSheet<Sailor>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            Expanded(
              child: _members.isEmpty
                  ? const Center(child: Text('メンバーがいません'))
                  : ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final m = _members[index];
                        final isAssigned = assigned.contains(m.id);
                        return ListTile(
                          enabled: !isAssigned,
                          leading: CircleAvatar(
                            backgroundColor: isAssigned
                                ? Colors.grey.shade300
                                : Colors.indigo.shade100,
                            child: Icon(Icons.person,
                                color:
                                    isAssigned ? Colors.grey : Colors.indigo),
                          ),
                          title: Text(m.name),
                          subtitle: Text(
                              _memberInfo(m) + (isAssigned ? '（配置済み）' : '')),
                          onTap: () => Navigator.pop(context, m),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // --- チェック実行 ---

  void _runCheck() {
    final ave = double.tryParse(_aveCtrl.text);
    if (ave == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('平均風速を入力してください')));
      return;
    }
    final cond = Conditions(
      aveWind: ave,
      maxWind: double.tryParse(_maxCtrl.text) ?? 0,
      waveHeight: double.tryParse(_waveCtrl.text) ?? 0,
      poorVisibility: _poorVisibility,
      warningIssued: _warningIssued,
      thunder: _thunder,
      harborStopRequest: _harborStop,
      insideHarbor: _insideHarbor,
    );

    final yachts = _yachts
        .where((y) => y.skipper != null || y.crews.any((c) => c != null))
        .map((y) => YachtPlan(
              yachtClass: y.yachtClass,
              skipper: y.skipper,
              crews: y.crews.whereType<Sailor>().toList(),
            ))
        .toList();

    final rescues = _rescues
        .where((r) => r.slots.any((s) => s.sailor != null))
        .map((r) => RescueBoatPlan(
              name: r.name,
              type: r.type,
              capacity: int.tryParse(r.capacityCtrl.text) ?? 0,
              status: r.equipmentStatus,
              members: r.slots
                  .where((s) => s.sailor != null)
                  .map((s) => RescueAssignment(s.sailor!, s.role))
                  .toList(),
            ))
        .toList();

    final shoreStaff = _shoreStaff.whereType<Sailor>().toList();

    final findings = runHaiteiCheck(
      cond: cond,
      yachts: yachts,
      rescues: rescues,
      shoreStaff: shoreStaff,
      date: DateTime.now(),
    );

    _showResults(cond, yachts, rescues, shoreStaff, findings);
  }

  // --- 結果表示 ---

  Color _verdictColor(List<Finding> findings) {
    if (findings.any((f) => f.severity == Severity.stop)) return Colors.red.shade800;
    if (findings.any((f) => f.severity == Severity.violation)) return Colors.red;
    if (findings.any((f) => f.severity == Severity.warning)) return Colors.orange;
    return Colors.green;
  }

  (IconData, Color) _findingStyle(Severity s) {
    switch (s) {
      case Severity.stop:
        return (Icons.dangerous, Colors.red.shade800);
      case Severity.violation:
        return (Icons.error, Colors.red);
      case Severity.warning:
        return (Icons.warning_amber, Colors.orange);
      case Severity.info:
        return (Icons.info_outline, Colors.blueGrey);
    }
  }

  void _showResults(Conditions cond, List<YachtPlan> yachts,
      List<RescueBoatPlan> rescues, List<Sailor> shoreStaff,
      List<Finding> findings) {
    final sorted = [...findings]
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    final verdict = verdictLabel(findings);
    final color = _verdictColor(findings);
    final reportText =
        _buildReportText(cond, yachts, rescues, shoreStaff, findings);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 2),
                ),
                child: Column(
                  children: [
                    Text('判定: $verdict',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    const SizedBox(height: 4),
                    Text(
                      '風域: ${windBandLabel(windBand(cond.aveWind))} / '
                      'ヨット${yachts.length}艇 / レスキュー${rescues.length}艇',
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final f = sorted[index];
                    final (icon, iconColor) = _findingStyle(f.severity);
                    return ListTile(
                      dense: true,
                      leading: Icon(icon, color: iconColor),
                      title: Text(f.message, style: const TextStyle(fontSize: 13)),
                      subtitle: Text('根拠: 安全マニュアル ${f.rule}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('報告テキストをコピー'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: reportText));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('配艇報告テキストをコピーしました（OB会への配艇送付などに使えます）')));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('結果を記録'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white),
                        onPressed: () => _savePlan(cond, findings, reportText),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  String _buildReportText(Conditions cond, List<YachtPlan> yachts,
      List<RescueBoatPlan> rescues, List<Sailor> shoreStaff,
      List<Finding> findings) {
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln('【配艇チェック報告】${DateFormat('yyyy/MM/dd HH:mm').format(now)}');
    if (_teamName.isNotEmpty) buf.writeln('チーム: $_teamName');
    buf.writeln('');
    buf.writeln('■気象・海象');
    buf.writeln(
        '平均風速: ${cond.aveWind}m/s / 最大風速: ${cond.maxWind}m/s / 波高: ${cond.waveHeight}m');
    final notes = <String>[
      if (cond.poorVisibility) '視界不良(2000m以下)',
      if (cond.warningIssued) '警報・注意報発令中',
      if (cond.thunder) '雷注意報・雷鳴',
      if (cond.harborStopRequest) 'ハーバー中止要請',
      if (cond.insideHarbor) '構内練習',
    ];
    if (notes.isNotEmpty) buf.writeln('特記: ${notes.join('、')}');
    buf.writeln('');
    buf.writeln('■ヨット（${yachts.length}艇）');
    for (var i = 0; i < yachts.length; i++) {
      final y = yachts[i];
      final skipper = y.skipper != null
          ? '${y.skipper!.name}(${sailingCertLabel(y.skipper!.effectiveCert)})'
          : '未定';
      final crews =
          y.crews.isEmpty ? '未定' : y.crews.map((c) => c.name).join('、');
      buf.writeln('${i + 1}. ${y.yachtClass}  S: $skipper / C: $crews');
    }
    buf.writeln('');
    buf.writeln('■レスキュー艇（${rescues.length}艇）');
    for (var i = 0; i < rescues.length; i++) {
      final r = rescues[i];
      final boatName = r.name.isNotEmpty ? '${r.name}・' : '';
      buf.writeln(
          '${i + 1}. $boatName${r.type}（定員${r.capacity}・乗員${r.members.length}）');
      for (final m in r.members) {
        buf.writeln('   ${rescueRoleLabels[m.role]}: ${m.sailor.name}');
      }
    }
    buf.writeln('');
    buf.writeln('■陸上要員（${shoreStaff.length}人）');
    for (final s in shoreStaff) {
      buf.writeln('・${s.name}');
    }
    buf.writeln('');
    final stops = findings.where((f) => f.severity == Severity.stop).length;
    final violations =
        findings.where((f) => f.severity == Severity.violation).length;
    final warnings =
        findings.where((f) => f.severity == Severity.warning).length;
    buf.writeln('■チェック結果: ${verdictLabel(findings)}');
    buf.writeln('出艇中止条件: $stops件 / 違反: $violations件 / 注意: $warnings件');
    for (final f in findings.where((f) => f.severity != Severity.info)) {
      final tag = switch (f.severity) {
        Severity.stop => '中止',
        Severity.violation => '違反',
        _ => '注意',
      };
      buf.writeln('・[$tag] ${f.message}');
    }
    return buf.toString();
  }

  Future<void> _savePlan(
      Conditions cond, List<Finding> findings, String reportText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _teamId == null) return;
    try {
      await FirebaseFirestore.instance.collection('haitei_plans').add({
        'teamId': _teamId,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'aveWind': cond.aveWind,
        'maxWind': cond.maxWind,
        'waveHeight': cond.waveHeight,
        'verdict': verdictLabel(findings),
        'stopCount':
            findings.where((f) => f.severity == Severity.stop).length,
        'violationCount':
            findings.where((f) => f.severity == Severity.violation).length,
        'warningCount':
            findings.where((f) => f.severity == Severity.warning).length,
        'reportText': reportText,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('チェック結果を記録しました')));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('permission-denied')
            ? '保存できませんでした（権限エラー）。Firestoreのセキュリティルールに'
                '「haitei_plans」コレクションへの書き込み許可が必要です。'
                '管理者はリポジトリの firestore.rules を反映してください。'
            : '保存エラー: $e';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
      }
    }
  }

  // --- 履歴 ---

  void _showHistory() {
    if (_teamId == null) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('配艇チェック履歴',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('haitei_plans')
                    .where('teamId', isEqualTo: _teamId)
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: Text('エラー: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red)));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                        child: Text('履歴はありません',
                            style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final verdict = data['verdict'] ?? '-';
                      final isOk = (data['stopCount'] ?? 0) == 0 &&
                          (data['violationCount'] ?? 0) == 0;
                      return ListTile(
                        leading: Icon(
                            isOk ? Icons.check_circle : Icons.error,
                            color: isOk ? Colors.green : Colors.red),
                        title: Text('${data['date'] ?? ''}  $verdict'),
                        subtitle: Text(
                            'Ave.${data['aveWind']}m/s / 違反${data['violationCount']}件 / 注意${data['warningCount']}件'),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('配艇チェック（${data['date']}）'),
                              content: SingleChildScrollView(
                                  child: SelectableText(
                                      data['reportText'] ?? '')),
                              actions: [
                                TextButton(
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(
                                        text: data['reportText'] ?? ''));
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  },
                                  child: const Text('コピー'),
                                ),
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('閉じる')),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
            title: const Text('配艇チェッカー'),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('配艇チェッカー'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'チェック履歴',
              onPressed: _showHistory),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildConditionsCard(),
          const SizedBox(height: 16),
          _buildYachtsCard(),
          const SizedBox(height: 16),
          _buildRescuesCard(),
          const SizedBox(height: 16),
          _buildShoreCard(),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.fact_check),
              label: const Text('安全マニュアルに基づきチェック',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: _runCheck,
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required String title, required IconData icon, required List<Widget> children, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo)),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildConditionsCard() {
    return _card(
      title: '気象・海象条件',
      icon: Icons.air,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _aveCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '平均風速 *',
                    suffixText: 'm/s',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _maxCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '最大風速',
                    suffixText: 'm/s',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _waveCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '波高',
                    suffixText: 'm',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('視界が非常に悪い（2000m以下）', style: TextStyle(fontSize: 13)),
          value: _poorVisibility,
          onChanged: (v) => setState(() => _poorVisibility = v!),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('射水市の警報・注意報が発令中', style: TextStyle(fontSize: 13)),
          value: _warningIssued,
          onChanged: (v) => setState(() => _warningIssued = v!),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('雷注意報（射水・富山・高岡・氷見）または雷鳴あり',
              style: TextStyle(fontSize: 13)),
          value: _thunder,
          onChanged: (v) => setState(() => _thunder = v!),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('ハーバーから出艇中止の要請あり', style: TextStyle(fontSize: 13)),
          value: _harborStop,
          onChanged: (v) => setState(() => _harborStop = v!),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('構内（港内）での練習', style: TextStyle(fontSize: 13)),
          value: _insideHarbor,
          onChanged: (v) => setState(() => _insideHarbor = v!),
        ),
      ],
    );
  }

  Widget _memberTile({
    required String label,
    required Sailor? selected,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700)),
              ),
              Expanded(
                child: selected == null
                    ? const Text('タップして選択',
                        style: TextStyle(color: Colors.grey, fontSize: 13))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selected.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(_memberInfo(selected),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
              ),
              if (selected != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                  onPressed: onClear,
                )
              else
                const Icon(Icons.person_add_alt, color: Colors.indigo, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYachtsCard() {
    return _card(
      title: 'ヨット配艇',
      icon: Icons.sailing,
      trailing: TextButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('艇を追加'),
        onPressed: () => setState(() => _yachts.add(_YachtForm())),
      ),
      children: [
        for (var i = 0; i < _yachts.length; i++) _buildYachtForm(i),
        if (_yachts.isEmpty)
          const Text('「艇を追加」からヨットを登録してください',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }

  Widget _buildYachtForm(int index) {
    final y = _yachts[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ヨット ${index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: y.yachtClass,
                isDense: true,
                items: ['470', 'スナイプ']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => y.yachtClass = v!),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => setState(() => _yachts.removeAt(index)),
              ),
            ],
          ),
          _memberTile(
            label: 'スキッパー',
            selected: y.skipper,
            onTap: () async {
              final s = await _pickMember('スキッパーを選択');
              if (s != null) setState(() => y.skipper = s);
            },
            onClear: () => setState(() => y.skipper = null),
          ),
          for (var c = 0; c < y.crews.length; c++)
            _memberTile(
              label: 'クルー ${y.crews.length > 1 ? c + 1 : ''}',
              selected: y.crews[c],
              onTap: () async {
                final s = await _pickMember('クルーを選択');
                if (s != null) setState(() => y.crews[c] = s);
              },
              onClear: () => setState(() {
                if (y.crews.length > 1) {
                  y.crews.removeAt(c);
                } else {
                  y.crews[c] = null;
                }
              }),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('クルーを追加（体験乗船など）',
                style: TextStyle(fontSize: 12)),
            onPressed: () => setState(() => y.crews.add(null)),
          ),
        ],
      ),
    );
  }

  Widget _buildRescuesCard() {
    return _card(
      title: 'レスキュー艇',
      icon: Icons.support,
      trailing: TextButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('艇を追加'),
        onPressed: () => setState(() => _rescues.add(_RescueForm())),
      ),
      children: [
        for (var i = 0; i < _rescues.length; i++) _buildRescueForm(i),
        if (_rescues.isEmpty)
          const Text('※練習時はレスキュー艇の出艇が必須です（マニュアルⅠ-6）',
              style: TextStyle(color: Colors.red, fontSize: 13)),
      ],
    );
  }

  // 機材ページで登録されたレスキュー艇から選択する
  Future<void> _pickRescueBoat(_RescueForm r) async {
    if (_boatOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('機材ページの「レスキュー」カテゴリに艇を登録すると、ここから選択できます')));
      return;
    }
    final picked = await showModalBottomSheet<_RescueBoatOption>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('レスキュー艇を選択（機材から）',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _boatOptions.length,
                itemBuilder: (context, index) {
                  final b = _boatOptions[index];
                  final broken = b.status != '使用可';
                  return ListTile(
                    leading: Icon(Icons.directions_boat,
                        color: broken ? Colors.red : Colors.teal),
                    title: Text(b.name),
                    subtitle: Text(
                        '${b.rescueType ?? '種別未設定'} / 定員: ${b.capacity?.toString() ?? '未設定'}人 / 状態: ${b.status}'),
                    trailing: broken
                        ? const Icon(Icons.warning_amber, color: Colors.red)
                        : null,
                    onTap: () => Navigator.pop(context, b),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
    if (picked != null) {
      setState(() {
        r.name = picked.name;
        r.equipmentStatus = picked.status;
        if (picked.rescueType != null) r.type = picked.rescueType!;
        if (picked.capacity != null) {
          r.capacityCtrl.text = picked.capacity.toString();
        }
      });
    }
  }

  Widget _buildRescueForm(int index) {
    final r = _rescues[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 艇の選択（機材から）
          InkWell(
            onTap: () => _pickRescueBoat(r),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.teal.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_boat, size: 18, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.name.isEmpty ? '艇を選択（機材から）' : r.name,
                      style: TextStyle(
                        fontWeight: r.name.isEmpty ? FontWeight.normal : FontWeight.bold,
                        color: r.name.isEmpty ? Colors.grey : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (r.equipmentStatus != null && r.equipmentStatus != '使用可')
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(r.equipmentStatus!,
                          style: const TextStyle(fontSize: 10, color: Colors.red)),
                    ),
                  if (r.name.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() {
                        r.name = '';
                        r.equipmentStatus = null;
                      }),
                      child: const Icon(Icons.clear, size: 16, color: Colors.grey),
                    )
                  else
                    const Icon(Icons.arrow_drop_down, color: Colors.teal),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Text('レスキュー ${index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: r.type,
                isDense: true,
                items: ['ゴムボート', 'ハードボート']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => r.type = v!),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: r.capacityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '定員',
                      suffixText: '人',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 20),
                onPressed: () => setState(() {
                  _rescues.removeAt(index).dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var s = 0; s < r.slots.length; s++) _buildRescueSlot(r, s),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('乗員を追加', style: TextStyle(fontSize: 12)),
            onPressed: () =>
                setState(() => r.slots.add(_RescueSlot(RescueRole.assistant))),
          ),
        ],
      ),
    );
  }

  Widget _buildShoreCard() {
    return _card(
      title: '陸上要員',
      icon: Icons.support_agent,
      trailing: TextButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('追加'),
        onPressed: () => setState(() => _shoreStaff.add(null)),
      ),
      children: [
        const Text(
          '陸上に1名以上待機し、気象情報を10分に1度確認して海上へ伝達します（マニュアルⅡ-1 対策3）。未設定の場合は違反になります。',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _shoreStaff.length; i++)
          _memberTile(
            label: '陸上 ${_shoreStaff.length > 1 ? i + 1 : ''}',
            selected: _shoreStaff[i],
            onTap: () async {
              final s = await _pickMember('陸上要員を選択');
              if (s != null) setState(() => _shoreStaff[i] = s);
            },
            onClear: () => setState(() {
              if (_shoreStaff.length > 1) {
                _shoreStaff.removeAt(i);
              } else {
                _shoreStaff[i] = null;
              }
            }),
          ),
      ],
    );
  }

  Widget _buildRescueSlot(_RescueForm r, int slotIndex) {
    final slot = r.slots[slotIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<RescueRole>(
              initialValue: slot.role,
              isDense: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: RescueRole.values
                  .map((role) => DropdownMenuItem(
                      value: role, child: Text(rescueRoleLabels[role]!)))
                  .toList(),
              onChanged: (v) => setState(() => slot.role = v!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () async {
                final s =
                    await _pickMember('${rescueRoleLabels[slot.role]}を選択');
                if (s != null) setState(() => slot.sailor = s);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: slot.sailor == null
                          ? const Text('タップして選択',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13))
                          : Text(
                              '${slot.sailor!.name}（${_memberInfo(slot.sailor!)}）',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                    ),
                    if (slot.sailor != null)
                      InkWell(
                        onTap: () => setState(() => slot.sailor = null),
                        child: const Icon(Icons.clear,
                            size: 16, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                size: 18, color: Colors.grey),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => setState(() => r.slots.removeAt(slotIndex)),
          ),
        ],
      ),
    );
  }
}
