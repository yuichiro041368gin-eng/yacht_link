import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart'; // ホーム画面へ遷移するために必要

class TeamSelectPage extends StatefulWidget {
  const TeamSelectPage({super.key});

  @override
  State<TeamSelectPage> createState() => _TeamSelectPageState();
}

class _TeamSelectPageState extends State<TeamSelectPage> {
  String _searchText = "";

  // 1. 既存のチームに申請する機能
  Future<void> _applyToTeam(String teamId, String teamName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email,
        'teamId': teamId,
        'teamName': teamName,
        'status': 'pending', // 承認待ち
        'role': 'member',    // 一般メンバー
        'appliedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('申請しました。管理者の承認をお待ちください。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    }
  }

  // 2. 新しいチームを作る機能
  void _showCreateTeamDialog() {
    final nameController = TextEditingController();
    final univController = TextEditingController();

    showDialog(
      context: context, // 親画面（TeamSelectPage）のcontext
      barrierDismissible: false,
      // ★修正: ここで dialogContext という名前をつけ、明確に区別します
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('新規チーム作成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('あなたが管理者となって、新しいチームを作成します。'),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'チーム名 (例: XX大学ヨット部)'),
              ),
              TextField(
                controller: univController,
                decoration: const InputDecoration(labelText: '所属大学・団体名'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext), // キャンセル時はダイアログを閉じる
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;

                try {
                  // A. チームを作成
                  final newTeamRef = await FirebaseFirestore.instance.collection('teams').add({
                    'name': nameController.text,
                    'univ': univController.text,
                    'createdAt': Timestamp.now(),
                  });

                  // B. 作成した本人を「管理者」かつ「承認済み」にする
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                      'email': user.email,
                      'teamId': newTeamRef.id,
                      'teamName': nameController.text,
                      'status': 'approved', // いきなり承認済みにする
                      'role': 'admin',      // 管理者権限をつける
                      'joinedAt': Timestamp.now(),
                    }, SetOptions(merge: true));
                  }

                  // C. 画面遷移処理
                  // ★重要: まずダイアログを閉じる (dialogContextを使用)
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }

                  // ★重要: その後、親画面をホーム画面に置き換える (contextを使用)
                  if (mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  }
                  
                } catch (e) {
                  debugPrint('チーム作成エラー: $e');
                  // エラー時もとりあえずダイアログは閉じる
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                }
              },
              child: const Text('作成して参加'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('所属チームを選択')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTeamDialog,
        icon: const Icon(Icons.add),
        label: const Text('新規チーム作成'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'チーム名で検索',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchText = value),
            ),
            const SizedBox(height: 20),
            
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('teams').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Text('エラーが発生しました');
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final teams = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['name'].toString();
                    return name.contains(_searchText);
                  }).toList();

                  if (teams.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.group_add, size: 60, color: Colors.grey),
                          SizedBox(height: 10),
                          Text(
                            "チームが見つかりません\n右下のボタンから作成してください",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: teams.length,
                    itemBuilder: (context, index) {
                      final doc = teams[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.sailing, size: 40, color: Colors.indigo),
                          title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(data['univ'] ?? ''),
                          trailing: ElevatedButton(
                            onPressed: () => _applyToTeam(doc.id, data['name']),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                            child: const Text('申請する', style: TextStyle(color: Colors.white)),
                          ),
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
    );
  }
}