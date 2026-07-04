import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

/// 天気図ページ
/// 安全マニュアル（Ⅱ-1 気象状況）に基づき、出艇前に気象庁の
/// 実況天気図・予想天気図を確認し、当日の気象変化（気圧配置・前線の動き）を
/// 予測するためのページ。
/// - 実況: 直近3日分（3時間毎）をスライダーで遡って気圧配置の推移を確認できる
/// - 予想: 24時間後・48時間後の予想天気図で今後の変化を確認できる
class WeatherMapPage extends StatefulWidget {
  const WeatherMapPage({super.key});

  @override
  State<WeatherMapPage> createState() => _WeatherMapPageState();
}

/// 天気図1枚分
class _ChartImage {
  final String url;
  final DateTime validJst; // この天気図が示す時刻（JST）
  const _ChartImage(this.url, this.validJst);
}

class _WeatherMapPageState extends State<WeatherMapPage> {
  static const String _listUrl =
      'https://www.jma.go.jp/bosai/weather_map/data/list.json';
  static const String _pngBase =
      'https://www.jma.go.jp/bosai/weather_map/data/png/';

  bool _loading = true;
  String? _error;

  List<_ChartImage> _actuals = []; // 実況天気図（古い順）
  _ChartImage? _forecast24; // 24時間予想
  _ChartImage? _forecast48; // 48時間予想

  int _mode = 0; // 0=実況, 1=24時間予想, 2=48時間予想
  int _actualIndex = 0; // 実況天気図の表示位置（_actualsのインデックス）

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse(_listUrl));
      if (res.statusCode != 200) {
        throw Exception('天気図リストの取得に失敗しました (${res.statusCode})');
      }
      final data = json.decode(res.body) as Map<String, dynamic>;
      final near = data['near'] as Map<String, dynamic>;

      final actuals = (near['now'] as List? ?? [])
          .map((f) => _parseChart(f as String, 0))
          .whereType<_ChartImage>()
          .toList();
      final ft24List = (near['ft24'] as List? ?? []);
      final ft48List = (near['ft48'] as List? ?? []);

      if (!mounted) return;
      setState(() {
        _actuals = actuals;
        _actualIndex = actuals.isEmpty ? 0 : actuals.length - 1; // 最新を表示
        _forecast24 = ft24List.isEmpty
            ? null
            : _parseChart(ft24List.last as String, 24);
        _forecast48 = ft48List.isEmpty
            ? null
            : _parseChart(ft48List.last as String, 48);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '取得エラー: $e';
      });
    }
  }

  /// ファイル名から基準時刻（UTC）を取り出して天気図情報を作る。
  /// 例: 20260704053031_0_Z__C_010000_20260704000000_MET_CHT_JCIfsas24_...png
  ///     → 「_MET」直前の14桁が基準時刻（UTC）
  _ChartImage? _parseChart(String fileName, int offsetHours) {
    final m = RegExp(r'_(\d{14})_MET').firstMatch(fileName);
    if (m == null) return null;
    final t = m.group(1)!;
    final baseUtc = DateTime.utc(
      int.parse(t.substring(0, 4)),
      int.parse(t.substring(4, 6)),
      int.parse(t.substring(6, 8)),
      int.parse(t.substring(8, 10)),
      int.parse(t.substring(10, 12)),
    );
    // JSTに変換し、予想図は基準時刻＋予想時間を表示時刻とする
    final validJst = baseUtc.add(Duration(hours: 9 + offsetHours));
    return _ChartImage('$_pngBase$fileName', validJst);
  }

  _ChartImage? get _currentChart {
    switch (_mode) {
      case 1:
        return _forecast24;
      case 2:
        return _forecast48;
      default:
        return (_actualIndex >= 0 && _actualIndex < _actuals.length)
            ? _actuals[_actualIndex]
            : null;
    }
  }

  String _chartLabel(_ChartImage chart) {
    final time = DateFormat('M月d日 HH:mm').format(chart.validJst);
    switch (_mode) {
      case 1:
        return '$time の予想（24時間後）';
      case 2:
        return '$time の予想（48時間後）';
      default:
        final isLatest = _actualIndex == _actuals.length - 1;
        return '$time 実況${isLatest ? '（最新）' : ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('天気図', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '天気図の読み方',
            icon: const Icon(Icons.help_outline),
            onPressed: _showReadingGuide,
          ),
          IconButton(
            tooltip: '再読み込み',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchList,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
              onPressed: _fetchList,
            ),
          ],
        ),
      );
    }

    final chart = _currentChart;
    return Column(
      children: [
        _buildModeSelector(),
        Expanded(
          child: chart == null
              ? const Center(
                  child: Text(
                    '天気図がありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _buildChartView(chart),
        ),
        if (_mode == 0) _buildActualTimeSlider(),
        _buildFooterNote(),
      ],
    );
  }

  // 実況 / 24時間予想 / 48時間予想 の切り替え
  Widget _buildModeSelector() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(
            value: 0,
            icon: Icon(Icons.map_outlined, size: 16),
            label: Text('実況', style: TextStyle(fontSize: 12)),
          ),
          ButtonSegment(
            value: 1,
            icon: Icon(Icons.update, size: 16),
            label: Text('24時間予想', style: TextStyle(fontSize: 12)),
          ),
          ButtonSegment(
            value: 2,
            icon: Icon(Icons.update, size: 16),
            label: Text('48時間予想', style: TextStyle(fontSize: 12)),
          ),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onSelectionChanged: (selection) {
          setState(() => _mode = selection.first);
        },
      ),
    );
  }

  // 天気図本体（ピンチ操作で拡大できる）
  Widget _buildChartView(_ChartImage chart) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            _chartLabel(chart),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: Image.network(
                chart.url,
                // 時刻を切り替えた際に前の画像が残らないようキーを付ける
                key: ValueKey(chart.url),
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Text(
                    '画像を読み込めませんでした',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 実況天気図の時刻スライダー（過去に遡って気圧配置の推移を確認できる）
  Widget _buildActualTimeSlider() {
    if (_actuals.length < 2) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '前の時刻',
            icon: const Icon(Icons.chevron_left, color: Colors.indigo),
            onPressed: _actualIndex > 0
                ? () => setState(() => _actualIndex--)
                : null,
          ),
          Expanded(
            child: Slider(
              value: _actualIndex.toDouble(),
              min: 0,
              max: (_actuals.length - 1).toDouble(),
              divisions: _actuals.length - 1,
              label: DateFormat(
                'd日 HH時',
              ).format(_actuals[_actualIndex].validJst),
              activeColor: Colors.indigo,
              onChanged: (v) => setState(() => _actualIndex = v.round()),
            ),
          ),
          IconButton(
            tooltip: '次の時刻',
            icon: const Icon(Icons.chevron_right, color: Colors.indigo),
            onPressed: _actualIndex < _actuals.length - 1
                ? () => setState(() => _actualIndex++)
                : null,
          ),
        ],
      ),
    );
  }

  // 出典と確認のポイント
  Widget _buildFooterNote() {
    return Container(
      width: double.infinity,
      color: Colors.indigo.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  '⚠ 出艇前に等圧線の間隔（狭い＝強風）と前線・低気圧の動きを確認し、'
                  '練習時間帯の風の変化を予測すること',
                  style: TextStyle(fontSize: 11, color: Colors.indigo),
                ),
              ),
              TextButton.icon(
                onPressed: _showReadingGuide,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.menu_book, size: 14),
                label: const Text(
                  '読み方ガイド',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Text(
            '出典: 気象庁ホームページ',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ===== 天気図の読み方ガイド =====

  void _showReadingGuide() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '天気図の読み方',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _guideSection(
                      Icons.multiline_chart,
                      Colors.indigo,
                      '等圧線と風の強さ',
                      const [
                        '等圧線は気圧の等しい地点を結んだ線。4hPaごとに引かれ、20hPaごとに太線になる',
                        '間隔が狭い（線が混んでいる）ほど風が強い。富山湾周辺に線が混みだしたら強風に警戒',
                        '風はおおむね等圧線に沿って、高気圧側から低気圧側へ回り込むように吹く',
                      ],
                    ),
                    _guideSection(
                      Icons.wb_sunny,
                      Colors.orange.shade800,
                      '高気圧（高）',
                      const [
                        '中心から時計回りに風が吹き出す。中心付近は下降気流で天気が安定しやすい',
                        '等圧線の間隔が広い日は気圧による風が弱く、日中は海風・朝夕は凪〜陸風（海陸風）が卓越しやすい',
                        '移動性高気圧は1〜2日で通過し、後ろから低気圧が来ることが多い（天気は下り坂へ）',
                      ],
                    ),
                    _guideSection(
                      Icons.cyclone,
                      Colors.blue.shade700,
                      '低気圧（低）',
                      const [
                        '中心へ反時計回りに風が吹き込む。接近すると南〜東寄りの風が強まり天気が崩れる',
                        '日本海を低気圧が東進する日は、南風が強まった後、寒冷前線の通過で西〜北西の強風へ急変しやすい（富山湾は特に注意）',
                        '実況の推移（スライダー）で進む速さをつかみ、練習時間帯にどこまで来るかを予想図で確認する',
                      ],
                    ),
                    _guideSection(
                      Icons.timeline,
                      Colors.red.shade700,
                      '前線の記号',
                      const [
                        '寒冷前線（▲の並んだ線）… 通過時に突風・雷雨・気温低下。風向が南寄りから西〜北寄りへ急変する。海上で最も警戒すべき前線',
                        '温暖前線（半円の並んだ線）… 接近すると雲が厚くなり雨が降り続く。通過後は南寄りの風で気温が上がる',
                        '停滞前線（▲と半円が反対向き）… 梅雨前線・秋雨前線。ぐずついた天気が続く',
                        '閉塞前線（▲と半円が同じ向き）… 低気圧が最盛期を過ぎた印。中心付近の強風域に注意',
                      ],
                    ),
                    _guideSection(
                      Icons.grid_view,
                      Colors.teal.shade700,
                      '典型的な気圧配置',
                      const [
                        '西高東低（冬型）… 西に高気圧・東に低気圧で等圧線が南北の縦縞になる。北西の季節風が強く、縦縞が混むほど強風・高波',
                        '南高北低（夏型）… 南の高気圧に覆われて南寄りの風。等圧線が緩ければ日中は熱的な海風が入る',
                        '春・秋は移動性高気圧と低気圧が交互に通過し、天気が数日周期で変わる。予想図での先読みが特に重要',
                      ],
                    ),
                    _guideSection(
                      Icons.checklist,
                      Colors.green.shade700,
                      '出艇前のチェック手順',
                      const [
                        '① 実況をスライダーで遡り、低気圧・前線の位置と進む速さをつかむ',
                        '② 24時間予想・48時間予想と見比べ、練習時間帯に前線や低気圧がどこまで来るかを読む',
                        '③ 予想図で富山湾付近の等圧線が今より混むなら「時間とともに風が上がる」と考える',
                        '④ 寒冷前線の通過が予想される日は、風の急変・雷に備えて早めのハーバーバック基準を共有しておく（安全マニュアルⅡ-1）',
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ガイドの1セクション（アイコン＋見出し＋箇条書き）
  Widget _guideSection(
    IconData icon,
    Color color,
    String title,
    List<String> points,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('・', style: TextStyle(fontSize: 12, height: 1.5)),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
