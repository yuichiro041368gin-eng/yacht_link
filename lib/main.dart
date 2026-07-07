import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'member_list_page.dart'; // 追加
import 'app_theme.dart';

// 各ページの読み込み
import 'auth_page.dart';
import 'team_select_page.dart';
import 'waiting_page.dart';
import 'home_page.dart';
import 'log_page.dart';
import 'video_page.dart';
import 'equipment_page.dart';
import 'settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const YachtLinkApp());
}

class YachtLinkApp extends StatelessWidget {
  const YachtLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YachtLink',
      theme: AppTheme.light,
      // ★ここから門番システム
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(), // 1. ログインしてる？
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          // A. ログインしてない → ログイン画面へ
          if (!snapshot.hasData) {
            return const AuthPage();
          }

          // B. ログインしてる → さらに「ユーザー情報(status)」を見に行く
          final User user = snapshot.data!;
          
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              // データがまだない（初回登録直後など） → ★チーム選択へ！
              if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                return const TeamSelectPage();
              }

              final userData = userSnapshot.data!.data() as Map<String, dynamic>;
              final status = userData['status']; // 'pending' や 'approved'

              // C. 状態によって振り分け
              if (status == 'approved') {
                return const MainScreen(); // 承認済み！いつもの画面へ
              } else if (status == 'pending') {
                return const WaitingPage(); // 承認待ち画面へ
              } else {
                return const TeamSelectPage(); // それ以外はチーム選択へ
              }
            },
          );
        },
      ),
    );
  }
}

// いつものメイン画面（中身は変更なし）
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = <Widget>[
    HomePage(),
    LogPage(),
    VideoPage(),
    EquipmentPage(),
    MemberListPage(),
    SettingsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack で全タブの状態（スクロール位置・入力途中の内容・
      // 読み込み済みデータ）を保持し、切替のたびの再構築と再クエリを防ぐ
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: _onItemTapped,
        selectedIndex: _selectedIndex,
        destinations: const <Widget>[
          NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics),
              label: 'コーチング'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '日誌'),
          NavigationDestination(
              icon: Icon(Icons.video_camera_front_outlined),
              selectedIcon: Icon(Icons.video_camera_front),
              label: '分析'),
          NavigationDestination(
              icon: Icon(Icons.sailing_outlined),
              selectedIcon: Icon(Icons.sailing),
              label: '機材'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: '名簿'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '設定'),
        ],
      ),
    );
  }
}