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
                  final sailingCert = data['sailingCert'] as String?;
                  final hasBoatLicense = data['hasBoatLicense'] == true;
                  final certInfo = (sailingCert != null && sailingCert != '未設定') ? ' / 帆走:$sailingCert' : '';
                  final licenseInfo = hasBoatLicense ? ' / 船舶免許' : '';

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
                      subtitle: Text('$grade / $yachtClass / $position$certInfo$licenseInfo'),
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
  // 管理者編集の結果を画面に反映できるようローカルに保持
  late Map<String, dynamic> _userData;
  // チャート用クエリの結果をキャッシュする。
  // buildごとに新しいFutureを渡すと再描画のたびに再クエリが走ってしまう。
  late Future<Map<String, List<double>>> _chartDataFuture;
  final List<String> _radarAxisTitles = ['動作', 'セール\nトリム', 'ヒール\nトリム', 'VMG', 'スタート', 'コース'];

  @override
  void initState() {
    super.initState();
    _userData = Map<String, dynamic>.from(widget.userData);
    _chartDataFuture = _fetchChartData();
    _checkViewerRole();
  }

  // 管理者によるプロフィール編集ページを開く
  Future<void> _openEditPage() async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MemberEditPage(userId: widget.userId, userData: _userData),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _userData = {..._userData, ...updated};
        _chartDataFuture = _fetchChartData();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィールを更新しました')),
      );
    }
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
    String currentRole = _userData['role'] ?? 'member';
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

      final String? targetTeamId = _userData['teamId'];
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
        if (avgWind >= 7.0) {
          windKey = 'heavy';
        } else if (avgWind >= 4.0) windKey = 'medium';

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
    final photoUrl = _userData['photoUrl'];
    final name = _userData['name'] ?? '未設定';
    final teamRole = _userData['teamRole'] ?? 'なし';
    final grade = _userData['grade'] ?? '-';
    final position = _userData['position'] ?? '-';
    final yachtClass = _userData['class'] ?? '-';

    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('$name さんの詳細'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_isViewerAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'プロフィールを編集（管理者）',
              onPressed: _openEditPage,
            ),
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
                if (_userData['role'] == 'admin') ...[
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
            const SizedBox(height: 8),
            // 帆走資格・船舶免許（配艇チェッカーで使用する安全情報）
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_userData['sailingCert'] != null && _userData['sailingCert'] != '未設定')
                  Chip(
                    avatar: const Icon(Icons.sailing, size: 16, color: Colors.indigo),
                    label: Text('帆走資格: ${_userData['sailingCert']}', style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
                if (_userData['hasBoatLicense'] == true)
                  const Chip(
                    avatar: Icon(Icons.badge, size: 16, color: Colors.teal),
                    label: Text('小型船舶免許', style: TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
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
              future: _chartDataFuture,
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

// --- 管理者用: メンバープロフィール編集ページ ---
class MemberEditPage extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;

  const MemberEditPage({super.key, required this.userId, required this.userData});

  @override
  State<MemberEditPage> createState() => _MemberEditPageState();
}

class _MemberEditPageState extends State<MemberEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _teamRoleController;
  late String _grade;
  late String _yachtClass;
  late String _position;
  late String _sailingCert;
  late String _gender;
  late bool _hasBoatLicense;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.userData;
    _nameController = TextEditingController(text: data['name'] ?? '');
    _teamRoleController = TextEditingController(text: data['teamRole'] ?? '');
    _grade = data['grade'] ?? '1年';
    _yachtClass = data['class'] ?? '470';
    _position = data['position'] ?? 'スキッパー';
    _sailingCert = data['sailingCert'] ?? '未設定';
    _gender = data['gender'] ?? '未設定';
    _hasBoatLicense = data['hasBoatLicense'] == true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teamRoleController.dispose();
    super.dispose();
  }

  // 既存データがリストにない値でもDropdownが壊れないように補完する
  List<String> _withCurrent(List<String> items, String current) =>
      items.contains(current) ? items : [current, ...items];

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('名前を入力してください')));
      return;
    }
    setState(() => _saving = true);
    try {
      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'grade': _grade,
        'class': _yachtClass,
        'position': _position,
        'teamRole': _teamRoleController.text.trim(),
        'sailingCert': _sailingCert,
        'gender': _gender,
        'hasBoatLicense': _hasBoatLicense,
      };
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid, // 誰が編集したかの記録
      }, SetOptions(merge: true));

      if (mounted) Navigator.pop(context, updates);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存エラー: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.userData['name'] ?? 'メンバー'} さんを編集'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: const Text(
                '管理者としてこのメンバーのプロフィールを編集しています。帆走資格・船舶免許は配艇チェッカーの判定に使用されます。',
                style: TextStyle(fontSize: 12, color: Colors.brown),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '名前', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _teamRoleController,
              decoration: const InputDecoration(
                labelText: '部内の役職',
                hintText: '例: 主将 / 会計（複数は「 / 」区切り）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _grade,
              decoration: const InputDecoration(labelText: '学年', border: OutlineInputBorder()),
              items: _withCurrent(['1年', '2年', '3年', '4年', '院生', 'OB/OG', 'コーチ'], _grade)
                  .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
              onChanged: (val) => setState(() => _grade = val!),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _yachtClass,
              decoration: const InputDecoration(labelText: 'クラス (艇種)', border: OutlineInputBorder()),
              items: _withCurrent(['470', 'Snipe', '両方', 'その他'], _yachtClass)
                  .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
              onChanged: (val) => setState(() => _yachtClass = val!),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _position,
              decoration: const InputDecoration(labelText: 'ポジション', border: OutlineInputBorder()),
              items: _withCurrent(['スキッパー', 'クルー', '両方', 'マネージャー', 'サポーター'], _position)
                  .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
              onChanged: (val) => setState(() => _position = val!),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _sailingCert,
              decoration: const InputDecoration(
                labelText: '部内帆走資格',
                helperText: '配艇チェッカーの出艇可否判定に使用',
                border: OutlineInputBorder(),
              ),
              items: _withCurrent(['未設定', '無資格', '初級', '中級', '上級'], _sailingCert)
                  .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
              onChanged: (val) => setState(() => _sailingCert = val!),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                labelText: '性別（任意）',
                helperText: 'レスキュー乗員の男女比チェックに使用',
                border: OutlineInputBorder(),
              ),
              items: _withCurrent(['未設定', '男性', '女性'], _gender)
                  .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
              onChanged: (val) => setState(() => _gender = val!),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('小型船舶操縦免許を保有'),
              subtitle: const Text('レスキュー艇の運転者チェックに使用', style: TextStyle(fontSize: 12)),
              value: _hasBoatLicense,
              activeThumbColor: Colors.indigo,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _hasBoatLicense = val),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_saving ? '保存中...' : '保存する'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
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