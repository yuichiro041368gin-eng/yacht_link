import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart'; // URLを開く用
import 'gemini_config.dart';
import 'haitei_checker_page.dart';
import 'amedas_page.dart';
import 'weather_map_page.dart';
import 'app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _resultText = '';
  String _analyzedDate = '';
  bool _isLoading = false;
  bool _hasAnalyzed = false;
  
  String _loadingMessage = '';
  String? _errorUrl; 

  String? _myTeamId;

  // チャート用クエリの結果をキャッシュする。
  // FutureBuilderにbuildごとの新しいFutureを渡すと、再描画のたびに
  // Firestoreへの再クエリが走り、スピナーが出続けて動作が重くなる。
  Future<Map<String, List<double>>>? _chartDataFuture;

  final List<String> _radarAxisTitles = ['動作', 'セール\nトリム', 'ヒール\nトリム', 'VMG', 'スタート', 'コース'];

  @override
  void initState() {
    super.initState();
    _fetchMyTeamId();
  }

  Future<void> _fetchMyTeamId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? teamId;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      teamId = userDoc.data()?['teamId'];
    } catch (e) {
      debugPrint("User fetch error: $e");
    }
    if (mounted) {
      setState(() {
        _myTeamId = teamId;
        // teamIdが確定してから1回だけチャートデータを取得する
        _chartDataFuture = _fetchChartData();
      });
    }
  }

  Future<void> _saveResult(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return;

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
    });
  }

  void _showHistoryDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return;

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
                        leading: CircleAvatar(backgroundColor: AppColors.primary.shade50, child: const Icon(Icons.history, color: AppColors.primary)),
                        title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$preview...', maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          setState(() {
                            _resultText = contentStr;
                            _analyzedDate = dateStr;
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

    if (!GeminiConfig.hasApiKey) {
      setState(() {
        _hasAnalyzed = true;
        _resultText = 'Gemini APIキーが設定されていません。\n'
            '起動時に --dart-define=GEMINI_API_KEY=... を指定してください。';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasAnalyzed = true;
      _loadingMessage = 'Step 1/3: データを検索しています...';
      _resultText = '';
      _errorUrl = null;
    });

    try {
      // Step 1: データ取得
      final snapshot = await FirebaseFirestore.instance
          .collection('practice_reports')
          .where('userId', isEqualTo: user.uid)
          .where('teamId', isEqualTo: _myTeamId)
          .orderBy('date', descending: true)
          .limit(3) 
          .get()
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw TimeoutException('データの取得に時間がかかりすぎています。\nおそらくインデックスが必要です。');
          });

      if (snapshot.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _resultText = 'データが見つかりませんでした。\n\n・日誌を投稿していますか？\n・チームIDは正しいですか？';
        });
        return;
      }

      setState(() => _loadingMessage = 'Step 2/3: データを整形しています (${snapshot.docs.length}件取得)...');
      
      final String latestDate = snapshot.docs.first.data()['date'];

      StringBuffer promptBuffer = StringBuffer();
      promptBuffer.writeln("あなたはプロのヨット競技コーチです。");
      promptBuffer.writeln("以下の選手（ユーザー）の直近（$latestDate）の練習データを元に、『課題』と『具体的な練習メニュー』をアドバイスしてください。");
      promptBuffer.writeln("※スコアの意味: 3=良(○), 2=普通(△), 1=悪(×)");
      promptBuffer.writeln("---");
      
      for (var doc in snapshot.docs) {
        final r = doc.data();
        if (r['date'] != latestDate) break;

        promptBuffer.writeln("## 日時: ${r['date']} (${r['timeSlot'] ?? ''})");
        if(r.containsKey('windSpeedMin')) promptBuffer.writeln("- 風速: ${r['windSpeedMin']}m - ${r['windSpeedMax']}m");
        
        if(r.containsKey('comment_動作')) promptBuffer.writeln("- 【動作メモ】: ${r['comment_動作']}");
        if(r.containsKey('comment_セーリング')) promptBuffer.writeln("- 【セーリングメモ】: ${r['comment_セーリング']}");
        if(r.containsKey('comment_スタート')) promptBuffer.writeln("- 【スタートメモ】: ${r['comment_スタート']}");
        if(r.containsKey('comment_コース')) promptBuffer.writeln("- 【コースメモ】: ${r['comment_コース']}");

        final scores = r['scores'] as Map<String, dynamic>? ?? {};
        if (scores.isNotEmpty) {
          promptBuffer.write("- 【自己評価スコア】: ");
          List<String> scoreStrings = [];
          scores.forEach((key, value) {
            if (value is int && value > 0) {
              scoreStrings.add("$key($value)");
            }
          });
          promptBuffer.writeln(scoreStrings.join(', '));
        }
        promptBuffer.writeln(""); 
      }
      
      promptBuffer.writeln("---");
      promptBuffer.writeln("出力はMarkdown形式で見やすく整理し、300文字〜500文字程度で簡潔にまとめてください。");

      setState(() => _loadingMessage = 'Step 3/3: AIが分析中...');

      // ★修正: maxOutputTokensを4000に増加
      final model = GenerativeModel(
        model: 'gemini-3-flash-preview', 
        apiKey: GeminiConfig.apiKey,
        generationConfig: GenerationConfig(
          maxOutputTokens: 4000, // ここを800から4000に変更
          temperature: 0.7,
        ),
      );
      
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
        String errorMsg = e.toString();
        String? url;
        
        if (errorMsg.contains('https://console.firebase.google.com')) {
          final RegExp regExp = RegExp(r'(https://console\.firebase\.google\.com[^\s]+)');
          final match = regExp.firstMatch(errorMsg);
          if (match != null) {
            url = match.group(0);
            errorMsg = "【重要】データベースの設定が必要です。\n下のボタンを押してインデックスを作成してください。";
          }
        } else if (errorMsg.contains('permission-denied')) {
          errorMsg = "権限エラーです。\nセキュリティルールを確認してください。";
        } else if (errorMsg.contains('503')) {
          errorMsg = "現在、AIサーバーが大変混雑しています(503)。\n1〜2分待ってから再度お試しください。";
        } else if (errorMsg.contains('404') || errorMsg.contains('not found')) {
           errorMsg = "指定したモデルが見つかりません(404)。\nモデル名が有効か確認してください。";
        }

        setState(() {
          _isLoading = false;
          _resultText = 'エラーが発生しました:\n$errorMsg';
          _errorUrl = url;
        });
      }
    }
  }

  // --- グラフデータ取得 ---
  Future<Map<String, List<double>>> _fetchChartData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return {};

    try {
      Map<String, List<String>> currentRadarMap = {};
      final checklistDoc = await FirebaseFirestore.instance.collection('teams').doc(_myTeamId).collection('settings').doc('checklist').get();

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

      final now = DateTime.now();
      final pastMonth = now.subtract(const Duration(days: 60));
      final DateFormat formatter = DateFormat('yyyy-MM-dd');

      final snapshot = await FirebaseFirestore.instance
          .collection('practice_reports')
          .where('userId', isEqualTo: user.uid)
          .where('teamId', isEqualTo: _myTeamId) 
          .where('date', isGreaterThanOrEqualTo: formatter.format(pastMonth))
          .get();

      Map<String, Map<String, List<int>>> aggregated = {'light': {}, 'medium': {}, 'heavy': {}};
      for (var wind in ['light', 'medium', 'heavy']) {
        for (var axis in _radarAxisTitles) {
          aggregated[wind]![axis] = [0, 0];
        }
      }

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final scores = data['scores'] as Map<String, dynamic>? ?? {};
        
        if (data['windSpeedMin'] == null || data['windSpeedMax'] == null) continue; 

        double avgWind = 0.0;
        try {
          double min = double.tryParse(data['windSpeedMin'].toString()) ?? 0;
          double max = double.tryParse(data['windSpeedMax'].toString()) ?? 0;
          avgWind = (min + max) / 2;
        } catch (_) { continue; }

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

  // 引っ張って更新: チームID未取得ならそこから、取得済みならチャートを再取得
  Future<void> _handleRefresh() async {
    if (_myTeamId == null) {
      await _fetchMyTeamId();
      return;
    }
    final future = _fetchChartData();
    setState(() => _chartDataFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        edgeOffset: 100,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeroHeader(),
              _buildQuickAccessSection(),
              _buildChartSection(),
              const SizedBox(height: 20),
              _buildAISection(),
            ],
          ),
        ),
      ),
      floatingActionButton: (_hasAnalyzed && !_isLoading)
          ? FloatingActionButton.extended(
              onPressed: _startAnalysis,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('最新データでAI分析',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  // ヒーローヘッダー（夜の海グラデーション）
  Widget _buildHeroHeader() {
    final now = DateTime.now();
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final dateStr = '${now.month}月${now.day}日 (${weekdays[now.weekday - 1]})';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -14,
              child: Icon(Icons.sailing,
                  size: 150, color: Colors.white.withValues(alpha: 0.07)),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateStr,
                        style: const TextStyle(
                            color: AppColors.aqua,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    const Text('マイ・ダッシュボード',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Text('今日も良い風を。データで次の一艇身へ。',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 出艇前チェックのクイックアクセス（配艇・風況・天気図）
  Widget _buildQuickAccessSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          GradientBanner(
            title: '配艇チェッカー',
            subtitle: '出艇前に配艇が安全マニュアルの基準を満たすかチェック',
            icon: Icons.fact_check_outlined,
            gradient: AppGradients.teal,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const HaiteiCheckerPage())),
          ),
          const SizedBox(height: 12),
          GradientBanner(
            title: 'アメダス風況モニター',
            subtitle: '風向に応じた観測地点の10分毎データを地図から確認',
            icon: Icons.air,
            gradient: AppGradients.sky,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const AmedasPage())),
          ),
          const SizedBox(height: 12),
          GradientBanner(
            title: '天気図',
            subtitle: '実況・予想天気図から今日の気象変化を出艇前に予測',
            icon: Icons.map_outlined,
            gradient: AppGradients.slate,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const WeatherMapPage())),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    return FutureBuilder<Map<String, List<double>>>(
      future: _chartDataFuture,
      builder: (context, snapshot) {
        // _chartDataFuture == null はチーム情報の読み込み待ち
        // スピナーではなく、チャートカードの骨組み（スケルトン）を明滅表示する
        if (_chartDataFuture == null || snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Skeleton(width: 38, height: 38, borderRadius: BorderRadius.all(Radius.circular(12))),
                    SizedBox(width: 10),
                    Skeleton(width: 160, height: 18),
                  ],
                ),
                const SizedBox(height: 18),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Skeleton(width: 56, height: 24, borderRadius: BorderRadius.all(Radius.circular(20))),
                    SizedBox(width: 8),
                    Skeleton(width: 56, height: 24, borderRadius: BorderRadius.all(Radius.circular(20))),
                    SizedBox(width: 8),
                    Skeleton(width: 56, height: 24, borderRadius: BorderRadius.all(Radius.circular(20))),
                  ],
                ),
                const SizedBox(height: 24),
                const Center(child: Skeleton.circle(size: 240)),
                const SizedBox(height: 16),
                const Skeleton(width: 140, height: 11),
              ],
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            height: 150,
            margin: const EdgeInsets.all(16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Text('データがありません。\n日誌を投稿するとグラフが表示されます。', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          );
        }
        final data = snapshot.data!;

        const Color lightWind = Color(0xFF12B886); // 微風: エメラルド
        const Color mediumWind = Color(0xFF339AF0); // 順風: スカイブルー
        const Color heavyWind = Color(0xFFFF6B6B); // 強風: コーラル

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.hairline),
            boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: AppGradients.hero,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.radar, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('風速別スキルバランス',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.navy, letterSpacing: 0.3)),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(color: lightWind, label: '微風'),
                  SizedBox(width: 8),
                  _LegendItem(color: mediumWind, label: '順風'),
                  SizedBox(width: 8),
                  _LegendItem(color: heavyWind, label: '強風'),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 300,
                child: RadarChart(
                  RadarChartData(
                    radarTouchData: RadarTouchData(enabled: false),
                    dataSets: [
                      RadarDataSet(
                        dataEntries: _radarAxisTitles.map((_) => const RadarEntry(value: 3.0)).toList(),
                        borderColor: Colors.transparent,
                        fillColor: Colors.transparent,
                        entryRadius: 0,
                        borderWidth: 0,
                      ),
                      _buildRadarDataSet(data['light']!, lightWind),
                      _buildRadarDataSet(data['medium']!, mediumWind),
                      _buildRadarDataSet(data['heavy']!, heavyWind),
                    ],
                    radarBackgroundColor: Colors.transparent,
                    borderData: FlBorderData(show: false),
                    radarBorderData: const BorderSide(color: AppColors.primary, width: 1.5),
                    titlePositionPercentageOffset: 0.1,
                    titleTextStyle: const TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.bold),
                    getTitle: (index, angle) {
                      if (index < _radarAxisTitles.length) return RadarChartTitle(text: _radarAxisTitles[index]);
                      return const RadarChartTitle(text: '');
                    },
                    tickCount: 3,
                    ticksTextStyle: const TextStyle(color: Colors.transparent),
                    tickBorderData: BorderSide(color: AppColors.primary.shade100, width: 0.8),
                    gridBorderData: BorderSide(color: AppColors.primary.shade100, width: 0.8),
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
      fillColor: color.withValues(alpha: 0.15),
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
          gradient: AppGradients.hero,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(Icons.psychology, size: 38, color: AppColors.aqua),
            ),
            const SizedBox(height: 16),
            const Text('AIコーチ分析',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text('あなたの日誌を分析し、課題と練習プランを提示します。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 13.5)),
            const SizedBox(height: 22),
            _GradientButton(
              label: '分析を開始',
              icon: Icons.auto_awesome,
              onPressed: _startAnalysis,
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _showHistoryDialog,
              icon: const Icon(Icons.history, color: AppColors.aqua, size: 20),
              label: const Text('過去の分析履歴を見る',
                  style: TextStyle(color: AppColors.aqua, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(_loadingMessage,
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: AppColors.scaffoldBg,
      child: Column(
        children: [
          if (_analyzedDate.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: const BoxDecoration(
                gradient: AppGradients.hero,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.aqua, size: 16),
                  const SizedBox(width: 8),
                  Text('実行: $_analyzedDate',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
               color: Colors.white,
               borderRadius: _analyzedDate.isNotEmpty ? const BorderRadius.vertical(bottom: Radius.circular(18)) : BorderRadius.circular(18),
               border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                Markdown(
                  data: _resultText,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                ),
                
                if (_errorUrl != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.link),
                      label: const Text('設定ページを開く (インデックス作成)'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () async {
                        final Uri url = Uri.parse(_errorUrl!);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                    ),
                  ),
              ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// シアングラデーションのCTAボタン
class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        gradient: AppGradients.cyanCta,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.deepNavy, size: 20),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.deepNavy,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
