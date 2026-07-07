import 'app_theme.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; 

class EquipmentPage extends StatefulWidget {
  const EquipmentPage({super.key});

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  final List<String> _fixedCategories = ['艇', 'セール', 'レスキュー', '部品・工具', 'その他'];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('ログインしてください'));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
        final String? currentTeamId = userData?['teamId'];

        if (currentTeamId == null || currentTeamId.isEmpty) {
          return const Center(child: Text('チームに所属していません。\n設定画面からチームを作成または参加してください。'));
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('categories').where('teamId', isEqualTo: currentTeamId).orderBy('createdAt', descending: false).snapshots(),
          builder: (context, categorySnapshot) {
            List<String> categories = [..._fixedCategories];

            if (categorySnapshot.hasData) {
              final customCats = categorySnapshot.data!.docs.map((d) => d['name'] as String).toList();
              for (var cat in customCats) {
                if (!categories.contains(cat)) categories.add(cat);
              }
            }

            return DefaultTabController(
              key: ValueKey(currentTeamId), 
              length: categories.length,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('機材・備品管理', style: TextStyle(fontWeight: FontWeight.bold)),
                  centerTitle: true,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  actions: [Padding(padding: const EdgeInsets.only(right: 8.0), child: IconButton(icon: const Icon(Icons.settings), onPressed: () => _showCategoryManager(currentTeamId)))],
                  bottom: TabBar(isScrollable: true, labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: AppColors.aqua, indicatorWeight: 3, tabs: categories.map((cat) => Tab(text: cat)).toList()),
                ),
                body: TabBarView(children: categories.map((cat) => _buildEquipmentList(cat, categories, currentTeamId)).toList()),
                floatingActionButton: Builder(
                  builder: (context) => FloatingActionButton(onPressed: () { final int currentIndex = DefaultTabController.of(context).index; _showFormSheet(context: context, categories: categories, initialCategory: categories[currentIndex], currentTeamId: currentTeamId); }, backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: Colors.white)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEquipmentList(String category, List<String> allCategories, String teamId) {
    Query query = FirebaseFirestore.instance.collection('equipment').where('teamId', isEqualTo: teamId).where('category', isEqualTo: category);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('requires an index')) {
             return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.warning_amber, color: Colors.orange, size: 40), const SizedBox(height: 10), const Text('データの準備中...', style: TextStyle(fontWeight: FontWeight.bold)), const Padding(padding: EdgeInsets.all(8.0), child: Text('管理者の方は、PCでデバッグコンソールを開き、\n表示されるURLからインデックスを作成してください。', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)))]));
          }
          return Center(child: Text('エラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return Center(child: Text('データなし', style: TextStyle(color: Colors.grey[400])));

        List<Map<String, dynamic>> items = docs.map((doc) { final data = doc.data() as Map<String, dynamic>; data['id'] = doc.id; return data; }).toList();

        // 艇やセールの場合、ExpansionTile (折りたたみ) を使う
        if (category == '艇' || category == 'セール') {
          List<Map<String, dynamic>> list470 = items.where((d) => d['type'] == '470').toList();
          List<Map<String, dynamic>> listSnipe = items.where((d) => d['type'] == 'Snipe').toList();
          
          int sortFunc(Map<String, dynamic> a, Map<String, dynamic> b) {
            String nameA = a['name'] ?? ''; String nameB = b['name'] ?? '';
            int numA = int.tryParse(nameA.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            int numB = int.tryParse(nameB.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            if (numA != numB) return numB.compareTo(numA);
            return nameA.compareTo(nameB);
          }
          list470.sort(sortFunc); listSnipe.sort(sortFunc);

          return ListView(
            padding: const EdgeInsets.all(10),
            children: [
              if (list470.isNotEmpty) _buildExpansionGroup('470 CLASS (${list470.length})', Colors.blue[800]!, list470, category, allCategories, teamId),
              if (listSnipe.isNotEmpty) _buildExpansionGroup('SNIPE CLASS (${listSnipe.length})', Colors.orange[800]!, listSnipe, category, allCategories, teamId),
            ],
          );
        } else {
          // その他のカテゴリは今まで通りのリスト表示
          items.sort((a, b) { final tA = a['createdAt'] as Timestamp?; final tB = b['createdAt'] as Timestamp?; if (tA == null) return 1; if (tB == null) return -1; return tB.compareTo(tA); });
          return ListView(padding: const EdgeInsets.all(10), children: items.map((d) => _buildEquipmentCard(d, category, allCategories, teamId)).toList());
        }
      },
    );
  }

  // 折りたたみ可能なグループを作るウィジェット
  Widget _buildExpansionGroup(String title, Color color, List<Map<String, dynamic>> items, String category, List<String> allCategories, String teamId) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.3))),
      child: ExpansionTile(
        // ★修正: Keyを追加して状態を独立させる
        key: PageStorageKey(title), 
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        leading: Icon(Icons.sailing, color: color),
        childrenPadding: const EdgeInsets.only(bottom: 10),
        children: items.map((d) => _buildEquipmentCard(d, category, allCategories, teamId)).toList(),
      ),
    );
  }

  Widget _buildEquipmentCard(Map<String, dynamic> data, String category, List<String> allCategories, String currentTeamId) {
    final String title = data['name'] ?? '名称なし';
    final String detail = data['detail'] ?? '';
    final String user = data['userName'] ?? '匿名';
    final int quantity = data['quantity'] ?? 0;
    // ★追加: 最終給油日
    final String lastRefueled = data['lastRefueled'] ?? '';

    bool isQuantityMode = (category == '部品・工具');
    
    String status = data.containsKey('status') ? data['status'] : (data['isAvailable'] == false ? '故障中' : '使用可');
    
    Color statusColor = (status == '修理中') ? Colors.orange.shade700 : (status == '故障中' ? Colors.red.shade700 : Colors.green.shade700);
    IconData statusIcon = (status == '修理中') ? Icons.build : (status == '故障中' ? Icons.error : Icons.check_circle);

    Widget leadingIcon;
    if (isQuantityMode) {
      leadingIcon = CircleAvatar(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, child: Text('$quantity', style: const TextStyle(fontWeight: FontWeight.bold)));
    } else {
      leadingIcon = SizedBox(width: 50, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(statusIcon, color: statusColor, size: 28), const SizedBox(height: 2), FittedBox(child: Text(status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)))]));
    }

    return Card(
      elevation: 0,
      color: Colors.grey[50], 
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        onTap: () => _showFormSheet(context: context, docId: data['id'], data: data, categories: allCategories, currentTeamId: currentTeamId),
        leading: leadingIcon,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (detail.isNotEmpty) Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87)),
          // ★追加: レスキューの場合、種別・定員・給油日を表示
          if (category == 'レスキュー')
            Text('${data['rescueType'] ?? '種別未設定'} / 定員: ${data['capacity']?.toString() ?? '未設定'}人', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 11)),
          if (category == 'レスキュー' && lastRefueled.isNotEmpty)
            Text('最終給油: $lastRefueled', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11)),
          
          Text(isQuantityMode ? '最終更新: $user' : '報告: $user', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
        trailing: const Icon(Icons.edit_note, color: Colors.grey),
      ),
    );
  }

  // --- ボトムシート (Bottom Sheet) ---
  void _showFormSheet({required BuildContext context, String? docId, Map<String, dynamic>? data, required List<String> categories, required String currentTeamId, String? initialCategory}) {
    if (data != null && data.containsKey('teamId') && data['teamId'] != currentTeamId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エラー: チーム情報が不整合です')));
      return;
    }

    String selectedCategory = data?['category'] ?? initialCategory ?? categories.first;
    String selectedType = data?['type'] ?? '470';
    String status = data?['status'] ?? '使用可';
    int quantity = data?['quantity'] ?? 1;
    // ★追加: レスキュー艇の種別・定員（配艇チェッカーで使用）
    String rescueType = data?['rescueType'] ?? 'ゴムボート';
    final capacityController = TextEditingController(text: data?['capacity']?.toString() ?? '');

    final nameController = TextEditingController(text: data?['name']);
    final detailController = TextEditingController(text: data?['detail']);
    final quantityController = TextEditingController(text: quantity.toString());
    final yearController = TextEditingController();
    final numberController = TextEditingController();
    // ★追加: 給油日コントローラー
    final refuelingDateController = TextEditingController(text: data?['lastRefueled']);

    if (data != null && data['name'] != null) {
      String currentName = data['name'];
      if (selectedCategory == 'セール' && currentName.contains('年 #')) {
        try { final parts = currentName.split('年 #'); yearController.text = parts[0]; numberController.text = parts[1]; } catch (_) { nameController.text = currentName; }
      } else if (selectedCategory == '艇') { numberController.text = currentName; }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 16,
              right: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      docId == null ? '備品を登録' : '備品を編集',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 20),

                  DropdownButtonFormField<String>(initialValue: categories.contains(selectedCategory) ? selectedCategory : categories.first, decoration: const InputDecoration(labelText: 'カテゴリ', border: OutlineInputBorder()), items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => selectedCategory = v!)),
                  const SizedBox(height: 20),
                  
                  if (selectedCategory == '艇' || selectedCategory == 'セール') ...[
                    Row(children: [Expanded(child: RadioListTile(title: const Text('470'), value: '470', groupValue: selectedType, onChanged: (v) => setState(() => selectedType = v!))), Expanded(child: RadioListTile(title: const Text('Snipe'), value: 'Snipe', groupValue: selectedType, onChanged: (v) => setState(() => selectedType = v!)))]),
                    const SizedBox(height: 10)
                  ],

                  if (selectedCategory == 'セール') ...[
                    Row(children: [Expanded(child: TextField(controller: yearController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '購入年', border: OutlineInputBorder()))), const SizedBox(width: 10), Expanded(child: TextField(controller: numberController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'No.', border: OutlineInputBorder())))]),
                  ] else if (selectedCategory == '艇') ...[
                    TextField(controller: numberController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '艇番', border: OutlineInputBorder()))
                  ] else ...[
                    TextField(controller: nameController, decoration: InputDecoration(labelText: selectedCategory == '部品・工具' ? '部品名' : '名称', border: const OutlineInputBorder()))
                  ],
                  
                  const SizedBox(height: 20),

                  // ★追加: レスキューの場合のみ種別・定員・給油日入力欄を表示
                  if (selectedCategory == 'レスキュー') ...[
                    const Text('レスキュー艇の種別', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Row(children: [
                      Expanded(child: RadioListTile(title: const Text('ゴムボート', style: TextStyle(fontSize: 13)), value: 'ゴムボート', groupValue: rescueType, onChanged: (v) => setState(() => rescueType = v!))),
                      Expanded(child: RadioListTile(title: const Text('ハードボート', style: TextStyle(fontSize: 13)), value: 'ハードボート', groupValue: rescueType, onChanged: (v) => setState(() => rescueType = v!))),
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                      controller: capacityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '定員（人）',
                        helperText: '配艇チェッカーの定員チェックに使用します',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: refuelingDateController,
                      readOnly: true, // キーボードを出さない
                      decoration: const InputDecoration(
                        labelText: '最終給油日',
                        hintText: 'タップして日付を選択',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (pickedDate != null) {
                          setState(() {
                            refuelingDateController.text = DateFormat('yyyy/MM/dd').format(pickedDate);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                  
                  if (selectedCategory == '部品・工具') ...[
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton.filledTonal(onPressed: () { int c = int.tryParse(quantityController.text) ?? 0; if (c > 0) quantityController.text = (c - 1).toString(); }, icon: const Icon(Icons.remove)), const SizedBox(width: 10), SizedBox(width: 80, child: TextField(controller: quantityController, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder()))), const SizedBox(width: 10), IconButton.filledTonal(onPressed: () { int c = int.tryParse(quantityController.text) ?? 0; quantityController.text = (c + 1).toString(); }, icon: const Icon(Icons.add))])
                  ] else ...[
                    const Text('状態', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildStatusOption('使用可', '使用可', Colors.green, Icons.check_circle_outline, status, (val) => setState(() => status = val)),
                        const SizedBox(width: 8),
                        _buildStatusOption('修理中', '修理中', Colors.orange, Icons.build, status, (val) => setState(() => status = val)),
                        const SizedBox(width: 8),
                        _buildStatusOption('故障中', '故障中', Colors.red, Icons.error_outline, status, (val) => setState(() => status = val)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                  TextField(controller: detailController, maxLines: 3, decoration: const InputDecoration(labelText: '備考・詳細', border: OutlineInputBorder())),
                  
                  const SizedBox(height: 30),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        String finalName = nameController.text;
                        if (selectedCategory == 'セール') finalName = (yearController.text.isNotEmpty && numberController.text.isNotEmpty) ? '${yearController.text}年 #${numberController.text}' : (numberController.text.isNotEmpty ? '#${numberController.text}' : finalName);
                        if (selectedCategory == '艇') finalName = numberController.text;
                        if (finalName.isEmpty) return;

                        int finalQuantity = int.tryParse(quantityController.text) ?? 0;
                        String userName = '匿名';
                        if (user != null) { try { final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get(); if (userDoc.exists) userName = userDoc.data()!['name'] ?? userName; } catch (_) {} }

                        final payload = {
                          'teamId': currentTeamId,
                          'category': selectedCategory,
                          'type': (selectedCategory == '艇' || selectedCategory == 'セール') ? selectedType : null,
                          'name': finalName,
                          'detail': detailController.text,
                          'quantity': (selectedCategory == '部品・工具') ? finalQuantity : null,
                          'status': (selectedCategory == '部品・工具') ? '在庫あり' : status, 
                          'isAvailable': status == '使用可',
                          'userName': userName,
                          // ★追加: レスキューの場合のみ日付・種別・定員を保存
                          'lastRefueled': (selectedCategory == 'レスキュー') ? refuelingDateController.text : null,
                          'rescueType': (selectedCategory == 'レスキュー') ? rescueType : null,
                          'capacity': (selectedCategory == 'レスキュー') ? int.tryParse(capacityController.text) : null,
                          'createdAt': data?['createdAt'] ?? FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        };

                        if (docId == null) { await FirebaseFirestore.instance.collection('equipment').add(payload); } else { await FirebaseFirestore.instance.collection('equipment').doc(docId).update(payload); }
                        Navigator.pop(context);
                      },
                      child: const Text('保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  if (docId != null) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () async { await FirebaseFirestore.instance.collection('equipment').doc(docId).delete(); Navigator.pop(context); }, 
                        child: const Text('このデータを削除', style: TextStyle(color: Colors.red))
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusOption(String label, String value, Color color, IconData icon, String currentStatus, Function(String) onSelect) {
    bool isSelected = currentStatus == value;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(value),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: isSelected ? 2 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryManager(String teamId) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カスタムカテゴリ編集'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      decoration: const InputDecoration(hintText: '追加カテゴリ名', labelText: '新しいカテゴリ'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 32),
                    onPressed: () async {
                      if (textController.text.isNotEmpty) {
                        await FirebaseFirestore.instance.collection('categories').add({
                          'name': textController.text.trim(),
                          'teamId': teamId,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        textController.clear();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              
              Flexible(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('categories')
                      .where('teamId', isEqualTo: teamId)
                      .orderBy('createdAt', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'インデックスが必要です。\nデバッグコンソールのリンクをクリックしてください。\n\nエラー詳細:\n${snapshot.error}',
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(child: Text('追加されたカテゴリはありません'));
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        return ListTile(
                          title: Text(doc['name']),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => FirebaseFirestore.instance
                                .collection('categories')
                                .doc(doc.id)
                                .delete(),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
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
}