import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _teamNameController = TextEditingController();

  List<TextEditingController> _roleControllers = [];

  String _position = 'スキッパー';
  String _grade = '1年';
  String _yachtClass = '470';
  String _sailingCert = '未設定'; // 部内帆走資格（配艇チェッカーで使用）
  bool _hasBoatLicense = false; // 小型船舶操縦免許
  String _gender = '未設定'; // レスキュー乗員の男女比チェックで使用（任意）
  bool _isLoading = true;
  bool _isAdmin = false;
  
  // ★追加: 現在のチームIDを保持しておく変数
  String? _currentTeamId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teamNameController.dispose();
    for (var controller in _roleControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    final prefs = await SharedPreferences.getInstance();

    if (mounted) {
      setState(() {
        _nameController.text = data?['name'] ?? prefs.getString('name') ?? '';
        _teamNameController.text = data?['teamName'] ?? 'ヨット部';

        _position = data?['position'] ?? prefs.getString('position') ?? 'スキッパー';
        _grade = data?['grade'] ?? prefs.getString('grade') ?? '1年';
        _yachtClass = data?['class'] ?? prefs.getString('class') ?? '470';
        _sailingCert = data?['sailingCert'] ?? '未設定';
        _hasBoatLicense = data?['hasBoatLicense'] == true;
        _gender = data?['gender'] ?? '未設定';
        _isAdmin = (data?['role'] == 'admin');
        
        // ★修正: 固定IDへの強制書き換えを削除し、現在のチームIDを保持
        _currentTeamId = data?['teamId'];

        String savedRoles = data?['teamRole'] ?? prefs.getString('teamRole') ?? '';
        _roleControllers = [];
        if (savedRoles.isNotEmpty) {
          final roles = savedRoles.split(' / ');
          for (var role in roles) {
            _roleControllers.add(TextEditingController(text: role));
          }
        } else {
          _roleControllers.add(TextEditingController());
        }

        _isLoading = false;
      });
    }
  }

  void _addRoleField() {
    setState(() {
      _roleControllers.add(TextEditingController());
    });
  }

  void _removeRoleField(int index) {
    if (_roleControllers.length > 1) {
      setState(() {
        _roleControllers[index].dispose();
        _roleControllers.removeAt(index);
      });
    } else {
      _roleControllers[0].clear();
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String combinedRoles = _roleControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).join(' / '); 
      
      // ★修正: チームIDは現在のものを維持 (上書きしない)
      // もしチームIDが未設定ならエラーにするか、何もしない
      if (_currentTeamId == null) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エラー: 所属チーム情報がありません')));
         return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameController.text,
        'position': _position,
        'grade': _grade,
        'class': _yachtClass,
        'teamRole': combinedRoles,
        'teamId': _currentTeamId, // ★修正: 保持していたIDを使用
        'teamName': _teamNameController.text,
        'sailingCert': _sailingCert,
        'hasBoatLicense': _hasBoatLicense,
        'gender': _gender,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', _nameController.text);
      await user.updateDisplayName(_nameController.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('プロフィールを更新しました！')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    }
  }

  void _showWithdrawDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退会の確認', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text(
          '本当にチームから退会しますか？\n\n'
          '・あなたのアカウント情報は削除されます。\n'
          '・過去に投稿した日誌や機材データは残ります。\n'
          '・再度利用するには、再登録と承認が必要です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await _withdraw();
            },
            child: const Text('退会する'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      Navigator.pop(context);
      setState(() => _isLoading = true);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('退会処理に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text('マイページ設定'), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircleAvatar(radius: 40, backgroundColor: Colors.indigo, child: Icon(Icons.person, size: 50, color: Colors.white)),
            const SizedBox(height: 20),

            if (_isAdmin) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPage())),
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('【管理者用】メンバー承認画面へ'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 30),
            ],

            TextField(
              controller: _teamNameController, 
              readOnly: true, 
              style: const TextStyle(color: Colors.black54),
              decoration: InputDecoration(
                labelText: '所属チーム名', 
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[200],
              ),
            ),
            const SizedBox(height: 20),

            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '名前', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            
            Align(alignment: Alignment.centerLeft, child: Text('部内の役職 (複数可)', style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.bold))),
            const SizedBox(height: 8),
            ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _roleControllers.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Expanded(child: TextField(controller: _roleControllers[index], decoration: InputDecoration(labelText: '役職 ${index + 1}', hintText: '例: 主将、会計', border: const OutlineInputBorder()))), const SizedBox(width: 8), IconButton(icon: Icon(Icons.remove_circle_outline, color: _roleControllers.length > 1 ? Colors.red : Colors.grey), onPressed: _roleControllers.length > 1 ? () => _removeRoleField(index) : null)]))),
            TextButton.icon(onPressed: _addRoleField, icon: const Icon(Icons.add), label: const Text('役職を追加')),
            
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(initialValue: _grade, decoration: const InputDecoration(labelText: '学年', border: OutlineInputBorder()), items: ['1年', '2年', '3年', '4年', '院生', 'OB/OG', 'コーチ'].map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(), onChanged: (val) => setState(() => _grade = val!)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(initialValue: _yachtClass, decoration: const InputDecoration(labelText: 'クラス (艇種)', border: OutlineInputBorder()), items: ['470', 'Snipe', '両方', 'その他'].map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(), onChanged: (val) => setState(() => _yachtClass = val!)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(initialValue: _position, decoration: const InputDecoration(labelText: 'ポジション', border: OutlineInputBorder()), items: ['スキッパー', 'クルー', '両方', 'マネージャー', 'サポーター'].map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(), onChanged: (val) => setState(() => _position = val!)),
            const SizedBox(height: 20),

            // ★配艇チェッカー用のプロフィール項目
            DropdownButtonFormField<String>(
              initialValue: _sailingCert,
              decoration: const InputDecoration(
                labelText: '部内帆走資格',
                helperText: 'スキッパーは必ず設定してください（配艇チェッカーの出艇可否判定に使用）',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              items: ['未設定', '無資格', '初級', '中級', '上級'].map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(),
              onChanged: (val) => setState(() => _sailingCert = val!),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                labelText: '性別（任意）',
                helperText: 'レスキュー乗員の男女比チェック（安全マニュアルⅠ-6）に使用',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              items: ['未設定', '男性', '女性'].map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(),
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

            SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: _saveProfile, icon: const Icon(Icons.cloud_upload), label: const Text('保存して公開'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white))),
            const SizedBox(height: 40),
            
            OutlinedButton.icon(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout), label: const Text('ログアウト'), style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo)),
            
            const SizedBox(height: 50),
            const Divider(),
            
            TextButton.icon(
              onPressed: _showWithdrawDialog,
              icon: const Icon(Icons.warning_amber, color: Colors.red, size: 18),
              label: const Text('アカウントを完全に削除する（退会）', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}