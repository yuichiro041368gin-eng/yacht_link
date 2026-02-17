import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  // ★★★ APIキー ★★★
  final String _apiKey = 'AIzaSyBWBmcMMbxmrNvl1n_dYnRKXCpV2tJ7SME';

  XFile? _videoFile;
  VideoPlayerController? _videoController;
  
  // ★追加: ユーザーの指示入力用コントローラー
  final TextEditingController _promptController = TextEditingController();

  String _resultText = '';
  String _analyzedDate = '';
  String _analyzedVideoName = '';
  String _analyzedBy = '';
  bool _isLoading = false;
  
  // チームID
  String? _myTeamId;

  @override
  void initState() {
    super.initState();
    _fetchMyTeamId();
  }

  // チームID取得
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
    } catch (_) {}
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _promptController.dispose(); // ★追加: メモリ解放
    super.dispose();
  }

  // --- 🔥 Firestore共有ロジック ---
  Future<void> _saveHistory(String text, String videoName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _myTeamId == null) return; 

    final userName = await _getUserName(user);

    await FirebaseFirestore.instance.collection('video_analysis_logs').add({
      'content': text,
      'videoName': videoName,
      'userPrompt': _promptController.text, // ★追加: どんな指示を出したかも保存
      'createdAt': FieldValue.serverTimestamp(),
      'userId': user.uid,
      'userName': userName,
      'teamId': _myTeamId, 
    });
    
    setState(() {
      _analyzedDate = DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());
      _analyzedVideoName = videoName;
      _analyzedBy = userName;
    });
  }

  void _showHistoryDialog() {
    if (_myTeamId == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('動画分析履歴 (チーム内共有)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('video_analysis_logs')
                    .where('teamId', isEqualTo: _myTeamId)
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                      if (snapshot.error.toString().contains('requires an index')) {
                        return const Center(child: Text('インデックスが必要です(デバッグコンソールを確認)', style: TextStyle(color: Colors.red)));
                      }
                      return Center(child: Text('エラー: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const Center(child: Text('履歴はありません', style: TextStyle(color: Colors.grey)));

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final dateStr = _formatDate(data['createdAt']);
                      final videoName = data['videoName'] ?? '名称不明';
                      final user = data['userName'] ?? '匿名';
                      final contentStr = data['content'] as String? ?? '';
                      // ユーザーの指示があれば表示に追加
                      final userPrompt = data['userPrompt'] as String? ?? '';
                      
                      final preview = contentStr.replaceAll('\n', ' ').substring(0, (contentStr.length > 30) ? 30 : contentStr.length);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: const Icon(Icons.movie_creation, color: Colors.indigo),
                        ),
                        title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$user ($videoName)'),
                            if (userPrompt.isNotEmpty)
                              Text('Q: $userPrompt', style: TextStyle(color: Colors.indigo.shade300, fontSize: 12)),
                            Text('A: $preview...'),
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () {
                          setState(() {
                            _resultText = contentStr;
                            _analyzedDate = dateStr;
                            _analyzedVideoName = videoName;
                            _analyzedBy = user;
                            // 履歴から復元するときは入力欄には反映しない、またはクリアする
                            _promptController.text = userPrompt; 
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

  // --- 動画処理ロジック ---
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 20),
    );

    if (pickedFile != null) {
      await _videoController?.dispose();
      final controller = VideoPlayerController.networkUrl(Uri.parse(pickedFile.path));
      await controller.initialize();

      setState(() {
        _videoFile = pickedFile;
        _videoController = controller;
        _resultText = ''; 
        _analyzedDate = '';
        _promptController.clear(); // 動画を選び直したらテキストもクリア
      });
    }
  }

  Future<void> _analyzeVideo() async {
    if (_videoFile == null) return;
    
    if (_myTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('チーム情報を読み込んでいます...')));
      return;
    }

    try {
      final int fileSize = await _videoFile!.length();
      if (fileSize > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('動画サイズが大きすぎます (20MB以下にしてください)。'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('サイズチェックエラー: $e');
    }

    setState(() {
      _isLoading = true;
      _resultText = ''; 
    });

    try {
      final videoBytes = await _videoFile!.readAsBytes();
      final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: _apiKey);
      
      // ★修正: ユーザー入力をプロンプトに組み込む
      String userInstruction = _promptController.text.trim();
      
      StringBuffer promptBuffer = StringBuffer();
      promptBuffer.writeln("あなたはプロのヨット競技コーチです。この動画を見て、セーリングの技術についてアドバイスしてください。");
      
      if (userInstruction.isNotEmpty) {
        promptBuffer.writeln("\n【選手からの相談・補足情報】");
        promptBuffer.writeln(userInstruction);
        promptBuffer.writeln("\nこれらを踏まえて、良い点と改善点を具体的に教えてください。");
      } else {
        promptBuffer.writeln("特に、フォーム、動作、風への対応などについて、良い点と改善点を具体的に教えてください。");
      }
      
      promptBuffer.writeln("\n出力はMarkdown形式で見やすく整理してください。");

      final content = [
        Content.multi([TextPart(promptBuffer.toString()), DataPart('video/mp4', videoBytes)])
      ];

      final response = await model.generateContent(content);
      final responseText = response.text ?? '分析結果を取得できませんでした。';

      await _saveHistory(responseText, _videoFile!.name);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _resultText = responseText;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _resultText = 'エラーが発生しました。\n詳細: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('動画分析', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      floatingActionButton: null,
      
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16.0),
              child: Text(
                '※ スマホのメモリ制限のため、動画は「20秒以内」「低画質」推奨です。',
                style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),

            // 1. 動画選択エリア
            if (_videoFile == null)
              GestureDetector(
                onTap: _pickVideo,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade100, width: 2),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_library, size: 50, color: Colors.indigo),
                      SizedBox(height: 10),
                      Text('ギャラリーから動画を選択', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ],
                  ),
                ),
              )
            else
              // 動画プレイヤー
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                    Container(
                      color: Colors.white,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.indigo,
                              size: 32,
                            ),
                            onPressed: () => setState(() => _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play()),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('選び直す'),
                            onPressed: _pickVideo,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // ★追加: ユーザー指示入力欄
            if (_videoFile != null && !_isLoading)
              TextField(
                controller: _promptController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'AIへの指示・補足 (任意)',
                  hintText: '例：ジャイブの瞬間の足の位置を見てください。\n例：この時の風速は5m/sです。',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  alignLabelWithHint: true,
                ),
              ),

            const SizedBox(height: 20),

            // 2. 分析ボタン
            ElevatedButton.icon(
              onPressed: (_videoFile != null && !_isLoading) ? _analyzeVideo : null,
              icon: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.analytics),
              label: Text(_isLoading ? '分析中...' : 'AI分析を実行'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 16),

            // 3. 履歴ボタン
            TextButton.icon(
              onPressed: _showHistoryDialog,
              icon: const Icon(Icons.history, color: Colors.indigo),
              label: const Text('過去の分析履歴を見る (チーム内共有)', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
            ),

            const SizedBox(height: 20),

            // 4. 結果表示エリア
            if (_isLoading)
               const Padding(
                 padding: EdgeInsets.all(32.0),
                 child: Text('動画を分析しています...\n(そのままお待ちください)', textAlign: TextAlign.center, style: TextStyle(color: Colors.indigo)),
               ),

            if (_resultText.isNotEmpty && !_isLoading) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.amber[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(
                  children: [
                    Text('実行: $_analyzedDate', style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
                    if (_analyzedVideoName.isNotEmpty) Text('対象: $_analyzedVideoName', style: const TextStyle(fontSize: 12, color: Colors.brown)),
                  ],
                ),
              ),
              
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Markdown(
                  data: _resultText,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('※この結果はチーム内に共有されます (by $_analyzedBy)', style: const TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.right),
              ),
              const SizedBox(height: 50),
            ],
          ],
        ),
      ),
    );
  }
}