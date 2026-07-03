import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'windy_view_stub.dart'
    if (dart.library.io) 'windy_view_io.dart'
    if (dart.library.html) 'windy_view_web.dart';

/// アメダス風況モニター
/// 安全マニュアル（Ⅰ-3 安全管理、Ⅱ-1 気象状況）に基づき、
/// 陸上要員が風向に応じた観測地点のアメダス10分値を確認するためのページ。
/// 風向を選ぶと対応する2地点（○○＋伏木）の10分値を時系列で並べて比較できる。
/// （自動記録は行わない）
class AmedasPage extends StatefulWidget {
  const AmedasPage({super.key});

  @override
  State<AmedasPage> createState() => _AmedasPageState();
}

/// アメダス観測地点
class _Station {
  final String id; // 気象庁の観測所番号
  final String name;
  final LatLng pos;
  const _Station(this.id, this.name, this.pos);
}

/// 風向レンジ（安全マニュアルⅠ-3：風向に応じて確認するアメダス地点）
class _WindSector {
  final String label;
  final String stationId; // 伏木と合わせて確認する観測地点のID
  final double startDeg; // 風向範囲の始点（方位角、北=0°時計回り。範囲は90°）
  const _WindSector(this.label, this.stationId, this.startDeg);
}

/// 10分値1件分
class _ObsRow {
  final String sortKey; // yyyymmddHHMMSS（時系列マージ用）
  final double? windSpeed; // 平均風速 m/s
  final int? windDir; // 風向 0=静穏, 1-16
  final double? temp; // 気温 ℃
  final double? precip10m; // 10分降水量 mm
  const _ObsRow(this.sortKey, this.windSpeed, this.windDir, this.temp, this.precip10m);

  String get timeLabel => '${sortKey.substring(8, 10)}:${sortKey.substring(10, 12)}';
}

/// 観測地点1つ分の取得状態（地点IDをキーにキャッシュする）
class _StationState {
  final bool loading;
  final String? error;
  final List<_ObsRow> rows; // 新しい順
  final double? gust; // 日最大瞬間風速（出艇中止基準 Max12.5m/s の参考値）
  final String? gustTimeLabel;
  final String latestTimeLabel;

  const _StationState({
    this.loading = false,
    this.error,
    this.rows = const [],
    this.gust,
    this.gustTimeLabel,
    this.latestTimeLabel = '',
  });

  _ObsRow? get latest => rows.isEmpty ? null : rows.first;

  _ObsRow? rowAt(String sortKey) {
    for (final r in rows) {
      if (r.sortKey == sortKey) return r;
    }
    return null;
  }
}

class _AmedasPageState extends State<AmedasPage> {
  static const String _fushikiId = '55091'; // 伏木は風向によらず常に確認する

  // 観測所番号・座標は気象庁 amedastable.json より
  static const List<_Station> _stations = [
    _Station('56036', '珠洲', LatLng(37.4467, 137.2867)),
    _Station('56176', '羽咋', LatLng(36.8933, 136.7767)),
    _Station(_fushikiId, '伏木', LatLng(36.7917, 137.0550)),
    _Station('55151', '秋ヶ島', LatLng(36.6483, 137.1867)),
    _Station('55022', '朝日', LatLng(36.9367, 137.5633)),
  ];

  // 安全マニュアルⅠ-3：風向ごとの確認地点（＋伏木）
  static const List<_WindSector> _sectors = [
    _WindSector('北西〜北東', '56036', 315), // 珠洲と伏木（北寄りの風）
    _WindSector('北西〜南西', '56176', 225), // 羽咋と伏木（西寄りの風）
    _WindSector('南西〜南東', '55151', 135), // 秋ヶ島と伏木（南寄りの風）
    _WindSector('南東〜北東', '55022', 45), // 朝日と伏木（東寄りの風）
  ];

  static const List<String> _dirNames = [
    '北北東', '北東', '東北東', '東', '東南東', '南東', '南南東', '南',
    '南南西', '南西', '西南西', '西', '西北西', '北西', '北北西', '北',
  ];

  int _selectedSector = 0;
  // 伏木と並べて表示するもう1地点（風向選択で切り替わる。地図タップでも変更可）
  String _altStationId = _sectors[0].stationId;
  final Map<String, _StationState> _stationStates = {}; // 地点IDごとにキャッシュ

  // 地図表示モード（0=アメダス実測, 1=Windy風予測）
  int _mapMode = 0;
  bool _windyLoaded = false; // Windyは初めて表示した時だけ読み込む（以後は保持）

  // Windy埋め込みマップ（富山湾周辺・風オーバーレイ・m/s表示）
  static const String _windyUrl =
      'https://embed.windy.com/embed.html?type=map&location=coordinates'
      '&metricWind=m%2Fs&metricTemp=%C2%B0C'
      '&zoom=9&overlay=wind&product=ecmwf&level=surface'
      '&lat=36.95&lon=137.15&message=true';

  @override
  void initState() {
    super.initState();
    for (final id in _displayIds) {
      _ensureLoaded(id);
    }
  }

  _Station _stationById(String id) => _stations.firstWhere((s) => s.id == id);

  /// 下部パネルに表示する2地点（風向対応地点・伏木の順）
  List<String> get _displayIds => [_altStationId, _fushikiId];

  void _onSectorSelected(int index) {
    setState(() {
      _selectedSector = index;
      _altStationId = _sectors[index].stationId;
    });
    for (final id in _displayIds) {
      _ensureLoaded(id);
    }
  }

  void _onMarkerTap(_Station station) {
    if (station.id != _fushikiId) {
      setState(() => _altStationId = station.id);
    }
    _ensureLoaded(station.id);
  }

  Future<void> _reloadAll() async {
    await Future.wait(_displayIds.map((id) => _ensureLoaded(id, force: true)));
  }

  /// 指定地点のアメダス最新データを取得してキャッシュする。
  /// [force]が false の場合、既に読み込み済みなら再取得しない。
  Future<void> _ensureLoaded(String id, {bool force = false}) async {
    final cached = _stationStates[id];
    if (!force && cached != null && (cached.loading || cached.rows.isNotEmpty)) return;

    setState(() => _stationStates[id] = const _StationState(loading: true));
    try {
      // 最新観測時刻（JST）を取得
      final latestRes = await http
          .get(Uri.parse('https://www.jma.go.jp/bosai/amedas/data/latest_time.txt'));
      if (latestRes.statusCode != 200) {
        throw Exception('最新時刻の取得に失敗しました (${latestRes.statusCode})');
      }
      final latest = DateTime.parse(latestRes.body.trim());
      // オフセット付きISO文字列をJSTの壁時計時刻に変換
      final jst = latest.toUtc().add(const Duration(hours: 9));

      // 10分値は3時間ごとのファイルに分かれているため、
      // 直近2時間分を確実に得るために現在ブロックと1つ前のブロックを読む
      final entries = <String, dynamic>{};
      for (final block in [jst.subtract(const Duration(hours: 3)), jst]) {
        final hh = ((block.hour ~/ 3) * 3).toString().padLeft(2, '0');
        final ymd = '${block.year}'
            '${block.month.toString().padLeft(2, '0')}'
            '${block.day.toString().padLeft(2, '0')}';
        final url = 'https://www.jma.go.jp/bosai/amedas/data/point/$id/${ymd}_$hh.json';
        try {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200) {
            entries.addAll(json.decode(res.body) as Map<String, dynamic>);
          }
        } catch (_) {
          // 片方のブロックが取れなくても続行する
        }
      }
      if (entries.isEmpty) {
        throw Exception('観測データを取得できませんでした');
      }

      final keys = entries.keys.toList()..sort();
      // 直近12件（2時間分）を新しい順で保持
      final recent = keys.reversed.take(12).toList();
      final rows = recent.map((k) {
        final e = entries[k] as Map<String, dynamic>;
        return _ObsRow(
          k,
          _numOf(e['wind']),
          _numOf(e['windDirection'])?.toInt(),
          _numOf(e['temp']),
          _numOf(e['precipitation10m']),
        );
      }).toList();

      // 日最大瞬間風速（最新エントリに日集計として入っている）
      final latestEntry = entries[keys.last] as Map<String, dynamic>;
      final gust = _numOf(latestEntry['gust']);
      String? gustTime;
      final gt = latestEntry['gustTime'];
      if (gt is Map) {
        gustTime =
            '${gt['hour'].toString().padLeft(2, '0')}:${gt['minute'].toString().padLeft(2, '0')}';
      }

      if (!mounted) return;
      setState(() {
        _stationStates[id] = _StationState(
          loading: false,
          rows: rows,
          gust: gust,
          gustTimeLabel: gustTime,
          latestTimeLabel: '${keys.last.substring(8, 10)}:${keys.last.substring(10, 12)} 時点',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stationStates[id] = _StationState(loading: false, error: '取得エラー: $e'));
    }
  }

  /// 気象庁JSONの [値, 品質フラグ] 形式から値を取り出す（フラグ0以外は欠測扱い）
  double? _numOf(dynamic v) {
    if (v is List && v.isNotEmpty && v[0] is num) {
      if (v.length > 1 && v[1] is num && (v[1] as num) != 0) return null;
      return (v[0] as num).toDouble();
    }
    return null;
  }

  String _dirLabel(int? dir) {
    if (dir == null) return '--';
    if (dir == 0) return '静穏';
    if (dir >= 1 && dir <= 16) return _dirNames[dir - 1];
    return '--';
  }

  /// 出艇基準（安全マニュアルⅠ-4）に基づく風速の色分け
  Color? _windColor(double? speed) {
    if (speed == null) return null;
    if (speed >= 10) return Colors.red.shade100; // 出艇中止
    if (speed >= 7) return Colors.orange.shade100; // 上級のみ
    if (speed >= 5) return Colors.amber.shade50; // 中級以上
    return null;
  }

  /// 最新風速に対する出艇基準の目安ラベル
  (String, Color) _windJudge(double speed) {
    if (speed >= 10) return ('出艇中止（Ave.10m/s以上）', Colors.red);
    if (speed >= 7) return ('上級のみ出艇可', Colors.orange);
    if (speed >= 5) return ('中級以上出艇可', Colors.amber.shade800);
    if (speed >= 3) return ('初級以上出艇可', Colors.teal);
    return ('制限なし', Colors.teal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('アメダス風況モニター', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildSectorSelector(),
          Expanded(
            // IndexedStackで両方の地図を保持し、切り替え時の再読み込みを防ぐ
            child: IndexedStack(
              index: _mapMode,
              children: [
                _buildMap(),
                if (_windyLoaded)
                  buildWindyView(_windyUrl)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
          _buildComparePanel(),
        ],
      ),
    );
  }

  // 風向レンジの選択チップ（選ぶと確認すべき2地点が下部パネルに表示される）
  Widget _buildSectorSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('当日の風向を選択（対応する2地点を下に表示）',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: List.generate(_sectors.length, (i) {
                final selected = i == _selectedSector;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    avatar: _SectorRangeIcon(
                      startDeg: _sectors[i].startDeg,
                      color: selected ? Colors.white : Colors.indigo,
                    ),
                    showCheckmark: false,
                    label: Text(_sectors[i].label),
                    selected: selected,
                    selectedColor: Colors.indigo,
                    labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.black87, fontSize: 13),
                    onSelected: (_) => _onSectorSelected(i),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          // 地図表示の切り替え（アメダス実測 / Windy風予測）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.speed, size: 16),
                    label: Text('実測（アメダス）', style: TextStyle(fontSize: 12))),
                ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.air, size: 16),
                    label: Text('風予測（Windy）', style: TextStyle(fontSize: 12))),
              ],
              selected: {_mapMode},
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (selection) {
                setState(() {
                  _mapMode = selection.first;
                  if (_mapMode == 1) _windyLoaded = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(37.02, 137.15), // 富山湾周辺
        initialZoom: 8.4,
      ),
      children: [
        TileLayer(
          // 国土地理院 淡色地図タイル
          urlTemplate: 'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.yacht_link',
        ),
        MarkerLayer(
          markers: _stations.map((s) {
            final displayed = _displayIds.contains(s.id);
            final color = displayed ? Colors.indigo : Colors.grey.shade500;
            final state = _stationStates[s.id];
            final dir = state?.latest?.windDir;
            return Marker(
              point: s.pos,
              width: 84,
              height: 74,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => _onMarkerTap(s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 地図上でも一目で風向がわかるよう小さなコンパスを表示
                    _WindCompass(dir: dir, size: 34, color: color, showLabel: false),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SimpleAttributionWidget(source: Text('国土地理院')),
      ],
    );
  }

  // ===== 下部：2地点比較パネル =====

  Widget _buildComparePanel() {
    final ids = _displayIds;
    final st0 = _stationStates[ids[0]];
    final st1 = _stationStates[ids[1]];
    final anyLoading = (st0?.loading ?? true) || (st1?.loading ?? true);
    final height = MediaQuery.of(context).size.height * 0.44;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows, color: Colors.indigo, size: 20),
                const SizedBox(width: 6),
                Text(
                  '${_stationById(ids[0]).name} × ${_stationById(ids[1]).name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(st1?.latestTimeLabel ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                IconButton(
                  tooltip: '再読み込み（10分毎に確認）',
                  icon: const Icon(Icons.refresh, color: Colors.indigo),
                  onPressed: anyLoading ? null : _reloadAll,
                ),
              ],
            ),
          ),
          if (anyLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            _buildLatestCompareRow(ids),
            const Divider(height: 1),
            Expanded(child: _buildCompareTable(ids)),
          ],
        ],
      ),
    );
  }

  // 最新値のサマリー（2地点を横並び）
  Widget _buildLatestCompareRow(List<String> ids) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(child: _buildLatestCard(ids[0])),
          const SizedBox(width: 8),
          Expanded(child: _buildLatestCard(ids[1])),
        ],
      ),
    );
  }

  Widget _buildLatestCard(String id) {
    final station = _stationById(id);
    final state = _stationStates[id];
    if (state == null) return const SizedBox.shrink();
    if (state.error != null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('${station.name}: 取得エラー',
            style: const TextStyle(fontSize: 12, color: Colors.red)),
      );
    }
    final latest = state.latest;
    final speed = latest?.windSpeed;
    final (judgeLabel, judgeColor) =
        speed != null ? _windJudge(speed) : ('--', Colors.grey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          _WindCompass(dir: latest?.windDir, size: 46, color: Colors.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(station.name,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(speed != null ? speed.toStringAsFixed(1) : '--',
                        style:
                            const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2, left: 2),
                      child: Text('m/s',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(_dirLabel(latest?.windDir),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo)),
                    ),
                  ],
                ),
                Text(judgeLabel,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, color: judgeColor)),
                if (state.gust != null)
                  Text(
                    '最大瞬間 ${state.gust!.toStringAsFixed(1)}m/s'
                    '${state.gustTimeLabel != null ? ' (${state.gustTimeLabel})' : ''}',
                    style: TextStyle(
                        fontSize: 10,
                        color: (state.gust! >= 12.5) ? Colors.red : Colors.grey.shade600,
                        fontWeight: (state.gust! >= 12.5)
                            ? FontWeight.bold
                            : FontWeight.normal),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2地点の10分値を時刻で揃えて並べる比較テーブル
  Widget _buildCompareTable(List<String> ids) {
    final st0 = _stationStates[ids[0]];
    final st1 = _stationStates[ids[1]];

    // 両地点の観測時刻キーをマージして新しい順に
    final keySet = <String>{
      ...?st0?.rows.map((r) => r.sortKey),
      ...?st1?.rows.map((r) => r.sortKey),
    };
    final keys = keySet.toList()..sort((a, b) => b.compareTo(a));
    if (keys.isEmpty) {
      return const Center(child: Text('データがありません', style: TextStyle(color: Colors.grey)));
    }

    const headStyle =
        TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const SizedBox(width: 44, child: Text('時刻', style: headStyle)),
              Expanded(
                  child: Text(_stationById(ids[0]).name,
                      textAlign: TextAlign.center, style: headStyle)),
              Container(width: 1, height: 12, color: Colors.grey.shade300),
              Expanded(
                  child: Text(_stationById(ids[1]).name,
                      textAlign: TextAlign.center, style: headStyle)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: keys.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final key = keys[index];
              final r0 = st0?.rowAt(key);
              final r1 = st1?.rowAt(key);
              final timeLabel = '${key.substring(8, 10)}:${key.substring(10, 12)}';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                        width: 44,
                        child: Text(timeLabel,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold))),
                    Expanded(child: _buildCompareCell(r0)),
                    Container(width: 1, height: 24, color: Colors.grey.shade200),
                    Expanded(child: _buildCompareCell(r1)),
                  ],
                ),
              );
            },
          ),
        ),
        // 安全マニュアルⅡ-1 ※1 の注意書き
        Container(
          width: double.infinity,
          color: Colors.indigo.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: const Text(
            '⚠ 風速5m/s未満から10m/s以上への急上昇を確認した場合は出艇を取りやめる（海上ではただちにハーバーバック）',
            style: TextStyle(fontSize: 11, color: Colors.indigo),
          ),
        ),
      ],
    );
  }

  // 比較テーブルの1セル（1地点×1時刻）：風向コンパス＋風向名＋風速
  Widget _buildCompareCell(_ObsRow? row) {
    if (row == null) {
      return const Center(
          child: Text('--', style: TextStyle(fontSize: 12, color: Colors.grey)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _windColor(row.windSpeed),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _WindCompass(dir: row.windDir, size: 20, color: Colors.indigo, showLabel: false),
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            child: Text(_dirLabel(row.windDir),
                style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
          Text(
            row.windSpeed != null ? row.windSpeed!.toStringAsFixed(1) : '--',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Text(' m/s', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }
}

/// 風向レンジ（90°の範囲）を扇形で示すミニコンパス。
/// 風向選択チップのアイコンとして使い、どの方角の風かを視覚的に示す。
class _SectorRangeIcon extends StatelessWidget {
  final double startDeg; // 方位角（北=0°時計回り）、範囲は90°
  final Color color;
  const _SectorRangeIcon({required this.startDeg, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _SectorRangePainter(startDeg: startDeg, color: color),
      ),
    );
  }
}

class _SectorRangePainter extends CustomPainter {
  final double startDeg;
  final Color color;
  _SectorRangePainter({required this.startDeg, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // 外枠の円
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius, ringPaint);

    // 北の目印（上の小さな点）
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius),
      1.2,
      Paint()..color = color,
    );

    // 風向範囲の扇形（方位角→Canvas角は -90°ずらす）
    final wedgePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final rect = Rect.fromCircle(center: center, radius: radius - 1.5);
    canvas.drawArc(
      rect,
      (startDeg - 90) * pi / 180,
      pi / 2, // 90°の範囲
      true,
      wedgePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SectorRangePainter oldDelegate) =>
      oldDelegate.startDeg != startDeg || oldDelegate.color != color;
}

/// 風向を視覚的に示すミニコンパス。
/// 矢印の向きは気象庁の風向コード（1〜16、0=静穏）に基づき、
/// 風が吹いてくる方角（真北=矢印が上）を指す。
class _WindCompass extends StatelessWidget {
  final int? dir; // 0=静穏, 1-16, null=データなし
  final double size;
  final Color color;
  final bool showLabel;

  const _WindCompass({
    required this.dir,
    this.size = 56,
    this.color = Colors.indigo,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    if (dir == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text('--',
              style: TextStyle(color: Colors.grey.shade400, fontSize: size * 0.25)),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CompassPainter(dir: dir!, color: color, showLabel: showLabel),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final int dir; // 0=静穏, 1-16
  final Color color;
  final bool showLabel;
  _CompassPainter({required this.dir, required this.color, required this.showLabel});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final ringPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, radius - 3, ringPaint);

    // N/E/S/W の目盛り
    final tickPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.2;
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2;
      final dx = sin(angle);
      final dy = -cos(angle);
      final p1 = center + Offset(dx, dy) * (radius - 3);
      final p2 = center + Offset(dx, dy) * (radius - (size.width > 30 ? 7 : 4));
      canvas.drawLine(p1, p2, tickPaint);
    }

    if (showLabel && size.width >= 40) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'N',
          style: TextStyle(
              fontSize: size.width * 0.15,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, center.dy - radius + 1),
      );
    }

    if (dir == 0) {
      // 静穏：矢印なし、中心の点のみ
      canvas.drawCircle(center, size.width * 0.06, Paint()..color = color);
      return;
    }

    final degree = (dir * 22.5) % 360;
    final radians = degree * pi / 180;
    final len = radius - (size.width > 30 ? 9 : 4);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, -len)
      ..lineTo(-len * 0.3, len * 0.4)
      ..lineTo(0, len * 0.18)
      ..lineTo(len * 0.3, len * 0.4)
      ..close();
    canvas.drawPath(path, arrowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) =>
      oldDelegate.dir != dir || oldDelegate.color != color || oldDelegate.showLabel != showLabel;
}
