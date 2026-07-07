import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui'; // すりガラス効果用
import 'app_theme.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String _errorMessage = '';
  bool _isLoading = false;

  // --- パスワードリセット処理 ---
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'メールアドレスを入力してください');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$email 宛に再設定メールを送信しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _getJapaneseMessage(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- ログイン・登録処理 ---
  Future<void> _submit() async {
    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _getJapaneseMessage(e.code);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '予期せぬエラーが発生しました';
          _isLoading = false;
        });
      }
    }
  }

  String _getJapaneseMessage(String code) {
    switch (code) {
      case 'user-not-found': return 'ユーザーが見つかりません';
      case 'wrong-password': return 'パスワードが正しくありません';
      case 'email-already-in-use': return 'このメールアドレスは既に使用されています';
      case 'invalid-email': return 'メールアドレスの形式が正しくありません';
      case 'weak-password': return 'パスワードが短すぎます';
      case 'too-many-requests': return '回数制限を超えました。後ほどお試しください';
      default: return 'エラー: $code';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ダークオーシャン背景上のテキスト入力スタイル
  InputDecoration _darkFieldDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      prefixIcon: Icon(icon, color: AppColors.aqua, size: 22),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cyan, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepNavy,
      body: Stack(
        children: [
          // 夜の海のグラデーション背景
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.deepNavy,
                  Color(0xFF0B3055),
                  Color(0xFF0F4C81),
                ],
              ),
            ),
          ),
          // 装飾: 波間の光をイメージした円
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ocean.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: -10,
            child: Icon(Icons.sailing,
                size: 140, color: Colors.white.withValues(alpha: 0.05)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    width: 350,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.cyan.withValues(alpha: 0.35),
                                blurRadius: 26,
                              ),
                            ],
                          ),
                          child: Image.asset('assets/images/logo.png', width: 60, height: 60),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'YachtLink',
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TEAM SAILING PLATFORM',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.aqua.withValues(alpha: 0.9),
                              letterSpacing: 3.0),
                        ),
                        const SizedBox(height: 30),

                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: AppColors.cyan,
                          decoration: _darkFieldDecoration(
                              label: 'メールアドレス', icon: Icons.email_outlined),
                        ),
                        const SizedBox(height: 15),

                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: AppColors.cyan,
                          decoration: _darkFieldDecoration(
                              label: 'パスワード', icon: Icons.lock_outline),
                        ),

                        // --- パスワードを忘れた場合のリンク (ログイン時のみ表示) ---
                        if (_isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _resetPassword,
                              child: Text(
                                'パスワードを忘れた場合',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12),
                              ),
                            ),
                          ),

                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(_errorMessage, style: const TextStyle(color: Color(0xFFFF8787), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),

                        const SizedBox(height: 20),

                        // シアングラデーションのログインボタン
                        Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: AppGradients.cyanCta,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.cyan.withValues(alpha: 0.4),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _isLoading ? null : _submit,
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: AppColors.deepNavy, strokeWidth: 2))
                                    : Text(
                                        _isLogin ? 'ログイン' : '登録する',
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.deepNavy,
                                            letterSpacing: 0.5),
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLogin = !_isLogin;
                              _errorMessage = '';
                            });
                          },
                          child: Text(
                            _isLogin ? '新しくアカウントを作る' : 'すでにアカウントをお持ちの方',
                            style: const TextStyle(color: AppColors.aqua, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
