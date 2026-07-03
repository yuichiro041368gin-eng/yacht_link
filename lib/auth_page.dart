import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui'; // すりガラス効果用

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE8EEF8),
                  Color(0xFFBFD7EA),
                  Color(0xFFF4F7FB),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 350,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/images/logo.png', width: 76, height: 76),
                        const SizedBox(height: 10),
                        const Text(
                          'YachtLink',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                        const SizedBox(height: 30),

                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'メールアドレス',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                            filled: true, fillColor: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 15),

                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'パスワード',
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                            filled: true, fillColor: Colors.white70,
                          ),
                        ),

                        // --- パスワードを忘れた場合のリンク (ログイン時のみ表示) ---
                        if (_isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _resetPassword,
                              child: const Text(
                                'パスワードを忘れた場合',
                                style: TextStyle(color: Colors.indigo, fontSize: 12),
                              ),
                            ),
                          ),

                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              elevation: 5,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _isLoading 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  _isLogin ? 'ログイン' : '登録する',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                            style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
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
