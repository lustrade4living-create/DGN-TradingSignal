// TradeSignal AI — Engine: giá LIVE (HttpClient thuần Dart, không plugin)
// + nến thật (CandleCache: Binance/Kraken/Yahoo, KHÔNG OKX) + tín hiệu tĩnh
// chốt theo nến H1 đã đóng + SessionHistory + AlertStore + NewsService.
//
// Nguyên tắc giữ từ bản web (spec-web):
//  - Giá live polling 2 giây, 5 nguồn v1.1.0 (gold-api/Binance/er-api+
//    Kraken/Yahoo dầu). Forex neo er-api (5 phút) + tick Kraken theo tỉ lệ.
//  - Nến thật là chính; chưa tải được thì FALLBACK nến mock (cờ
//    candlesAreMock) và UI phải hiện badge "NẾN MOCK".
//  - Tín hiệu TĨNH: chỉ tính lại khi có nến H1 mới đóng hoặc force=true
//    (đổi chiến lược/thông số). KHÔNG tính lại theo giá live.
//  - Lịch sử chỉ giữ trong phiên mở app (đóng app là mất) — đúng web.
//  - Auto-Trade chỉ là DEMO mô phỏng, LIVE khóa, không gọi API Exness thật.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'alerts.dart';
import 'gauge_ladder.dart';
import 'history.dart';
import 'indicators.dart' as ind;
import 'market_data.dart';
import 'news_live.dart';
import 'patterns.dart';
import 'safe_json.dart';
import 'signal_core.dart';
import 'storage.dart';
import 'volume_profile.dart';

// ---------------------------------------------------------------------------
// Model dữ liệu
// ---------------------------------------------------------------------------

class Candle {
  final double o;
  final double h;
  final double l;
  final double c;
  final double vol;
  final int time; // epoch milliseconds, đầu nến.
  const Candle(this.o, this.h, this.l, this.c, this.vol, this.time);
  double get open => o;
  double get high => h;
  double get low => l;
  double get close => c;
}

class SymbolInfo {
  final String code;
  final String name;
  final double base;
  final double tick;
  final int decimals;
  const SymbolInfo(this.code, this.name, this.base, this.tick, this.decimals);
}

const List<SymbolInfo> symbols = <SymbolInfo>[
  SymbolInfo('BTCUSD', 'Bitcoin / USD', 65100, 1, 2),
  SymbolInfo('XAUUSD', 'Vàng / USD', 3880, 0.01, 2),
  SymbolInfo('EURUSD', 'Euro / USD', 1.1025, 0.0001, 4),
  SymbolInfo('GBPUSD', 'Bảng Anh / USD', 1.3210, 0.0001, 4),
  SymbolInfo('USDCAD', 'USD / CAD', 1.4270, 0.0001, 4),
  SymbolInfo('USDCHF', 'USD / CHF', 0.8390, 0.0001, 4),
  SymbolInfo('USDJPY', 'USD / Yên Nhật', 159.70, 0.01, 2),
  SymbolInfo('USOIL', 'Dầu WTI / USD', 88.30, 0.01, 2),
];

SymbolInfo symbolByCode(String code) {
  for (final SymbolInfo s in symbols) {
    if (s.code == code) return s;
  }
  return symbols[1]; // Mặc định XAUUSD nếu mã lạ.
}

/// Tín hiệu cũ (v1.1.0) — giữ lại class để code ngoài không vỡ, nhưng
/// engine mới dùng StaticSignal (signal_core.dart) làm tín hiệu chính.
class Signal {
  final String symbol;
  final String timeframe;
  final String action;
  final String bias;
  final String mode;
  final String status;
  final String id;
  final double entry;
  final double sl;
  final double tp;
  final double rr;
  final double confidence;
  final double atr;
  final List<String> reasons;
  final DateTime time;

  const Signal({
    required this.symbol,
    required this.timeframe,
    required this.action,
    required this.bias,
    required this.mode,
    required this.status,
    required this.id,
    required this.entry,
    required this.sl,
    required this.tp,
    required this.rr,
    required this.confidence,
    required this.atr,
    required this.reasons,
    required this.time,
  });
}

class IndicatorSet {
  final List<double?> ema20;
  final List<double?> ema50;
  final List<double?> ema200;
  final List<double?> rsi;
  final List<double?> macd;
  final List<double?> macdSignal;
  final List<double?> atr;
  final List<double?> bbUp;
  final List<double?> bbMid;
  final List<double?> bbLow;

  const IndicatorSet({
    required this.ema20,
    required this.ema50,
    required this.ema200,
    required this.rsi,
    required this.macd,
    required this.macdSignal,
    required this.atr,
    required this.bbUp,
    required this.bbMid,
    required this.bbLow,
  });
}

class Trade {
  final String id;
  final String symbol;
  final String action; // 'BUY' | 'SELL'
  String status; // 'open' | 'closed'
  final double entry;
  final double sl;
  final double tp;
  final double lot;
  final DateTime opened;
  double? closePrice;
  double? pnl;

  String get profit => pnl == null ? '—' : '${pnl!.toStringAsFixed(2)} USD';

  Trade({
    required this.id,
    required this.symbol,
    required this.action,
    required this.entry,
    required this.sl,
    required this.tp,
    required this.lot,
    required this.opened,
    this.status = 'open',
    this.closePrice,
    this.pnl,
  });
}

/// Gói hiệu suất một cặp — SỐ THẬT từ SessionHistory; null khi chưa có
/// lệnh đóng trong phiên (UI hiện "—"). ĐÃ BỎ fallback mock theo hash.
class Performance {
  final double? winRate;
  final double? profitFactor;
  final double? avgRr;
  const Performance({this.winRate, this.profitFactor, this.avgRr});
}

// ---------------------------------------------------------------------------
// Chỉ báo kỹ thuật cũ (giữ nguyên — volume_profile.dart dùng ema/atr)
// ---------------------------------------------------------------------------

List<double?> ema(List<double> closes, int period) {
  final List<double?> out = List<double?>.filled(closes.length, null);
  if (period <= 0 || closes.length < period) return out;
  double sum = 0;
  for (int i = 0; i < period; i++) {
    sum += closes[i];
  }
  double prev = sum / period;
  out[period - 1] = prev;
  final double k = 2 / (period + 1);
  for (int i = period; i < closes.length; i++) {
    prev = closes[i] * k + prev * (1 - k);
    out[i] = prev;
  }
  return out;
}

List<double?> rsi(List<double> closes, int period) {
  final List<double?> out = List<double?>.filled(closes.length, null);
  if (period <= 0 || closes.length <= period) return out;
  double gain = 0;
  double loss = 0;
  for (int i = 1; i <= period; i++) {
    final double d = closes[i] - closes[i - 1];
    if (d > 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  double avgGain = gain / period;
  double avgLoss = loss / period;
  out[period] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
  for (int i = period + 1; i < closes.length; i++) {
    final double d = closes[i] - closes[i - 1];
    final double g = d > 0 ? d : 0;
    final double l = d < 0 ? -d : 0;
    avgGain = (avgGain * (period - 1) + g) / period;
    avgLoss = (avgLoss * (period - 1) + l) / period;
    out[i] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
  }
  return out;
}

List<double?> atr(List<Candle> cs, int period) {
  final List<double?> out = List<double?>.filled(cs.length, null);
  if (period <= 0 || cs.length < period) return out;
  final List<double> tr = List<double>.filled(cs.length, 0);
  for (int i = 0; i < cs.length; i++) {
    if (i == 0) {
      tr[i] = cs[i].h - cs[i].l;
    } else {
      final double hl = cs[i].h - cs[i].l;
      final double hc = (cs[i].h - cs[i - 1].c).abs();
      final double lc = (cs[i].l - cs[i - 1].c).abs();
      tr[i] = max(hl, max(hc, lc));
    }
  }
  double sum = 0;
  for (int i = 0; i < period; i++) {
    sum += tr[i];
  }
  double prev = sum / period;
  out[period - 1] = prev;
  for (int i = period; i < cs.length; i++) {
    prev = (prev * (period - 1) + tr[i]) / period;
    out[i] = prev;
  }
  return out;
}

List<double?> macdLine(List<double> closes) {
  final List<double?> e12 = ema(closes, 12);
  final List<double?> e26 = ema(closes, 26);
  return List<double?>.generate(closes.length, (int i) {
    if (e12[i] != null && e26[i] != null) {
      return e12[i]! - e26[i]!;
    }
    return null;
  });
}

List<double?> macdSignal(List<double> closes) {
  final List<double?> line = macdLine(closes);
  final List<double?> out = List<double?>.filled(closes.length, null);
  final List<double> vals = <double>[];
  final List<int> idx = <int>[];
  for (int i = 0; i < line.length; i++) {
    if (line[i] != null) {
      vals.add(line[i]!);
      idx.add(i);
    }
  }
  final List<double?> sig = ema(vals, 9);
  for (int j = 0; j < idx.length; j++) {
    out[idx[j]] = sig[j];
  }
  return out;
}

List<List<double?>> _bollinger(List<double> closes, int period, double mult) {
  final List<double?> mid = List<double?>.filled(closes.length, null);
  final List<double?> up = List<double?>.filled(closes.length, null);
  final List<double?> low = List<double?>.filled(closes.length, null);
  if (period <= 0 || closes.length < period) {
    return <List<double?>>[up, mid, low];
  }
  for (int i = period - 1; i < closes.length; i++) {
    double sum = 0;
    for (int j = i - period + 1; j <= i; j++) {
      sum += closes[j];
    }
    final double mean = sum / period;
    double sq = 0;
    for (int j = i - period + 1; j <= i; j++) {
      final double d = closes[j] - mean;
      sq += d * d;
    }
    final double sd = sqrt(sq / period);
    mid[i] = mean;
    up[i] = mean + mult * sd;
    low[i] = mean - mult * sd;
  }
  return <List<double?>>[up, mid, low];
}

List<double?> bollingerUp(List<double> closes) => _bollinger(closes, 20, 2)[0];
List<double?> bollingerMid(List<double> closes) => _bollinger(closes, 20, 2)[1];
List<double?> bollingerLow(List<double> closes) => _bollinger(closes, 20, 2)[2];

/// ATR series (trung bình đơn giản của True Range, theo indicators.dart).
List<double?> _atrSeries(List<Candle> cs, int period) {
  final List<double?> out = List<double?>.filled(cs.length, null);
  if (period < 1 || cs.length < period + 1) return out;
  final List<double> tr = List<double>.filled(cs.length, 0);
  for (int i = 0; i < cs.length; i++) {
    if (i == 0) {
      tr[i] = cs[i].h - cs[i].l;
    } else {
      tr[i] = max(
        cs[i].h - cs[i].l,
        max((cs[i].h - cs[i - 1].c).abs(), (cs[i].l - cs[i - 1].c).abs()),
      );
    }
  }
  for (int i = period; i < cs.length; i++) {
    double sum = 0;
    for (int j = i - period + 1; j <= i; j++) {
      sum += tr[j];
    }
    out[i] = sum / period;
  }
  return out;
}

/// Tính chỉ báo theo [indParams] hiện tại (indicators.dart, công thức
/// spec §13.2). Giữ nguyên tên/chữ ký trả về. Lưu ý: ema200/Bollinger
/// chỉ lưu trữ theo spec §13.4, không đưa vào tín hiệu.
IndicatorSet computeIndicators(List<Candle> cs,
    {ind.IndicatorParams? params}) {
  final ind.IndicatorParams p = params ?? ind.IndicatorParams.defaults;
  final List<double> closes = cs.map((Candle c) => c.c).toList();
  // MACD cần RawCandle — chuyển tạm từ Candle (chỉ dùng o/h/l/c/v/t).
  final List<RawCandle> raw = cs
      .map((Candle c) =>
          RawCandle(t: c.time, o: c.o, h: c.h, l: c.l, c: c.c, v: c.vol))
      .toList();
  final ind.MacdResult macd =
      ind.macdSeries(raw, p.macdF, p.macdS, p.macdSig);
  final ind.BollingerResult bands = ind.bollinger(closes, p.bbPeriod, p.bbMult);
  return IndicatorSet(
    ema20: ind.emaSeries(closes, p.emaFast),
    ema50: ind.emaSeries(closes, p.emaSlow),
    ema200: ind.emaSeries(closes, p.ema200),
    rsi: ind.rsiSeries(closes, p.rsiChart),
    macd: macd.line,
    macdSignal: macd.signal,
    atr: _atrSeries(cs, p.atrPeriod),
    bbUp: bands.upper,
    bbMid: bands.middle,
    bbLow: bands.lower,
  );
}

double? _lastValue(List<double?> values) {
  for (int i = values.length - 1; i >= 0; i--) {
    if (values[i] != null) return values[i];
  }
  return null;
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

const List<String> _allTfs = <String>['M5', 'M15', 'H1', 'H4', 'D1'];

/// Kết quả parse báo giá dầu Yahoo CL=F: giá đóng của nến 1 phút mới nhất,
/// giờ mở của nến đó, % thay đổi so với giá đóng phiên trước, và tháng hợp
/// đồng (dạng "T12/26", parse từ meta.shortName của Yahoo, VD
/// "Crude Oil Dec 26") — null khi Yahoo không kèm tên tháng.
class YahooOilQuote {
  const YahooOilQuote({
    required this.price,
    required this.quoteTime,
    this.chgPct,
    this.contractLabel,
  });
  final double price;
  final DateTime quoteTime;
  final double? chgPct;
  final String? contractLabel;
}

/// Chính sách thử lại nến còn thiếu (thuần, test được — xem
/// test/auto_load_test.dart). Sửa lỗi 18/11 "phải tắt mở lại mới load":
/// warmup chỉ chạy 1 lần lúc mở app nên lần tải đầu lỗi là nến không bao
/// giờ về nữa; chính sách này cho phép quét lại: lần đầu sau ~10 giây,
/// sau mỗi lần quét thất bại liên tiếp thì giãn gấp đôi: 10s → 20s →
/// 40s → tối đa 60s. Chỉ cần 1 series về được là đếm lỗi về 0.
class CandleRetryPolicy {
  static const Duration firstDelay = Duration(seconds: 10);
  static const Duration maxDelay = Duration(seconds: 60);

  /// Nhịp chờ trước lần thử lại tiếp theo theo số lần thất bại liên tiếp.
  static Duration delayForFailures(int consecutiveFailures) {
    if (consecutiveFailures <= 0) return firstDelay;
    int seconds = firstDelay.inSeconds;
    for (int i = 0; i < consecutiveFailures; i++) {
      seconds *= 2;
      if (seconds >= maxDelay.inSeconds) return maxDelay;
    }
    return Duration(seconds: seconds);
  }

  /// Đã tới lúc thử lại chưa (dựa trên lần thử cuối + nhịp backoff).
  static bool shouldRetry({
    required DateTime? lastAttempt,
    required int consecutiveFailures,
    required DateTime now,
  }) {
    if (lastAttempt == null) return true;
    return now.difference(lastAttempt) >=
        delayForFailures(consecutiveFailures);
  }
}

class MockEngine extends ChangeNotifier with WidgetsBindingObserver {
  String selectedSymbol = 'XAUUSD';
  String timeframe = 'M5';
  bool offline = false;

  // --- Nến thật -------------------------------------------------------------
  // [cache] có thể chích từ ngoài để test (VD fetcher lỗi vài lần rồi
  // thành công); production luôn dùng CandleCache() mặc định.
  final CandleCache cache;

  /// true khi cặp/khung đang xem CHƯA có nến thật (đang dùng nến mock).
  bool hasRealCandles(String symbol, String tf) =>
      cache.seriesOrNull(symbol, tf) != null;

  /// true khi cặp/khung đang chọn đang dùng nến mock (UI hiện badge).
  bool get candlesAreMock => !hasRealCandles(selectedSymbol, timeframe);

  // --- Giá live ---------------------------------------------------------------
  Map<String, String> liveSource = <String, String>{};
  Map<String, DateTime> liveUpdated = <String, DateTime>{};
  Map<String, bool> liveOk = <String, bool>{};
  /// % thay đổi 24h từng cặp (Binance 24hr / Kraken open / CNBC change).
  Map<String, double> chg24h = <String, double>{};
  /// Giờ của nguồn giá (srcTime) — null nếu chưa có.
  Map<String, DateTime?> srcTime = <String, DateTime?>{};

  bool get hasLive {
    final DateTime now = DateTime.now();
    return liveOk.entries.any(
      (e) =>
          e.value &&
          liveUpdated[e.key] != null &&
          now.difference(liveUpdated[e.key]!).inSeconds < 10,
    );
  }

  String priceStatus(String code) {
    final DateTime? t = liveUpdated[code];
    if (liveOk[code] == true && t != null) {
      if (DateTime.now().difference(t).inSeconds < 10) return 'LIVE';
    }
    return 'DỮ LIỆU CŨ';
  }

  String priceSource(String code) => liveSource[code] ?? 'Mock (dữ liệu cũ)';

  String updatedLabel(String code) {
    final DateTime? t = liveUpdated[code];
    if (t == null) return 'chưa cập nhật';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  Map<String, double> prices = <String, double>{};
  Set<String> followed = <String>{};

  // --- Tín hiệu tĩnh ---------------------------------------------------------
  Map<String, StaticSignal?> staticSignals = <String, StaticSignal?>{};
  Map<String, Invalidation?> lastInvalidations = <String, Invalidation?>{};
  AiStrategy strategy = AiStrategy.swing;
  ind.IndicatorParams indParams = ind.IndicatorParams.defaults;
  String? settingsNote; // dòng trạng thái lưu/khôi phục cài đặt
  bool soundOn = true;

  // --- Lịch sử phiên / cảnh báo / tin tức / quét VP --------------------------
  final SessionHistory history = SessionHistory();
  final AlertStore alerts = AlertStore();
  final NewsService news = NewsService();
  Map<String, VpScanResult?> vpScan = <String, VpScanResult?>{};

  // --- Auto-Trade demo --------------------------------------------------------
  bool autoTrade = false;
  bool demoOnly = true;
  DateTime? demoStarted;
  DateTime? demoEnd;
  bool exnessConnected = false;
  String exnessAccount = '';
  List<Trade> openTrades = <Trade>[];
  List<Trade> closedTrades = <Trade>[];
  double dailyPnl = 0;
  double riskPct = 1;
  double fixedLot = 0.01;
  bool useFixedLot = true;
  int maxOpen = 3;
  double maxDrawdownPct = 5;
  double minConfidence = 70;
  Set<String> allowedSymbols = <String>{'XAUUSD', 'BTCUSD', 'EURUSD'};
  String tradeStart = '00:00';
  String tradeEnd = '23:59';
  final Set<String> tradedKeys = <String>{}; // sym|action|closedAt

  String ruleJson = '{"rsi_lt":30,"close_gt_ema":200}';
  String ruleResult = 'Chưa chạy';

  final Map<String, List<Candle>> _m1 = <String, List<Candle>>{};
  final Random _tickRand = Random();
  Timer? _timer;
  Timer? _liveTimer;
  // Timer thử lại nến còn thiếu (10 giây/nhịp, chỉ fetch series thiếu).
  Timer? _candleRetryTimer;
  bool _fetchingLive = false;
  int _tickCount = 0;
  bool _warmupDone = false;
  // Backoff thử lại nến: số lần quét thất bại liên tiếp + lần quét cuối.
  int _candleRetryFailures = 0;
  DateTime? _lastCandleRetryAt;
  bool _retryingCandles = false;

  // Neo forex er-api: sym -> (anchorPrice, krakenMid lúc neo, thời điểm neo)
  final Map<String, double> _fxAnchorPrice = <String, double>{};
  final Map<String, double> _fxAnchorMid = <String, double>{};
  DateTime? _fxAnchorAt;

  // Cache tính toán theo (symbol, closedAt) — xem trendsFor/paFor.
  final Map<String, String> _trendCacheKey = <String, String>{};
  final Map<String, Map<String, TrendInfo>> _trendCache =
      <String, Map<String, TrendInfo>>{};
  final Map<String, String> _paCacheKey = <String, String>{};
  final Map<String, PaResult> _paCache = <String, PaResult>{};
  final Map<String, String> _patCacheKey = <String, String>{};
  final Map<String, List<PatternStat>> _patCache =
      <String, List<PatternStat>>{};
  final Map<String, int> _vpScanKey = <String, int>{};
  final Map<String, TierTracker> _tierTrackers = <String, TierTracker>{};

  MockEngine({CandleCache? cache}) : cache = cache ?? CandleCache() {
    WidgetsBinding.instance.addObserver(this);
    for (final SymbolInfo s in symbols) {
      _m1[s.code] = _generateM1(s);
      prices[s.code] = _m1[s.code]!.last.c;
      liveSource[s.code] = 'Mock (dữ liệu cũ)';
      liveOk[s.code] = false;
      staticSignals[s.code] = null;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    _liveTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _fetchLivePrices(),
    );
    // Thử lại nến còn thiếu (nhịp 10 giây, có backoff — xem
    // _candleRetryTick): warmup chỉ chạy 1 lần nên lần tải đầu lỗi là
    // nến không bao giờ về nếu không có timer này. Timer mới này không
    // động vào _timer/_liveTimer và không đổi chu kỳ của chúng.
    _candleRetryTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _candleRetryTick(),
    );
    _fetchLivePrices();
    _loadSettings();
    _warmup();
    news.startScanning();
    unawaited(news.fetchOnce());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _liveTimer?.cancel();
    _candleRetryTimer?.cancel();
    news.stopScanning();
    cache.dispose();
    super.dispose();
  }

  // --- Lưu/khôi phục cài đặt (settings.json qua MethodChannel) --------------
  // Dong thoi nap lich su tin hieu da luu ben (signal_history.json):
  // moi tin hieu ket thuc (TP/SL/huy som) deu duoc SessionHistory luu
  // ngay khi dong (xem history.dart: _schedulePersist, goi tu
  // checkOutcomes/closeReversal — 2 duong dong duy nhat cua engine).
  Future<void> _loadSettings() async {
    await history.loadPersisted();
    final Map<String, dynamic>? j =
        await AppStorage.loadJson(file: 'settings.json');
    if (j == null) return;
    bool changed = false;
    final Object? st = j['strategy'];
    if (st is String) {
      final AiStrategy? s = switch (st) {
        'swing' => AiStrategy.swing,
        'volumebs' => AiStrategy.volumebs,
        'ai' => AiStrategy.ai,
        _ => null,
      };
      if (s != null && s != strategy) {
        strategy = s;
        changed = true;
      }
    }
    final Object? ip = j['ind'];
    if (ip is Map<String, dynamic>) {
      indParams = ind.IndicatorParams.fromJson(ip);
      changed = true;
    }
    final Object? snd = j['soundOn'];
    if (snd is bool) soundOn = snd;
    if (changed) {
      settingsNote = 'Đã khôi phục cài đặt đã lưu (chiến lược + thông số).';
      _checkStaticSignals(force: true);
      notifyListeners();
    }
  }

  Future<bool> _saveSettings() async {
    final bool ok = await AppStorage.saveJson(<String, dynamic>{
      'strategy': strategy.name,
      'ind': indParams.toJson(),
      'soundOn': soundOn,
    }, file: 'settings.json');
    settingsNote = ok
        ? 'Đã lưu lúc ${_hhmmss(DateTime.now())}.'
        : '⚠ Không lưu được cài đặt (thiết bị chưa hỗ trợ lưu) — tải lại app sẽ mất lựa chọn này.';
    notifyListeners();
    return ok;
  }

  static String _hhmmss(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  Future<void> setStrategy(AiStrategy s) async {
    if (strategy == s) return;
    strategy = s;
    await _saveSettings();
    _checkStaticSignals(force: true);
    notifyListeners();
  }

  Future<void> applyIndicatorParams(ind.IndicatorParams p) async {
    indParams = p;
    _trendCache.clear();
    _paCache.clear();
    _patCache.clear();
    await _saveSettings();
    _checkStaticSignals(force: true);
    notifyListeners();
  }

  Future<void> resetIndicatorParams() async {
    indParams = ind.IndicatorParams.defaults;
    _trendCache.clear();
    _paCache.clear();
    _patCache.clear();
    await AppStorage.saveJson(<String, dynamic>{
      'strategy': strategy.name,
      'soundOn': soundOn,
    }, file: 'settings.json');
    settingsNote = 'Đã khôi phục mặc định và xóa bản lưu thông số.';
    _checkStaticSignals(force: true);
    notifyListeners();
  }

  Future<void> setSoundOn(bool v) async {
    soundOn = v;
    await _saveSettings();
    if (v) unawaited(ChimePlayer.playTestChime());
    notifyListeners();
  }

  // --- Nến: thật là chính, mock là fallback ----------------------------------
  static Candle _toEngineCandle(RawCandle r) =>
      Candle(r.o, r.h, r.l, r.c, r.v, r.t);

  static List<Candle> _toEngineCandles(List<RawCandle> rs) =>
      rs.map(_toEngineCandle).toList();

  /// Series nến theo khung: ƯU TIÊN nến thật từ cache (đã đóng + đang chạy).
  /// Chưa tải được nến thật thì FALLBACK pipeline mock M1 hiện có.
  List<Candle> candlesFor(String symbol, String tf) {
    final List<RawCandle>? real = cache.seriesOrNull(symbol, tf);
    if (real != null && real.isNotEmpty) return _toEngineCandles(real);
    const Map<String, int> minutes = <String, int>{
      'M1': 1,
      'M5': 5,
      'M15': 15,
      'H1': 60,
      'H4': 240,
      'D1': 1440,
    };
    final List<Candle> m1 = _m1[symbol] ?? <Candle>[];
    final List<Candle> series = _aggregate(m1, minutes[tf] ?? 5);
    if (series.length <= 200) return series;
    return series.sublist(series.length - 200);
  }

  /// Nến thật (RawCandle) cho module logic; [] nếu chưa tải.
  List<RawCandle> rawCandlesFor(String symbol, String tf) =>
      cache.seriesOrNull(symbol, tf) ?? <RawCandle>[];

  /// Nến đã đóng 5 khung cho 1 cặp (map tf -> closed).
  Map<String, List<RawCandle>> closedByTf(String symbol) {
    final Map<String, List<RawCandle>> out = <String, List<RawCandle>>{};
    for (final String tf in _allTfs) {
      out[tf] = cache.closed(symbol, tf);
    }
    return out;
  }

  double priceOf(String symbol) => prices[symbol] ?? symbolByCode(symbol).base;

  double contractSize(String symbol) {
    switch (symbol) {
      case 'XAUUSD':
        return 100;
      case 'BTCUSD':
        return 1;
      case 'USOIL':
        return 1000;
      default:
        return 100000;
    }
  }

  // --- Warmup nến nền (mỗi cặp cách nhau ~350ms, như web warmupSignals) -----
  void _warmup() {
    for (int i = 0; i < symbols.length; i++) {
      final String code = symbols[i].code;
      Future<void>.delayed(Duration(milliseconds: 350 * i), () async {
        for (final String tf in _allTfs) {
          try {
            await cache.ensureCandles(code, tf);
          } catch (_) {
            // Lỗi 1 khung không chặn khung khác; cờ lastError giữ message.
          }
        }
        try {
          _checkStaticSignals();
          _checkVpScan();
        } catch (e) {
          // Phong thu: loi tinh toan sau warmup khong duoc crash app.
          debugPrint('TradeSignal: warmup check loi: $e');
        }
        _safeNotify();
      });
    }
    Future<void>.delayed(
      Duration(milliseconds: 350 * symbols.length + 500),
      () => _warmupDone = true,
    );
  }

  bool get warmupDone => _warmupDone;

  // --- Tự tải lại nến còn thiếu (sửa lỗi "phải tắt mở lại mới load") -----
  // NGUYÊN NHÂN GỐC THỨ 2 (xác định 18/11): _warmup() chỉ chạy 1 lần lúc
  // mở app; lần tải đầu lỗi là nến thật không bao giờ về nữa vì không
  // code nào khác gọi ensureCandles — tín hiệu kẹt mãi ở "ĐANG TẢI",
  // VP scan cũng không chạy (chỉ gọi từ warmup). Timer _candleRetryTimer
  // quét lại các series còn thiếu với backoff (10s → 20s → 40s → tối đa
  // 60s), chỉ fetch series thiếu nên không spam request; nến về tới đâu
  // thì tín hiệu/VP tính lại tới đó, không cần khởi động lại app.
  // KHÔNG đổi nhịp polling giá (2s) / tin (1s) hay logic tín hiệu tĩnh.

  /// Các series (cặp, khung) chưa có nến thật.
  List<(String, String)> _missingCandles() {
    final List<(String, String)> out = <(String, String)>[];
    for (final SymbolInfo s in symbols) {
      for (final String tf in _allTfs) {
        if (cache.seriesOrNull(s.code, tf) == null) out.add((s.code, tf));
      }
    }
    return out;
  }

  /// true khi còn series chưa tải được nến thật.
  bool get hasMissingCandles => _missingCandles().isNotEmpty;

  /// Số series (cặp × khung) chưa có nến thật — UI dùng để báo kẹt.
  int get missingCandlesCount => _missingCandles().length;

  /// true khi warmup đã xong mà vẫn còn nến chưa tải được: dữ liệu đang
  /// kẹt, UI phải hiện nút "Thử lại" thay vì chỉ hiện "ĐANG TẢI".
  bool get candlesStuck => _warmupDone && hasMissingCandles;

  /// Nhịp 10 giây: thử lại nến thiếu nếu đã qua thời gian backoff.
  /// Quét rỗng (không còn thiếu) thì chỉ tốn 1 lần duyệt map.
  void _candleRetryTick() {
    if (_retryingCandles) return;
    final List<(String, String)> missing = _missingCandles();
    if (missing.isEmpty) return;
    if (!CandleRetryPolicy.shouldRetry(
      lastAttempt: _lastCandleRetryAt,
      consecutiveFailures: _candleRetryFailures,
      now: DateTime.now(),
    )) {
      return;
    }
    unawaited(_retryMissingCandles(missing));
  }

  /// Thử tải lại các series còn thiếu. Lỗi 1 series không chặn series
  /// khác. Về được series nào thì tính lại tín hiệu/VP ngay; lỗi hết thì
  /// tăng đếm thất bại để lần sau giãn nhịp (backoff).
  Future<void> _retryMissingCandles(List<(String, String)> missing) async {
    if (_retryingCandles || missing.isEmpty) return;
    _retryingCandles = true;
    _lastCandleRetryAt = DateTime.now();
    bool anyOk = false;
    try {
      for (final (String code, String tf) in missing) {
        try {
          await cache.ensureCandles(code, tf);
          anyOk = true;
        } catch (_) {
          // Lỗi 1 khung không chặn khung khác; cờ lastError giữ message.
        }
      }
    } finally {
      _retryingCandles = false;
    }
    if (anyOk) {
      _candleRetryFailures = 0;
      try {
        _checkStaticSignals();
        _checkVpScan();
      } catch (e) {
        debugPrint('TradeSignal: retry nen — tinh lai loi: $e');
      }
    } else {
      _candleRetryFailures++;
    }
    _safeNotify();
  }

  /// Làm mới toàn bộ dữ liệu theo yêu cầu (nút "Thử lại" trên UI / app
  /// từ nền quay lại): giá live ngay, nến còn thiếu (bỏ qua backoff),
  /// tính lại tín hiệu, tin live + lịch tuần (bắn rồi quên để không kẹt
  /// nút khi 1 nguồn chậm — mỗi service tự có nhịp thử lại riêng).
  /// Không đổi nhịp polling hay logic tín hiệu tĩnh.
  Future<void> refreshAllData() async {
    _candleRetryFailures = 0;
    _lastCandleRetryAt = null;
    unawaited(_fetchLivePrices());
    await _retryMissingCandles(_missingCandles());
    try {
      _checkStaticSignals();
      _checkVpScan();
    } catch (e) {
      debugPrint('TradeSignal: refreshAllData — tinh lai loi: $e');
    }
    // Tin + lịch: bắn rồi quên, không chờ (chờ sẽ làm nút Thử lại phản
    // hồi chậm khi 1 nguồn chậm).
    unawaited(news.fetchOnce());
    unawaited(_refreshCalendarSilently());
    _safeNotify();
  }

  Future<void> _refreshCalendarSilently() async {
    try {
      await news.fetchCalendar();
    } catch (_) {
      // Lịch lỗi thì giữ lịch cũ trong phiên; tab Lịch đã có nút tải lại.
    }
  }

  /// App từ nền quay lại foreground: làm mới dữ liệu để không đứng yên
  /// với dữ liệu cũ/kẹt từ trước khi xuống nền. Trước đây không có
  /// observer nào nên resume không làm mới gì cả.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshAllData());
    }
  }

  /// notifyListeners không bao giờ được làm chết timer/vòng lặp: listener
  /// lỗi (VD widget đã dispose) chỉ ghi log, lần tick sau vẫn chạy.
  /// (Trước đây notifyListeners() nằm ngoài try/catch ở tick() và
  /// _fetchLivePrices() nên listener lỗi sẽ văng ra zone và main.dart
  /// thay toàn bộ app bằng màn hình "App gặp lỗi khi mở".)
  void _safeNotify() {
    try {
      notifyListeners();
    } catch (e) {
      debugPrint('TradeSignal: notify loi: $e');
    }
  }

  // --- Giá live: HttpClient thuần Dart, timeout 5s mỗi nguồn -----------------
  Future<double?> _getJsonPrice(
    String url, {
    Map<String, String>? headers,
    double? Function(Map<String, dynamic> json)? pick,
  }) async {
    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(url)).timeout(
                const Duration(seconds: 5),
              );
      headers?.forEach(req.headers.set);
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final String body =
          await resp.transform(utf8.decoder).join().timeout(
                const Duration(seconds: 5),
              );
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      return pick?.call(decoded);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>?> _getJsonMap(String url,
      {Map<String, String>? headers}) async {
    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(url)).timeout(
                const Duration(seconds: 5),
              );
      headers?.forEach(req.headers.set);
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final String body =
          await resp.transform(utf8.decoder).join().timeout(
                const Duration(seconds: 5),
              );
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Áp giá live: cập nhật giá + nến thật đang chạy (patchForming) +
  /// căn mức series 1 lần (maybeShift) cho cả 5 khung. KHÔNG tính lại
  /// tín hiệu ở đây (tín hiệu tĩnh chỉ tính theo nhịp 30 giây).
  void _applyLivePrice(String code, double price, String source,
      {double? chgPct, DateTime? src}) {
    if (price <= 0 || price.isNaN || price.isInfinite) return;
    prices[code] = price;
    // Phát hiện giá cũ: nếu báo giá kèm giờ của nguồn (src) mà giờ đó cũ
    // hơn 5 phút thì vẫn giữ giá để hiển thị, nhưng đánh dấu KHÔNG live
    // để UI hiện "DỮ LIỆU CŨ" thay vì LIVE. Trước đây LIVE chỉ nghĩa là
    // fetch thành công, không đảm bảo giá mới — dầu CNBC ngày 18/11 là
    // ví dụ (Exness 83,7 trong khi app vẫn LIVE ở 85,2). Chỉ các nguồn
    // truyền src mới bị kiểm tra (hiện chỉ USOIL/Yahoo); các nguồn khác
    // không đổi hành vi.
    final bool stale = isQuoteStale(src);
    liveOk[code] = !stale;
    liveSource[code] = source;
    liveUpdated[code] = DateTime.now();
    if (chgPct != null) chg24h[code] = chgPct;
    if (src != null) srcTime[code] = src;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final String tf in _allTfs) {
      cache.patchForming(code, tf, price, nowMs);
      cache.maybeShift(code, tf, price);
    }
    // Neo nến mock cuối (fallback) vào giá live để chart mock không lệch.
    final List<Candle>? m1 = _m1[code];
    if (m1 != null && m1.isNotEmpty) {
      final Candle last = m1.last;
      m1[m1.length - 1] = Candle(
        last.o,
        max(last.h, price),
        min(last.l, price),
        price,
        last.vol,
        last.time,
      );
    }
  }

  /// Forex theo công thức web fxDisplay (spec §2.3): neo er-api (refresh
  /// mỗi 5 phút) + tick Kraken theo tỉ lệ anchorPrice*krakenMid/anchorMid.
  /// Chưa có neo → dùng thẳng Kraken mid; chưa có cả hai → không có giá.
  void _applyFx(String code, double krakenMid, double? chgPct,
      Map<String, dynamic>? fxRates) {
    if (krakenMid <= 0) return;
    final bool anchorStale = _fxAnchorAt == null ||
        DateTime.now().difference(_fxAnchorAt!).inMinutes >= 5;
    if (anchorStale && fxRates != null) {
      final String cur = _fxCurrency(code);
      final double? rate = numD(fxRates[cur]);
      if (rate != null && rate > 0) {
        final bool inv = code == 'EURUSD' || code == 'GBPUSD';
        _fxAnchorPrice[code] = inv ? 1 / rate : rate;
        _fxAnchorMid[code] = krakenMid;
        _fxAnchorAt = DateTime.now();
      }
    }
    final double? anchor = _fxAnchorPrice[code];
    final double? anchorMid = _fxAnchorMid[code];
    if (anchor != null && anchorMid != null && anchorMid > 0) {
      _applyLivePrice(code, anchor * krakenMid / anchorMid, 'Kraken + er-api',
          chgPct: chgPct);
    } else {
      _applyLivePrice(code, krakenMid, 'Kraken', chgPct: chgPct);
    }
  }

  String _fxCurrency(String code) => switch (code) {
        'EURUSD' => 'EUR',
        'GBPUSD' => 'GBP',
        'USDJPY' => 'JPY',
        'USDCAD' => 'CAD',
        'USDCHF' => 'CHF',
        _ => '',
      };

  /// Parse Kraken Ticker `result` -> {pair: (mid, chgPct)}.
  /// CHU Y: 'a'/'b'/'c' la list chuoi so, nhung 'o' (gia mo hom nay) la
  /// CHUOI ("3882.50") — code cu ep `v['o'] as List<dynamic>?` nen no
  /// ngay khi Kraken tra ve OK (loi crash mo app v1.2.0 #1). Ham nay
  /// khong bao gio throw: muc nao sai kieu thi bo qua muc do.
  static Map<String, (double, double?)> parseKrakenTicker(
      Map<String, dynamic> result) {
    final Map<String, (double, double?)> out = <String, (double, double?)>{};
    for (final MapEntry<String, dynamic> e in result.entries) {
      final Object? v = e.value;
      if (v is! Map<String, dynamic>) continue;
      final List<dynamic>? b = asList(v['b']);
      final List<dynamic>? a = asList(v['a']);
      final List<dynamic>? c = asList(v['c']);
      final double? bid =
          b != null && b.isNotEmpty ? numD(b.first) : null;
      final double? ask =
          a != null && a.isNotEmpty ? numD(a.first) : null;
      final double? last =
          c != null && c.isNotEmpty ? numD(c.first) : null;
      final double? open = numD(v['o']);
      if (bid != null && ask != null) {
        final double mid = (bid + ask) / 2;
        double? chg;
        if (last != null && open != null && open != 0) {
          chg = (last - open) / open * 100;
        }
        out[e.key] = (mid, chg);
      }
    }
    return out;
  }

  /// Kết quả parse báo giá dầu Yahoo CL=F: giá đóng của nến 1 phút mới
  /// nhất, giờ mở của nến đó, và % thay đổi so với giá đóng phiên trước.
  /// Báo giá được coi là cũ khi giờ của nguồn (src) cũ hơn 5 phút so với
  /// lúc kiểm tra. src null (nguồn không kèm giờ) thì không kết luận cũ.
  static bool isQuoteStale(DateTime? src, {DateTime? now}) {
    if (src == null) return false;
    return (now ?? DateTime.now()).difference(src).inMinutes >= 5;
  }

  /// "Crude Oil Dec 26" -> "T12/26"; "Crude Oil Jan 27" -> "T1/27".
  /// Trả null khi tên không chứa tháng/năm (để caller chỉ ghi "HĐTL").
  static String? parseContractMonth(String? shortName) {
    if (shortName == null) return null;
    const Map<String, int> months = <String, int>{
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final RegExpMatch? m = RegExp(
      r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{2})\b',
    ).firstMatch(shortName);
    if (m == null) return null;
    final int? month = months[m.group(1)];
    if (month == null) return null;
    return 'T$month/${m.group(2)}';
  }

  /// Parse JSON Yahoo chart (đã decode) cho CL=F range=1d interval=1m.
  /// Trả null khi thiếu dữ liệu (caller dùng fallback CNBC). Không bao giờ
  /// throw: lỗi cấu trúc nào cũng trả null.
  static YahooOilQuote? parseYahooOilQuote(Map<String, dynamic> decoded) {
    try {
      final List<RawCandle> candles =
          CandleFetcher.parseYahooChart(decoded, aggregateH4: false);
      if (candles.isEmpty) return null;
      final RawCandle last = candles.last;
      double? chgPct;
      String? contractLabel;
      final Map<String, dynamic>? chart = asMap(decoded['chart']);
      final List<dynamic>? result =
          chart == null ? null : asList(chart['result']);
      if (result != null &&
          result.isNotEmpty &&
          result.first is Map<String, dynamic>) {
        final Map<String, dynamic>? meta =
            asMap((result.first as Map<String, dynamic>)['meta']);
        final double? prevClose =
            meta == null ? null : numD(meta['chartPreviousClose']);
        if (prevClose != null && prevClose != 0) {
          chgPct = (last.c - prevClose) / prevClose * 100;
        }
        // Tháng hợp đồng từ tên Yahoo, VD "Crude Oil Dec 26" -> "T12/26".
        final Object? shortName = meta == null ? null : meta['shortName'];
        contractLabel = parseContractMonth(
          shortName is String ? shortName : null,
        );
      }
      return YahooOilQuote(
        price: last.c,
        quoteTime: DateTime.fromMillisecondsSinceEpoch(last.t),
        chgPct: chgPct,
        contractLabel: contractLabel,
      );
    } catch (_) {
      return null;
    }
  }

  /// Lấy giá thật mỗi 2 giây, 5 nguồn v1.1.0. Nguồn nào lỗi thì giữ giá cũ,
  /// không bao giờ bịa giá. Đây là HTTP polling 2 giây, KHÔNG phải
  /// WebSocket 1 giây.
  Future<void> _fetchLivePrices() async {
    if (offline || _fetchingLive) return;
    _fetchingLive = true;
    try {
      // XAUUSD — gold-api.com
      final double? xau = await _getJsonPrice(
        'https://api.gold-api.com/price/XAU',
        pick: (j) => numD(j['price']),
      );
      if (xau != null) {
        _applyLivePrice('XAUUSD', xau, 'gold-api.com');
      }

      // BTCUSD — Binance (giá)
      final double? btc = await _getJsonPrice(
        'https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT',
        pick: (j) => double.tryParse('${j['price']}'),
      );
      if (btc != null) _applyLivePrice('BTCUSD', btc, 'Binance');
      // % 24h BTC/PAXG (chỉ lấy %, không lấy giá PAXG làm giá vàng)
      final List<dynamic>? hr = await _fetchBinance24h();
      if (hr != null) {
        for (final Object? row in hr) {
          if (row is Map<String, dynamic>) {
            final String sym = '${row['symbol']}';
            final double? pct =
                double.tryParse('${row['priceChangePercent']}');
            if (pct != null) {
              if (sym == 'BTCUSDT') chg24h['BTCUSD'] = pct;
              if (sym == 'PAXGUSDT') chg24h['XAUUSD'] = pct;
            }
          }
        }
      }

      // Kraken ticker forex (mid + % từ open)
      final Map<String, dynamic>? kr = await _getJsonMap(
        'https://api.kraken.com/0/public/Ticker?pair=EURUSD,GBPUSD,USDJPY,USDCAD,USDCHF',
      );
      Map<String, double>? krakenMid;
      Map<String, double>? krakenChg;
      if (kr != null) {
        final Object? result = kr['result'];
        if (result is Map<String, dynamic>) {
          krakenMid = <String, double>{};
          krakenChg = <String, double>{};
          for (final MapEntry<String, (double, double?)> e
              in parseKrakenTicker(result).entries) {
            krakenMid[e.key] = e.value.$1;
            if (e.value.$2 != null) krakenChg[e.key] = e.value.$2!;
          }
        }
      }

      // Neo er-api (chỉ lấy khi neo cũ > 5 phút hoặc chưa có neo)
      Map<String, dynamic>? fxRates;
      final bool needAnchor = _fxAnchorAt == null ||
          DateTime.now().difference(_fxAnchorAt!).inMinutes >= 5;
      if (needAnchor) {
        final Map<String, dynamic>? fx = await _getJsonMap(
          'https://open.er-api.com/v6/latest/USD',
        );
        if (fx != null && fx['rates'] is Map<String, dynamic>) {
          fxRates = fx['rates'] as Map<String, dynamic>;
        }
      }

      if (krakenMid != null) {
        double? midFor(String base, String quote) {
          for (final MapEntry<String, double> e in krakenMid!.entries) {
            if (e.key.contains(base) && e.key.contains(quote)) return e.value;
          }
          return null;
        }

        double? chgFor(String base, String quote) {
          if (krakenChg == null) return null;
          for (final MapEntry<String, double> e in krakenChg.entries) {
            if (e.key.contains(base) && e.key.contains(quote)) return e.value;
          }
          return null;
        }

        final Map<String, (String, String)> pairs = <String, (String, String)>{
          'EURUSD': ('EUR', 'USD'),
          'GBPUSD': ('GBP', 'USD'),
          'USDJPY': ('USD', 'JPY'),
          'USDCAD': ('USD', 'CAD'),
          'USDCHF': ('USD', 'CHF'),
        };
        for (final MapEntry<String, (String, String)> e in pairs.entries) {
          final double? mid = midFor(e.value.$1, e.value.$2);
          if (mid != null) {
            _applyFx(e.key, mid, chgFor(e.value.$1, e.value.$2), fxRates);
          }
        }
      } else if (fxRates != null) {
        // Không có Kraken nhưng có neo mới: dùng thẳng giá neo.
        for (final String code in <String>[
          'EURUSD',
          'GBPUSD',
          'USDJPY',
          'USDCAD',
          'USDCHF',
        ]) {
          final String cur = _fxCurrency(code);
          final double? rate = numD(fxRates[cur]);
          if (rate == null || rate <= 0) continue;
          final bool inv = code == 'EURUSD' || code == 'GBPUSD';
          _applyLivePrice(
            code,
            inv ? 1 / rate : rate,
            'open.er-api.com',
          );
        }
      }

      // USOIL — Yahoo Finance CL=F (giá đóng nến 1 phút mới nhất),
      // CNBC @CL.1 chỉ làm dự phòng. Yahoo là cùng nguồn với nến dầu
      // (CL=F) nên giá live khớp nến, và nến 1 phút có timestamp để phát
      // hiện giá cũ. LƯU Ý (kiểm chứng 18/11): giá này là HĐTL WTI tháng
      // gần nhất (T12/26, đáo hạn 20/11) — Exness USOIL 83,7 lúc 10:31
      // thấp hơn ~1,5 USD KHÔNG phải vì CNBC/Yahoo chậm (cả hai đều
      // đúng giá HĐTL ~85,2: Yahoo CL=F 85,24 lúc 03:19 UTC), mà vì
      // Exness bám giá spot/CFD hoặc đã roll sang hợp đồng T1/27
      // (ngày roll USOIL.f của Exness là 18/11; giá spot/perpetual lúc
      // đó ~84,2-84,35, nằm giữa hai tháng HĐTL). Không có nguồn JSON
      // miễn phí ổn định nào cho giá spot dầu, nên app giữ nguồn HĐTL
      // và ghi rõ tháng hợp đồng + chú thích để user không nhầm.
      final Map<String, dynamic>? oilJson = await _getJsonMap(
        'https://query1.finance.yahoo.com/v8/finance/chart/CL=F?range=1d&interval=1m',
        headers: <String, String>{
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) TradeSignalAI/1.2.2',
        },
      );
      final YahooOilQuote? oilQuote =
          oilJson == null ? null : parseYahooOilQuote(oilJson);
      if (oilQuote != null) {
        // Nhãn ghi rõ đây là giá HĐTL tháng gần nhất + tháng hợp đồng
        // (VD "Yahoo (CL=F) · HĐTL T12/26"), để user không nhầm với giá
        // spot/CFD trên Exness — hai bên có thể lệch 1-2 USD, nhất là
        // quanh ngày roll hợp đồng (T12/26 đáo hạn 20/11/2026).
        final String monthLabel = oilQuote.contractLabel == null
            ? 'HĐTL'
            : 'HĐTL ${oilQuote.contractLabel}';
        _applyLivePrice(
          'USOIL',
          oilQuote.price,
          'Yahoo (CL=F) · $monthLabel',
          chgPct: oilQuote.chgPct,
          src: oilQuote.quoteTime,
        );
      } else {
        // Dự phòng CNBC khi Yahoo lỗi (không có timestamp nên không kiểm
        // tra được độ cũ — nhãn nguồn ghi rõ để user biết).
        final double? oil = await _getJsonPrice(
          'https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol?symbols=@CL.1&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json',
          pick: (j) {
            try {
              final Object? fq = j['FormattedQuoteResult'];
              if (fq is Map<String, dynamic>) {
                final Object? list = fq['FormattedQuote'];
                if (list is List && list.isNotEmpty) {
                  final Object? first = list.first;
                  if (first is Map<String, dynamic>) {
                    final double? last =
                        double.tryParse('${first['last']}');
                    final double? change =
                        double.tryParse('${first['change']}');
                    if (last != null &&
                        change != null &&
                        last - change != 0) {
                      chg24h['USOIL'] = change / (last - change) * 100;
                    }
                    return last;
                  }
                }
              }
            } catch (_) {}
            return null;
          },
        );
        if (oil != null) {
          _applyLivePrice('USOIL', oil, 'CNBC (WTI) · HĐTL');
        }
      }
    } catch (e) {
      // Phong thu: bat ky loi parse/mang nao trong vong gia live cung
      // khong duoc crash app — giu gia cu, UI hien "DU LIEU CU".
      // (Truoc day try/finally khong co catch nen loi ep kieu o day
      // thoat ra zone -> man hinh "App gap loi khi mo".)
      debugPrint('TradeSignal: _fetchLivePrices loi: $e');
    } finally {
      _fetchingLive = false;
      _safeNotify();
    }
  }

  Future<List<dynamic>?> _fetchBinance24h() async {
    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final HttpClientRequest req = await client
          .getUrl(Uri.parse(
            'https://data-api.binance.vision/api/v3/ticker/24hr?symbols=%5B%22BTCUSDT%22%2C%22PAXGUSDT%22%5D',
          ))
          .timeout(const Duration(seconds: 5));
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final String body =
          await resp.transform(utf8.decoder).join().timeout(
                const Duration(seconds: 5),
              );
      final Object? decoded = jsonDecode(body);
      if (decoded is List) return decoded;
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  // --- Sinh dữ liệu mock (fallback khi chưa có nến thật) ----------------------
  double _stepPct(String code) {
    if (code == 'BTCUSD') return 0.0012;
    if (code == 'USOIL') return 0.001;
    return 0.0003;
  }

  List<Candle> _generateM1(SymbolInfo s) {
    final Random rand = Random(s.code.hashCode & 0x7fffffff);
    final DateTime now = DateTime.now();
    final DateTime start =
        DateTime(now.year, now.month, now.day, now.hour, now.minute)
            .subtract(const Duration(minutes: 300));
    final double step = _stepPct(s.code);
    double price = s.base;
    final List<Candle> out = <Candle>[];
    for (int i = 0; i < 300; i++) {
      final double o = price;
      final double drift = (rand.nextDouble() - 0.5) * 2 * step;
      double c = o * (1 + drift);
      if (c <= 0) c = o;
      final double h = max(o, c) * (1 + rand.nextDouble() * step * 0.5);
      final double l = min(o, c) * (1 - rand.nextDouble() * step * 0.5);
      final double vol = 10 + rand.nextDouble() * 90;
      out.add(
        Candle(o, h, l, c, vol, start.millisecondsSinceEpoch + i * 60000),
      );
      price = c;
    }
    return out;
  }

  List<Candle> _aggregate(List<Candle> m1, int minutes) {
    if (minutes <= 1) return List<Candle>.from(m1);
    final int bucketMs = minutes * 60000;
    final List<Candle> out = <Candle>[];
    int? bucketStart;
    double o = 0;
    double h = 0;
    double l = 0;
    double c = 0;
    double vol = 0;
    for (final Candle candle in m1) {
      final int b = (candle.time ~/ bucketMs) * bucketMs;
      if (bucketStart == null || b != bucketStart) {
        if (bucketStart != null) {
          out.add(Candle(o, h, l, c, vol, bucketStart));
        }
        bucketStart = b;
        o = candle.o;
        h = candle.h;
        l = candle.l;
        c = candle.c;
        vol = candle.vol;
      } else {
        if (candle.h > h) h = candle.h;
        if (candle.l < l) l = candle.l;
        c = candle.c;
        vol += candle.vol;
      }
    }
    if (bucketStart != null) {
      out.add(Candle(o, h, l, c, vol, bucketStart));
    }
    return out;
  }

  // --- Chọn cặp / khung / offline / theo dõi ----------------------------------
  void selectSymbol(String code) {
    if (symbols.any((SymbolInfo s) => s.code == code)) {
      selectedSymbol = code;
      notifyListeners();
    }
  }

  void setTimeframe(String tf) {
    timeframe = tf;
    notifyListeners();
  }

  void setOffline(bool value) {
    offline = value;
    notifyListeners();
  }

  void toggleAllowedSymbol(String code) {
    if (allowedSymbols.contains(code)) {
      allowedSymbols.remove(code);
    } else {
      allowedSymbols.add(code);
    }
    notifyListeners();
  }

  void toggleFollow(String code) {
    if (followed.contains(code)) {
      followed.remove(code);
    } else {
      followed.add(code);
    }
    notifyListeners();
  }

  // --- Tick 1 giây: chỉ cập nhật nến mock khi đang fallback + nhịp nền ------
  // KHÔNG tính lại tín hiệu ở đây (tín hiệu tĩnh chỉ theo nhịp 30 giây).
  void tick() {
    _tickCount++;
    try {
      _tickUnsafe();
    } catch (e) {
      // Phong thu: loi trong nhip 1 giay khong duoc crash app.
      debugPrint('TradeSignal: tick loi: $e');
    }
    _safeNotify();
  }

  void _tickUnsafe() {
    if (!offline) {
      for (final SymbolInfo s in symbols) {
        if (hasRealCandles(s.code, 'M5')) continue; // nến thật: giá live
        // đã patch nến thật, không random-walk mock nữa.
        final DateTime? lu = liveUpdated[s.code];
        if (liveOk[s.code] == true &&
            lu != null &&
            DateTime.now().difference(lu).inSeconds < 10) {
          continue;
        }
        final List<Candle>? m1 = _m1[s.code];
        if (m1 == null || m1.isEmpty) continue;
        final Candle last = m1.last;
        final double step = _stepPct(s.code);
        final double drift = (_tickRand.nextDouble() - 0.5) * 2 * step;
        double nc = last.c * (1 + drift);
        if (nc <= 0) nc = last.c;
        final double nh = max(last.h, nc);
        final double nl = min(last.l, nc);
        m1[m1.length - 1] = Candle(
          last.o,
          nh,
          nl,
          nc,
          last.vol + _tickRand.nextDouble() * 5,
          last.time,
        );
        prices[s.code] = nc;
      }
      if (_tickCount % 3 == 0) _checkHistoryOutcomes();
      if (_tickCount % 5 == 0) _checkAlerts();
      if (_tickCount % 30 == 0) _checkStaticSignals();
    }
  }

  // --- Tín hiệu tĩnh (nhịp 30 giây, chỉ chốt khi có nến H1 mới đóng) ---------
  void _checkStaticSignals({bool force = false}) {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    for (final SymbolInfo s in symbols) {
      final String sym = s.code;
      final Map<String, List<RawCandle>> closed = closedByTf(sym);
      final List<RawCandle> m15 = closed['M15'] ?? const <RawCandle>[];
      // POC/VAH/VAL + Delta từ Volume Profile M15 (phục vụ vpCore).
      double? poc;
      double? vah;
      double? val;
      double step = 0;
      double? deltaPct;
      if (m15.isNotEmpty) {
        final ({double? poc, double? vah, double? val, double step}) lv =
            vpLevels(_toEngineCandles(m15));
        poc = lv.poc;
        vah = lv.vah;
        val = lv.val;
        step = lv.step;
        final VpScanResult? scan = vpScan[sym];
        deltaPct = scan?.deltaPct;
      }
      final StaticSignal? prev = staticSignals[sym];
      final StaticSignal? fresh = computeStaticSignal(
        symbol: sym,
        closedByTf: closed,
        livePrice: prices[sym],
        strategy: strategy,
        ind: indParams,
        previous: prev,
        nowMs: nowMs,
        force: force,
        poc: poc,
        vah: vah,
        val: val,
        step: step,
        deltaPct: deltaPct,
      );
      if (fresh == null) continue; // chưa đủ nến H1 — UI hiện "ĐANG TẢI"
      if (identical(fresh, prev)) continue;
      // Tín hiệu đổi (closedAt mới hoặc force): ghi hủy sớm nếu hướng đổi.
      if (prev != null &&
          prev.action != fresh.action &&
          (prev.action == 'BUY' || prev.action == 'SELL')) {
        final String reason = force
            ? 'Đổi chiến lược/thông số — tính lại, hủy lệnh cũ'
            : fresh.action == 'WAIT'
                ? 'Mất điều kiện (về WAIT) — hủy lệnh sớm'
                : 'Đảo chiều sang ${fresh.action} — hủy lệnh sớm';
        final Invalidation? inv =
            makeInvalidation(prev, prices[sym], reason);
        if (inv != null) lastInvalidations[sym] = inv;
        history.closeReversal(
          sym,
          prices[sym] ?? prev.entry,
          nowMs,
          reason,
        );
      }
      staticSignals[sym] = fresh;
      changed = true;
      if (fresh.action == 'BUY' || fresh.action == 'SELL') {
        final Map<String, dynamic>? levelsMap = fresh.levels == null
            ? null
            : <String, dynamic>{
                'inv': fresh.levels!.inv,
                't1': fresh.levels!.t1,
                't2': fresh.levels!.t2,
                't3': fresh.levels!.t3,
                't4': fresh.levels!.t4,
                'entry': fresh.levels!.entry,
              };
        history.recordOpen(
          symbol: sym,
          action: fresh.action,
          entry: fresh.entry,
          sl: fresh.sl,
          tp: fresh.tp,
          atr: fresh.atr,
          startAt: fresh.closedAt,
          strategy: strategy.name,
          conf: fresh.conf.toDouble(),
          rr: fresh.rr,
          levels: levelsMap,
          openPrice: prices[sym],
          livePrice: prices[sym],
        );
        // TierTracker cho lệnh mới mở.
        if (fresh.levels != null) {
          _tierTrackers[sym] = TierTracker(
            levels: fresh.levels!,
            action: fresh.action,
            startAt: fresh.closedAt,
          );
        }
        maybeAutoTradeFor(fresh);
      }
    }
    if (changed) notifyListeners();
  }

  // --- Cache Trend / Price Action / mẫu hình theo (symbol, closedAt) ---------
  // Ghi rõ: cache key = thời gian nến đóng cuối của khung liên quan + hash
  // thông số chỉ báo; nến chưa đóng nến mới thì trả kết quả cũ, không tính lại.
  String _closedKey(String sym) {
    final StringBuffer b = StringBuffer();
    for (final String tf in _allTfs) {
      final List<RawCandle> cs = cache.closed(sym, tf);
      b.write(cs.isEmpty ? '0' : cs.last.t);
      b.write('|');
    }
    b.write(indParams.hashCode);
    return b.toString();
  }

  Map<String, TrendInfo> trendsFor(String sym) {
    final String key = _closedKey(sym);
    if (_trendCacheKey[sym] == key && _trendCache[sym] != null) {
      return _trendCache[sym]!;
    }
    final Map<String, List<RawCandle>> closed = closedByTf(sym);
    final Map<String, TrendInfo> out = <String, TrendInfo>{};
    for (final String tf in _allTfs) {
      out[tf] = trendForTf(closed[tf] ?? const <RawCandle>[], indParams);
    }
    _trendCacheKey[sym] = key;
    _trendCache[sym] = out;
    return out;
  }

  PaResult paFor(String sym) {
    final Map<String, List<RawCandle>> closed = closedByTf(sym);
    final List<RawCandle> m15 = closed['M15'] ?? const <RawCandle>[];
    final String key =
        '${m15.isEmpty ? 0 : m15.last.t}|${indParams.hashCode}';
    if (_paCacheKey[sym] == key && _paCache[sym] != null) {
      return _paCache[sym]!;
    }
    final PaResult pa = computePriceAction(
      m15: m15,
      m5: closed['M5'] ?? const <RawCandle>[],
      h1: closed['H1'] ?? const <RawCandle>[],
      ind: indParams,
      livePrice: prices[sym],
    );
    _paCacheKey[sym] = key;
    _paCache[sym] = pa;
    return pa;
  }

  GaugeData gaugeFor(String sym) => gaugeFromTrends(trendsFor(sym));

  List<PatternStat> patternsFor(String sym, String tf) {
    final List<RawCandle> closed = cache.closed(sym, tf);
    final String key = '$sym|$tf|${closed.isEmpty ? 0 : closed.last.t}';
    if (_patCacheKey[key] == key && _patCache[key] != null) {
      return _patCache[key]!;
    }
    final List<PatternStat> stats = countPatterns(closed, lookback: 200);
    _patCacheKey[key] = key;
    _patCache[key] = stats;
    return stats;
  }

  // --- VolumeB/S quét 8 cặp (cache theo thời gian nến M15 đóng cuối) ---------
  void _checkVpScan() {
    bool changed = false;
    for (final SymbolInfo s in symbols) {
      final String sym = s.code;
      final List<RawCandle> m15 = cache.closed(sym, 'M15');
      final List<RawCandle> h1 = cache.closed(sym, 'H1');
      if (m15.isEmpty || h1.isEmpty) continue;
      final int key = m15.last.t;
      if (_vpScanKey[sym] == key && vpScan[sym] != null) continue;
      final VpScanResult r = vpScanFor(
        m15: _toEngineCandles(m15),
        h1: _toEngineCandles(h1),
        price: priceOf(sym),
      );
      r.symbol = sym;
      vpScan[sym] = r;
      _vpScanKey[sym] = key;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // --- Lịch sử: đóng TP/SL mỗi 3 giây + cập nhật thang tầng ------------------
  void _checkHistoryOutcomes() {
    history.checkOutcomes(prices, ind.pipSize);
    _checkDemoTrades();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final HistEntry e in List<HistEntry>.of(history.entries)) {
      if (e.status != 'open' || e.levels == null) continue;
      final TierTracker? tr = _tierTrackers[e.symbol];
      if (tr == null) continue;
      tr.checkCandles(
        cache.seriesOrNull(e.symbol, 'M5') ?? const <RawCandle>[],
        cache.seriesOrNull(e.symbol, 'M15') ?? const <RawCandle>[],
        prices[e.symbol],
        nowMs,
      );
      final Map<String, dynamic> tiersMap = <String, dynamic>{};
      for (final MapEntry<String, TierStatus> t in tr.tiers.entries) {
        tiersMap[t.key] = <String, dynamic>{
          'hit': t.value.hit,
          'at': t.value.at,
          'price': t.value.price,
        };
      }
      final bool? invHit = tr.tiers['Inv']?.hit;
      history.updateTiers(e.symbol, tiersMap, invHit);
    }
  }

  /// Trạng thái tầng (đã chạm/chưa) cho 1 cặp — UI thang TP dùng.
  Map<String, TierStatus>? tierStatusFor(String sym) =>
      _tierTrackers[sym]?.tiers;

  String tierNoteFor(String sym, String key) {
    final TierTracker? tr = _tierTrackers[sym];
    if (tr == null) return '';
    return tr.tierNote(key, prices[sym], ind.pipSize(sym));
  }

  // --- Cảnh báo Xung/TURN (nhịp 5 giây, đủ 5 khung mới kiểm tra) ------------
  void _checkAlerts() {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final SymbolInfo s in symbols) {
      final Map<String, TrendInfo> tr = trendsFor(s.code);
      bool enough = true;
      final Map<String, String> dirs = <String, String>{};
      for (final String tf in _allTfs) {
        final TrendInfo? t = tr[tf];
        if (t == null || !t.enough) {
          enough = false;
          break;
        }
        dirs[tf] = t.dir;
      }
      if (!enough) continue;
      alerts.check(s.code, dirs, nowMs);
    }
  }

  // --- Rule Engine (JSON của user) -------------------------------------------
  String evaluateRule(String jsonText, String symbol) {
    try {
      final Object? decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, Object?>) {
        ruleResult = 'Lỗi: JSON phải là một object {...}';
        notifyListeners();
        return ruleResult;
      }
      for (final String key in <String>[
        'rsi_lt',
        'rsi_gt',
        'close_gt_ema',
        'close_lt_ema',
      ]) {
        if (decoded.containsKey(key) && decoded[key] is! num) {
          ruleResult = 'Lỗi: "$key" phải là số';
          notifyListeners();
          return ruleResult;
        }
      }
      for (final String key in <String>[
        'ema20_gt_ema50',
        'ema20_lt_ema50',
      ]) {
        if (decoded.containsKey(key) && decoded[key] is! bool) {
          ruleResult = 'Lỗi: "$key" phải là true/false';
          notifyListeners();
          return ruleResult;
        }
      }

      ruleJson = jsonText;
      final List<Candle> m15 = candlesFor(symbol, 'M15');
      final IndicatorSet indSet = computeIndicators(m15, params: indParams);
      final List<double> closes = m15.map((Candle c) => c.c).toList();
      final double lastClose =
          closes.isNotEmpty ? closes.last : priceOf(symbol);
      final double rsiVal = _lastValue(indSet.rsi) ?? 50;
      final double? e20 = _lastValue(indSet.ema20);
      final double? e50 = _lastValue(indSet.ema50);
      final double? e200 = _lastValue(indSet.ema200);

      double? emaByPeriod(int p) {
        if (p == 50) return e50;
        if (p == 200) return e200;
        return e20;
      }

      bool allTrue = true;
      bool hasBullish = false;
      bool hasBearish = false;

      if (decoded.containsKey('rsi_lt')) {
        hasBullish = true;
        final double? lt = numD(decoded['rsi_lt']);
        if (lt != null && !(rsiVal < lt)) {
          allTrue = false;
        }
      }
      if (decoded.containsKey('rsi_gt')) {
        hasBearish = true;
        final double? gt = numD(decoded['rsi_gt']);
        if (gt != null && !(rsiVal > gt)) {
          allTrue = false;
        }
      }
      if (decoded.containsKey('close_gt_ema')) {
        hasBullish = true;
        final int? p = numI(decoded['close_gt_ema']);
        final double? e = p == null ? null : emaByPeriod(p);
        if (e == null || !(lastClose > e)) allTrue = false;
      }
      if (decoded.containsKey('close_lt_ema')) {
        hasBearish = true;
        final int? p = numI(decoded['close_lt_ema']);
        final double? e = p == null ? null : emaByPeriod(p);
        if (e == null || !(lastClose < e)) allTrue = false;
      }
      if (decoded['ema20_gt_ema50'] == true) {
        hasBullish = true;
        if (e20 == null || e50 == null || !(e20 > e50)) allTrue = false;
      }
      if (decoded['ema20_lt_ema50'] == true) {
        hasBearish = true;
        if (e20 == null || e50 == null || !(e20 < e50)) allTrue = false;
      }

      if (!allTrue) {
        ruleResult = 'WAIT';
        notifyListeners();
        return ruleResult;
      }
      if (decoded.containsKey('action')) {
        final String a = decoded['action'].toString().toUpperCase();
        ruleResult = (a == 'BUY' || a == 'SELL') ? a : 'BUY';
      } else if (hasBearish && !hasBullish) {
        ruleResult = 'SELL';
      } else {
        ruleResult = 'BUY';
      }
      notifyListeners();
      return ruleResult;
    } catch (e) {
      ruleResult = 'Lỗi: $e';
      notifyListeners();
      return ruleResult;
    }
  }

  // --- Exness (chỉ kết nối hiển thị, KHÔNG lưu key/secret) -------------------
  void connectExness(String key, String secret) {
    if (key.isNotEmpty && secret.isNotEmpty) {
      exnessConnected = true;
      final String tail =
          key.length >= 4 ? key.substring(key.length - 4) : key;
      exnessAccount = 'DEMO ••••$tail';
    }
    notifyListeners();
  }

  void disconnectExness() {
    exnessConnected = false;
    exnessAccount = '';
    autoTrade = false;
    notifyListeners();
  }

  // --- Auto-trade DEMO (mô phỏng, nối tín hiệu tĩnh mới) ----------------------
  void enableAutoTrade() {
    autoTrade = true;
    demoStarted ??= DateTime.now();
    demoEnd ??= demoStarted!.add(const Duration(hours: 24));
    notifyListeners();
  }

  void disableAutoTrade() {
    autoTrade = false;
    notifyListeners();
  }

  bool get demoExpired =>
      demoEnd != null && DateTime.now().isAfter(demoEnd!);

  String get demoRemainingLabel {
    if (demoEnd == null) return 'DEMO · chưa bắt đầu';
    final Duration d = demoEnd!.difference(DateTime.now());
    if (d.isNegative) return 'DEMO đã hết 24h · LIVE khóa';
    return 'DEMO · còn ${d.inHours} giờ ${d.inMinutes % 60} phút · LIVE khóa';
  }

  /// Có đang trong giờ giao dịch (giờ địa phương, qua đêm được: from > to
  /// thì h >= from || h <= to). Web §17.3 mặc định 00:00 → 23:59.
  bool get inTradeHours {
    int toMin(String s) {
      final List<String> p = s.split(':');
      final int h = int.tryParse(p.isNotEmpty ? p[0] : '0') ?? 0;
      final int m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
      return h * 60 + m;
    }

    final DateTime now = DateTime.now();
    final int cur = now.hour * 60 + now.minute;
    final int from = toMin(tradeStart);
    final int to = toMin(tradeEnd);
    if (from <= to) return cur >= from && cur <= to;
    return cur >= from || cur <= to;
  }

  /// Mở lệnh demo từ 1 tín hiệu tĩnh: tại giá live, SL/TP từ tín hiệu tĩnh,
  /// chống mở trùng bằng key sym|action|closedAt.
  void maybeAutoTradeFor(StaticSignal sig) {
    if (!autoTrade) return;
    if (!exnessConnected) return;
    if (demoExpired) return;
    if (!inTradeHours) return;
    if (sig.action != 'BUY' && sig.action != 'SELL') return;
    if (sig.conf < minConfidence) return;
    if (sig.sl == null || sig.tp == null) return;
    if (!allowedSymbols.contains(sig.symbol)) return;
    if (openTrades.length >= maxOpen) return;
    if (openTrades.any((Trade t) => t.symbol == sig.symbol)) return;
    final String key = '${sig.symbol}|${sig.action}|${sig.closedAt}';
    if (tradedKeys.contains(key)) return;
    tradedKeys.add(key);
    openTrades.add(
      Trade(
        id: 'T${DateTime.now().millisecondsSinceEpoch}_${sig.symbol}',
        symbol: sig.symbol,
        action: sig.action,
        entry: priceOf(sig.symbol),
        sl: sig.sl!,
        tp: sig.tp!,
        lot: useFixedLot ? fixedLot : fixedLot * riskPct,
        opened: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  /// Giữ tên cũ cho code ngoài: mở lệnh demo từ tín hiệu tĩnh hiện tại.
  void maybeAutoTrade() {
    for (final StaticSignal? sig in staticSignals.values) {
      if (sig != null) maybeAutoTradeFor(sig);
    }
  }

  /// Đóng lệnh demo chạm SL/TP theo giá live (nhịp 3 giây, gọi trong
  /// _checkHistoryOutcomes qua _checkDemoTrades).
  void _checkDemoTrades() {
    if (openTrades.isEmpty) return;
    bool changed = false;
    for (final Trade t in List<Trade>.of(openTrades)) {
      final double p = priceOf(t.symbol);
      bool hitTp = false;
      bool hitSl = false;
      if (t.action == 'BUY') {
        hitTp = p >= t.tp;
        hitSl = p <= t.sl;
      } else {
        hitTp = p <= t.tp;
        hitSl = p >= t.sl;
      }
      if (hitTp || hitSl) {
        openTrades.remove(t);
        t.closePrice = hitTp ? t.tp : t.sl;
        final double dir = t.action == 'BUY' ? 1 : -1;
        t.pnl = (t.closePrice! - t.entry) * dir * t.lot * contractSize(t.symbol);
        t.status = 'closed';
        dailyPnl += t.pnl ?? 0;
        closedTrades.add(t);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _settleTrade(Trade t) {
    final double p = priceOf(t.symbol);
    final double dir = t.action == 'BUY' ? 1 : -1;
    t.closePrice = p;
    t.pnl = (p - t.entry) * dir * t.lot * contractSize(t.symbol);
    t.status = 'closed';
    dailyPnl += t.pnl ?? 0;
  }

  void closeTrade(Trade t) {
    if (!openTrades.remove(t)) return;
    _settleTrade(t);
    closedTrades.add(t);
    notifyListeners();
  }

  void panicStop() {
    final List<Trade> copy = List<Trade>.from(openTrades);
    for (final Trade t in copy) {
      openTrades.remove(t);
      _settleTrade(t);
      closedTrades.add(t);
    }
    autoTrade = false;
    notifyListeners();
  }

  // --- Thống kê thật từ SessionHistory (null = chưa có lệnh đóng) -------------
  double? winRate(String symbol) {
    final List<HistEntry> closed = history.entries
        .where((HistEntry e) =>
            e.symbol == symbol && e.status == 'closed')
        .toList();
    if (closed.isEmpty) return null;
    final int wins = closed
        .where((HistEntry e) => e.realizedR != null && e.realizedR! >= 0)
        .length;
    return wins / closed.length * 100;
  }

  double? profitFactor(String symbol) {
    final List<HistEntry> closed = history.entries
        .where((HistEntry e) =>
            e.symbol == symbol && e.status == 'closed')
        .toList();
    if (closed.isEmpty) return null;
    double sumWin = 0;
    double sumLoss = 0;
    for (final HistEntry e in closed) {
      final double r = e.realizedR ?? 0;
      if (r >= 0) {
        sumWin += r;
      } else {
        sumLoss += r.abs();
      }
    }
    if (sumWin <= 0) return null;
    if (sumLoss <= 0) return double.infinity;
    return sumWin / sumLoss;
  }

  double? avgRr(String symbol) {
    final List<HistEntry> closed = history.entries
        .where((HistEntry e) =>
            e.symbol == symbol && e.status == 'closed')
        .toList();
    if (closed.isEmpty) return null;
    double sum = 0;
    int n = 0;
    for (final HistEntry e in closed) {
      final double risk = (e.entry - (e.sl ?? e.entry)).abs();
      final double reward = ((e.tp ?? e.entry) - e.entry).abs();
      if (risk > 0) {
        sum += reward / risk;
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }

  Performance performanceFor(String symbol) => Performance(
        winRate: winRate(symbol),
        profitFactor: profitFactor(symbol),
        avgRr: avgRr(symbol),
      );

  // --- Định dạng ---------------------------------------------------------------
  String fmt(double v, String symbol) {
    return v.toStringAsFixed(symbolByCode(symbol).decimals);
  }

  String fmtPct(double v) {
    final String s = v.abs().toStringAsFixed(2).replaceAll('.', ',');
    return '${v > 0 ? '+' : v < 0 ? '−' : ''}$s%';
  }
}
