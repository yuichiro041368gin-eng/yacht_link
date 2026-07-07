import 'app_theme.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('ログインしてください'));

    // ★重要: まず自分の teamId を取得してから画面を表示する
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
        final String? myTeamId = userData?['teamId'];

        if (myTeamId == null) {
          return const Center(child: Text('チーム情報が取得できませんでした'));
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('管理者ページ'),
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              bottom: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(text: '承認待ち', icon: Icon(Icons.notifications)),
                  Tab(text: '部員一覧・編集', icon: Icon(Icons.people)),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _PendingUsersTab(teamId: myTeamId), 
                _ApprovedUsersTab(teamId: myTeamId),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 1. 承認待ちユーザーのリスト
// -----------------------------------------------------------------------------
class _PendingUsersTab extends StatelessWidget {
  final String teamId;
  const _PendingUsersTab({required this.teamId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('teamId', isEqualTo: teamId) // 自チームで絞り込み
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // インデックスエラー等の表示
          return Center(child: Text('エラーが発生しました: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('承認待ちのユーザーはいません', style: TextStyle(color: Colors.grey)));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final uid = docs[index].id;
            final name = data['name'] ?? '未設定';
            final email = data['email'] ?? '';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(email),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  onPressed: () async {
                    try {
                      // ★承認処理 (エラー処理付き)
                      await FirebaseFirestore.instance.collection('users').doc(uid).update({
                        'status': 'approved',
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('承認しました')));
                      }
                    } catch (e) {
                      // エラー発生時は赤帯を表示
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('承認エラー: $e\nセキュリティルールを確認してください'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('承認する'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 2. 承認済み部員のリスト
// -----------------------------------------------------------------------------
class _ApprovedUsersTab extends StatelessWidget {
  final String teamId;
  const _ApprovedUsersTab({required this.teamId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('teamId', isEqualTo: teamId) // 自チームで絞り込み
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('部員がいません'));

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (context, index) => const Divider(),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final uid = docs[index].id;
            final name = data['name'] ?? '未設定';
            final role = data['role'] ?? 'member';
            final teamRole = data['teamRole'] ?? ''; 
            final grade = data['grade'] ?? '';

            final bool isTargetAdmin = (role == 'admin');

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isTargetAdmin ? Colors.redAccent : AppColors.primary.shade100,
                child: Icon(Icons.person, color: isTargetAdmin ? Colors.white : AppColors.primary),
              ),
              title: Text('$name ($grade)'),
              subtitle: Text(teamRole.isNotEmpty ? teamRole : '役職なし'),
              trailing: isTargetAdmin
                  ? const Chip(label: Text('管理者', style: TextStyle(fontSize: 10)))
                  : IconButton(
                      icon: const Icon(Icons.person_remove, color: Colors.red),
                      onPressed: () => _showDeleteDialog(context, uid, name),
                    ),
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, String uid, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メンバーの退会処理'),
        content: Text('本当に「$name」さんをチームから退会させますか？\n\n※この操作を実行すると、相手はログインしてもアプリを使用できなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                // ★削除処理 (エラー処理付き)
                await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$name さんを退会させました')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // ダイアログを閉じる
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('削除エラー: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('退会させる'),
          ),
        ],
      ),
    );
  }
}