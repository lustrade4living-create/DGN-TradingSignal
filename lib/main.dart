// TradeSignal AI — UI chính (theme trắng, 10 tab như bản web).
// Tab 0 Trang chủ (hero CEO + thống kê thật + thẻ nổi bật + dải tín hiệu
// ngang + statusbar + pair-strip + chart thuần) · 1 Tín hiệu · 2 Phân tích
// vĩ mô · 3 Lịch kinh tế · 4 Tin tức LIVE · 5 Lịch sử · 6 VolumeB/S ·
// 7 Chiến lược AI · 8 Backtest · 9 Auto-Trade (DEMO mô phỏng).
// Thanh nav dưới 5 nút cũ đã bỏ — thay bằng menu 3 gạch (☰) góc dưới
// bên trái; tabbar 10 tab ở trên vẫn giữ.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analysis_content.dart';
import 'app_theme.dart';
import 'backtest.dart';
import 'chart.dart';
import 'engine.dart';
import 'history.dart';
import 'indicators.dart' as ind;
import 'market_data.dart';
import 'news_live.dart';
import 'safe_json.dart';
import 'signal_core.dart';
import 'signal_status.dart';
import 'storage.dart';
import 'volume_profile.dart';
import 'widgets/dynamic_island.dart';
import 'widgets/hamburger_menu.dart';
import 'widgets/hero_widget.dart';
import 'widgets/signal_widgets.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const TradeSignalApp());
    },
    (error, stack) {
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('App gặp lỗi khi mở'),
                      Text('$error'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class TradeSignalApp extends StatelessWidget {
  const TradeSignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = MockEngine();
    return MaterialApp(
      title: 'TradeSignal AI',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: _SplashGate(engine: engine),
    );
  }
}

/// Intro: chỉ chạy logo nguyên khối hiện dần + phóng nhẹ (~1.5s),
/// tự ẩn sau 2.0s, chạm bỏ qua; phát chime 1 lần (im lặng nếu không có
/// tiếng — không báo lỗi cho user).
class _SplashGate extends StatefulWidget {
  const _SplashGate({required this.engine});

  final MockEngine engine;

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate>
    with SingleTickerProviderStateMixin {
  bool _done = false;
  bool _visible = false;
  bool _chimed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
      _playChimeOnce();
    });
    Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _done = true);
    });
  }

  Future<void> _playChimeOnce() async {
    if (_chimed || !widget.engine.soundOn) return;
    _chimed = true;
    final bool ok = await ChimePlayer.playChime();
    if (!ok) {
      // Không có tiếng: im lặng, chỉ ghi log (không báo lỗi cho user).
      debugPrint('TradeSignal: chime intro không phát được (thiết bị chưa hỗ trợ).');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return HomeScreen(engine: widget.engine);
    return GestureDetector(
      onTap: () => setState(() => _done = true),
      child: Scaffold(
        backgroundColor: AppColors.bg2,
        body: Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: _visible ? 1.0 : 0.86,
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOut,
              child: Image.asset(
                'assets/dgn-logo-clear.png',
                width: 300,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                  'DGN',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> _tabLabels = <String>[
  'Trang chủ',
  'Tín hiệu',
  'Phân tích',
  'Lịch KT',
  'Tin tức',
  'Lịch sử',
  'VolumeB/S',
  'Chiến lược AI',
  'Backtest',
  'Auto-Trade',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  MockEngine get engine => widget.engine;

  void _goTab(int i, {String? symbol}) {
    if (symbol != null) engine.selectSymbol(symbol);
    setState(() => _tabIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/dgn-mark-clear.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 30,
                      height: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'TradeSignal AI',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    engine.hasLive ? 'LIVE' : 'DỮ LIỆU CŨ',
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: engine.hasLive
                      ? AppColors.up.withOpacity(0.15)
                      : AppColors.gold.withOpacity(0.15),
                  side: BorderSide(
                    color: engine.hasLive ? AppColors.up : AppColors.gold,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              if (engine.offline)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  color: Colors.amber,
                  child: const Text(
                    'Chế độ Offline — dữ liệu có thể cũ',
                    style: TextStyle(color: Colors.black),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (!engine.offline && !engine.hasLive)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  color: Colors.amber,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'DỮ LIỆU CŨ — chưa lấy được giá live, đang dùng giá tham chiếu',
                          style: TextStyle(color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton(
                        onPressed: () => engine.refreshAllData(),
                        child: const Text(
                          'Thử lại',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Dynamic Island: chỉ ở các tab ngoài Trang chủ.
              if (_tabIndex != 0) DynamicIsland(engine: engine),
              // Tabbar 10 tab (cuộn ngang).
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: List.generate(_tabLabels.length, (i) {
                    final bool selected = _tabIndex == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_tabLabels[i]),
                        selected: selected,
                        onSelected: (_) => setState(() => _tabIndex = i),
                      ),
                    );
                  }),
                ),
              ),
              if (engine.autoTrade)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  child: FloatingActionButton.extended(
                    backgroundColor: AppColors.panic,
                    foregroundColor: Colors.white,
                    onPressed: () {
                      engine.panicStop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'PANIC STOP — đã đóng tất cả lệnh DEMO và tắt Auto-Trade',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.warning),
                    label: const Text('■ PANIC STOP'),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    HomeTab(engine: engine, onGoSignals: _goTab),
                    SignalsTab(engine: engine, onGoChart: _goTab),
                    AnalysisTab(engine: engine),
                    CalendarTab(engine: engine),
                    NewsTab(engine: engine),
                    HistoryTab(engine: engine),
                    VolumeProfileTab(engine: engine),
                    StrategyTab(engine: engine, onGoSignals: _goTab),
                    BacktestTab(engine: engine),
                    AutoTradeTab(engine: engine),
                  ],
                ),
              ),
            ],
          ),
          // Icon 3 gạch cố định góc dưới bên trái — mở menu 10 mục.
          // Nút nhỏ (mini) để không che nội dung; Dynamic Island ở phía
          // trên nên không xung đột. Nút PANIC STOP (khi Auto-Trade bật)
          // nằm trong body, phía trên vùng nội dung — không bị icon này che.
          floatingActionButtonLocation:
              FloatingActionButtonLocation.startFloat,
          floatingActionButton: FloatingActionButton(
            mini: true,
            tooltip: 'Menu',
            onPressed: () => showHamburgerMenu(
              context,
              currentIndex: _tabIndex,
              onSelect: (i) => setState(() => _tabIndex = i),
            ),
            child: const Icon(Icons.menu),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Trang chủ (tab 0): hero + thống kê + thẻ nổi bật + dải tín hiệu ngang +
// statusbar + pair-strip + chart thuần
// ---------------------------------------------------------------------------

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.engine, required this.onGoSignals});

  final MockEngine engine;
  final void Function(int tab, {String? symbol}) onGoSignals;

  @override
  Widget build(BuildContext context) {
    final List<StaticSignal> buys = engine.staticSignals.values
        .whereType<StaticSignal>()
        .where((s) => s.action == 'BUY' || s.action == 'SELL')
        .toList();
    StaticSignal? strongest;
    for (final StaticSignal s in buys) {
      if (strongest == null || s.conf > strongest.conf) strongest = s;
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // IntrinsicHeight: HeroWidget dùng Row(stretch) trong Stack — đặt
        // trực tiếp trong ListView (chiều cao không giới hạn) thì stretch
        // cấp constraint cao vô hạn cho con, layout hero vỡ và kéo theo
        // cả ListView không vẽ được gì (tab Trang chủ trắng trơn trên máy
        // thật). IntrinsicHeight cho hero chiều cao hữu hạn theo đúng nội
        // dung cột chữ, giao diện giữ nguyên.
        IntrinsicHeight(child: HeroWidget(engine: engine)),
        const SizedBox(height: 12),
        HeroStatsRow(engine: engine),
        const SizedBox(height: 12),
        // Thẻ tín hiệu nổi bật (số liệu thật — không dùng số mockup).
        if (strongest != null)
          _FeaturedCard(
            engine: engine,
            signal: strongest,
            onDetail: () => onGoSignals(1, symbol: strongest!.symbol),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Đang quét 8 cặp…\nChưa có tín hiệu BUY/SELL đủ mạnh lúc này (cần đủ nến H1 đã đóng).',
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Tín hiệu 8 cặp',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SignalRail(
          engine: engine,
          onSelect: (sym) => onGoSignals(1, symbol: sym),
        ),
        const SizedBox(height: 12),
        // Statusbar: trạng thái nguồn + offline + âm thanh (chỉ Trang chủ).
        _StatusBar(engine: engine),
        const SizedBox(height: 12),
        // Pair-strip: 8 cặp + giá + trạng thái.
        _PairStrip(engine: engine),
        const SizedBox(height: 12),
        ChartPanel(engine: engine),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.engine,
    required this.signal,
    required this.onDetail,
  });

  final MockEngine engine;
  final StaticSignal signal;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final double? live = engine.prices[signal.symbol];
    final double? liveVsEntry = live == null
        ? null
        : (live - signal.entry) / signal.entry * 100;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.gold, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tín hiệu nổi bật',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                actionBadge(signal.action),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              signal.symbol,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _kvMini('Entry',
                      engine.fmt(signal.entry, signal.symbol)),
                ),
                Expanded(
                  child: _kvMini(
                      'TP',
                      signal.tp == null
                          ? '—'
                          : engine.fmt(signal.tp!, signal.symbol),
                      color: AppColors.up),
                ),
                Expanded(
                  child: _kvMini(
                      'SL',
                      signal.sl == null
                          ? '—'
                          : engine.fmt(signal.sl!, signal.symbol),
                      color: AppColors.dn),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (liveVsEntry != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (liveVsEntry >= 0 ? AppColors.up : AppColors.dn)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Giá live ${liveVsEntry >= 0 ? '+' : ''}${liveVsEntry.toStringAsFixed(2).replaceAll('.', ',')}% so với Entry',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        liveVsEntry >= 0 ? AppColors.up : AppColors.dn,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text('✓ Đã chốt tín hiệu tĩnh',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.up)),
            Text(sigStopInfo(signal),
                style: const TextStyle(fontSize: 12, color: AppColors.mut)),
            Text(
              'Độ tin cậy ${signal.conf}% · RR 1 : ${signal.rr.toStringAsFixed(1)} · ${strategyLabel(engine.strategy)}',
              style: const TextStyle(fontSize: 12, color: AppColors.mut),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDetail,
                child: const Text('Xem chi tiết tín hiệu →'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvMini(String k, String v, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 11, color: AppColors.mut2)),
        Text(v,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color ?? AppColors.txt)),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.engine});

  final MockEngine engine;

  @override
  Widget build(BuildContext context) {
    final String src = engine.priceSource(engine.selectedSymbol);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              engine.hasLive
                  ? '● GIÁ LIVE THẬT — đang trực tiếp · cập nhật mỗi 2 giây · lần cuối ${engine.updatedLabel(engine.selectedSymbol)}'
                  : '◐ DỮ LIỆU CŨ — chưa lấy được giá live',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: engine.hasLive ? AppColors.up : AppColors.gold,
              ),
            ),
            Text(
              'Nguồn: $src · Cập nhật mỗi 2 giây (HTTP polling, không phải WebSocket 1 giây)',
              style: const TextStyle(fontSize: 12, color: AppColors.mut),
            ),
            // USOIL: giá app là HĐTL tháng gần nhất — ghi rõ để user không
            // nhầm với giá spot/CFD trên Exness (lệch 1-2 USD quanh ngày
            // roll hợp đồng là bình thường, không phải lỗi dữ liệu).
            if (engine.selectedSymbol == 'USOIL')
              const Text(
                'Giá HĐTL NYMEX tháng gần nhất — có thể lệch 1–2 USD với giá spot/CFD trên Exness, nhất là quanh ngày roll hợp đồng.',
                style: TextStyle(fontSize: 12, color: AppColors.mut),
              ),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Giả lập Offline',
                        style: TextStyle(fontSize: 13)),
                    value: engine.offline,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => engine.setOffline(v),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => engine.setSoundOn(!engine.soundOn),
                  icon: Icon(
                    engine.soundOn ? Icons.volume_up : Icons.volume_off,
                    size: 18,
                  ),
                  label: Text(
                    'Âm thanh: ${engine.soundOn ? 'Bật' : 'Tắt'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PairStrip extends StatelessWidget {
  const _PairStrip({required this.engine});

  final MockEngine engine;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: symbols.map((s) {
          final bool selected = s.code == engine.selectedSymbol;
          final bool followed = engine.followed.contains(s.code);
          final String status = engine.priceStatus(s.code);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => engine.selectSymbol(s.code),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.blue : AppColors.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppColors.blue : AppColors.line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${followed ? '★ ' : ''}${s.code}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            selected ? Colors.white : AppColors.txt,
                      ),
                    ),
                    Text(
                      engine.fmt(engine.priceOf(s.code), s.code),
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white70 : AppColors.mut,
                      ),
                    ),
                    Text(
                      status == 'LIVE'
                          ? '● LIVE · ${engine.updatedLabel(s.code)}'
                          : '○ CHƯA LẤY ĐƯỢC GIÁ LIVE',
                      style: TextStyle(
                        fontSize: 10,
                        color: selected
                            ? Colors.white70
                            : status == 'LIVE'
                                ? AppColors.up
                                : AppColors.dn,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart panel (dùng ở Trang chủ): chip cặp/khung, banner nguồn, công cụ vẽ,
// chart 64 nến + pan, panel MACD + RSI, panel tín hiệu cặp đang chọn.
// ---------------------------------------------------------------------------

class ChartPanel extends StatefulWidget {
  const ChartPanel({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<ChartPanel> {
  static const List<String> _timeframes = ['M5', 'M15', 'H1', 'H4', 'D1'];

  final Map<String, List<Drawing>> _drawings = {};
  DrawTool _tool = DrawTool.none;
  int _pan = 0;

  // Memo MACD/RSI theo (cặp, khung, nến cuối, thông số) — tránh tính lại
  // mỗi lần engine notify (giá về mỗi 2 giây).
  String _indKey = '';
  ind.MacdResult? _macdCache;
  List<double?>? _rsiCache;

  MockEngine get engine => widget.engine;

  @override
  Widget build(BuildContext context) {
    final String symbol = engine.selectedSymbol;
    final List<Candle> candles = engine.candlesFor(symbol, engine.timeframe);
    final ind.IndicatorParams p = engine.indParams;
    final List<double> closes = candles.map((c) => c.c).toList();
    final List<double?> emaFast = ind.emaSeries(closes, p.emaFast);
    final List<double?> emaSlow = ind.emaSeries(closes, p.emaSlow);
    final List<double?> ema34 = ind.emaSeries(closes, p.ema34);
    final StaticSignal? signal = engine.staticSignals[symbol];
    final List<Drawing> drawings = _drawings['$symbol|${engine.timeframe}'] ??
        const <Drawing>[];
    final bool followed = engine.followed.contains(symbol);
    final int decimals = symbolByCode(symbol).decimals;
    final int maxPan = candles.length > 20 ? candles.length - 20 : 0;
    if (_pan > maxPan) _pan = maxPan;
    final Map<String, bool>? tierHits =
        engine.tierStatusFor(symbol)?.map((k, v) => MapEntry(k, v.hit));

    // MACD/RSI (memo theo nến cuối + thông số).
    final List<RawCandle> raw = engine.rawCandlesFor(symbol, engine.timeframe);
    final String key =
        '$symbol|${engine.timeframe}|${raw.isEmpty ? 0 : raw.last.t}|${p.hashCode}';
    if (key != _indKey) {
      _indKey = key;
      if (raw.isNotEmpty) {
        _macdCache = ind.macdSeries(raw, p.macdF, p.macdS, p.macdSig);
        _rsiCache = ind.rsiSeries(closes, p.rsiChart);
      } else {
        _macdCache = null;
        _rsiCache = null;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hàng chip chọn cặp.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: symbols.map((s) {
              final bool selected = s.code == symbol;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s.code),
                  selected: selected,
                  onSelected: (_) {
                    engine.selectSymbol(s.code);
                    setState(() => _pan = 0);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Hàng chip khung thời gian.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _timeframes.map((tf) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tf),
                  selected: engine.timeframe == tf,
                  onSelected: (_) {
                    engine.setTimeframe(tf);
                    setState(() => _pan = 0);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        if (engine.candlesAreMock)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold),
            ),
            child: Text(
              'NẾN MOCK — chưa tải được nến thật cho $symbol (${engine.timeframe})${engine.cache.lastError['$symbol|${engine.timeframe}'] != null ? ' — ${engine.cache.lastError['$symbol|${engine.timeframe}']}' : ''}. Tín hiệu tính từ nến mock KHÔNG phải tín hiệu thật.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: engine.priceStatus(symbol) == 'LIVE'
                ? AppColors.up.withOpacity(0.12)
                : AppColors.gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${engine.priceSource(symbol)} • cập nhật ${engine.updatedLabel(symbol)} • ${engine.priceStatus(symbol)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: engine.priceStatus(symbol) == 'LIVE'
                  ? AppColors.up
                  : AppColors.gold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Hàng nút công cụ vẽ + xem quá khứ.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _toolButton('Trend', DrawTool.trend),
            _toolButton('Ngang', DrawTool.horizontal),
            _toolButton('Fib', DrawTool.fib),
            _toolButton('Hộp', DrawTool.rect),
            _toolButton('Chữ', DrawTool.text),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _drawings['$symbol|${engine.timeframe}'] = [];
                  _tool = DrawTool.none;
                });
              },
              icon: const Icon(Icons.delete, size: 18),
              label: const Text('Xóa'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dn.withOpacity(0.85),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Hang nut xem qua khu: cuon ngang (5 nut cong lai ~881px, tran
        // ca tren may tinh bang — truoc day Row tran 105px o rong 776px,
        // tren dien thoai cat mat nut). Noi dung/nut giu nguyen.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton(
                onPressed: _pan >= maxPan
                    ? null
                    : () => setState(() => _pan = (_pan + 16).clamp(0, maxPan)),
                child: const Text('◀◀ Lùi 16 nến'),
              ),
              TextButton(
                onPressed: _pan >= maxPan
                    ? null
                    : () => setState(() => _pan = (_pan + 1).clamp(0, maxPan)),
                child: const Text('◀ 1 nến'),
              ),
              TextButton(
                onPressed: _pan <= 0
                    ? null
                    : () => setState(() => _pan = (_pan - 1).clamp(0, maxPan)),
                child: const Text('1 nến ▶'),
              ),
              TextButton(
                onPressed: _pan <= 0
                    ? null
                    : () => setState(() => _pan = (_pan - 16).clamp(0, maxPan)),
                child: const Text('16 nến ▶▶'),
              ),
              TextButton(
                onPressed: _pan == 0 ? null : () => setState(() => _pan = 0),
                child: const Text('Về hiện tại (Live)'),
              ),
            ],
          ),
        ),
        if (_pan > 0)
          Text(
            'Đang xem QUÁ KHỨ — lùi $_pan nến so với hiện tại',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
        const SizedBox(height: 4),
        SizedBox(
          height: 340,
          child: CandleChart(
            candles: candles,
            signal: signal,
            emaFast: emaFast,
            emaSlow: emaSlow,
            ema34: ema34,
            drawings: drawings,
            tool: _tool,
            decimals: decimals,
            tierHits: tierHits,
            pan: _pan,
            onPanChanged: (v) => setState(() => _pan = v),
            onDrawingAdded: (Drawing d) {
              setState(() {
                _drawings
                    .putIfAbsent(
                        '$symbol|${engine.timeframe}', () => [])
                    .add(d);
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'EMA nhanh (${p.emaFast}) vàng · EMA chậm (${p.emaSlow}) xanh · EMA34 cam',
          style: const TextStyle(fontSize: 12, color: AppColors.mut),
        ),
        const SizedBox(height: 8),
        // Panel MACD + RSI dưới chart (spec §13.2).
        _MacdRsiPanel(
          macd: _macdCache,
          rsi: _rsiCache,
          params: p,
          pan: _pan,
        ),
        const SizedBox(height: 12),
        // Panel tín hiệu cặp đang chọn (bản gọn trên Trang chủ).
        if (signal != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        signal.symbol,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      actionBadge(signal.action),
                    ],
                  ),
                  const SizedBox(height: 8),
                  confBar(signal.conf),
                  const SizedBox(height: 8),
                  kvRow('Entry (đã chốt tĩnh)',
                      engine.fmt(signal.entry, symbol)),
                  kvRow(
                      'SL',
                      signal.sl == null
                          ? '—'
                          : engine.fmt(signal.sl!, symbol),
                      vColor: AppColors.dn),
                  kvRow(
                      'TP',
                      signal.tp == null
                          ? '—'
                          : engine.fmt(signal.tp!, symbol),
                      vColor: AppColors.up),
                  kvRow('RR', '1 : ${signal.rr.toStringAsFixed(1)}'),
                  kvRow('Bias (H4)', signal.bias),
                  kvRow('ATR (H1)', engine.fmt(signal.atr, symbol)),
                  const SizedBox(height: 8),
                  ...signal.reasons.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $r'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => engine.toggleFollow(symbol),
                      icon: Icon(
                        followed ? Icons.star : Icons.star_border,
                      ),
                      label: Text(
                        followed ? 'Đang theo dõi' : 'Theo dõi cặp này',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.org,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'ĐANG TẢI — chưa đủ nến H1 đã đóng (cần ≥ 55 nến) để chốt tín hiệu tĩnh.'),
                  if (engine.candlesStuck)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Đã thử tải mà chưa được (${engine.missingCandlesCount} cặp/khung còn thiếu) — app sẽ tự thử lại, hoặc bấm nút dưới để thử ngay.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.mut),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => engine.refreshAllData(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại ngay'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolButton(String label, DrawTool tool) {
    final bool selected = _tool == tool;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _tool = selected ? DrawTool.none : tool;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor:
            selected ? Theme.of(context).colorScheme.primary : null,
      ),
      child: Text(label),
    );
  }
}

/// Panel MACD + RSI dưới chart: đường MACD xanh, Signal cam, Histogram
/// xanh/đỏ; RSI xanh, đường 70/30 vàng đứt nét.
class _MacdRsiPanel extends StatelessWidget {
  const _MacdRsiPanel({
    required this.macd,
    required this.rsi,
    required this.params,
    required this.pan,
  });

  final ind.MacdResult? macd;
  final List<double?>? rsi;
  final ind.IndicatorParams params;
  final int pan;

  double? _lastNonNull(List<double?> values, int pan) {
    final int end = values.length - pan;
    for (int i = end - 1; i >= 0; i--) {
      if (values[i] != null) return values[i];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final double? macdLine = macd == null
        ? null
        : _lastNonNull(macd!.line, pan);
    final double? macdSig =
        macd == null ? null : _lastNonNull(macd!.signal, pan);
    final double? rsiVal = rsi == null ? null : _lastNonNull(rsi!, pan);
    final String rsiState = rsiVal == null
        ? '—'
        : rsiVal >= 70
            ? 'Quá mua'
            : rsiVal <= 30
                ? 'Quá bán'
                : 'Trung tính';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MACD (${params.macdF},${params.macdS},${params.macdSig})${pan > 0 ? ' (tại nến đang xem)' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (macd == null || macdLine == null || macdSig == null)
              Text(
                'Chưa đủ nến cho MACD — cần trên ${params.macdS + params.macdSig + 2} nến.',
                style: const TextStyle(fontSize: 12, color: AppColors.mut),
              )
            else ...[
              Text(
                'MACD ${macdLine.toStringAsFixed(4)} · Signal ${macdSig.toStringAsFixed(4)} · Hist ${(macdLine - macdSig).toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 56,
                child: _MiniLines(
                  series: [
                    (macd!.line, AppColors.blue),
                    (macd!.signal, AppColors.ema34),
                  ],
                  pan: pan,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'RSI (${params.rsiChart})${pan > 0 ? ' (tại nến đang xem)' : ''} — Quá mua 70 · Quá bán 30',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (rsiVal == null)
              const Text('Chưa đủ nến cho RSI.',
                  style: TextStyle(fontSize: 12, color: AppColors.mut))
            else
              Text(
                'RSI = ${rsiVal.toStringAsFixed(1)} · $rsiState',
                style: const TextStyle(fontSize: 12),
              ),
            if (rsi != null)
              SizedBox(
                height: 56,
                child: _MiniLines(
                  series: [(rsi!, AppColors.blue)],
                  pan: pan,
                  levels: const [70, 30],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Vẽ nhanh 1–2 đường chỉ báo (mini chart).
class _MiniLines extends StatelessWidget {
  const _MiniLines({
    required this.series,
    this.pan = 0,
    this.levels,
  });

  final List<(List<double?>, Color)> series;
  final int pan;
  final List<double>? levels;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MiniLinesPainter(series: series, pan: pan, levels: levels),
      size: Size.infinite,
    );
  }
}

class _MiniLinesPainter extends CustomPainter {
  _MiniLinesPainter({
    required this.series,
    required this.pan,
    this.levels,
  });

  final List<(List<double?>, Color)> series;
  final int pan;
  final List<double>? levels;

  @override
  void paint(Canvas canvas, Size size) {
    double? minV;
    double? maxV;
    for (final (values, _) in series) {
      final int end = (values.length - pan).clamp(0, values.length);
      for (int i = 0; i < end; i++) {
        final double? v = values[i];
        if (v == null || v.isNaN) continue;
        minV = minV == null ? v : (v < minV ? v : minV);
        maxV = maxV == null ? v : (v > maxV ? v : maxV);
      }
    }
    if (levels != null) {
      for (final double lv in levels!) {
        minV = minV == null ? lv : (lv < minV ? lv : minV);
        maxV = maxV == null ? lv : (lv > maxV ? lv : maxV);
      }
    }
    if (minV == null || maxV == null) return;
    final double span = (maxV - minV).abs() < 1e-12 ? 1 : maxV - minV;
    final double pad = span * 0.1;
    minV -= pad;
    maxV += pad;
    // Đường 70/30 (vàng đứt nét).
    if (levels != null) {
      for (final double lv in levels!) {
        final double y = size.height - (lv - minV) / (maxV - minV) * size.height;
        final Paint p = Paint()
          ..color = AppColors.gold
          ..strokeWidth = 1;
        double x = 0;
        while (x < size.width) {
          canvas.drawLine(Offset(x, y), Offset(x + 5, y), p);
          x += 9;
        }
      }
    }
    for (final (values, color) in series) {
      final int end = (values.length - pan).clamp(0, values.length);
      final int start = end > 64 ? end - 64 : 0;
      final Path path = Path();
      bool started = false;
      for (int i = start; i < end; i++) {
        final double? v = values[i];
        if (v == null || v.isNaN) {
          started = false;
          continue;
        }
        final double x = (i - start) / 64 * size.width;
        final double y =
            size.height - (v - minV) / (maxV - minV) * size.height;
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniLinesPainter old) => true;
}

// ---------------------------------------------------------------------------
// Tab Tín hiệu (tab 1)
// ---------------------------------------------------------------------------

class SignalsTab extends StatefulWidget {
  const SignalsTab({super.key, required this.engine, required this.onGoChart});

  final MockEngine engine;
  final void Function(int tab, {String? symbol}) onGoChart;

  @override
  State<SignalsTab> createState() => _SignalsTabState();
}

class _SignalsTabState extends State<SignalsTab> {
  final Map<String, bool> _pairOpen = <String, bool>{};

  MockEngine get engine => widget.engine;

  @override
  Widget build(BuildContext context) {
    final String sym = engine.selectedSymbol;
    final StaticSignal? sg = engine.staticSignals[sym];
    final List<StaticSignal> all = engine.staticSignals.values
        .whereType<StaticSignal>()
        .toList();
    StaticSignal? strongest;
    for (final StaticSignal s in all) {
      if (s.action == 'WAIT') continue;
      if (strongest == null || s.conf > strongest.conf) strongest = s;
    }
    final bool mock = engine.candlesAreMock;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (mock)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold),
            ),
            child: const Text(
              'NẾN MOCK — chưa tải được nến thật. Tín hiệu dưới đây tính từ nến mock, KHÔNG phải tín hiệu thật.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
          ),
        sectionTitle('Tín hiệu 8 cặp'),
        if (all.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'ĐANG TẢI — đang tải nến thật, cần ≥ 55 nến H1 đã đóng để chốt tín hiệu.'),
                  if (engine.candlesStuck)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Đã thử tải mà chưa được (${engine.missingCandlesCount} cặp/khung còn thiếu) — app sẽ tự thử lại, hoặc bấm nút dưới để thử ngay.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.mut),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => engine.refreshAllData(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại ngay'),
                  ),
                ],
              ),
            ),
          )
        else
          ...all.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SignalCard(
                  engine: engine,
                  signal: s,
                  isStrongest: strongest != null && identical(s, strongest),
                  onTap: () => engine.selectSymbol(s.symbol),
                ),
              )),
        if (sg != null) ...[
          sectionTitle('Tín hiệu cặp đang chọn — $sym'),
          _SignalDetailPanel(engine: engine, signal: sg),
        ] else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chưa có tín hiệu cho cặp đang chọn.'),
            ),
          ),
        sectionTitle('Cảnh báo Xung đa khung / TURN đồng bộ'),
        AlertsView(engine: engine),
        if (strongest != null) ...[
          sectionTitle('Tín hiệu mạnh nhất lúc này'),
          SignalCard(
            engine: engine,
            signal: strongest,
            isStrongest: true,
            onTap: () => widget.onGoChart(0, symbol: strongest!.symbol),
          ),
        ],
        sectionTitle('Phân tích chi tiết theo từng cặp'),
        ...symbols.map((s) {
          final bool open = _pairOpen[s.code] == true;
          final StaticSignal? ps = engine.staticSignals[s.code];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() => _pairOpen[s.code] = !open);
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.code,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            ps == null
                                ? 'ĐANG TẢI'
                                : '${ps.action} · ${ps.conf}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: ps == null
                                  ? AppColors.mut2
                                  : AppColors.actionColor(ps.action),
                            ),
                          ),
                          Text(
                            open ? 'Ẩn phân tích ▲' : 'Hiện phân tích ▼',
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (open && ps != null)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: _PairAnalysis(engine: engine, signal: ps),
                    ),
                  if (open && ps == null)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('ĐANG TẢI — chưa đủ nến H1.'),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        const SwingRulesCard(),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Panel tín hiệu cặp đang chọn (đầy đủ).
class _SignalDetailPanel extends StatelessWidget {
  const _SignalDetailPanel({required this.engine, required this.signal});

  final MockEngine engine;
  final StaticSignal signal;

  @override
  Widget build(BuildContext context) {
    final String sym = signal.symbol;
    final bool followed = engine.followed.contains(sym);
    final Invalidation? inv = engine.lastInvalidations[sym];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  sym,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                actionBadge(signal.action),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text(strategyLabel(engine.strategy)),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                const Chip(
                  label: Text('TÍN HIỆU TĨNH — chốt khi nến đóng'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            confBar(signal.conf),
            const SizedBox(height: 8),
            kvRow('Entry (đã chốt tĩnh)',
                engine.fmt(signal.entry, sym)),
            kvRow(
                'SL',
                signal.sl == null
                    ? '—'
                    : engine.fmt(signal.sl!, sym),
                vColor: AppColors.dn),
            kvRow(
                'TP',
                signal.tp == null
                    ? '—'
                    : engine.fmt(signal.tp!, sym),
                vColor: AppColors.up),
            kvRow('RR', '1 : ${signal.rr.toStringAsFixed(1)}'),
            kvRow('Bias (H4)', signal.bias),
            kvRow('ATR (H1)', engine.fmt(signal.atr, sym)),
            const SizedBox(height: 4),
            Text(sigStopInfo(signal),
                style: const TextStyle(fontSize: 12, color: AppColors.mut)),
            const SizedBox(height: 8),
            SignalStatusRow(
              status: classifyStaticSignal(
                signal,
                livePrice: engine.prices[sym],
                nowMs: DateTime.now().millisecondsSinceEpoch,
              ),
              symbol: sym,
              issuedAtMs: signal.closedAt,
              expiryAtMs: signalExpiryMs(signal.closedAt),
            ),
            const SizedBox(height: 12),
            const Text('Thang TP Inv/T1–T4',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LadderView(engine: engine, signal: signal),
            const SizedBox(height: 12),
            const Text('Lý do',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ...signal.reasons.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $r'),
              ),
            ),
            if (inv != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.dn.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.dn),
                ),
                child: Text(
                  'Hủy sớm: ${inv.reason}\nLệnh cũ ${inv.oldAction} · Entry ${engine.fmt(inv.entry, sym)} · SL ${inv.sl == null ? '—' : engine.fmt(inv.sl!, sym)} · cắt tại ${engine.fmt(inv.exit, sym)} · ${fmtPips(inv.pips)} pip (${fmtPct2(inv.pct)}) · lúc ${vnDateStr(inv.exitAt)}',
                  style: const TextStyle(color: AppColors.dn),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Collapsible(
              title: 'Hiện chi tiết điểm & điểm vào tối ưu',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScoreTable(signal: signal),
                  const Divider(),
                  OptimalBox(engine: engine, signal: signal),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Collapsible(
              title: 'Hiện Trend đa khung & gauge cộng hưởng',
              child: TrendGaugeBlock(engine: engine, symbol: sym),
            ),
            const SizedBox(height: 12),
            Text(
              'SL = Entry ∓ ${engine.indParams.slMult}×ATR(H1) · TP = Entry ± ${engine.indParams.tpMult}×ATR(H1) · Chiến lược: ${strategyLabel(engine.strategy)}',
              style: const TextStyle(fontSize: 12, color: AppColors.mut),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => engine.toggleFollow(sym),
                icon: Icon(followed ? Icons.star : Icons.star_border),
                label: Text(followed
                    ? '✓ Đang theo dõi $sym — bấm để bỏ theo dõi'
                    : '＋ Theo dõi cặp này'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.org,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nội dung khối phân tích theo từng cặp (spec §16.5).
class _PairAnalysis extends StatelessWidget {
  const _PairAnalysis({required this.engine, required this.signal});

  final MockEngine engine;
  final StaticSignal signal;

  @override
  Widget build(BuildContext context) {
    final String sym = signal.symbol;
    final VpScanResult? scan = engine.vpScan[sym];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrendGaugeBlock(engine: engine, symbol: sym),
        const Divider(),
        PaSummary(engine: engine, symbol: sym),
        const Divider(),
        const Text('Mẫu hình nến (top 6)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        PatternList(engine: engine, symbol: sym),
        const Divider(),
        if (scan != null) ...[
          Text(
            'VolumeB/S quét: ${scan.action} · ${scan.score}/5 · POC ${scan.poc == null ? '—' : engine.fmt(scan.poc!, sym)} · VAH ${scan.vah == null ? '—' : engine.fmt(scan.vah!, sym)} · VAL ${scan.val == null ? '—' : engine.fmt(scan.val!, sym)} · Delta ${scan.deltaPct == null ? '—' : '${scan.deltaPct!.toStringAsFixed(1)}%'} · H1 ${scan.h1Trend}',
          ),
        ] else
          const Text('VolumeB/S quét: đang tải…'),
        const Divider(),
        ScoreTable(signal: signal),
        const SizedBox(height: 8),
        OptimalBox(engine: engine, signal: signal),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Phân tích vĩ mô (tab 2) — CHỈ 3 khối nhận định, ghi rõ không có dữ
// liệu vị thế thật (spec §16.6).
// ---------------------------------------------------------------------------

class AnalysisTab extends StatelessWidget {
  const AnalysisTab({super.key, required this.engine});

  final MockEngine engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine.news,
      builder: (context, _) {
        final StaticSignal? gold = engine.staticSignals['XAUUSD'];
        final String goldBias = gold?.bias ?? '—';
        final double goldPrice = engine.priceOf('XAUUSD');
        final double? oilPrice =
            engine.liveOk['USOIL'] == true ? engine.priceOf('USOIL') : null;
        final DateTime now = DateTime.now();
        final List<CalEvent> upcomingHigh = engine.news.lastGood
            .where((e) =>
                e.impact.toLowerCase() == 'high' &&
                e.time.isAfter(now) &&
                e.time.difference(now) <= const Duration(hours: 24))
            .toList();
        final List<MacroSection> macro = macroCommentary(
          chg24h: engine.chg24h,
          goldPrice: goldPrice,
          goldBias: goldBias,
          btcChg: engine.chg24h['BTCUSD'],
          oilPrice: oilPrice,
          upcomingHigh: upcomingHigh,
        );
        final Map<String, List<NewsItem>> byPair =
            pairNews(engine.news.items);
        final Map<String, VpScanView> scans = <String, VpScanView>{};
        for (final SymbolInfo s in symbols) {
          final VpScanResult? r = engine.vpScan[s.code];
          if (r == null) continue;
          scans[s.code] = VpScanView(
            symbol: s.code,
            action: r.action,
            h1Trend: r.h1Trend == 'up'
                ? 'Tăng'
                : r.h1Trend == 'down'
                    ? 'Giảm'
                    : 'Đi ngang',
            nearPoc: r.nearPoc,
            price: r.price,
            poc: r.poc,
            vah: r.vah,
            val: r.val,
            deltaPct: r.deltaPct,
          );
        }
        final List<FlowNote> flows = bigMoneyNotes(scans);

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            sectionTitle('Nhận định vĩ mô'),
            ...macro.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(m.body),
                        ],
                      ),
                    ),
                  ),
                )),
            sectionTitle('Tin tức đang tác động lên từng cặp'),
            if (engine.news.items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                      'Chưa có tin live để ghép (tin đang quét ở tab Tin tức).'),
                ),
              )
            else
              ...symbols.map((s) {
                final List<NewsItem> list = byPair[s.code] ?? const [];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.code,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          if (list.isEmpty)
                            const Text(
                              'Không có tin khớp từ khóa của cặp này.',
                              style: TextStyle(color: AppColors.mut),
                            )
                          else
                            ...list.map((n) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 4),
                                  child: Text('• ${n.title}'),
                                )),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            sectionTitle('Nhận định biến động — dòng tiền lớn'),
            if (flows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                      'Chưa có kết quả quét VolumeB/S để nhận định dòng tiền.'),
                ),
              )
            else
              ...flows.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(f.text),
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Lịch kinh tế (tab 3) — ForexFactory trực tiếp, giữ lastGood khi lỗi.
// ---------------------------------------------------------------------------

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  List<CalEvent> _events = <CalEvent>[];
  bool _loading = false;
  bool _failed = false;
  String _scope = 'Hôm nay';
  String _impact = 'Mọi mức độ';

  MockEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _events = engine.news.lastGood;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final List<CalEvent> ev = await engine.news.fetchCalendar();
      if (mounted) {
        setState(() {
          _events = ev;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _events = engine.news.lastGood;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime todayStart =
        DateTime(now.year, now.month, now.day);
    List<CalEvent> filtered = _events.where((e) {
      if (_scope == 'Hôm nay') {
        if (!e.time.isAfter(todayStart.subtract(const Duration(seconds: 1))) ||
            e.time.isAfter(todayStart.add(const Duration(days: 1)))) {
          return false;
        }
      }
      if (_impact == 'Chỉ tin vàng') return e.isGold;
      if (_impact != 'Mọi mức độ') {
        return e.impact.toLowerCase() == _impact.toLowerCase();
      }
      return true;
    }).toList();
    filtered.sort((a, b) => a.time.compareTo(b.time));
    final CalEvent? strong = engine.news.nextStrongGoldEvent(_events, now);
    // Nhóm theo ngày.
    final Map<String, List<CalEvent>> byDay = <String, List<CalEvent>>{};
    for (final CalEvent e in filtered) {
      final String d = NewsService.fmtDayVN(e.time);
      byDay.putIfAbsent(d, () => []).add(e);
    }

    return Column(
      children: [
        if (strong != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: AppColors.dn.withOpacity(0.12),
            child: Text(
              NewsService.strongGoldBanner(strong, now),
              style: const TextStyle(
                color: AppColors.dn,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        if (_failed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: AppColors.gold.withOpacity(0.15),
            child: Text(
              _events.isEmpty
                  ? 'CHƯA LẤY ĐƯỢC LỊCH TRỰC TIẾP — chưa có dữ liệu lịch nào trong phiên.'
                  : 'CHƯA LẤY ĐƯỢC LỊCH TRỰC TIẾP — đang hiện lịch đã lấy được trong phiên (có thể đã cũ).',
              style: const TextStyle(
                  color: AppColors.gold, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Hôm nay', 'Cả tuần'].map((s) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(s),
                          selected: _scope == s,
                          onSelected: (_) => setState(() => _scope = s),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _refresh,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Tải lại lịch',
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: ['Mọi mức độ', 'High', 'Medium', 'Low', 'Chỉ tin vàng']
                .map((f) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f),
                  selected: _impact == f,
                  onSelected: (_) => setState(() => _impact = f),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('Không có sự kiện nào (hoặc chưa tải được lịch).'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: byDay.length,
                  itemBuilder: (context, dayIdx) {
                    final String day = byDay.keys.elementAt(dayIdx);
                    final List<CalEvent> dayEvents = byDay[day]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            day,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...dayEvents.map((e) {
                          final bool isHot = e.isGold || e.impact == 'High';
                          final Color impactColor =
                              e.impact.toLowerCase() == 'high'
                                  ? AppColors.dn
                                  : e.impact.toLowerCase() == 'medium'
                                      ? AppColors.gold
                                      : AppColors.mut2;
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isHot
                                    ? AppColors.dn
                                    : AppColors.line,
                                width: isHot ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              leading: isHot
                                  ? const Icon(Icons.warning,
                                      color: AppColors.dn)
                                  : const Icon(Icons.event),
                              title: Text(e.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${NewsService.fmtHourMinuteVN(e.time)} • ${e.country}${e.isGold ? ' • TIN VÀNG' : ''}'),
                                  Text(
                                    'Impact: ${e.impact}',
                                    style: TextStyle(
                                      color: impactColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Dự báo: ${e.forecast ?? '—'} • Thực tế: ${e.actual ?? '—'} • Kỳ trước: ${e.previous ?? '—'}',
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Tin tức LIVE (tab 4) — NewsService quét 1 giây, bấm tin copy link.
// ---------------------------------------------------------------------------

class NewsTab extends StatefulWidget {
  const NewsTab({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  String _keyword = 'Tất cả';

  MockEngine get engine => widget.engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine.news,
      builder: (context, _) {
        final NewsService news = engine.news;
        final List<NewsItem> items = news.filter(_keyword);
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: news.isLive
                  ? AppColors.up.withOpacity(0.10)
                  : AppColors.gold.withOpacity(0.12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    news.liveLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: news.isLive ? AppColors.up : AppColors.gold,
                    ),
                  ),
                  Text(
                    '${news.scanInfo} · Trạng thái: ${news.statusText}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.mut),
                  ),
                  const Text(
                    'Trang quét lại nguồn mỗi 1 giây và chỉ thay danh sách khi có tin mới (nguồn RSS thường chỉ có tin mới theo phút).',
                    style: TextStyle(fontSize: 11, color: AppColors.mut2),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: NewsService.filterKeywords.map((k) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(k),
                        selected: _keyword == k,
                        onSelected: (_) => setState(() => _keyword = k),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        news.items.isEmpty
                            ? 'CHƯA LẤY ĐƯỢC TIN LIVE — đang quét lại nguồn FXStreet RSS…'
                            : 'Không có tin nào khớp từ khóa.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final NewsItem n = items[index];
                        final String summary = n.summary.length > 180
                            ? '${n.summary.substring(0, 180)}…'
                            : n.summary;
                        final Color tagColor = n.goldTag == 'pos'
                            ? AppColors.up
                            : n.goldTag == 'neg'
                                ? AppColors.dn
                                : AppColors.mut2;
                        return Card(
                          child: InkWell(
                            onTap: () async {
                              await Clipboard.setData(
                                ClipboardData(text: n.link),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Đã copy link bài gốc'),
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(summary),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              tagColor.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          n.goldTagLabel,
                                          style: TextStyle(
                                            color: tagColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${n.source} · ${NewsService.fmtDayTimeVN(n.pubDate)} (giờ VN)',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const Text(
                                    'Bấm để copy link bài gốc',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.mut2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Lịch sử tín hiệu (tab 5) — thẻ TỔNG TOÀN PHIÊN + thống kê từng cặp.
// ---------------------------------------------------------------------------

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  String _symFilter = 'Tất cả';
  bool _todayOnly = false;
  String _resultFilter = 'all';

  MockEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    // Nap lich su da luu ben (neu engine khoi dong chua nap xong).
    // ensureLoaded() an toan khi goi nhieu lan — chi nap 1 lan.
    unawaited(engine.history.ensureLoaded());
  }

  /// Xoa TOAN BO lich su (ca bo nho lan file da luu) — co hop xac nhan.
  Future<void> _confirmClearHistory() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Xóa toàn bộ lịch sử?'),
        content: const Text(
          'Toàn bộ lịch sử tín hiệu đã đóng sẽ bị xóa vĩnh viễn, '
          'kể cả bản đã lưu trên máy. Không thể khôi phục.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa hết'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final bool ok = await engine.history.clearAllPersisted();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Đã xóa toàn bộ lịch sử tín hiệu.'
            : 'Đã xóa lịch sử trong app (không ghi được file lưu — thử lại sau).'),
      ),
    );
  }

  String _fmtR(double? r) {
    if (r == null) return '—';
    return '${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)}';
  }

  String _fmtPf(double? pf) {
    if (pf == null) return '—';
    if (pf.isInfinite) return '∞';
    return pf.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine.history,
      builder: (context, _) {
        final SessionHistory h = engine.history;
        final List<HistEntry> list = h.filter(
          symbol: _symFilter,
          todayOnly: _todayOnly,
          result: _resultFilter,
        );
        final Map<String,
                ({int wins, int losses, double? winRate, double? profitFactor, double? avgR, double? totalR})>
            byPair = h.statsByPair();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Thẻ TỔNG TOÀN PHIÊN (viền vàng).
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppColors.gold, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TỔNG TOÀN PHIÊN · Đang mở ${h.openCount}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    kvRow('Tín hiệu đã đóng', '${h.closedCount}'),
                    kvRow(
                      'Win rate',
                      h.winRate == null
                          ? '—'
                          : '${h.winRate!.toStringAsFixed(1)}% (${h.wins} thắng / ${h.losses} thua)',
                    ),
                    kvRow('Profit factor', _fmtPf(h.profitFactor)),
                    kvRow(
                        'RR thực tế TB',
                        h.avgRealRr == null
                            ? '—'
                            : '1 : ${h.avgRealRr!.toStringAsFixed(2)}'),
                    kvRow('R trung bình / tín hiệu', _fmtR(h.avgR)),
                    kvRow('Tổng R', _fmtR(h.totalR)),
                    kvRow(
                      'Theo loại kết quả',
                      'TP ${h.closeKindCounts[closeKindTP]} · SL ${h.closeKindCounts[closeKindSL]} · Thoát tại Entry ${h.closeKindCounts[closeKindEntry]} · Cắt lỗ sớm ${h.closeKindCounts[closeKindEarlyLoss]} · Cắt lãi sớm ${h.closeKindCounts[closeKindEarlyProfit]}',
                    ),
                    if (h.closedCount == 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Chưa có tín hiệu nào đóng — bảng winrate sẽ tự cập nhật ngay khi có lệnh chạm TP/SL hoặc hủy sớm. Lịch sử đã đóng được lưu lại trên máy, mở lại app vẫn thấy.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.mut),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            sectionTitle('Thống kê từng cặp'),
            ...histSymbols.map((sym) {
              final s = byPair[sym]!;
              final int closed = s.wins + s.losses;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sym,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      Text(
                        closed == 0
                            ? 'Win rate: — · Chưa có tín hiệu đóng để tính hiệu suất'
                            : 'Win rate: ${s.winRate!.toStringAsFixed(1)}% (${s.wins} thắng / ${s.losses} thua) · PF: ${_fmtPf(s.profitFactor)} · Tổng R: ${_fmtR(s.totalR)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }),
            sectionTitle('Danh sách lịch sử'),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _symFilter,
                    isExpanded: true,
                    items: <String>['Tất cả', ...histSymbols]
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _symFilter = v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _resultFilter,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                      DropdownMenuItem(
                          value: 'open', child: Text('Đang mở')),
                      DropdownMenuItem(value: 'win', child: Text('Win')),
                      DropdownMenuItem(value: 'loss', child: Text('Loss')),
                      DropdownMenuItem(
                          value: closeKindTP, child: Text('TP')),
                      DropdownMenuItem(
                          value: closeKindSL, child: Text('SL')),
                      DropdownMenuItem(
                          value: closeKindEntry,
                          child: Text('Thoát tại Entry')),
                      DropdownMenuItem(
                          value: closeKindEarlyLoss,
                          child: Text('Cắt lỗ sớm')),
                      DropdownMenuItem(
                          value: closeKindEarlyProfit,
                          child: Text('Cắt lãi sớm')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _resultFilter = v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Hôm nay'),
                  selected: _todayOnly,
                  onSelected: (v) => setState(() => _todayOnly = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Chưa có tín hiệu nào (lịch sử đã đóng được lưu lại trên máy, mở lại app vẫn thấy).'),
                ),
              )
            else
              ...list.map((e) => _HistCard(engine: engine, entry: e)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: h.closedCount == 0 && h.openCount == 0
                    ? null
                    : _confirmClearHistory,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Xóa toàn bộ lịch sử'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _HistCard extends StatelessWidget {
  const _HistCard({required this.engine, required this.entry});

  final MockEngine engine;
  final HistEntry entry;

  @override
  Widget build(BuildContext context) {
    final HistEntry e = entry;
    final bool isOpen = e.status == 'open';
    // Badge dong: loai ket qua thoat lenh (5 loai) + WIN/LOSS theo R.
    final String kindLabel = e.closeLabel ?? '';
    final String badge = isOpen
        ? 'ĐANG MỞ'
        : e.result == 'win'
            ? '${kindLabel.isEmpty ? 'WIN' : kindLabel} · WIN ${_fmtSignedR(e.realizedR)}R'
            : '${kindLabel.isEmpty ? 'LOSS' : kindLabel} · LOSS ${_fmtSignedR(e.realizedR)}R';
    final Color badgeColor = isOpen
        ? AppColors.blue
        : switch (e.closeKind) {
            closeKindTP => AppColors.up,
            closeKindSL => AppColors.dn,
            closeKindEntry => AppColors.gold,
            closeKindEarlyLoss => AppColors.dn,
            closeKindEarlyProfit => AppColors.up,
            _ => e.result == 'win' ? AppColors.up : AppColors.dn,
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${e.symbol} · ${e.action}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Chiến lược lúc phát: ${e.strategy} · Tin cậy lúc phát: ${e.conf.toStringAsFixed(0)}% · Giờ mở: ${vnDateStr(e.openAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.mut),
            ),
            const SizedBox(height: 4),
            Text(
              'Entry ${engine.fmt(e.entry, e.symbol)} · SL ${e.sl == null ? '—' : engine.fmt(e.sl!, e.symbol)} · TP ${e.tp == null ? '—' : engine.fmt(e.tp!, e.symbol)}',
            ),
            if (e.levels != null) ...[
              const SizedBox(height: 4),
              _tiersText(e),
            ],
            if (e.simDiffPips != null)
              Text(
                'Chênh mở phòng: ${fmtPips(e.simDiffPips!)} pip · mở mô phỏng tại ${e.openPrice == null ? '—' : engine.fmt(e.openPrice!, e.symbol)}',
                style: const TextStyle(fontSize: 12, color: AppColors.mut),
              ),
            if (isOpen)
              Text(
                'Giờ lên: ${vnDateStr(e.startAt)} · Giờ dừng dự kiến: ${vnDateStr(e.planStop)} (nến H1 đóng tiếp theo) — Đang chờ giá chạm TP/SL hoặc đảo chiều hủy sớm.',
                style: const TextStyle(fontSize: 12, color: AppColors.mut),
              )
            else ...[
              Text(
                'Giá đóng: ${e.exit == null ? '—' : engine.fmt(e.exit!, e.symbol)} · Giờ đóng: ${e.exitAt == null ? '—' : vnDateStr(e.exitAt!)} · ${e.exitPips == null ? '' : '${fmtPips(e.exitPips!)} pip'} ${e.exitPct == null ? '' : '(${fmtPct2(e.exitPct!)})'}',
              ),
              if (e.note.isNotEmpty)
                Text(
                  'Ghi chú: ${e.note}',
                  style: const TextStyle(fontSize: 12, color: AppColors.mut),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtSignedR(double? r) {
    if (r == null) return '—';
    return '${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)}';
  }

  Widget _tiersText(HistEntry e) {
    final Map<String, dynamic>? tiers = e.tiers;
    final Map<String, dynamic>? levels = e.levels;
    if (levels == null) return const SizedBox.shrink();
    final List<String> parts = <String>[];
    for (final String k in ['T1', 'T2', 'T3', 'T4']) {
      final double? lv = numD(levels[k.toLowerCase()]);
      final Map<String, dynamic>? t = asMap(tiers?[k]);
      final bool hit = t?['hit'] == true;
      parts.add(
          '$k ${lv == null ? '—' : engine.fmt(lv, e.symbol)}${hit ? ' ✓' : ''}');
    }
    final double? inv = numD(levels['inv']);
    parts.add(
        'Inv ${inv == null ? '—' : engine.fmt(inv, e.symbol)}${e.invHit == true ? ' ✓' : ''}');
    return Text(
      'Thang: ${parts.join(' · ')}',
      style: const TextStyle(fontSize: 12, color: AppColors.mut),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab VolumeB/S (tab 6) — quét 8 cặp + chi tiết VP cặp đang chọn.
// ---------------------------------------------------------------------------

class VolumeProfileTab extends StatefulWidget {
  const VolumeProfileTab({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<VolumeProfileTab> createState() => _VolumeProfileTabState();
}

class _VolumeProfileTabState extends State<VolumeProfileTab> {
  String _vpSym = 'XAUUSD';
  late final TextEditingController _capitalController;
  late final TextEditingController _riskController;
  late final TextEditingController _slController;
  late final TextEditingController _fxController;
  bool _slInit = false;

  MockEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _capitalController = TextEditingController(text: '10000000');
    _riskController = TextEditingController(text: '0.5');
    _slController = TextEditingController(text: '5');
    _fxController = TextEditingController(text: '26000');
  }

  @override
  void dispose() {
    _capitalController.dispose();
    _riskController.dispose();
    _slController.dispose();
    _fxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VolumeSetup s = analyzeVolumeProfile(
      m15: engine.candlesFor(_vpSym, 'M15'),
      h1: engine.candlesFor(_vpSym, 'H1'),
      h4: engine.candlesFor(_vpSym, 'H4'),
    );
    if (!_slInit && s.action != 'WAIT' && (s.entry - s.sl).abs() > 0) {
      _slController.text = (s.entry - s.sl).abs().toStringAsFixed(2);
      _slInit = true;
    }
    // Trạng thái vào lệnh VolumeB/S (Việc 1): VolumeSetup không có giờ
    // chốt riêng như tín hiệu Swing — lấy giờ ra tín hiệu = giờ đóng của
    // nến M15 đã đóng gần nhất (setup tính từ nến M15 đã đóng), hết hiệu
    // lực = giờ đó + 1 giờ (cùng chu kỳ H1 như Swing). ATR(H1) lấy từ nến
    // H1 thật; chưa có thì dùng khoảng cách Entry–SL làm thang đo dự phòng.
    final List<RawCandle> vpM15Closed =
        engine.closedByTf(_vpSym)['M15'] ?? <RawCandle>[];
    final int vpIssuedAt = vpM15Closed.isNotEmpty
        ? vpM15Closed.last.t + 15 * 60 * 1000
        : DateTime.now().millisecondsSinceEpoch;
    final double vpAtr =
        ind.atrLast(engine.rawCandlesFor(_vpSym, 'H1'), 14) ??
            (s.entry - s.sl).abs();
    final SignalStatusResult vpStatus = classifySignalStatus(
      action: s.action,
      entry: s.entry,
      tp1: s.tp1,
      atr: vpAtr,
      livePrice: engine.prices[_vpSym],
      issuedAtMs: vpIssuedAt,
      expiryAtMs: signalExpiryMs(vpIssuedAt),
      nowMs: DateTime.now().millisecondsSinceEpoch,
      pipSize: ind.pipSize(_vpSym),
    );
    final double maxVol =
        s.bins.fold(0.0, (a, b) => b.volume > a ? b.volume : a);
    final Color actionColor = s.action == 'BUY'
        ? AppColors.up
        : s.action == 'SELL'
            ? AppColors.dn
            : AppColors.mut2;
    final double contract = engine.contractSize(_vpSym);

    // Máy tính lot theo từng cặp.
    final double capital =
        double.tryParse(_capitalController.text.replaceAll(',', '')) ?? 0;
    final double riskPct = double.tryParse(_riskController.text) ?? 0;
    final double slUsd = double.tryParse(_slController.text) ?? 0;
    final double fx = double.tryParse(_fxController.text) ?? 26000;
    final double riskVnd = capital * riskPct / 100;
    final double riskUsd = fx > 0 ? riskVnd / fx : 0;
    final double lossPerLot = contract * slUsd;
    double lot = lossPerLot > 0 ? riskUsd / lossPerLot : 0;
    bool minLotUsed = false;
    if (lot > 0 && lot < 0.01) {
      lot = 0.01;
      minLotUsed = true;
    }
    final double actualLoss = lot * lossPerLot;

    // Kế hoạch ngày: bias + vùng chờ + tin vàng hôm nay.
    final DateTime now = DateTime.now();
    final List<CalEvent> goldToday = engine.news.lastGood.where((e) {
      return e.isGold &&
          e.impact.toLowerCase() == 'high' &&
          e.time.year == now.year &&
          e.time.month == now.month &&
          e.time.day == now.day;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        sectionTitle('Quét VolumeB/S — 8 cặp'),
        if (engine.vpScan.values.whereType<VpScanResult>().isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('Đang quét 8 cặp… (chờ tải nến M15/H1 thật).'),
            ),
          )
        else
          ...symbols.map((sym) {
            final VpScanResult? r = engine.vpScan[sym.code];
            if (r == null) return const SizedBox.shrink();
            final bool selected = sym.code == _vpSym;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected ? AppColors.blue : AppColors.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  onTap: () => setState(() => _vpSym = sym.code),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sym.code,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Giá ${engine.fmt(r.price, sym.code)} · H1 ${r.h1Trend} · ${r.nearPoc ? 'đang tại vùng POC' : 'chưa tại vùng POC'}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.mut),
                              ),
                              Text(
                                'POC ${r.poc == null ? '—' : engine.fmt(r.poc!, sym.code)} · VAH ${r.vah == null ? '—' : engine.fmt(r.vah!, sym.code)} · VAL ${r.val == null ? '—' : engine.fmt(r.val!, sym.code)} · Delta ${r.deltaPct == null ? '—' : '${r.deltaPct!.toStringAsFixed(1)}%'}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.mut),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              r.action,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.actionColor(r.action),
                              ),
                            ),
                            Text('${r.score}/5',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'VolumeB/S • $_vpSym',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      s.action,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: actionColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Giá: ${engine.fmt(s.price, _vpSym)} • '
                  '${engine.priceSource(_vpSym)} • '
                  '${engine.priceStatus(_vpSym)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.mut),
                ),
                const SizedBox(height: 8),
                SignalStatusRow(
                  status: vpStatus,
                  symbol: _vpSym,
                  issuedAtMs: vpIssuedAt,
                  expiryAtMs: signalExpiryMs(vpIssuedAt),
                ),
                const SizedBox(height: 8),
                kvRow('Mô hình', s.model == 'NONE' ? 'Chưa có' : 'Mô hình ${s.model}'),
                kvRow('Xu hướng H1', s.h1Trend,
                    vColor: s.h1Trend == 'TANG'
                        ? AppColors.up
                        : s.h1Trend == 'GIAM'
                            ? AppColors.dn
                            : AppColors.mut2),
                kvRow('Điểm chấm', '${s.score}/10'),
                kvRow('Kết luận', s.verdict,
                    vColor: s.verdict == 'XEM XET'
                        ? AppColors.up
                        : s.verdict == 'CHO THEM'
                            ? AppColors.gold
                            : AppColors.dn),
              ],
            ),
          ),
        ),
        sectionTitle('Cấu trúc 4 khung'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'H4 Market Map: Supply/Demand = đỉnh/đáy 100 nến H4.'),
                const Text(
                    'H1 Trend Filter: Ichimoku + EMA20 + POC.'),
                const Text('M15 Setup: HVN, LVN, VAH, VAL, Delta.'),
                const Text('M5 Execution: Sweep, CHoCH, BOS, Retest.'),
                const Divider(),
                kvRow('Tenkan (9)', engine.fmt(s.tenkan, _vpSym)),
                kvRow('Kijun (26)', engine.fmt(s.kijun, _vpSym)),
                kvRow('Senkou A', engine.fmt(s.senkouA, _vpSym)),
                kvRow('Senkou B', engine.fmt(s.senkouB, _vpSym)),
                kvRow('EMA20 H1', engine.fmt(s.ema20H1, _vpSym)),
                kvRow(
                  'Sweep',
                  s.sweepBuy
                      ? 'Quét đáy (Buy)'
                      : s.sweepSell
                          ? 'Quét đỉnh (Sell)'
                          : 'Không có',
                ),
                kvRow(
                  'CHoCH / BOS',
                  s.chochBuy
                      ? 'Phá đỉnh (Buy)'
                      : s.chochSell
                          ? 'Phá đáy (Sell)'
                          : 'Không có',
                ),
              ],
            ),
          ),
        ),
        sectionTitle('Volume Profile M15 — lookback 200 nến'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                kvRow('POC', engine.fmt(s.poc, _vpSym)),
                kvRow('VAH (70%)', engine.fmt(s.vah, _vpSym)),
                kvRow('VAL (70%)', engine.fmt(s.val, _vpSym)),
                kvRow('HVN', s.hvn.isEmpty
                    ? '—'
                    : s.hvn.map((v) => engine.fmt(v, _vpSym)).join(', ')),
                kvRow('LVN', s.lvn.isEmpty
                    ? '—'
                    : s.lvn.map((v) => engine.fmt(v, _vpSym)).join(', ')),
                kvRow('Delta ước tính',
                    '${s.deltaPct.toStringAsFixed(1)}% (Buy ${engine.fmt(s.buyVol, _vpSym)} · Sell ${engine.fmt(s.sellVol, _vpSym)})'),
                const SizedBox(height: 8),
                ...s.bins.map((b) {
                  final double w = maxVol > 0 ? b.volume / maxVol : 0;
                  final bool isPoc =
                      (b.mid - s.poc).abs() < (s.vah - s.val) / 20;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(
                            engine.fmt(b.mid, _vpSym),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: w,
                              minHeight: 10,
                              backgroundColor: AppColors.line,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isPoc ? AppColors.org : AppColors.blue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        sectionTitle('Setup vào lệnh (theo cấu trúc giá)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                kvRow('Entry (giá live)', engine.fmt(s.entry, _vpSym)),
                kvRow('SL', engine.fmt(s.sl, _vpSym), vColor: AppColors.dn),
                kvRow('TP1', engine.fmt(s.tp1, _vpSym), vColor: AppColors.up),
                kvRow('TP2', engine.fmt(s.tp2, _vpSym), vColor: AppColors.up),
                kvRow('RR tới TP2', '1 : ${s.rr.toStringAsFixed(2)}'),
                const SizedBox(height: 4),
                const Text(
                  'SL/TP này theo cấu trúc giá, khác công thức ATR của tab tín hiệu Swing.',
                  style: TextStyle(fontSize: 12, color: AppColors.mut),
                ),
              ],
            ),
          ),
        ),
        sectionTitle('Bảng chấm điểm 10đ'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: s.scoreItems
                  .map((it) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(it.label)),
                            Text(
                              it.met ? '✓ +${it.points}' : '✗ 0/${it.points}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: it.met
                                    ? AppColors.up
                                    : AppColors.mut2,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        sectionTitle('3 mô hình'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('A — Buy tại POC/HVN: H1 tăng + giá tại vùng + Sweep đáy hoặc CHoCH/BOS tăng.'),
                Text('B — Sell tại POC/HVN: H1 giảm + giá tại vùng + Sweep đỉnh hoặc CHoCH/BOS giảm.'),
                Text('C — Phá vỡ LVN: nến M15 đóng vượt LVN + volume > trung bình 1,15× + M5 có BOS/CHoCH cùng hướng.'),
              ],
            ),
          ),
        ),
        sectionTitle('Quy trình 5 bước'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('1. Xu hướng H1 bằng Ichimoku.'),
                Text('2. Vùng VP M15 (POC/HVN/VAH/VAL/LVN).'),
                Text('3. Chờ giá quay lại vùng.'),
                Text('4. Xác nhận M5 (Sweep/CHoCH/BOS).'),
                Text('5. Vào lệnh sau xác nhận, chỉ khi điểm ≥ 8.'),
              ],
            ),
          ),
        ),
        sectionTitle('Quản trị vốn + máy tính lot'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Quy tắc: rủi ro 0,25–0,5%/lệnh, RR tối thiểu 1:2, tối đa 3 lệnh/ngày, thua liên tiếp 2 lệnh thì dừng, tránh tin mạnh.'),
                const SizedBox(height: 8),
                TextField(
                  controller: _capitalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Vốn (VND)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _riskController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '% rủi ro mỗi lệnh',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _slController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'SL (USD)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fxController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tỷ giá VND/USD',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rủi ro tối đa: ${riskVnd.toStringAsFixed(0)} đồng (≈ ${riskUsd.toStringAsFixed(2)} USD) · Với SL $slUsd USD → khối lượng ≈ ${lot.toStringAsFixed(2)} lot${minLotUsed ? ' (đã làm tròn lên lot tối thiểu 0,01)' : ''} (làm tròn xuống theo bước lot của sàn; chưa trừ phí và trượt giá)',
                ),
                Text(
                  'Khối lượng thực tế ${lot.toStringAsFixed(2)} lot ≈ rủi ro ${actualLoss.toStringAsFixed(2)} USD nếu chạm SL · 1 lot $_vpSym = ${contract.toStringAsFixed(0)} đơn vị.',
                  style: const TextStyle(fontSize: 12, color: AppColors.mut),
                ),
              ],
            ),
          ),
        ),
        sectionTitle('Kế hoạch ngày'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bias ngày (Ichimoku H1): ${s.h1Trend}.'),
                Text(
                    'Vùng chờ Buy: POC ${engine.fmt(s.poc, _vpSym)} · VAL ${engine.fmt(s.val, _vpSym)} · HVN dưới.'),
                Text(
                    'Vùng chờ Sell: POC ${engine.fmt(s.poc, _vpSym)} · VAH ${engine.fmt(s.vah, _vpSym)} · HVN trên.'),
                Text('Điểm lọc hiện tại: ${s.score}/10.'),
                Text(
                  goldToday.isEmpty
                      ? 'Tin mạnh vàng hôm nay: không có (theo lịch đã tải).'
                      : 'Tin mạnh vàng hôm nay: ${goldToday.map((e) => '${NewsService.fmtHourMinuteVN(e.time)} ${e.title}').join(' · ')}',
                ),
                const Text('Giới hạn ngày: tối đa 3 lệnh, thua 2 liên tiếp thì dừng.'),
              ],
            ),
          ),
        ),
        sectionTitle('Ghi chú'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: s.notes
                  .map((n) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $n'),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Chiến lược AI (tab 7) — 3 radio + dải tín hiệu + thông số chỉ báo.
// ---------------------------------------------------------------------------

class StrategyTab extends StatefulWidget {
  const StrategyTab(
      {super.key, required this.engine, required this.onGoSignals});

  final MockEngine engine;
  final void Function(int tab, {String? symbol}) onGoSignals;

  @override
  State<StrategyTab> createState() => _StrategyTabState();
}

class _StrategyTabState extends State<StrategyTab> {
  final Map<String, TextEditingController> _c = <String, TextEditingController>{};
  String _saveMsg = '';

  MockEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _fillFromParams();
  }

  void _fillFromParams() {
    final ind.IndicatorParams p = engine.indParams;
    final Map<String, String> vals = <String, String>{
      'emaFast': '${p.emaFast}',
      'emaSlow': '${p.emaSlow}',
      'ema34': '${p.ema34}',
      'ema200': '${p.ema200}',
      'macdF': '${p.macdF}',
      'macdS': '${p.macdS}',
      'macdSig': '${p.macdSig}',
      'rsiChart': '${p.rsiChart}',
      'rsiSig': '${p.rsiSig}',
      'atrPeriod': '${p.atrPeriod}',
      'slMult': '${p.slMult}',
      'tpMult': '${p.tpMult}',
      'bbPeriod': '${p.bbPeriod}',
      'bbMult': '${p.bbMult}',
    };
    for (final MapEntry<String, String> e in vals.entries) {
      _c.putIfAbsent(e.key, () => TextEditingController());
      _c[e.key]!.text = e.value;
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _apply() async {
    final Map<String, dynamic> raw = <String, dynamic>{};
    for (final MapEntry<String, TextEditingController> e in _c.entries) {
      final double? v = double.tryParse(e.value.text.replaceAll(',', '.'));
      if (v != null) raw[e.key] = v;
    }
    final ind.IndicatorParams p =
        ind.IndicatorParams.fromJson(raw); // clamp min-max theo spec §13.1
    await engine.applyIndicatorParams(p);
    _fillFromParams();
    if (mounted) {
      setState(() {
        _saveMsg =
            'Đã áp dụng & tính lại lúc ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')} · RR kế hoạch = 1 : ${p.rr.toStringAsFixed(1)} · ${engine.settingsNote ?? ''}';
      });
    }
  }

  Future<void> _reset() async {
    await engine.resetIndicatorParams();
    _fillFromParams();
    if (mounted) {
      setState(() => _saveMsg = engine.settingsNote ?? 'Đã khôi phục mặc định.');
    }
  }

  Widget _field(String key, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _c[key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AiStrategy strat = engine.strategy;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        sectionTitle('Chiến lược AI'),
        Card(
          child: Column(
            children: [
              RadioListTile<AiStrategy>(
                title: Text(strategyLabel(AiStrategy.swing)),
                value: AiStrategy.swing,
                groupValue: strat,
                onChanged: (v) {
                  if (v != null) engine.setStrategy(v);
                },
              ),
              RadioListTile<AiStrategy>(
                title: Text(strategyLabel(AiStrategy.volumebs)),
                value: AiStrategy.volumebs,
                groupValue: strat,
                onChanged: (v) {
                  if (v != null) engine.setStrategy(v);
                },
              ),
              RadioListTile<AiStrategy>(
                title: Text(strategyLabel(AiStrategy.ai)),
                value: AiStrategy.ai,
                groupValue: strat,
                onChanged: (v) {
                  if (v != null) engine.setStrategy(v);
                },
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '"AI" ở đây là bộ suy luận xác định chạy ngay trong app (Swing + VolumeB/S + MACD) — app chưa nối LLM thật và không tự vào lệnh.',
            style: TextStyle(fontSize: 12, color: AppColors.mut),
          ),
        ),
        if (engine.settingsNote != null)
          Text(
            engine.settingsNote!,
            style: const TextStyle(fontSize: 12, color: AppColors.up),
          ),
        sectionTitle('Dải tín hiệu theo chiến lược hiện tại'),
        SignalRail(
          engine: engine,
          onSelect: (sym) => widget.onGoSignals(1, symbol: sym),
        ),
        sectionTitle('Cài đặt thông số chỉ báo'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('emaFast', 'EMA nhanh', 'mặc định 20 · 2–400'),
                _field('emaSlow', 'EMA chậm', 'mặc định 50 · 3–400'),
                _field('ema34', 'EMA giữa (34)', 'mặc định 34 · 2–400'),
                _field('ema200', 'EMA dài hạn (200) — chỉ lưu trữ',
                    'mặc định 200 · 10–400'),
                _field('macdF', 'MACD nhanh', 'mặc định 34 · 2–200'),
                _field('macdS', 'MACD chậm', 'mặc định 58 · 3–300'),
                _field('macdSig', 'MACD signal', 'mặc định 12 · 2–100'),
                _field('rsiChart', 'RSI chart', 'mặc định 9 · 2–50'),
                _field('rsiSig', 'RSI tín hiệu', 'mặc định 14 · 2–50'),
                _field('atrPeriod', 'ATR', 'mặc định 14 · 2–60'),
                _field('slMult', 'Hệ số SL (×ATR)',
                    'mặc định 1,5 · 0,3–6'),
                _field('tpMult', 'Hệ số TP (×ATR)',
                    'mặc định 3,0 · 0,5–12'),
                _field('bbPeriod', 'Bollinger chu kỳ — chỉ lưu trữ',
                    'mặc định 20 · 5–100'),
                _field('bbMult', 'Bollinger độ lệch — chỉ lưu trữ',
                    'mặc định 2,0 · 0,5–5'),
                const Text(
                  'EMA200 và Bollinger chỉ lưu trữ — bản web không dùng chúng trong bất kỳ công thức hay hình vẽ nào (spec §13.4).',
                  style: TextStyle(fontSize: 12, color: AppColors.mut),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _apply,
                    child: const Text('Áp dụng & tính lại'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('Khôi phục mặc định'),
                  ),
                ),
                if (_saveMsg.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_saveMsg,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.up)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Backtest (tab 8)
// ---------------------------------------------------------------------------

class BacktestTab extends StatefulWidget {
  const BacktestTab({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<BacktestTab> createState() => _BacktestTabState();
}

class _BacktestTabState extends State<BacktestTab> {
  String _sym = 'XAUUSD';
  String _tf = 'H1';
  int _range = 2000;
  String _strat = 'swing';
  BacktestResult? _result;
  bool _running = false;
  // Tiến trình chạy: 'Đang tải nến… x/2000' rồi 'Đang chạy backtest…'.
  String _progress = '';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  String _methodMsg = '';

  MockEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _strat = engine.strategy.name;
    _nameController.text = strategyLabel(engine.strategy);
    _loadMethod();
  }

  Future<void> _loadMethod() async {
    final Map<String, dynamic>? j =
        await AppStorage.loadJson(file: 'backtest_methods.json');
    if (j == null || !mounted) return;
    final BtMethod m = BtMethod.fromJson(j);
    setState(() {
      _nameController.text = m.name;
      _descController.text = m.desc;
      _strat = m.strategy;
      _methodMsg = 'Đã khôi phục phương pháp đã lưu.';
    });
  }

  Future<void> _saveMethod() async {
    final BtMethod m = BtMethod(
      name: _nameController.text.trim(),
      desc: _descController.text.trim(),
      strategy: _strat,
    );
    final bool ok =
        await AppStorage.saveJson(m.toJson(), file: 'backtest_methods.json');
    if (mounted) {
      setState(() {
        _methodMsg = ok
            ? 'Đã lưu phương pháp "${m.name}" lúc ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}.'
            : '⚠ Không lưu được phương pháp (thiết bị chưa hỗ trợ lưu).';
      });
    }
  }

  void _onStratChanged(String? v) {
    if (v == null) return;
    setState(() {
      _strat = v;
      final AiStrategy s = switch (v) {
        'volumebs' => AiStrategy.volumebs,
        'ai' => AiStrategy.ai,
        _ => AiStrategy.swing,
      };
      _nameController.text = strategyLabel(s);
      if (_descController.text.trim().isEmpty) {
        _descController.text = 'Chiến lược test: ${strategyLabel(s)}.';
      }
    });
  }

  /// Nguồn nến của cặp (để ghi rõ trong khung kết quả khi không đủ nến).
  String _btSourceLabel(String sym) {
    if (sym == 'BTCUSD' || sym == 'XAUUSD') return 'Binance';
    if (sym == 'USOIL') return 'Yahoo Finance (CL=F)';
    return 'Kraken';
  }

  /// Tải tối đa [_range] nến (tối đa 2000) rồi chạy backtest BẤT ĐỒNG BỘ:
  /// tải nến có báo tiến trình từng trang, engine chạy trên isolate riêng
  /// ([runBacktestAsync]) nên UI không đơ. Lỗi tải/chạy đều hiện trong
  /// khung kết quả, không crash. Dùng fetcher chung của engine
  /// (không tạo HttpClient mới); KHÔNG dùng cache 300 nến của tín hiệu.
  Future<void> _run() async {
    if (_running) return;
    final String methodName = _nameController.text.trim().isEmpty
        ? strategyLabel(engine.strategy)
        : _nameController.text.trim();
    setState(() {
      _running = true;
      _result = null;
      _progress = 'Đang tải nến… 0/$_range';
    });
    try {
      final List<RawCandle> candles =
          await engine.cache.fetcher.fetchCandlesHistory(
        _sym,
        _tf,
        maxCandles: _range,
        onProgress: (int loaded, int target) {
          if (!mounted) return;
          setState(() => _progress = 'Đang tải nến… $loaded/$target');
        },
      );
      if (!mounted) return;
      setState(() =>
          _progress = 'Đang chạy backtest trên ${candles.length} nến…');
      final BacktestResult r = await runBacktestAsync(
        symbol: _sym,
        candles: candles,
        tf: _tf,
        range: _range,
        strategy: _strat,
        ind: engine.indParams,
        methodName: methodName,
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _running = false;
        _progress = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = '';
        _result = BacktestResult.error(
          methodName: methodName,
          strategyUsed: _strat,
          candleCount: 0,
          error: 'Không tải được nến $_sym ($_tf) để backtest: $e',
        );
      });
    }
  }

  String _fmtPf(double pf) {
    if (pf.isNaN) return '—';
    if (pf.isInfinite) return '∞';
    return pf.toStringAsFixed(2);
  }

  String _fmtRr(double v) {
    if (v.isNaN) return '—';
    return '1 : ${v.toStringAsFixed(2)}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BacktestResult? r = _result;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        sectionTitle('Backtest trên nến thật đã tải'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  value: _sym,
                  isExpanded: true,
                  items: symbols
                      .map((s) => DropdownMenuItem(
                          value: s.code, child: Text(s.code)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _sym = v);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['M15', 'H1', 'H4'].map((tf) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tf),
                        selected: _tf == tf,
                        onSelected: (_) => setState(() => _tf = tf),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                const Text('Khoảng test (nến) — tối đa 2000:'),
                Row(
                  children: [200, 500, 1000, 2000].map((n) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('$n'),
                        selected: _range == n,
                        onSelected: (_) => setState(() => _range = n),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: _strat,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'swing',
                        child: Text('Swing M15/H1 · xác nhận H4')),
                    DropdownMenuItem(
                        value: 'volumebs',
                        child: Text('VolumeB/S — TonyD Volume Profile')),
                    DropdownMenuItem(
                        value: 'ai',
                        child: Text('AI hợp nhất (Swing + VolumeB/S + MACD)')),
                  ],
                  onChanged: _onStratChanged,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _running ? null : _run,
                    child: Text(
                        _running ? 'Đang chạy…' : 'Chạy Backtest'),
                  ),
                ),
                if (_running) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Text(
                    _progress,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.mut),
                  ),
                ],
              ],
            ),
          ),
        ),
        sectionTitle('Phương pháp giao dịch'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên phương pháp',
                    hintText: 'VD: Swing H1 theo EMA + retest POC',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả / quy tắc',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveMethod,
                    child: const Text('Lưu phương pháp'),
                  ),
                ),
                if (_methodMsg.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_methodMsg,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.up)),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Lưu ý: app chưa tự chuyển văn bản tự do thành quy tắc chạy được — engine vẫn chạy theo chiến lược đã chọn ở trên cùng thông số chỉ báo hiện tại; phần tự viết chỉ là tên + ghi chú quy tắc để đối chiếu.',
                  style: TextStyle(fontSize: 12, color: AppColors.mut),
                ),
              ],
            ),
          ),
        ),
        if (r != null) ...[
          sectionTitle('Kết quả'),
          // KHUNG KẾT QUẢ RIÊNG: viền cam 2px + bo góc, tách hẳn khỏi
          // phần chọn cặp/khung và khung nhập phương pháp. Chứa toàn bộ:
          // phương pháp, chiến lược, số nến đã tải/test, thống kê, danh
          // sách lệnh và lưu ý quá khứ — hoặc lỗi (chưa đủ nến / tải lỗi).
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.gold, width: 2),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.panel,
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kết quả Backtest',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                kvRow('Phương pháp', r.methodName),
                kvRow('Chiến lược engine chạy', r.strategyUsed),
                kvRow('Số nến đã tải (đã đóng)',
                    '${r.candleCount} nến ($_sym · $_tf)'),
                kvRow('Số nến đã test', '${r.testedCandles} nến'),
                if (r.error == null && r.candleCount + 1 < _range)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '⚠ Chỉ tải được ${r.candleCount + 1}/$_range nến — ${_btSourceLabel(_sym)} không có đủ lịch sử cho khung $_tf (đặc biệt Yahoo giới hạn range). Kết quả dưới đây chỉ dùng số nến thực tế trên.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.dn,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                if (r.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      r.error!,
                      style: const TextStyle(
                          color: AppColors.dn,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                else ...[
                  kvRow('Số lệnh test', '${r.trades.length}'),
                  kvRow('Thắng / Thua', '${r.wins} / ${r.losses}'),
                  kvRow('Win rate',
                      '${r.winRate.toStringAsFixed(1)}%'),
                  kvRow('Tổng kết quả (R)',
                      '${r.totalR >= 0 ? '+' : ''}${r.totalR.toStringAsFixed(2)}'),
                  kvRow('Profit factor', _fmtPf(r.profitFactor)),
                  kvRow('RR thực tế TB', _fmtRr(r.avgRealRr)),
                  kvRow('R trung bình / lệnh',
                      '${r.avgR >= 0 ? '+' : ''}${r.avgR.toStringAsFixed(2)}'),
                  kvRow('Max drawdown (R)',
                      r.maxDrawdownR.toStringAsFixed(2)),
                  const SizedBox(height: 4),
                  Text(
                    'Thông số: EMA ${engine.indParams.emaFast}/${engine.indParams.emaSlow} · MACD ${engine.indParams.macdF},${engine.indParams.macdS},${engine.indParams.macdSig} · RSI ${engine.indParams.rsiSig} · ATR ${engine.indParams.atrPeriod} · SL ${engine.indParams.slMult}×ATR · TP ${engine.indParams.tpMult}×ATR',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.mut),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Danh sách lệnh test (tối đa 80 gần nhất)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (r.trades.isEmpty)
                    const Text(
                      'Chiến lược không sinh lệnh nào trong khoảng đã chọn — thử khoảng dài hơn.',
                      style: TextStyle(fontSize: 12),
                    )
                  else
                    ...r.trades.reversed.take(80).map((t) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${t.symbol} · ${t.action}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${t.result == 'win' ? 'WIN' : 'LOSS'} ${t.r >= 0 ? '+' : ''}${t.r.toStringAsFixed(2)}R',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: t.result == 'win'
                                          ? AppColors.up
                                          : AppColors.dn,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Mở ${vnDateStr(t.openAt)} · Entry ${engine.fmt(t.entry, t.symbol)} · SL ${engine.fmt(t.sl, t.symbol)} · TP ${engine.fmt(t.tp, t.symbol)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                'Đóng ${vnDateStr(t.closeAt)} tại ${engine.fmt(t.exit, t.symbol)} · ${t.note}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.mut),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
                const SizedBox(height: 12),
                const Text(
                  btPastDisclaimer,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.gold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Auto-Trade (tab 9) — GIỮ NGUYÊN luồng demo v1.1.0, chỉ đổi theme
// trắng + nối lệnh demo với tín hiệu tĩnh mới.
// ---------------------------------------------------------------------------

class AutoTradeTab extends StatefulWidget {
  const AutoTradeTab({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<AutoTradeTab> createState() => _AutoTradeTabState();
}

class _AutoTradeTabState extends State<AutoTradeTab> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _secretController;
  late final TextEditingController _ruleController;
  late final TextEditingController _lotController;
  late final TextEditingController _riskController;
  late final TextEditingController _drawdownController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  MockEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _secretController = TextEditingController();
    _ruleController = TextEditingController(text: engine.ruleJson);
    _lotController = TextEditingController(text: engine.fixedLot.toString());
    _riskController = TextEditingController(text: engine.riskPct.toString());
    _drawdownController =
        TextEditingController(text: engine.maxDrawdownPct.toString());
    _startController = TextEditingController(text: engine.tradeStart);
    _endController = TextEditingController(text: engine.tradeEnd);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretController.dispose();
    _ruleController.dispose();
    _lotController.dispose();
    _riskController.dispose();
    _drawdownController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _confirmAutoTrade() async {
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cảnh báo rủi ro'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Auto-Trade có thể mở/đóng lệnh tự động và gây thua lỗ. '
                'Đây chỉ là bản DEMO mô phỏng, không giao dịch tiền thật. '
                'Lần đầu chỉ Demo 24h, chưa mở Live thật.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Gõ đúng chữ “TÔI ĐỒNG Ý” để xác nhận:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  hintText: 'TÔI ĐỒNG Ý',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                confirmController.text.trim() == 'TÔI ĐỒNG Ý',
              ),
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    );
    confirmController.dispose();

    if (confirmed == true) {
      engine.enableAutoTrade();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã bật Auto-Trade DEMO 24h (mô phỏng).'),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa xác nhận')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = engine.exnessAccount.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle('Trạng thái Auto-Trade'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    engine.autoTrade
                        ? 'Đang bật · ${engine.demoRemainingLabel}'
                        : 'Chưa bật',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'LIVE khóa — trong app không có đường nào chuyển sang LIVE; hết 24 giờ demo cũng chỉ hiển thị "LIVE khóa".',
                    style: TextStyle(fontSize: 12, color: AppColors.mut),
                  ),
                  Text(
                    'Lệnh demo mở tại giá live, SL/TP lấy từ tín hiệu tĩnh; chống mở trùng bằng key cặp|hướng|giờ đóng nến H1.',
                    style: const TextStyle(fontSize: 12, color: AppColors.mut),
                  ),
                ],
              ),
            ),
          ),
          sectionTitle('Đăng nhập Exness (MOCK — mô phỏng phiên)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (connected) ...[
                    Text(
                      'Đã kết nối (mô phỏng phiên): ${engine.exnessAccount}',
                      style: const TextStyle(
                        color: AppColors.up,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => engine.disconnectExness(),
                      child: const Text('Ngắt kết nối'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _secretController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Secret',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          engine.connectExness(
                            _apiKeyController.text,
                            _secretController.text,
                          );
                          _apiKeyController.clear();
                          _secretController.clear();
                        },
                        child: const Text('Kết nối & tạo phiên'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Key chỉ giữ trong bộ nhớ phiên, không ghi file/log, '
                    'không gọi API thật. App chỉ giữ session token mô phỏng.',
                    style: TextStyle(fontSize: 12, color: AppColors.mut),
                  ),
                ],
              ),
            ),
          ),
          sectionTitle('Rule Engine'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _ruleController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Rule JSON',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ví dụ: {"rsi_lt":30,"close_gt_ema":200}',
                    style: TextStyle(fontSize: 12, color: AppColors.mut),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        engine.evaluateRule(
                          _ruleController.text,
                          engine.selectedSymbol,
                        );
                      },
                      child: const Text('Chạy Rule'),
                    ),
                  ),
                  if (engine.ruleResult.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      engine.ruleResult,
                      style: const TextStyle(color: AppColors.up),
                    ),
                  ],
                ],
              ),
            ),
          ),
          sectionTitle('Auto-Trade (MOCK DEMO)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Auto-Trade'),
                    subtitle: const Text(
                      'Lần đầu chỉ Demo 24h, chưa mở Live thật.',
                    ),
                    value: engine.autoTrade,
                    onChanged: (value) {
                      if (value) {
                        if (!engine.exnessConnected) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Hãy kết nối Exness (mô phỏng phiên) ở mục trên trước khi bật Auto-Trade.',
                              ),
                            ),
                          );
                          return;
                        }
                        _confirmAutoTrade();
                      } else {
                        engine.disableAutoTrade();
                      }
                    },
                  ),
                  const Divider(),
                  const Text(
                    'Cặp được phép giao dịch:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...symbols.map((s) {
                    return CheckboxListTile(
                      title: Text(s.code),
                      value: engine.allowedSymbols.contains(s.code),
                      onChanged: (_) => engine.toggleAllowedSymbol(s.code),
                      dense: true,
                    );
                  }),
                  TextField(
                    controller: _lotController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Lot cố định',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final v = double.tryParse(value);
                      if (v != null) engine.fixedLot = v;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _riskController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '% rủi ro mỗi lệnh',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final v = double.tryParse(value);
                      if (v != null) engine.riskPct = v;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Số lệnh mở tối đa: ${engine.maxOpen}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: engine.maxOpen.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '${engine.maxOpen}',
                    onChanged: (value) {
                      engine.maxOpen = value.round();
                    },
                  ),
                  TextField(
                    controller: _drawdownController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Max drawdown ngày (%)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final v = double.tryParse(value);
                      if (v != null) engine.maxDrawdownPct = v;
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _startController,
                          decoration: const InputDecoration(
                            labelText: 'Giờ bắt đầu',
                            hintText: 'VD: 08:00',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => engine.tradeStart = value,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _endController,
                          decoration: const InputDecoration(
                            labelText: 'Giờ kết thúc',
                            hintText: 'VD: 22:00',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => engine.tradeEnd = value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ngưỡng confidence tối thiểu: ${engine.minConfidence}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: engine.minConfidence.toDouble(),
                    min: 50,
                    max: 90,
                    divisions: 8,
                    label: '${engine.minConfidence}%',
                    onChanged: (value) {
                      engine.minConfidence = value;
                    },
                  ),
                  const Text(
                    'Lần đầu chỉ Demo 24h, chưa mở Live thật.',
                    style: TextStyle(fontSize: 12, color: AppColors.gold),
                  ),
                ],
              ),
            ),
          ),
          sectionTitle('Lệnh đang mở (DEMO)'),
          if (engine.openTrades.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Không có lệnh nào đang mở.'),
              ),
            )
          else
            ...engine.openTrades.map((t) {
              return Card(
                child: ListTile(
                  title: Text('${t.symbol} • ${t.action}'),
                  subtitle: Text(
                    'Entry: ${engine.fmt(t.entry, t.symbol)} • Lot: ${t.lot} • '
                    'Lợi nhuận: ${t.profit}',
                  ),
                  trailing: TextButton(
                    onPressed: () => engine.closeTrade(t),
                    child: const Text('Đóng'),
                  ),
                ),
              );
            }),
          sectionTitle('Lịch sử lệnh DEMO đã đóng'),
          if (engine.closedTrades.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Chưa có lệnh nào đã đóng.'),
              ),
            )
          else
            ...engine.closedTrades.map((t) {
              return Card(
                child: ListTile(
                  title: Text('${t.symbol} • ${t.action}'),
                  subtitle: Text(
                    'Entry: ${engine.fmt(t.entry, t.symbol)} • Lot: ${t.lot} • '
                    'Lợi nhuận: ${t.profit}',
                  ),
                ),
              );
            }),
          sectionTitle('Hiệu suất từng cặp (từ lịch sử tín hiệu phiên)'),
          ...symbols.map((s) {
            final p = engine.performanceFor(s.code);
            return Card(
              child: ListTile(
                title: Text(s.code),
                subtitle: Text(
                  'Win rate: ${p.winRate == null ? '—' : '${p.winRate!.toStringAsFixed(1)}%'} • '
                  'Profit factor: ${p.profitFactor == null ? '—' : p.profitFactor!.isInfinite ? '∞' : p.profitFactor!.toStringAsFixed(2)} • '
                  'Avg RR: ${p.avgRr == null ? '—' : p.avgRr!.toStringAsFixed(2)}',
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
