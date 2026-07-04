// 使用モデル: gemini-3-flash-preview
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
  
  // チームIDと権限、ユーザー名
  String? _myTeamId;
  bool _isAdmin = false;
  String _myUserName = '匿名'; 

  // ★追加: 画面の即時反映用（楽観的更新データ）
  // データベースの反応を待たずに、ここに入っている値を優先して表示します
  final Map<String, int> _optimisticScores = {};

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

  // チェックリストデータ
  Map<String, dynamic> _checklistData = {}; 

  // デフォルトのチェックリスト
  final Map<String, dynamic> _defaultChecklistData = {
    '動作': {
      '動作': ['適切なヒール量、ロール量', 'ヘルム使えてるか', 'メイン、ジブ引いてこれてるか', '煽りの加速感', '船を揺らさない', 'タック後のリーチ', '動作前後のスピードがあるか', '逆ジブ量', 'かかってる時間', '船のアングル'],
    },
    'セーリング': {
      'セールトリム': ['シーティングスタイルの確立', 'ジブは両ピロ、メインはリーチ崩さない', '風の強弱に合わせられる', 'コントロールロープ適切に扱える', '波に合わせられる'],
      'バランス': ['ヒール（ヘルム）が一定', '波の海面での微ヒール、平水面でのフラット', 'しっかりハイクアウトできているか', 'ランニングの一定パワーとヒール'],
      'VMG': ['スピードファースト', '角度とれる'],
    },
    'スタート': {
      'スタート前': ['下のルーム1.5艇幅確保', '微速前進ができる', '動作の確認（煽り）', 'ライン感覚（見通し）', 'デンジャーの見極め（潮・振れ）'],
      'スタート後': ['自艇の上下艇よりバウ出す', 'フルスピード', 'フレッシュウィンドで2分間走れる'],
    },
    'コース': {
      'スタート前': ['ルーティン実施（海面調査）'],
      'スタート後': ['ロングを走る', 'ゲインを確定できる', 'オーバーセールしない', '振れ、ブローの見極め', '艇団に対してのポジショニング'],
    },
  };

  // 表示順序を固定するための優先順位リスト
  final List<String> _sortOrder = [
    '動作',
    'セールトリム', 'バランス', 'VMG',
    'スタート前', 'スタート後',
  ];

  @override
  void initState() {
    super.initState();
    _windSpeeds = List.generate(51, (index) {
      return (index * 0.5).toStringAsFixed(1);
    });
    _fetchUserInfo();
  }

  // 日付や時間が変わったら、一時データをリセット
  void _resetOptimisticData() {
    setState(() {
      _optimisticScores.clear();
    });
  }

  // ユーザー情報とチームID、チェックリスト設定を取得
  Future<void> _fetchUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        final data = doc.data()!;
        setState(() {
          _myTeamId = data['teamId'];
          _isAdmin = data['role'] == 'admin';
          if (data.containsKey('name') && data['name'].toString().isNotEmpty) {
            _myUserName = data['name'];
          }
        });

        if (_myTeamId != null) {
          _loadChecklistConfig();
        }
      }
    } catch (e) {
      debugPrint("Error fetching user info: $e");
    }
  }

  Future<void> _loadChecklistConfig() async {
    if (_myTeamId == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('teams')
          .doc(_myTeamId)
          .collection('settings')
          .doc('checklist');

      final doc = await docRef.get();

      if (doc.exists && doc.data() != null && doc.data()!.isNotEmpty) {
        setState(() {
          _checklistData = doc.data()!;
        });
      } else {
        await docRef.set(_defaultChecklistData);
        setState(() {
          _checklistData = _defaultChecklistData;
        });
      }
    } catch (e) {
      debugPrint("Error loading checklist: $e");
      setState(() {
        _checklistData = _defaultChecklistData;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      _resetOptimisticData(); // 日付変更時にリセット
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
        _resetOptimisticData();
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

  void _showAddItemDialog() {
    if (_checklistData.isEmpty) return;

    final categories = _checklistData.keys.toList();
    String selectedCategory = categories.first;
    String? selectedSubCategory;
    
    Map<String, dynamic> subCats = _checklistData[selectedCategory] ?? {};
    
    List<String> subCatKeys = subCats.keys.toList();
    subCatKeys.sort((a, b) {
      int idxA = _sortOrder.indexOf(a);
      int idxB = _sortOrder.indexOf(b);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return a.compareTo(b);
    });

    if (subCatKeys.isNotEmpty) selectedSubCategory = subCatKeys.first;

    final TextEditingController itemController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('チェック項目の追加'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('新しい評価項目を追加します。\n※チーム全員に反映されます。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: '大カテゴリ', border: OutlineInputBorder()),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      setStateSB(() {
                        selectedCategory = val!;
                        final newSubCats = _checklistData[selectedCategory] as Map<String, dynamic>? ?? {};
                        final newKeys = newSubCats.keys.toList();
                         newKeys.sort((a, b) {
                            int idxA = _sortOrder.indexOf(a);
                            int idxB = _sortOrder.indexOf(b);
                            if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
                            if (idxA != -1) return -1;
                            if (idxB != -1) return 1;
                            return a.compareTo(b);
                          });

                        if (newKeys.isNotEmpty) {
                          selectedSubCategory = newKeys.first;
                        } else {
                          selectedSubCategory = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: selectedSubCategory,
                    decoration: const InputDecoration(labelText: '小カテゴリ', border: OutlineInputBorder()),
                    items: () {
                       final currentSubCats = _checklistData[selectedCategory] as Map<String, dynamic>? ?? {};
                       final keys = currentSubCats.keys.toList();
                       keys.sort((a, b) {
                          int idxA = _sortOrder.indexOf(a);
                          int idxB = _sortOrder.indexOf(b);
                          if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
                          if (idxA != -1) return -1;
                          if (idxB != -1) return 1;
                          return a.compareTo(b);
                       });
                       return keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList();
                    }(),
                    onChanged: (val) => setStateSB(() => selectedSubCategory = val),
                  ),
                  
                  const SizedBox(height: 16),
                  TextField(
                    controller: itemController,
                    decoration: const InputDecoration(labelText: '項目名', hintText: '例：ジャイブの角度', border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                ElevatedButton(
                  onPressed: () async {
                    if (itemController.text.isNotEmpty && selectedSubCategory != null) {
                      await _addNewItemToChecklist(selectedCategory, selectedSubCategory!, itemController.text);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  child: const Text('追加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addNewItemToChecklist(String category, String subCategory, String newItem) async {
    if (_myTeamId == null) return;

    try {
      Map<String, dynamic> newData = Map.from(_checklistData);
      List<String> currentList = List<String>.from(newData[category][subCategory] ?? []);
      
      if (!currentList.contains(newItem)) {
        currentList.add(newItem);
        newData[category][subCategory] = currentList;

        await FirebaseFirestore.instance
            .collection('teams')
            .doc(_myTeamId)
            .collection('settings')
            .doc('checklist')
            .set(newData);
        
        setState(() {
          _checklistData = newData;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('項目を追加しました！')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('追加エラー: $e')));
      }
    }
  }

  void _showDeleteConfirmDialog(String category, String subCategory, String itemToDelete) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('項目の削除'),
          content: Text('「$itemToDelete」を削除しますか？\n※この操作は元に戻せません。チーム全員からこの項目が消えます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                await _deleteItemFromChecklist(category, subCategory, itemToDelete);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteItemFromChecklist(String category, String subCategory, String itemToDelete) async {
    if (_myTeamId == null) return;

    try {
      Map<String, dynamic> newData = Map.from(_checklistData);
      List<String> currentList = List<String>.from(newData[category][subCategory] ?? []);
      
      if (currentList.contains(itemToDelete)) {
        currentList.remove(itemToDelete);
        newData[category][subCategory] = currentList;

        await FirebaseFirestore.instance
            .collection('teams')
            .doc(_myTeamId)
            .collection('settings')
            .doc('checklist')
            .set(newData);
        
        setState(() {
          _checklistData = newData;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('項目を削除しました')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('削除エラー: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checklistData.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
                      _resetOptimisticData(); // 時間帯変更時にリセット
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
            if (_isAdmin)
              IconButton(
                icon: const Icon(Icons.edit_note),
                tooltip: 'チェック項目を追加',
                onPressed: _showAddItemDialog,
              ),
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
                          initialValue: _directions.contains(windDirFrom) ? windDirFrom : null,
                          decoration: const InputDecoration(labelText: 'から (From)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                          items: _directions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (val) => _saveCondition('windDirFrom', val),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Icon(Icons.arrow_forward, color: Colors.grey)),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _directions.contains(windDirTo) ? windDirTo : null,
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
                          initialValue: windSpeedMin,
                          decoration: const InputDecoration(labelText: '最小 (Min)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white, suffixText: 'm/s'),
                          items: _windSpeeds.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) => _saveCondition('windSpeedMin', val),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Icon(Icons.arrow_forward, color: Colors.grey)),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: windSpeedMax,
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
    final subCategories = _checklistData[category] as Map<String, dynamic>? ?? {};

    final sortedKeys = subCategories.keys.toList();
    sortedKeys.sort((a, b) {
      int indexA = _sortOrder.indexOf(a);
      int indexB = _sortOrder.indexOf(b);
      if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
      if (indexA != -1) return -1;
      if (indexB != -1) return 1;
      return a.compareTo(b);
    });

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
        Map<String, dynamic> serverScores = currentData['scores'] ?? {}; // Firestoreのデータ
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

            ...sortedKeys.map((subCatName) {
              final items = List<String>.from(subCategories[subCatName] ?? []);

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
                    // ★重要: 「今押した値 (_optimisticScores)」があればそれを優先表示
                    // なければ「サーバーの値 (serverScores)」を表示
                    int val = _optimisticScores[item] ?? serverScores[item] ?? 0;
                    
                    return GestureDetector(
                      onLongPress: () {
                        if (_isAdmin) {
                          _showDeleteConfirmDialog(category, subCatName, item);
                        }
                      },
                      child: Card(
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
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
              );
            }),

            const Divider(),
            
            // ★追加: 過去の似た条件のログを呼び出すボタン
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('「$category」のメモ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => _showSimilarPastLogsBottomSheet(context, category, currentData),
                  icon: const Icon(Icons.manage_search, color: Colors.indigo),
                  label: const Text('似た風の日の過去ログ', style: TextStyle(color: Colors.indigo)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.indigo.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
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

    final query = FirebaseFirestore.instance
        .collection('practice_reports')
        .where('date', isEqualTo: _formattedDate)
        .where('timeSlot', isEqualTo: _timeSlot)
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

  Widget _buildRadioBtn(String item, int value, String label, int currentVal, Color color) {
    final isSelected = value == currentVal;
    
    return Material(
      color: isSelected ? color : Colors.white,
      shape: CircleBorder(
        side: BorderSide(color: isSelected ? color : Colors.grey[300]!, width: isSelected ? 2 : 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () {
          int newValue = isSelected ? 0 : value;
          setState(() {
            _optimisticScores[item] = newValue;
          });
          _saveScore(item, newValue);
        },
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveScore(String item, int value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return;

    final docRef = FirebaseFirestore.instance.collection('practice_reports').doc(_documentId);
    
    await docRef.set({
      'date': _formattedDate,
      'timeSlot': _timeSlot,
      'userId': user.uid,
      'userName': _myUserName,
      'teamId': _myTeamId,
      'scores': {item: value},
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveComment(String category, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return;

    await FirebaseFirestore.instance.collection('practice_reports').doc(_documentId).set({
      'userName': _myUserName,
      'timeSlot': _timeSlot,
      'date': _formattedDate,
      'teamId': _myTeamId,
      'comment_$category': text,
    }, SetOptions(merge: true));
  }

  // ★修正箇所1: シングルクォーテーションを外し、変数keyとして保存されるようにしました
  Future<void> _saveCondition(String key, dynamic value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return;
    
    await FirebaseFirestore.instance.collection('practice_reports').doc(_documentId).set({
      'timeSlot': _timeSlot,
      'date': _formattedDate,
      'teamId': _myTeamId,
      key: value, // ← ここを修正しています
    }, SetOptions(merge: true));
  }

  // ★修正箇所2: チームIDを含めて検索し、権限エラーとインデックスエラーを回避しました
  void _showSimilarPastLogsBottomSheet(BuildContext context, String category, Map<String, dynamic> currentData) {
    final String? currentWindDir = currentData['windDirFrom'];
    final String? currentWindSpeed = currentData['windSpeedMin'];

    if (currentWindDir == null && currentWindSpeed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先に「風」タブで今日の風向や風速を入力してください')),
      );
      return;
    }

    // クエリはシート表示前に1回だけ実行する。
    // builder内で生成するとシートのドラッグ等で再ビルドされるたびに
    // 全件再取得が走り、スピナーが出続けて動作が重くなる。
    final Future<QuerySnapshot> pastLogsFuture = FirebaseFirestore.instance
        .collection('practice_reports')
        .where('teamId', isEqualTo: _myTeamId)
        .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .get();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history, color: Colors.indigo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '過去の「$category」の反省\n(条件: $currentWindDir / $currentWindSpeed m/s)',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                  ),
                  
                  Expanded(
                    child: FutureBuilder<QuerySnapshot>(
                      future: pastLogsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
                        }

                        // ★追加: 取得後にDart側で日付順にソートする
                        final docs = snapshot.data?.docs.toList() ?? [];
                        docs.sort((a, b) {
                          final aData = a.data() as Map<String, dynamic>;
                          final bData = b.data() as Map<String, dynamic>;
                          final aDate = aData['date']?.toString() ?? '';
                          final bDate = bData['date']?.toString() ?? '';
                          return bDate.compareTo(aDate); // 新しい日付順（降順）
                        });
                        
                        final similarLogs = docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final logDate = data['date'];
                          final logWindDir = data['windDirFrom'];
                          final logComment = data['comment_$category'];

                          if (logDate == _formattedDate || logComment == null || logComment.toString().trim().isEmpty) {
                            return false;
                          }

                          if (currentWindDir != null && logWindDir == currentWindDir) {
                            return true;
                          }
                          return false;
                        }).toList();

                        if (similarLogs.isEmpty) {
                          return const Center(
                            child: Text('似た条件で、コメントが書かれた過去ログはありません。', style: TextStyle(color: Colors.grey)),
                          );
                        }

                        return ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.all(16),
                          itemCount: similarLogs.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final data = similarLogs[index].data() as Map<String, dynamic>;
                            final date = data['date'];
                            final timeSlot = data['timeSlot'];
                            final speed = data['windSpeedMin'] ?? '?';
                            final comment = data['comment_$category'];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('$date ($timeSlot)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('風速: $speed m/s〜', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(comment, style: const TextStyle(fontSize: 14, height: 1.5)),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
  void initState() { 
    super.initState(); 
    _controller = TextEditingController(text: widget.initialText); 
  }

  @override
  void didUpdateWidget(covariant AutoSaveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != _controller.text) {
       _controller.text = widget.initialText;
    }
  }

  @override
  void dispose() { 
    // ★修正箇所3: タブ移動等で画面が破棄される瞬間に、未保存があれば強制保存
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      widget.onSave(_controller.text);
    }
    _controller.dispose(); 
    super.dispose(); 
  }

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