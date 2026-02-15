import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  DateTime _selectedDate = DateTime.now();
  String get _formattedDate => DateFormat('yyyy-MM-dd').format(_selectedDate);
  
  String _timeSlot = 'AM'; // 'AM' or 'PM'
  
  // ★追加: 自分のチームIDを保持する変数
  String? _myTeamId;

  String get _documentId {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    return '${_formattedDate}_${_timeSlot}_$uid';
  }

  final List<String> _directions = [
    '北', '北北東', '北東', '東北東',
    '東', '東南東', '南東', '南南東',
    '南', '南南西', '南西', '西南西',
    '西', '西北西', '北西', '北北西',
  ];

  late final List<String> _windSpeeds;

  @override
  void initState() {
    super.initState();
    _windSpeeds = List.generate(51, (index) {
      return (index * 0.5).toStringAsFixed(1);
    });
    // ★追加: 起動時にチームIDを取得しておく
    _fetchMyTeamId();
  }

  // ★追加: ユーザー情報からチームIDを取得
  Future<void> _fetchMyTeamId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        setState(() {
          _myTeamId = doc.data()?['teamId'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching teamId: $e");
    }
  }

  final Map<String, Map<String, List<String>>> _checklistData = {
    '動作': {
      '動作': [
        '適切なヒール量、ロール量',
        'ヘルム使えてるか',
        'メイン、ジブ引いてこれてるか',
        '煽りの加速感',
        '船を揺らさない',
        'タック後のリーチ',
        '動作前後のスピードがあるか',
        '逆ジブ量',
        'かかってる時間',
        '船のアングル',
      ],
    },
    'セーリング': {
      'セールトリム': [
        'シーティングスタイルの確立',
        'ジブは両ピロ、メインはリーチ崩さない',
        '風の強弱に合わせられる',
        'コントロールロープ適切に扱える',
        '波に合わせられる',
      ],
      'バランス': [
        'ヒール（ヘルム）が一定',
        '波の海面での微ヒール、フラット',
        'しっかりハイクアウトできているか',
        'ランニングの一定パワーとヒール',
      ],
      'VMG': [
        'スピードファースト',
        '角度とれる',
      ],
    },
    'スタート': {
      'スタート前': [
        '下のルーム1.5艇幅確保',
        '微速前進ができる',
        '動作の確認（煽り）',
        'ライン感覚（見通し）',
        'デンジャーの見極め（潮・振れ）',
      ],
      'スタート後': [
        '自艇の上下艇よりバウ出す',
        'フルスピード',
        'フレッシュウィンドで2分間走れる',
      ],
    },
    'コース': {
      'スタート前': [
        'ルーティン実施（海面調査）',
      ],
      'スタート後': [
        'ロングを走る',
        'ゲインを確定できる',
        'オーバーセールしない',
        '振れ、ブローの見極め',
        '艇団に対してのポジショニング',
      ],
    },
  };

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _deleteLog() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('日誌の削除', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text('$_formattedDate ($_timeSlot) の記録を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('practice_reports').doc(_documentId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          title: Row(
            children: [
              InkWell(
                onTap: () => _selectDate(context),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 18, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(_formattedDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ToggleButtons(
                  isSelected: [_timeSlot == 'AM', _timeSlot == 'PM'],
                  onPressed: (index) {
                    setState(() {
                      _timeSlot = index == 0 ? 'AM' : 'PM';
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.indigo,
                  fillColor: Colors.white,
                  color: Colors.white70,
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 40),
                  children: const [
                    Text('午前', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('午後', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'この時間の記録を削除',
              onPressed: _deleteLog,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amber,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.air), text: '風'),
              Tab(text: '動作'),
              Tab(text: 'セーリング'),
              Tab(text: 'スタート'),
              Tab(text: 'コース'),
              Tab(icon: Icon(Icons.analytics), text: '全体集計'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildWindTab(),
            _buildInputTab('動作'),
            _buildInputTab('セーリング'),
            _buildInputTab('スタート'),
            _buildInputTab('コース'),
            _buildAnalysisTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildWindTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('practice_reports')
          .doc(_documentId)
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic> currentData = {};
        if (snapshot.hasData && snapshot.data!.exists) {
          currentData = snapshot.data!.data() as Map<String, dynamic>;
        }

        String? windDirFrom = currentData['windDirFrom'];
        String? windDirTo = currentData['windDirTo'];
        String? windSpeedMin = currentData['windSpeedMin'];
        if (windSpeedMin != null && !_windSpeeds.contains(windSpeedMin)) windSpeedMin = null;
        String? windSpeedMax = currentData['windSpeedMax'];
        if (windSpeedMax != null && !_windSpeeds.contains(windSpeedMax)) windSpeedMax = null;
        String windComment = currentData['comment_風'] ?? '';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isToday(_selectedDate))
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(8),
                color: Colors.orange[100],
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(child: Text('現在は $_formattedDate (過去) の記録を表示しています', style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),

            Text('$_formattedDate ($_timeSlot) のコンディション', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.3))),
              child: Column(
                children: [
                  const Row(children: [Icon(Icons.explore, color: Colors.blue), SizedBox(width: 8), Text('風向 (Wind Direction)', style: TextStyle(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _directions.contains(windDirFrom) ? windDirFrom : null,
                          decoration: const InputDecoration(labelText: 'から (From)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                          items: _directions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (val) => _saveCondition('windDirFrom', val),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Icon(Icons.arrow_forward, color: Colors.grey)),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _directions.contains(windDirTo) ? windDirTo : null,
                          decoration: const InputDecoration(labelText: 'まで (To)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                          items: _directions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (val) => _saveCondition('windDirTo', val),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.3))),
              child: Column(
                children: [
                  const Row(children: [Icon(Icons.air, color: Colors.blue), SizedBox(width: 8), Text('風速 (Wind Speed)', style: TextStyle(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: windSpeedMin,
                          decoration: const InputDecoration(labelText: '最小 (Min)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white, suffixText: 'm/s'),
                          items: _windSpeeds.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) => _saveCondition('windSpeedMin', val),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Icon(Icons.arrow_forward, color: Colors.grey)),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: windSpeedMax,
                          decoration: const InputDecoration(labelText: '最大 (Max)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white, suffixText: 'm/s'),
                          items: _windSpeeds.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) => _saveCondition('windSpeedMax', val),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('コンディション・海面に関するメモ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            AutoSaveTextField(
              key: ValueKey('wind_comment_${_formattedDate}_$_timeSlot'),
              initialText: windComment,
              hintText: '例：ブローの入り方、潮の状況、波の高さなど...',
              onSave: (val) => _saveComment('風', val),
            ),
            const SizedBox(height: 50),
          ],
        );
      },
    );
  }

  Widget _buildInputTab(String category) {
    final subCategories = _checklistData[category]!;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('practice_reports')
          .doc(_documentId)
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic> currentData = {};
        if (snapshot.hasData && snapshot.data!.exists) {
          currentData = snapshot.data!.data() as Map<String, dynamic>;
        }
        Map<String, dynamic> scores = currentData['scores'] ?? {};
        String initialComment = currentData['comment_$category'] ?? '';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isToday(_selectedDate))
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(8),
                color: Colors.orange[100],
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(child: Text('現在は $_formattedDate (過去) の記録を表示しています', style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),

            ...subCategories.entries.map((entry) {
              final subCatName = entry.key;
              final items = entry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      border: const Border(left: BorderSide(color: Colors.indigo, width: 4)),
                    ),
                    child: Text(
                      subCatName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  ...items.map((item) {
                    int val = scores[item] ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item, style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _buildRadioBtn(item, 3, '○', val, Colors.green),
                                const SizedBox(width: 12),
                                _buildRadioBtn(item, 2, '△', val, Colors.orange),
                                const SizedBox(width: 12),
                                _buildRadioBtn(item, 1, '×', val, Colors.red),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
              );
            }),

            const Divider(),
            Text('「$category」のメモ', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            AutoSaveTextField(
              key: ValueKey('${_formattedDate}_${_timeSlot}_$category'),
              initialText: initialComment,
              hintText: 'ここに記入すると、全体集計画面で全員に共有されます。',
              onSave: (val) {
                _saveComment(category, val);
              },
            ),
            const SizedBox(height: 50),
          ],
        );
      },
    );
  }

  Widget _buildAnalysisTab() {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    // ★重要: 他のチームの記録が混ざらないように、ユーザーID等だけでなくチームIDでも絞りたいところですが、
    // セキュリティルールで `isSameTeam` を設定したので、チーム外のデータは読めなくなっています。
    // ただし、念のためアプリ上でもフィルタリングするのがベストです。
    // 今回は「同じ日・同じ時間帯」のデータ取得なので、セキュリティルールが正しく効いていればOKです。

    final query = FirebaseFirestore.instance
        .collection('practice_reports')
        .where('date', isEqualTo: _formattedDate)
        .where('timeSlot', isEqualTo: _timeSlot)
        // ★追加: チームIDで絞り込み (セキュリティルールと二重の防御)
        .where('teamId', isEqualTo: _myTeamId);

    if (_myTeamId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['lastUpdated'] is Timestamp ? aData['lastUpdated'] as Timestamp : Timestamp(0, 0);
          final bTime = bData['lastUpdated'] is Timestamp ? bData['lastUpdated'] as Timestamp : Timestamp(0, 0);
          return bTime.compareTo(aTime);
        });
        
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics_outlined, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 10),
                Text('まだ $_timeSlot の記録がありません', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        String windInfo = '情報なし';
        Map<String, dynamic>? myData;
        try {
          final myDoc = docs.firstWhere((d) => (d.data() as Map<String, dynamic>)['userId'] == currentUserUid);
          myData = myDoc.data() as Map<String, dynamic>;
        } catch (_) {}

        Map<String, dynamic>? targetData;
        if (myData != null && myData.containsKey('windDirFrom')) {
          targetData = myData;
        } else if (docs.isNotEmpty) {
          targetData = docs.first.data() as Map<String, dynamic>;
        }

        if (targetData != null && targetData.containsKey('windDirFrom')) {
           windInfo = "${targetData['windDirFrom']}〜${targetData['windDirTo']}\n${targetData['windSpeedMin']}〜${targetData['windSpeedMax']}m/s";
           if (targetData != myData) {
             windInfo += " (チーム最新)";
           }
        }

        Map<String, List<int>> aggregation = {};
        Map<String, List<Map<String, String>>> allComments = {};

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final userName = data['userName'] ?? '匿名';

          final scores = data['scores'] as Map<String, dynamic>? ?? {};
          scores.forEach((key, value) {
            if (value is int && value > 0) {
              if (!aggregation.containsKey(key)) aggregation[key] = [0, 0];
              aggregation[key]![0] += value;
              aggregation[key]![1] += 1;
            }
          });

          data.forEach((key, value) {
            if (key.startsWith('comment_') && value is String && value.isNotEmpty) {
              final cat = key.replaceAll('comment_', '');
              if (!allComments.containsKey(cat)) allComments[cat] = [];
              allComments[cat]!.add({
                'user': userName,
                'text': value,
              });
            }
          });
        }

        final sortedKeys = aggregation.keys.toList()
          ..sort((a, b) {
            double avgA = aggregation[a]![0] / aggregation[a]![1];
            double avgB = aggregation[b]![0] / aggregation[b]![1];
            return avgA.compareTo(avgB);
          });

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 2,
              color: Colors.indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.air, color: Colors.white, size: 32),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('WIND CONDITION', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.0)),
                        Text(windInfo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.indigo),
                SizedBox(width: 8),
                Text('チームスコア平均', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('点数が低い順（重点課題）', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: sortedKeys.map((item) {
                  final count = aggregation[item]![1];
                  final avg = aggregation[item]![0] / count;
                  
                  Color barColor = avg >= 2.5 ? Colors.green : (avg >= 2.0 ? Colors.orange : Colors.red);
                  double percent = (avg - 1.0) / 2.0; 
                  if (percent < 0) percent = 0;

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: barColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Text(avg.toStringAsFixed(1), style: TextStyle(color: barColor, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent,
                                backgroundColor: Colors.grey[100],
                                color: barColor,
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 30),

            const Row(
              children: [
                Icon(Icons.forum, color: Colors.indigo),
                SizedBox(width: 8),
                Text('振り返りコメント', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
              ],
            ),
            const SizedBox(height: 10),

            if (allComments.isEmpty)
               Container(
                 padding: const EdgeInsets.all(20),
                 alignment: Alignment.center,
                 decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                 child: const Text('まだコメントはありません', style: TextStyle(color: Colors.grey)),
               ),

            ...allComments.entries.map((entry) {
              final cat = entry.key;
              final comments = entry.value;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.indigo.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ExpansionTile(
                  leading: const Icon(Icons.folder_open, color: Colors.indigo),
                  title: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold)),
                  childrenPadding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                  initiallyExpanded: false, 
                  children: comments.map((c) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.indigo.shade100,
                              child: Text(c['user']!.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                            ),
                            const SizedBox(width: 8),
                            Text(c['user']!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(c['text']!, style: const TextStyle(fontSize: 14, height: 1.4)),
                      ],
                    ),
                  )).toList(),
                ),
              );
            }),
            const SizedBox(height: 50),
          ],
        );
      },
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Future<String> _getUserName(User user) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null && data.containsKey('name') && data['name'].toString().isNotEmpty) {
        return data['name'];
      }
    } catch (e) {
      debugPrint('Error fetching user name: $e');
    }
    return user.email?.split('@')[0] ?? '匿名';
  }

  Widget _buildRadioBtn(String item, int value, String label, int currentVal, Color color) {
    final isSelected = value == currentVal;
    return InkWell(
      onTap: () {
        if (isSelected) {
          _saveScore(item, 0); 
        } else {
          _saveScore(item, value);
        }
      },
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          border: Border.all(color: isSelected ? color : Colors.grey[300]!, width: isSelected ? 2 : 1),
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  // ★修正: チームIDも一緒に保存
  Future<void> _saveScore(String item, int value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return; // チームIDがなければ保存しない

    final userName = await _getUserName(user);

    final docRef = FirebaseFirestore.instance.collection('practice_reports').doc(_documentId);
    await docRef.set({
      'date': _formattedDate,
      'timeSlot': _timeSlot,
      'userId': user.uid,
      'userName': userName,
      'teamId': _myTeamId, // ★追加
      'scores': {item: value},
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ★修正: チームIDも一緒に保存
  Future<void> _saveComment(String category, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return;

    final userName = await _getUserName(user);

    await FirebaseFirestore.instance.collection('practice_reports').doc(_documentId).set({
      'userName': userName,
      'timeSlot': _timeSlot,
      'date': _formattedDate,
      'teamId': _myTeamId, // ★追加
      'comment_$category': text,
    }, SetOptions(merge: true));
  }

  // ★修正: チームIDも一緒に保存
  Future<void> _saveCondition(String key, dynamic value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return;
    
    await FirebaseFirestore.instance.collection('practice_reports').doc(_documentId).set({
      'timeSlot': _timeSlot,
      'date': _formattedDate,
      'teamId': _myTeamId, // ★追加
      key: value,
    }, SetOptions(merge: true));
  }
}

class AutoSaveTextField extends StatefulWidget {
  final String initialText;
  final String hintText;
  final Function(String) onSave;
  const AutoSaveTextField({super.key, required this.initialText, required this.onSave, this.hintText = ''});
  @override
  State<AutoSaveTextField> createState() => _AutoSaveTextFieldState();
}
class _AutoSaveTextFieldState extends State<AutoSaveTextField> {
  late TextEditingController _controller;
  Timer? _debounce;
  @override
  void initState() { super.initState(); _controller = TextEditingController(text: widget.initialText); }
  @override
  void didUpdateWidget(covariant AutoSaveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != _controller.text) {
       _controller.text = widget.initialText;
    }
  }
  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller, maxLines: 3,
      decoration: InputDecoration(hintText: widget.hintText, border: const OutlineInputBorder(), filled: true, fillColor: Colors.white),
      onChanged: (val) {
        if (_debounce?.isActive ?? false) _debounce!.cancel();
        _debounce = Timer(const Duration(seconds: 1), () => widget.onSave(val));
      },
    );
  }
}