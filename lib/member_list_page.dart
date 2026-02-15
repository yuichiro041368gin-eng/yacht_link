import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart'; 

class MemberListPage extends StatelessWidget {
  const MemberListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('チームメンバー名簿'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          final myTeamId = userData['teamId'];

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('teamId', isEqualTo: myTeamId)
                .where('status', isEqualTo: 'approved')
                .orderBy('grade') 
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("メンバーがいません"));
              }

              final members = snapshot.data!.docs;

              return ListView.builder(
                itemCount: members.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final data = members[index].data() as Map<String, dynamic>;
                  final name = data['name'] ?? '名前未設定';
                  final grade = data['grade'] ?? '-';
                  final position = data['position'] ?? '-';
                  final teamRole = data['teamRole'] ?? '';
                  final role = data['role'] ?? 'member';
                  final photoUrl = data['photoUrl'];
                  final yachtClass = data['class'] ?? '-';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MemberDetailPage(userData: data, userId: members[index].id),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        backgroundColor: role == 'admin' ? Colors.redAccent : Colors.indigo.shade100,
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Icon(Icons.person, color: role == 'admin' ? Colors.white : Colors.indigo)
                            : null,
                      ),
                      title: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          if (teamRole.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Text(
                                teamRole.split(' / ')[0],
                                style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text('$grade / $yachtClass / $position'),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// --- メンバー詳細ページ ---
class MemberDetailPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;

  const MemberDetailPage({super.key, required this.userData, required this.userId});

  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  bool _isViewerAdmin = false;
  final List<String> _radarAxisTitles = ['動作', 'セール\nトリム', 'ヒール\nトリム', 'VMG', 'スタート', 'コース'];

  @override
  void initState() {
    super.initState();
    _checkViewerRole();
  }

  // 自分（閲覧者）が管理者かどうかチェック
  Future<void> _checkViewerRole() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _isViewerAdmin = doc.data()?['role'] == 'admin';
      });
    }
  }

  // 権限変更ダイアログ
  void _showRoleChangeDialog() {
    String currentRole = widget.userData['role'] ?? 'member';
    String newRole = currentRole;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('権限の変更'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('このメンバーに管理者権限を付与、または解除します。管理者はメンバーの承認や設定変更が可能になります。'),
                  const SizedBox(height: 20),
                  RadioListTile<String>(
                    title: const Text('一般メンバー'),
                    value: 'member',
                    groupValue: newRole,
                    onChanged: (val) => setState(() => newRole = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('管理者 (Admin)'),
                    subtitle: const Text('※慎重に選択してください'),
                    value: 'admin',
                    groupValue: newRole,
                    activeColor: Colors.red,
                    onChanged: (val) => setState(() => newRole = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                ElevatedButton(
                  onPressed: () async {
                    if (newRole != currentRole) {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.userId)
                          .update({'role': newRole});
                      
                      if (mounted) {
                        Navigator.pop(context); // ダイアログ閉じる
                        Navigator.pop(context); // 一覧画面に戻る
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('権限を ${newRole == 'admin' ? '管理者' : '一般'} に変更しました')),
                        );
                      }
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // チャートデータ取得ロジック (動的対応版)
  Future<Map<String, List<double>>> _fetchChartData() async {
    try {
      final now = DateTime.now();
      final pastMonth = now.subtract(const Duration(days: 60));
      final DateFormat formatter = DateFormat('yyyy-MM-dd');

      final String? targetTeamId = widget.userData['teamId'];
      if (targetTeamId == null) return {};

      // 1. 最新のチェックリスト設定を取得 (home_page.dartと同様)
      Map<String, List<String>> currentRadarMap = {};
      final checklistDoc = await FirebaseFirestore.instance
          .collection('teams')
          .doc(targetTeamId)
          .collection('settings')
          .doc('checklist')
          .get();

      if (checklistDoc.exists && checklistDoc.data() != null) {
        final data = checklistDoc.data()!;
        currentRadarMap['動作'] = List<String>.from(data['動作']?['動作'] ?? []);
        currentRadarMap['セール\nトリム'] = List<String>.from(data['セーリング']?['セールトリム'] ?? []);
        currentRadarMap['ヒール\nトリム'] = List<String>.from(data['セーリング']?['バランス'] ?? []);
        currentRadarMap['VMG'] = List<String>.from(data['セーリング']?['VMG'] ?? []);
        
        List<String> startItems = [];
        final startMap = data['スタート'] as Map<String, dynamic>? ?? {};
        startMap.forEach((_, v) => startItems.addAll(List<String>.from(v)));
        currentRadarMap['スタート'] = startItems;

        List<String> courseItems = [];
        final courseMap = data['コース'] as Map<String, dynamic>? ?? {};
        courseMap.forEach((_, v) => courseItems.addAll(List<String>.from(v)));
        currentRadarMap['コース'] = courseItems;
      } else {
        // データがない場合は空を返す
        return {};
      }

      // 2. 練習記録を取得
      final snapshot = await FirebaseFirestore.instance
          .collection('practice_reports')
          .where('userId', isEqualTo: widget.userId)
          .where('teamId', isEqualTo: targetTeamId)
          .where('date', isGreaterThanOrEqualTo: formatter.format(pastMonth))
          .get();

      // 3. 集計
      Map<String, Map<String, List<int>>> aggregated = {'light': {}, 'medium': {}, 'heavy': {}};
      for (var wind in ['light', 'medium', 'heavy']) {
        for (var cat in _radarAxisTitles) {
          aggregated[wind]![cat] = [0, 0];
        }
      }

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final scores = data['scores'] as Map<String, dynamic>? ?? {};
        double avgWind = 0.0;
        try {
          double min = double.tryParse(data['windSpeedMin']?.toString() ?? '0') ?? 0;
          double max = double.tryParse(data['windSpeedMax']?.toString() ?? '0') ?? 0;
          avgWind = (min + max) / 2;
        } catch (_) {}
        String windKey = 'light';
        if (avgWind >= 7.0) windKey = 'heavy';
        else if (avgWind >= 4.0) windKey = 'medium';

        currentRadarMap.forEach((categoryName, items) {
          for (var item in items) {
            if (scores.containsKey(item) && scores[item] is int && scores[item] > 0) {
              aggregated[windKey]![categoryName]![0] += scores[item] as int;
              aggregated[windKey]![categoryName]![1] += 1;
            }
          }
        });
      }

      Map<String, List<double>> result = {};
      for (var wind in ['light', 'medium', 'heavy']) {
        List<double> averages = [];
        for (var cat in _radarAxisTitles) {
          final sum = aggregated[wind]![cat]![0];
          final count = aggregated[wind]![cat]![1];
          averages.add(count > 0 ? sum / count : 0.0);
        }
        result[wind] = averages;
      }
      return result;
    } catch (e) {
      debugPrint("Member Chart Error: $e");
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.userData['photoUrl'];
    final name = widget.userData['name'] ?? '未設定';
    final teamRole = widget.userData['teamRole'] ?? 'なし';
    final grade = widget.userData['grade'] ?? '-';
    final position = widget.userData['position'] ?? '-';
    final yachtClass = widget.userData['class'] ?? '-';

    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('$name さんの詳細'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_isViewerAdmin && currentUser?.uid != widget.userId)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: '権限を変更',
              onPressed: _showRoleChangeDialog,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null ? const Icon(Icons.person, size: 60, color: Colors.white) : null,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                if (widget.userData['role'] == 'admin') ...[
                  const SizedBox(width: 8),
                  const Chip(
                    label: Text('Admin', style: TextStyle(color: Colors.white, fontSize: 10)),
                    backgroundColor: Colors.redAccent,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ]
              ],
            ),
            const SizedBox(height: 8),
            Text('$grade / $yachtClass / $position', style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),
            if (teamRole != 'なし')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(teamRole, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            
            const SizedBox(height: 30),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('📊 直近60日のスキルバランス', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              ),
            ),

            FutureBuilder<Map<String, List<double>>>(
              future: _fetchChartData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(32), child: Text('データがありません', style: TextStyle(color: Colors.grey)));
                }

                final data = snapshot.data!;
                return Container(
                  height: 300,
                  padding: const EdgeInsets.all(16),
                  child: RadarChart(
                    RadarChartData(
                      radarTouchData: RadarTouchData(enabled: false),
                      dataSets: [
                        // ★重要: スケールを固定するための透明なデータセット（最大値3.0）
                        RadarDataSet(
                          dataEntries: List.generate(6, (_) => const RadarEntry(value: 3.0)),
                          borderColor: Colors.transparent,
                          fillColor: Colors.transparent,
                          entryRadius: 0,
                          borderWidth: 0,
                        ),
                        // 実際のデータ
                        _buildRadarDataSet(data['light']!, Colors.green),
                        _buildRadarDataSet(data['medium']!, Colors.blue),
                        _buildRadarDataSet(data['heavy']!, Colors.red),
                      ],
                      radarBackgroundColor: Colors.transparent,
                      borderData: FlBorderData(show: false),
                      radarBorderData: const BorderSide(color: Colors.indigo, width: 1.5),
                      titlePositionPercentageOffset: 0.1,
                      titleTextStyle: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
                      getTitle: (index, angle) {
                        if (index < _radarAxisTitles.length) return RadarChartTitle(text: _radarAxisTitles[index]);
                        return const RadarChartTitle(text: '');
                      },
                      tickCount: 3,
                      ticksTextStyle: const TextStyle(color: Colors.transparent),
                      tickBorderData: const BorderSide(color: Colors.grey, width: 0.5),
                      gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                );
              },
            ),
            
            const Padding(
              padding: EdgeInsets.only(bottom: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(color: Colors.green, label: '微風'),
                  SizedBox(width: 12),
                  _LegendItem(color: Colors.blue, label: '順風'),
                  SizedBox(width: 12),
                  _LegendItem(color: Colors.red, label: '強風'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  RadarDataSet _buildRadarDataSet(List<double> values, Color color) {
    if (values.every((v) => v == 0)) {
        // 全て0の場合は透明なデータを返す（エラー回避）
        return RadarDataSet(dataEntries: List.generate(6, (_) => const RadarEntry(value: 0)), borderColor: Colors.transparent, fillColor: Colors.transparent);
    }
    return RadarDataSet(
      fillColor: color.withOpacity(0.15),
      borderColor: color,
      entryRadius: 2.5,
      borderWidth: 2,
      dataEntries: values.map((e) => RadarEntry(value: e)).toList(),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
      ],
    );
  }
}