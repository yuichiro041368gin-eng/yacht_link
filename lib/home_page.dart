import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ★★★ APIキー ★★★
  final String _apiKey = 'AIzaSyBWBmcMMbxmrNvl1n_dYnRKXCpV2tJ7SME';

  String _resultText = '';
  String _analyzedDate = '';
  String _analyzedBy = '';
  bool _isLoading = false;
  bool _hasAnalyzed = false;
  String _loadingMessage = '';
  
  // 自分のチームIDを保持する変数
  String? _myTeamId;

  // チャートの軸ラベル（固定）
  final List<String> _radarAxisTitles = ['動作', 'セール\nトリム', 'ヒール\nトリム', 'VMG', 'スタート', 'コース'];

  @override
  void initState() {
    super.initState();
    _fetchMyTeamId();
  }

  // 自分のチームIDを取得する
  Future<void> _fetchMyTeamId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && userDoc.exists) {
        setState(() {
          _myTeamId = userDoc.data()?['teamId'];
        });
      }
    } catch (e) {
      debugPrint("User fetch error: $e");
    }
  }

  // --- 🔥 Firestore共有ロジック ---
  Future<void> _saveResult(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    if (_myTeamId == null) return;

    final userName = await _getUserName(user);

    await FirebaseFirestore.instance.collection('team_analysis_logs').add({
      'content': text,
      'createdAt': FieldValue.serverTimestamp(),
      'userId': user.uid,
      'userName': userName,
      'teamId': _myTeamId, 
      'type': 'personal_analysis'
    });

    setState(() {
      _analyzedDate = DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());
      _analyzedBy = userName;
    });
  }

  void _showHistoryDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_myTeamId == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('AI分析履歴', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('team_analysis_logs')
                    .where('userId', isEqualTo: user.uid)
                    .where('teamId', isEqualTo: _myTeamId)
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('エラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const Center(child: Text('履歴はありません', style: TextStyle(color: Colors.grey)));

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final dateStr = _formatDate(data['createdAt']);
                      final contentStr = data['content'] as String? ?? '';
                      final preview = contentStr.replaceAll('\n', ' ').substring(0, (contentStr.length > 30) ? 30 : contentStr.length);

                      return ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.indigo.shade100, child: const Icon(Icons.history, color: Colors.indigo)),
                        title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$preview...', maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          setState(() {
                            _resultText = contentStr;
                            _analyzedDate = dateStr;
                            _analyzedBy = '自分';
                            _hasAnalyzed = true;
                          });
                          Navigator.pop(context);
                        },
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
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

  String _formatDate(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('yyyy/MM/dd HH:mm').format(timestamp.toDate());
    }
    return '日時不明';
  }

  Future<String> _getUserName(User user) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()!.containsKey('name')) {
        return doc.data()!['name'];
      }
    } catch (_) {}
    return user.email?.split('@')[0] ?? '匿名';
  }

  // --- AI分析ロジック ---
  Future<void> _startAnalysis() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    if (_myTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('チーム情報を読み込み中です。少々お待ちください。')));
      return;
    }

    setState(() {
      _isLoading = true;
      _hasAnalyzed = true;
      _loadingMessage = 'データを収集しています...';
      _resultText = '';
    });

    try {
      // ★修正: 最新の3件だけ取得（1日分ならAM/PMで2件、予備で3件あれば十分）
      final snapshot = await FirebaseFirestore.instance
          .collection('practice_reports')
          .where('userId', isEqualTo: user.uid)
          .where('teamId', isEqualTo: _myTeamId)
          .orderBy('date', descending: true)
          .limit(3) 
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _resultText = '分析に必要なデータがありません。\nまずは日誌を投稿してください。';
        });
        return;
      }

      setState(() => _loadingMessage = 'AIコーチが分析レポートを作成中...');
      
      // ★追加: 最新の日付を取得し、その日付のデータだけを抽出する
      final String latestDate = snapshot.docs.first.data()['date'];

      StringBuffer promptBuffer = StringBuffer();
      promptBuffer.writeln("あなたはプロのヨット競技コーチです。");
      promptBuffer.writeln("以下の選手（ユーザー）の直近（$latestDate）の練習データを元に、『課題』と『具体的な練習メニュー』をアドバイスしてください。");
      promptBuffer.writeln("---");
      
      for (var doc in snapshot.docs) {
        final r = doc.data();
        // ★追加: 違う日付のデータが出てきたらループを終了（直近1日分のみにする）
        if (r['date'] != latestDate) break;

        promptBuffer.writeln("日付: ${r['date']} (${r['timeSlot'] ?? ''})");
        if(r.containsKey('windSpeedMin')) promptBuffer.writeln("- 風速: ${r['windSpeedMin']}m - ${r['windSpeedMax']}m");
        if(r.containsKey('comment_動作')) promptBuffer.writeln("- 動作メモ: ${r['comment_動作']}");
        if(r.containsKey('comment_コース')) promptBuffer.writeln("- コースメモ: ${r['comment_コース']}");
      }
      
      promptBuffer.writeln("---");
      promptBuffer.writeln("出力はMarkdown形式で見やすく整理してください。");

      final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: _apiKey);
      final response = await model.generateContent([Content.text(promptBuffer.toString())]);
      final responseText = response.text ?? 'AIからの応答が空でした。';

      await _saveResult(responseText);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _resultText = responseText;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _resultText = 'エラーが発生しました。\n\n詳細: $e';
        });
      }
    }
  }

  // --- グラフデータ取得（動的対応） ---
  Future<Map<String, List<double>>> _fetchChartData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};
    if (_myTeamId == null) return {};

    try {
      // 1. 最新のチェックリスト設定を取得
      Map<String, List<String>> currentRadarMap = {};
      
      final checklistDoc = await FirebaseFirestore.instance
          .collection('teams')
          .doc(_myTeamId)
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
        return {};
      }

      // 2. 直近のレポートを取得
      final now = DateTime.now();
      final pastMonth = now.subtract(const Duration(days: 60));
      final DateFormat formatter = DateFormat('yyyy-MM-dd');

      final snapshot = await FirebaseFirestore.instance
          .collection('practice_reports')
          .where('userId', isEqualTo: user.uid)
          .where('teamId', isEqualTo: _myTeamId) 
          .where('date', isGreaterThanOrEqualTo: formatter.format(pastMonth))
          .get();

      // 3. 集計処理
      Map<String, Map<String, List<int>>> aggregated = {
        'light': {}, 'medium': {}, 'heavy': {},
      };

      for (var wind in ['light', 'medium', 'heavy']) {
        for (var axis in _radarAxisTitles) {
          aggregated[wind]![axis] = [0, 0];
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
        } else if (avgWind >= 4.0) {
          windKey = 'medium';
        }

        currentRadarMap.forEach((axisName, items) {
          for (var item in items) {
            if (scores.containsKey(item) && scores[item] is int && scores[item] > 0) {
              aggregated[windKey]![axisName]![0] += scores[item] as int;
              aggregated[windKey]![axisName]![1] += 1;
            }
          }
        });
      }

      Map<String, List<double>> result = {};
      for (var wind in ['light', 'medium', 'heavy']) {
        List<double> averages = [];
        for (var axis in _radarAxisTitles) {
          final sum = aggregated[wind]![axis]![0];
          final count = aggregated[wind]![axis]![1];
          averages.add(count > 0 ? sum / count : 0.0);
        }
        result[wind] = averages;
      }

      return result;

    } catch (e) {
      debugPrint("★★★ グラフデータの取得エラー: $e");
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('マイ・ダッシュボード', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildChartSection(),
            const SizedBox(height: 20),
            _buildAISection(),
          ],
        ),
      ),
      floatingActionButton: (_hasAnalyzed && !_isLoading)
          ? FloatingActionButton.extended(
              onPressed: _startAnalysis,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('最新データでAI分析'),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildChartSection() {
    return FutureBuilder<Map<String, List<double>>>(
      future: _fetchChartData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            height: 150,
            margin: const EdgeInsets.all(16),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Text('データがありません。\n日誌を投稿するとグラフが表示されます。', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          );
        }

        final data = snapshot.data!;
        
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.radar, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text('風速別スキルバランス', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ],
              ),
              const SizedBox(height: 12),
              
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(color: Colors.green, label: '微風'),
                  SizedBox(width: 12),
                  _LegendItem(color: Colors.blue, label: '順風'),
                  SizedBox(width: 12),
                  _LegendItem(color: Colors.red, label: '強風'),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                height: 300,
                child: RadarChart(
                  RadarChartData(
                    radarTouchData: RadarTouchData(enabled: false),
                    dataSets: [
                      // ★透明なデータセット（最大値3.0固定用）
                      RadarDataSet(
                        dataEntries: _radarAxisTitles.map((_) => const RadarEntry(value: 3.0)).toList(),
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
                      if (index < _radarAxisTitles.length) {
                        return RadarChartTitle(text: _radarAxisTitles[index]);
                      }
                      return const RadarChartTitle(text: '');
                    },
                    tickCount: 3, 
                    ticksTextStyle: const TextStyle(color: Colors.transparent),
                    tickBorderData: const BorderSide(color: Colors.grey, width: 0.5),
                    gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
                  ),
                ),
              ),
              const Text('※各項目の平均スコア (最大3.0)', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  RadarDataSet _buildRadarDataSet(List<double> values, Color color) {
    if (values.every((v) => v == 0)) {
       return RadarDataSet(dataEntries: _radarAxisTitles.map((_) => const RadarEntry(value: 0)).toList(), borderColor: Colors.transparent, fillColor: Colors.transparent);
    }

    return RadarDataSet(
      fillColor: color.withOpacity(0.15),
      borderColor: color,
      entryRadius: 2.5,
      borderWidth: 2,
      dataEntries: values.map((e) => RadarEntry(value: e)).toList(),
    );
  }

  Widget _buildAISection() {
    if (!_hasAnalyzed) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.indigo.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            const Icon(Icons.psychology, size: 60, color: Colors.indigo),
            const SizedBox(height: 16),
            const Text('AIコーチ分析', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('あなたの日誌を分析し、課題と練習プランを提示します。', 
              textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: _startAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo, 
                  foregroundColor: Colors.white, 
                ),
                child: const Text('分析を開始', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _showHistoryDialog,
              icon: const Icon(Icons.history, color: Colors.indigo),
              label: const Text('過去の分析履歴を見る', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_loadingMessage, style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          if (_analyzedDate.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(color: Colors.amber[100], borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
              child: Text('実行: $_analyzedDate', textAlign: TextAlign.center, style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
            ),
          
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
               color: Colors.white,
               borderRadius: _analyzedDate.isNotEmpty ? const BorderRadius.vertical(bottom: Radius.circular(12)) : BorderRadius.circular(12),
               border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Markdown(
              data: _resultText,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
            ),
          ),
          const SizedBox(height: 100),
        ],
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