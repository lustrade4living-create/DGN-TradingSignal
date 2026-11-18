// signal_core.dart — Lõi tín hiệu tĩnh TradeSignal AI (port từ bản web, spec §3–§5, §8.1, §11).
//
// Thuần Dart, không plugin. Làm việc trên RawCandle (market_data.dart) và
// IndicatorParams (indicators.dart). KHÔNG import engine.dart.
//
// Nguyên tắc giữ từ web:
//  - Entry = giá đóng nến H1 đã đóng gần nhất; SL/TP chốt cứng lúc nến H1 đóng,
//    KHÔNG đổi theo giá live.
//  - Chỉ tính lại khi có nến H1 mới đóng (closedAt khác) hoặc force = true.
//  - % tin cậy = 50% tín hiệu gốc + 25% Trend đa khung + 25% Price Action;
//    WAIT trần 62%, clamp 5..97.
//  - Mọi công thức chỉ báo theo spec §13.2: EMA hạt giống SMA, RSI/ATR trung
//    bình đơn giản (không phải Wilder), MACD = EMA(macdF) − EMA(macdS).
import 'dart:math' as math;

import 'indicators.dart';
import 'market_data.dart';

// ---------------------------------------------------------------------------
// Chiến lược AI (§11)
// ---------------------------------------------------------------------------

enum AiStrategy { swing, volumebs, ai }

String strategyLabel(AiStrategy s) => switch (s) {
      AiStrategy.swing => 'Swing M15/H1 · xác nhận H4',
      AiStrategy.volumebs => 'VolumeB/S — TonyD Volume Profile',
      AiStrategy.ai => 'AI hợp nhất (Swing + VolumeB/S + MACD)',
    };

// ---------------------------------------------------------------------------
// Định dạng giờ VN (không dùng package intl)
// ---------------------------------------------------------------------------

String _two(int v) => v.toString().padLeft(2, '0');

/// 'DD/MM · HH:MM:SS' (giờ địa phương của máy — trên máy user là giờ VN).
String vnDateStr(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return '${_two(d.day)}/${_two(d.month)} · ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// 'HH:MM:SS' (giờ địa phương của máy).
String vnTimeStr(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// Format giá gọn: >= 100 → tối đa 2 số lẻ, còn lại tối đa 4 số lẻ,
/// cắt số 0 thừa ở cuối (3880.10 → '3880.1', 95.0 → '95').
String fmtPrice(double v) {
  final dec = v.abs() >= 100 ? 2 : 4;
  var s = v.toStringAsFixed(dec);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

// ---------------------------------------------------------------------------
// Chỉ báo nội bộ (theo spec §13.2 — tự tính trong file này để không phụ thuộc
// vào tên hàm của indicators.dart; chỉ dùng các trường của IndicatorParams)
// ---------------------------------------------------------------------------

/// EMA cuối của [values]; null nếu chưa đủ [period] giá trị.
/// Hạt giống = SMA của [period] giá đầu tiên, k = 2/(period+1).
double? _emaLast(List<double> values, int period) {
  if (period < 1 || values.length < period) return null;
  final k = 2 / (period + 1);
  var e = 0.0;
  for (var i = 0; i < period; i++) {
    e += values[i];
  }
  e /= period;
  for (var i = period; i < values.length; i++) {
    e = values[i] * k + e * (1 - k);
  }
  return e;
}

/// Toàn bộ chuỗi EMA (null ở các vị trí chưa đủ dữ liệu).
List<double?> _emaSeries(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period < 1 || values.length < period) return out;
  final k = 2 / (period + 1);
  var e = 0.0;
  for (var i = 0; i < period; i++) {
    e += values[i];
  }
  e /= period;
  out[period - 1] = e;
  for (var i = period; i < values.length; i++) {
    e = values[i] * k + e * (1 - k);
    out[i] = e;
  }
  return out;
}

/// RSI cuối (trung bình đơn giản, spec §13.2); null nếu chưa đủ dữ liệu.
double? _rsiLast(List<double> values, int period) {
  if (period < 1 || values.length < period + 1) return null;
  var gain = 0.0;
  var loss = 0.0;
  for (var i = values.length - period; i < values.length; i++) {
    final d = values[i] - values[i - 1];
    if (d > 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  if (loss == 0) return 100.0;
  final rs = (gain / period) / (loss / period);
  return 100 - 100 / (1 + rs);
}

/// ATR cuối (trung bình đơn giản của True Range, spec §13.2).
double? _atrLast(List<RawCandle> cs, int period) {
  if (period < 1 || cs.length < period + 1) return null;
  var sum = 0.0;
  for (var i = cs.length - period; i < cs.length; i++) {
    final c = cs[i];
    final prevC = cs[i - 1].c;
    final tr = math.max(
      c.h - c.l,
      math.max((c.h - prevC).abs(), (c.l - prevC).abs()),
    );
    sum += tr;
  }
  return sum / period;
}

/// MACD cuối (line, signal) theo IndicatorParams; null nếu chưa đủ nến.
/// Yêu cầu hiển thị của web: cần trên macdS + macdSig + 2 nến.
({double line, double signal})? _macdLast(
    List<RawCandle> cs, IndicatorParams ind) {
  final closes = cs.map((c) => c.c).toList();
  final fast = _emaSeries(closes, ind.macdF);
  final slow = _emaSeries(closes, ind.macdS);
  final lineVals = <double>[];
  for (var i = 0; i < closes.length; i++) {
    final f = fast[i];
    final s = slow[i];
    if (f != null && s != null) lineVals.add(f - s);
  }
  if (lineVals.length < ind.macdSig) return null;
  final sig = _emaLast(lineVals, ind.macdSig);
  if (sig == null) return null;
  return (line: lineVals.last, signal: sig);
}

/// Ichimoku H1 (spec §10.2); null nếu < 52 nến.
/// pos: 'above' (trên mây) / 'below' (dưới mây) / 'inside' (trong mây).
({double tenkan, double kijun, double senkouA, double senkouB, String pos})?
    _ichimoku(List<RawCandle> cs) {
  if (cs.length < 52) return null;
  double hl(int n) {
    var hi = double.negativeInfinity;
    var lo = double.infinity;
    for (var i = cs.length - n; i < cs.length; i++) {
      if (cs[i].h > hi) hi = cs[i].h;
      if (cs[i].l < lo) lo = cs[i].l;
    }
    return (hi + lo) / 2;
  }

  final tenkan = hl(9);
  final kijun = hl(26);
  final senkouA = (tenkan + kijun) / 2;
  final senkouB = hl(52);
  final last = cs.last.c;
  final top = math.max(senkouA, senkouB);
  final bot = math.min(senkouA, senkouB);
  final pos = last > top
      ? 'above'
      : last < bot
          ? 'below'
          : 'inside';
  return (
    tenkan: tenkan,
    kijun: kijun,
    senkouA: senkouA,
    senkouB: senkouB,
    pos: pos,
  );
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Tín hiệu tĩnh đã chốt theo nến H1 đóng.
class StaticSignal {
  String symbol;
  String action; // 'BUY' | 'SELL' | 'WAIT'
  double entry;
  double? sl;
  double? tp;
  double rr;
  double atr;
  int baseConf;
  int trendIndex;
  int paIndex;
  int conf;
  String bias; // 'bullish' | 'bearish'
  List<String> reasons;
  int closedAt; // thời điểm nến H1 đóng và chốt tín hiệu (ms)
  int trendAligned;
  int trendAvail;
  int paAligned;
  int paOpposed;
  int paTotal;
  OptimalEntry? optimal;
  LadderLevels? levels;
  String? invalidReason;

  StaticSignal({
    required this.symbol,
    required this.action,
    required this.entry,
    this.sl,
    this.tp,
    required this.rr,
    required this.atr,
    required this.baseConf,
    required this.trendIndex,
    required this.paIndex,
    required this.conf,
    required this.bias,
    required this.reasons,
    required this.closedAt,
    this.trendAligned = 0,
    this.trendAvail = 0,
    this.paAligned = 0,
    this.paOpposed = 0,
    this.paTotal = 0,
    this.optimal,
    this.levels,
    this.invalidReason,
  });
}

/// Trend 1 khung (§4.1). `enough` = false khi chưa đủ 55 nến đã đóng
/// (khi đó dir = 'flat', rsi9 = null — UI hiện "chưa đủ nến").
class TrendInfo {
  String dir; // 'up' | 'dn' | 'flat'
  double? rsi9;
  bool enough;

  TrendInfo({required this.dir, this.rsi9, required this.enough});
}

/// Điểm vào tối ưu (§5.3) — chỉ là điểm chờ vào tốt hơn, KHÔNG thay
/// Entry/SL/TP tĩnh.
class OptimalEntry {
  double price;
  double zoneLow;
  double zoneHigh;
  double rrOptimal;
  String label;
  String quality; // 'Chuẩn & đẹp' | 'Chuẩn — chờ thêm 1 xác nhận PA' | 'Chưa đẹp — chờ xác nhận'
  int stars; // 3 | 2 | 1
  bool isFallback;

  OptimalEntry({
    required this.price,
    required this.zoneLow,
    required this.zoneHigh,
    required this.rrOptimal,
    required this.label,
    required this.quality,
    required this.stars,
    required this.isFallback,
  });
}

/// Thang TP nhiều tầng (§8.1).
class LadderLevels {
  double inv;
  double t1;
  double t2;
  double t3;
  double t4;
  double entry;

  LadderLevels({
    required this.inv,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.t4,
    required this.entry,
  });
}

/// Bản ghi tín hiệu đã đóng (dùng cho giờ dừng thật trong sigStopInfo).
class HistClose {
  int exitAt;
  String reason; // 'Chạm TP' | 'Chạm SL' | 'Hủy sớm' (+ chi tiết)
  double exitPrice;

  HistClose({required this.exitAt, required this.reason, required this.exitPrice});
}

/// Thông tin lệnh cũ bị hủy sớm (§3.4).
class Invalidation {
  String symbol;
  String oldAction;
  double entry;
  double? sl;
  double exit;
  int exitAt;
  double pips;
  double pct;
  String reason;

  Invalidation({
    required this.symbol,
    required this.oldAction,
    required this.entry,
    this.sl,
    required this.exit,
    required this.exitAt,
    required this.pips,
    required this.pct,
    required this.reason,
  });
}

// ---------------------------------------------------------------------------
// Trend từng khung + điểm Trend đa khung (§4.1, §4.2)
// ---------------------------------------------------------------------------

/// Trend 1 khung từ nến đã đóng của chính khung đó; cần >= 55 nến.
TrendInfo trendForTf(List<RawCandle> closed, IndicatorParams ind) {
  if (closed.length < 55) {
    return TrendInfo(dir: 'flat', rsi9: null, enough: false);
  }
  final closes = closed.map((c) => c.c).toList();
  final e20 = _emaLast(closes, ind.emaFast);
  final e50 = _emaLast(closes, ind.emaSlow);
  final e34 = _emaLast(closes, ind.ema34);
  final rsi9 = _rsiLast(closes, ind.rsiChart);
  final last = closes.last;
  var score = 0;
  if (e20 != null && e50 != null) {
    if (e20 > e50) {
      score += 1;
    } else if (e20 < e50) {
      score -= 1;
    }
  }
  if (e34 != null) {
    if (last > e34) {
      score += 1;
    } else if (last < e34) {
      score -= 1;
    }
  }
  final dir = score >= 2
      ? 'up'
      : score <= -2
          ? 'dn'
          : 'flat';
  return TrendInfo(dir: dir, rsi9: rsi9, enough: true);
}

const Map<String, int> _trendWeights = {
  'M5': 10,
  'M15': 20,
  'H1': 30,
  'H4': 25,
  'D1': 15,
};

/// Điểm Trend đa khung (§4.2). Chỉ tính khung có enough.
/// index = round(50 + 50 * (wNet / wTot)), 0..100.
({int index, int aligned, int avail}) multiTrend(
    Map<String, TrendInfo> byTf, bool wantUp) {
  var wNet = 0;
  var wTot = 0;
  var aligned = 0;
  var avail = 0;
  for (final entry in _trendWeights.entries) {
    final t = byTf[entry.key];
    if (t == null || !t.enough) continue;
    avail++;
    wTot += entry.value;
    final isUp = t.dir == 'up';
    final isDn = t.dir == 'dn';
    if ((wantUp && isUp) || (!wantUp && isDn)) {
      wNet += entry.value;
      aligned++;
    } else if ((wantUp && isDn) || (!wantUp && isUp)) {
      wNet -= entry.value;
    }
    // flat: wNet += 0
  }
  final index = wTot == 0 ? 50 : (50 + 50 * (wNet / wTot)).round().clamp(0, 100);
  return (index: index, aligned: aligned, avail: avail);
}

// ---------------------------------------------------------------------------
// Price Action 2 mức (§5)
// ---------------------------------------------------------------------------

class PaPattern {
  String name;
  String level; // 'basic' | 'advanced'
  String? dir; // 'bull' | 'bear' | null (trung tính / không có)

  PaPattern({required this.name, required this.level, this.dir});
}

class PaLevels {
  double? hi20;
  double? lo20;
  String? brDir; // 'bull' | 'bear' — hướng phá đỉnh/đáy 20 nến
  String? sweepDir;
  String? chochDir;
  String? fvgDir;
  String? obDir;
  String? retestDir;
  double? sweepLevel;
  ({double low, double high})? fvgZone;
  ({double low, double high})? obZone;

  PaLevels({
    this.hi20,
    this.lo20,
    this.brDir,
    this.sweepDir,
    this.chochDir,
    this.fvgDir,
    this.obDir,
    this.retestDir,
    this.sweepLevel,
    this.fvgZone,
    this.obZone,
  });
}

class PaResult {
  List<PaPattern> basic;
  List<PaPattern> advanced;
  int bull;
  int bear;
  int total;
  PaLevels levels;

  PaResult({
    required this.basic,
    required this.advanced,
    required this.bull,
    required this.bear,
    required this.total,
    required this.levels,
  });

  /// Điểm PA (§4.4): round(50 + 50 * (aligned − opposed) / total); total = 0 → 50.
  int index(bool wantUp) {
    if (total == 0) return 50;
    final aligned = wantUp ? bull : bear;
    final opposed = wantUp ? bear : bull;
    return (50 + 50 * (aligned - opposed) / total).round().clamp(0, 100);
  }
}

double _body(RawCandle c) => (c.c - c.o).abs();

/// Price Action 2 mức từ nến đã đóng.
/// Yêu cầu M15 >= 25 nến (ít hơn → kết quả rỗng, index() = 50).
/// M5 >= 22 nến cho xác nhận Execution, H1 >= 55 cho xu hướng H1;
/// thiếu thì mẫu liên quan có dir null nhưng vẫn tính vào total.
PaResult computePriceAction({
  required List<RawCandle> m15,
  required List<RawCandle> m5,
  required List<RawCandle> h1,
  required IndicatorParams ind,
  required double? livePrice,
}) {
  final empty = PaResult(
    basic: [],
    advanced: [],
    bull: 0,
    bear: 0,
    total: 0,
    levels: PaLevels(),
  );
  if (m15.length < 25) return empty;

  final n = m15.length;
  final last = m15[n - 1];
  final prev = m15[n - 2];
  final body = _body(last);
  final upW = last.h - math.max(last.o, last.c);
  final dnW = math.min(last.o, last.c) - last.l;

  // --- Mức Cơ bản (5 mẫu, nến M15 đóng gần nhất) ---
  final basic = <PaPattern>[];

  // 1. Pin Bar
  String? pinDir;
  if (body > 0 && dnW > body * 2 && upW < body * 0.9) {
    pinDir = 'bull';
  } else if (body > 0 && upW > body * 2 && dnW < body * 0.9) {
    pinDir = 'bear';
  }
  basic.add(PaPattern(name: 'Pin Bar', level: 'basic', dir: pinDir));

  // 2. Engulfing (nhấn chìm)
  String? engDir;
  if (last.c > last.o &&
      prev.c < prev.o &&
      last.c >= prev.o &&
      last.o <= prev.c) {
    engDir = 'bull';
  } else if (last.c < last.o &&
      prev.c > prev.o &&
      last.c <= prev.o &&
      last.o >= prev.c) {
    engDir = 'bear';
  }
  basic.add(PaPattern(name: 'Engulfing', level: 'basic', dir: engDir));

  // 3. Inside Bar — luôn trung tính (chỉ báo nén giá, chờ phá biên).
  // Điều kiện: last.h <= prev.h && last.l >= prev.l (dir luôn null).
  basic.add(PaPattern(name: 'Inside Bar', level: 'basic', dir: null));

  // 4. Doji / từ chối giá — ngưỡng 0.12 (khác thư viện mẫu hình: 0.10).
  // Điều kiện: body / range < 0.12 (dir luôn null).
  basic.add(PaPattern(name: 'Doji', level: 'basic', dir: null));

  // 5. Phá đỉnh / đáy 20 nến
  double hi20 = double.negativeInfinity;
  double lo20 = double.infinity;
  for (var i = n - 21; i <= n - 2; i++) {
    if (m15[i].h > hi20) hi20 = m15[i].h;
    if (m15[i].l < lo20) lo20 = m15[i].l;
  }
  String? brDir;
  if (last.c > hi20) {
    brDir = 'bull';
  } else if (last.c < lo20) {
    brDir = 'bear';
  }
  basic.add(PaPattern(
      name: 'Phá đỉnh/đáy 20 nến', level: 'basic', dir: brDir));

  // --- Mức Nâng cao (7 mẫu) ---
  final advanced = <PaPattern>[];
  final levels = PaLevels(hi20: hi20, lo20: lo20, brDir: brDir);

  // 1. Liquidity Sweep — quét 5 nến M15 gần nhất, cửa sổ 20 nến trước mỗi nến
  String? sweepDir;
  double? sweepLevel;
  for (var i = n - 5; i <= n - 1; i++) {
    if (i - 20 < 0) continue;
    var hh = double.negativeInfinity;
    var ll = double.infinity;
    for (var j = i - 20; j <= i - 1; j++) {
      if (m15[j].h > hh) hh = m15[j].h;
      if (m15[j].l < ll) ll = m15[j].l;
    }
    final c = m15[i];
    if (c.h > hh && c.c < hh) {
      sweepDir = 'bear';
      sweepLevel = hh;
    }
    if (c.l < ll && c.c > ll) {
      sweepDir = 'bull';
      sweepLevel = ll;
    }
  }
  levels.sweepDir = sweepDir;
  levels.sweepLevel = sweepLevel;
  advanced.add(PaPattern(name: 'Liquidity Sweep', level: 'advanced', dir: sweepDir));

  // 2. BOS — cùng điều kiện phá đỉnh/đáy 20 nến
  advanced.add(PaPattern(name: 'BOS', level: 'advanced', dir: brDir));

  // 3. CHoCH — phá ngược xu hướng H1 (EMA20 vs EMA50 H1)
  String? chochDir;
  if (brDir != null && h1.length >= 2) {
    final closesH1 = h1.map((c) => c.c).toList();
    final e20h1 = _emaLast(closesH1, ind.emaFast);
    final e50h1 = _emaLast(closesH1, ind.emaSlow);
    if (e20h1 != null && e50h1 != null) {
      final h1Up = e20h1 > e50h1;
      if (brDir == 'bull' && !h1Up) {
        chochDir = 'bull';
      } else if (brDir == 'bear' && h1Up) {
        chochDir = 'bear';
      }
    }
  }
  levels.chochDir = chochDir;
  advanced.add(PaPattern(name: 'CHoCH', level: 'advanced', dir: chochDir));

  // 4. FVG — quét 15 nến gần nhất, bộ 3 nến (a = m15[j-2], b = m15[j])
  String? fvgDir;
  ({double low, double high})? fvgZone;
  for (var j = math.max(2, n - 15); j <= n - 1; j++) {
    final a = m15[j - 2];
    final b = m15[j];
    if (b.l > a.h) {
      fvgDir = 'bull';
      fvgZone = (low: a.h, high: b.l);
    } else if (b.h < a.l) {
      fvgDir = 'bear';
      fvgZone = (low: b.h, high: a.l);
    }
  }
  levels.fvgDir = fvgDir;
  levels.fvgZone = fvgZone;
  advanced.add(PaPattern(name: 'FVG', level: 'advanced', dir: fvgDir));

  // 5. Order Block — chỉ khi có BOS
  String? obDir;
  ({double low, double high})? obZone;
  if (brDir != null) {
    final wantBearish = brDir == 'bull'; // phá lên: tìm nến giảm cuối trước nhịp phá
    for (var i = n - 2; i >= math.max(0, n - 13); i--) {
      final c = m15[i];
      final isTarget = wantBearish ? c.c < c.o : c.c > c.o;
      if (isTarget) {
        obZone = (low: c.l, high: c.h);
        obDir = brDir;
        break;
      }
    }
  }
  levels.obDir = obDir;
  levels.obZone = obZone;
  advanced.add(PaPattern(name: 'Order Block', level: 'advanced', dir: obDir));

  // 6. Retest vùng phá vỡ — giá hiện tại trong 0.3×ATR(H1) quanh mức phá
  String? retestDir;
  if (brDir != null && h1.isNotEmpty) {
    final atrH1 = _atrLast(h1, ind.atrPeriod);
    if (atrH1 != null) {
      final lvl = brDir == 'bull' ? hi20 : lo20;
      final cur = livePrice ?? last.c;
      if ((cur - lvl).abs() <= 0.3 * atrH1) retestDir = brDir;
    }
  }
  levels.retestDir = retestDir;
  advanced.add(PaPattern(name: 'Retest', level: 'advanced', dir: retestDir));

  // 7. Xác nhận M5 (Execution) — nến M5 đóng gần nhất vs đỉnh/đáy 20 nến M5 trước nó
  String? m5Dir;
  if (m5.length >= 22) {
    final m = m5.length;
    final m5last = m5[m - 1];
    var m5hi = double.negativeInfinity;
    var m5lo = double.infinity;
    for (var i = m - 21; i <= m - 2; i++) {
      if (m5[i].h > m5hi) m5hi = m5[i].h;
      if (m5[i].l < m5lo) m5lo = m5[i].l;
    }
    if (m5last.c > m5hi) {
      m5Dir = 'bull';
    } else if (m5last.c < m5lo) {
      m5Dir = 'bear';
    }
  }
  advanced.add(PaPattern(name: 'Xác nhận M5', level: 'advanced', dir: m5Dir));

  var bull = 0;
  var bear = 0;
  for (final p in [...basic, ...advanced]) {
    if (p.dir == 'bull') bull++;
    if (p.dir == 'bear') bear++;
  }
  return PaResult(
    basic: basic,
    advanced: advanced,
    bull: bull,
    bear: bear,
    total: basic.length + advanced.length,
    levels: levels,
  );
}

// ---------------------------------------------------------------------------
// Điểm vào tối ưu (§5.3)
// ---------------------------------------------------------------------------

/// Điểm vào tối ưu. Thứ tự ưu tiên: Retest BOS/CHoCH → Sweep → FVG →
/// Order Block → EMA20 H1 → fallback 0.5×ATR (ưu tiên 9, "chưa nên vào tại đây").
/// [action] là 'BUY' hoặc 'SELL' (với tín hiệu WAIT, gọi hàm với hướng theo bias).
OptimalEntry computeOptimal({
  required String action,
  required double entry,
  required double? sl,
  required double? tp,
  required double atr,
  required PaLevels levels,
  required double? e20h1,
  required int paIndex,
}) {
  final isBuy = action == 'BUY';
  final wantDir = isBuy ? 'bull' : 'bear';
  final winLow = isBuy ? entry - 1.8 * atr : entry - 0.3 * atr;
  final winHigh = isBuy ? entry + 0.3 * atr : entry + 1.8 * atr;
  bool inWindow(double p) => p >= winLow && p <= winHigh;

  double? price;
  String? label;
  var isFallback = false;

  // 1. Retest sau BOS/CHoCH
  if (levels.brDir == wantDir && levels.hi20 != null && levels.lo20 != null) {
    final p = isBuy ? levels.hi20! : levels.lo20!;
    if (inWindow(p)) {
      price = p;
      label = levels.chochDir == wantDir
          ? (isBuy ? 'Retest sau CHoCH tăng' : 'Retest sau CHoCH giảm')
          : (isBuy ? 'Retest sau BOS tăng' : 'Retest sau BOS giảm');
    }
  }
  // 2. Sau Liquidity Sweep
  if (price == null &&
      levels.sweepDir == wantDir &&
      levels.sweepLevel != null &&
      inWindow(levels.sweepLevel!)) {
    price = levels.sweepLevel;
    label = isBuy ? 'Sau Liquidity Sweep đáy' : 'Sau Liquidity Sweep đỉnh';
  }
  // 3. Mép / giữa FVG
  if (price == null &&
      levels.fvgDir == wantDir &&
      levels.fvgZone != null) {
    final p = (levels.fvgZone!.low + levels.fvgZone!.high) / 2;
    if (inWindow(p)) {
      price = p;
      label = 'Giữa vùng FVG';
    }
  }
  // 4. Order Block
  if (price == null && levels.obDir == wantDir && levels.obZone != null) {
    final p = (levels.obZone!.low + levels.obZone!.high) / 2;
    if (inWindow(p)) {
      price = p;
      label = 'Giữa vùng Order Block';
    }
  }
  // 5. Hồi về EMA20 H1
  if (price == null && e20h1 != null && inWindow(e20h1)) {
    price = e20h1;
    label = 'Hồi về EMA20 H1';
  }
  // 9. Fallback — vùng hồi 0.5×ATR (tham chiếu, chưa nên vào tại đây)
  if (price == null) {
    price = isBuy ? entry - 0.5 * atr : entry + 0.5 * atr;
    label = 'Vùng hồi 0,5×ATR (tham chiếu — chưa nên vào tại đây)';
    isFallback = true;
  }

  final zoneLow = price - 0.15 * atr;
  final zoneHigh = price + 0.15 * atr;
  double rrOptimal = 0.0;
  if (sl != null && tp != null) {
    final denom = (price - sl).abs();
    rrOptimal = denom > 0 ? (tp - price).abs() / denom : 0.0;
  }
  final String quality;
  final int stars;
  if (!isFallback && paIndex >= 60) {
    quality = 'Chuẩn & đẹp';
    stars = 3;
  } else if (!isFallback && paIndex >= 45) {
    quality = 'Chuẩn — chờ thêm 1 xác nhận PA';
    stars = 2;
  } else {
    quality = 'Chưa đẹp — chờ xác nhận';
    stars = 1;
  }
  return OptimalEntry(
    price: price,
    zoneLow: zoneLow,
    zoneHigh: zoneHigh,
    rrOptimal: rrOptimal,
    // label luôn được gán ở 1 trong 6 nhánh trên (nhánh fallback cuối cùng).
    label: label ?? 'Điểm vào tối ưu',
    quality: quality,
    stars: stars,
    isFallback: isFallback,
  );
}

// ---------------------------------------------------------------------------
// Thang TP (§8.1)
// ---------------------------------------------------------------------------

/// Các mức Inv/T1–T4. WAIT hoặc thiếu SL/TP → null.
LadderLevels? sigLevels(String action, double entry, double? sl, double? tp) {
  if (action == 'WAIT' || sl == null || tp == null) return null;
  final dist = (tp - entry).abs();
  if (dist <= 0) return null;
  final dir = action == 'BUY' ? 1.0 : -1.0;
  return LadderLevels(
    inv: sl,
    t1: entry + dir * dist * 0.25,
    t2: entry + dir * dist * 0.50,
    t3: entry + dir * dist * 0.75,
    t4: tp,
    entry: entry,
  );
}

// ---------------------------------------------------------------------------
// Lõi chiến lược (§3.2, §11)
// ---------------------------------------------------------------------------

class _Core {
  String action; // 'BUY' | 'SELL' | 'WAIT'
  int baseConf;
  String bias; // 'bullish' | 'bearish'
  List<String> reasons;

  _Core({
    required this.action,
    required this.baseConf,
    required this.bias,
    required this.reasons,
  });
}

_Core _swingCore({
  required List<RawCandle> h1,
  required List<RawCandle> h4,
  required List<RawCandle> m15,
  required IndicatorParams ind,
  required double atr,
}) {
  final closesH1 = h1.map((c) => c.c).toList();
  final e20h1 = _emaLast(closesH1, ind.emaFast);
  final e50h1 = _emaLast(closesH1, ind.emaSlow);
  final closesH4 = h4.map((c) => c.c).toList();
  final e20h4 = _emaLast(closesH4, ind.emaFast);
  final e50h4 = _emaLast(closesH4, ind.emaSlow);
  final rsi = m15.length >= 20
      ? _rsiLast(m15.map((c) => c.c).toList(), ind.rsiSig)
      : null;

  final reasons = <String>[];
  if (e20h1 == null || e50h1 == null) {
    return _Core(
      action: 'WAIT',
      baseConf: 42,
      bias: 'bullish',
      reasons: ['Chưa đủ nến tính EMA H1 — chờ tải thêm nến'],
    );
  }

  // bias: H4, fallback H1 (§3.1)
  final String bias;
  if (e20h4 != null && e50h4 != null) {
    bias = e20h4 >= e50h4 ? 'bullish' : 'bearish';
  } else {
    bias = e20h1 >= e50h1 ? 'bullish' : 'bearish';
  }
  final trendUp = e20h1 > e50h1;
  final strength = (e20h1 - e50h1).abs() / atr;

  reasons.add(
      'EMA20 H1 ${fmtPrice(e20h1)} ${trendUp ? '>' : '<'} EMA50 ${fmtPrice(e50h1)}');
  if (e20h4 != null && e50h4 != null) {
    reasons.add(
        'H4 cùng chiều ${bias == 'bullish' ? 'tăng' : 'giảm'} (EMA20 ${fmtPrice(e20h4)} ${e20h4 >= e50h4 ? '>=' : '<'} EMA50 ${fmtPrice(e50h4)})');
  } else {
    reasons.add('H4 chưa đủ nến — bias lấy từ H1');
  }
  reasons.add(rsi == null
      ? 'RSI(${ind.rsiSig}) M15 = — (chưa đủ nến)'
      : 'RSI(${ind.rsiSig}) M15 = ${rsi.toStringAsFixed(1)}');
  reasons.add('ATR(${ind.atrPeriod}) H1 = ${fmtPrice(atr)}');

  if (strength < 0.08) {
    return _Core(
      action: 'WAIT',
      baseConf: (38 + strength * 100).round(),
      bias: bias,
      reasons: [...reasons, 'EMA20/50 H1 tách quá hẹp — chờ'],
    );
  }
  if (trendUp && bias == 'bullish' && (rsi == null || rsi < 78)) {
    final bonus = (rsi != null && rsi >= 48 && rsi <= 68) ? 9 : 0;
    return _Core(
      action: 'BUY',
      baseConf: math.min(95, 56 + strength * 55 + bonus).round(),
      bias: bias,
      reasons: reasons,
    );
  }
  if (!trendUp && bias == 'bearish' && (rsi == null || rsi > 22)) {
    final bonus = (rsi != null && rsi >= 32 && rsi <= 52) ? 9 : 0;
    return _Core(
      action: 'SELL',
      baseConf: math.min(95, 56 + strength * 55 + bonus).round(),
      bias: bias,
      reasons: reasons,
    );
  }
  final extremeRsi = (trendUp && rsi != null && rsi >= 78) ||
      (!trendUp && rsi != null && rsi <= 22);
  return _Core(
    action: 'WAIT',
    baseConf: (42 + math.min(14, strength * 30)).round(),
    bias: bias,
    reasons: [
      ...reasons,
      extremeRsi
          ? 'RSI ở vùng cực đoan — chờ hồi'
          : 'H1 và H4 chưa đồng thuận — chờ',
    ],
  );
}

_Core _vpCore({
  required List<RawCandle> h1,
  required List<RawCandle> m15,
  required IndicatorParams ind,
  required double entry,
  required double atr,
  required double? poc,
  required double? vah,
  required double? val,
  required double step,
  required double? deltaPct,
}) {
  final reasons = <String>[];
  if (m15.length < 40) {
    return _Core(
      action: 'WAIT',
      baseConf: 46,
      bias: 'bullish',
      reasons: ['Chưa đủ nến M15 cho VolumeB/S (cần ≥ 40 nến)'],
    );
  }
  final closesH1 = h1.map((c) => c.c).toList();
  final e20h1 = _emaLast(closesH1, ind.emaFast);
  final e50h1 = _emaLast(closesH1, ind.emaSlow);

  // Xu hướng H1 từ Ichimoku, fallback EMA nhanh/chậm H1 (§11.2)
  String trend; // 'up' | 'down' | 'neutral'
  final ichi = _ichimoku(h1);
  if (ichi != null) {
    trend = ichi.pos == 'above'
        ? 'up'
        : ichi.pos == 'below'
            ? 'down'
            : 'neutral';
    reasons.add(
        'Ichimoku H1: giá ${ichi.pos == 'above' ? 'trên mây' : ichi.pos == 'below' ? 'dưới mây' : 'trong mây'} (Tenkan ${fmtPrice(ichi.tenkan)} · Kijun ${fmtPrice(ichi.kijun)})');
  } else if (e20h1 != null && e50h1 != null) {
    trend = e20h1 > e50h1 ? 'up' : 'down';
    reasons.add('Ichimoku chưa đủ 52 nến — xu hướng H1 theo EMA20/50');
  } else {
    trend = 'neutral';
    reasons.add('Chưa đủ nến xác định xu hướng H1');
  }
  final bias =
      trend == 'down' ? 'bearish' : (trend == 'up' ? 'bullish' : (e20h1 != null && e50h1 != null && e20h1 < e50h1 ? 'bearish' : 'bullish'));

  // Vùng POC / VAH / VAL (cần POC từ module Volume Profile)
  bool nearPoc = false;
  String? beyond; // 'up' | 'down'
  if (poc == null) {
    reasons.add('Chưa có POC — dùng xu hướng Ichimoku H1');
  } else {
    nearPoc = (entry - poc).abs() <= math.max(step * 1.5, atr * 0.6);
    if (vah != null && entry > vah) beyond = 'up';
    if (val != null && entry < val) beyond = 'down';
    reasons.add(
        'POC ${fmtPrice(poc)}${vah != null ? ' · VAH ${fmtPrice(vah)}' : ''}${val != null ? ' · VAL ${fmtPrice(val)}' : ''} — ${nearPoc ? 'giá đang tại vùng POC' : 'giá chưa tại vùng POC'}');
  }
  if (deltaPct != null) {
    reasons.add('Delta ước tính M15: ${deltaPct.toStringAsFixed(1)}%');
  }

  String action;
  int baseConf;
  if (poc == null) {
    // Không có POC: baseConf theo trend (ghi rõ lý do ở trên).
    if (trend == 'up') {
      action = 'BUY';
      baseConf = 63;
    } else if (trend == 'down') {
      action = 'SELL';
      baseConf = 63;
    } else {
      action = 'WAIT';
      baseConf = 46;
    }
  } else if (trend == 'up' && (nearPoc || beyond == 'up')) {
    action = 'BUY';
    baseConf = nearPoc ? 72 : 63;
  } else if (trend == 'down' && (nearPoc || beyond == 'down')) {
    action = 'SELL';
    baseConf = nearPoc ? 72 : 63;
  } else if (trend != 'neutral') {
    action = 'WAIT';
    baseConf = 52;
    reasons.add('Có xu hướng H1 nhưng giá chưa tại vùng POC/HVN — chờ');
  } else {
    action = 'WAIT';
    baseConf = 46;
    reasons.add('H1 chưa có xu hướng rõ (giá trong mây) — chờ');
  }

  // Điều chỉnh Delta (§11.2)
  if (deltaPct != null && action != 'WAIT') {
    final isBuy = action == 'BUY';
    final sameDir = isBuy ? deltaPct > 2 : deltaPct < -2;
    final oppStrong = isBuy ? deltaPct < -6 : deltaPct > 6;
    if (sameDir) {
      baseConf = math.min(92, baseConf + 4);
      reasons.add('Delta ước tính cùng hướng — cộng 4 điểm gốc');
    } else if (oppStrong) {
      baseConf = math.max(40, baseConf - 6);
      reasons.add('Delta ước tính đang ngược hướng — trừ điểm');
    }
  }
  return _Core(action: action, baseConf: baseConf, bias: bias, reasons: reasons);
}

/// AI hợp nhất (§11.3): Swing làm gốc, đối chiếu VolumeB/S + MACD H1.
_Core _aiCore({
  required _Core swing,
  required _Core vp,
  required List<RawCandle> h1,
  required IndicatorParams ind,
}) {
  var action = swing.action;
  var baseConf = swing.baseConf;
  final reasons = <String>[
    'AI hợp nhất: Swing + VolumeB/S + MACD + Trend + PA',
    ...swing.reasons,
  ];
  // Đối chiếu VolumeB/S
  final conflict =
      (swing.action == 'BUY' && vp.action == 'SELL') ||
          (swing.action == 'SELL' && vp.action == 'BUY');
  if (conflict) {
    action = 'WAIT';
    baseConf = math.min(baseConf, 48);
    reasons.add(
        'AI: VolumeB/S (Ichimoku + POC) ngược chiều Swing — hạ về WAIT chờ đồng thuận');
  } else if (action != 'WAIT' && vp.action == swing.action) {
    baseConf = math.min(95, baseConf + 6);
    reasons.add(
        'AI: VolumeB/S đồng thuận hướng ${action == 'BUY' ? 'tăng' : 'giảm'} — cộng 6 điểm gốc');
  }
  // Đối chiếu MACD H1
  if (action != 'WAIT') {
    final macd = _macdLast(h1, ind);
    if (macd != null) {
      final macdUp = macd.line > macd.signal;
      final opposite =
          (action == 'BUY' && !macdUp) || (action == 'SELL' && macdUp);
      if (opposite) {
        baseConf = math.max(35, baseConf - 4);
        reasons.add(
            'MACD(${ind.macdF},${ind.macdS},${ind.macdSig}) H1 ngược hướng — trừ 4 điểm gốc');
      }
    }
  }
  return _Core(action: action, baseConf: baseConf, bias: swing.bias, reasons: reasons);
}

// ---------------------------------------------------------------------------
// Tín hiệu tĩnh (§3.1–§3.3, §4.3, §11)
// ---------------------------------------------------------------------------

/// Tính (hoặc giữ nguyên) tín hiệu tĩnh cho 1 cặp.
///
/// - H1 đã đóng < 55 nến → null (UI hiện "ĐANG TẢI").
/// - Quy tắc tĩnh: nếu [previous] có cùng closedAt và không [force] thì trả
///   lại [previous] (không tính lại theo giá live).
/// - [poc]/[vah]/[val]/[step] nhận từ module Volume Profile (tùy chọn);
///   thiếu POC thì vpCore dùng xu hướng Ichimoku + Delta (nếu có [deltaPct]).
/// - Đổi chiến lược / đổi thông số chỉ báo → gọi với force: true.
StaticSignal? computeStaticSignal({
  required String symbol,
  required Map<String, List<RawCandle>> closedByTf,
  required double? livePrice,
  required AiStrategy strategy,
  required IndicatorParams ind,
  StaticSignal? previous,
  required int nowMs,
  bool force = false,
  double? poc,
  double? vah,
  double? val,
  double step = 0,
  double? deltaPct,
}) {
  final h1 = closedByTf['H1'] ?? const <RawCandle>[];
  if (h1.length < 55) return null;
  final h4 = closedByTf['H4'] ?? const <RawCandle>[];
  final m15 = closedByTf['M15'] ?? const <RawCandle>[];
  final m5 = closedByTf['M5'] ?? const <RawCandle>[];

  final lastH1 = h1.last;
  final closedAt = lastH1.t + 3600000; // nến H1 đóng sau 60 phút
  if (!force &&
      previous != null &&
      previous.symbol == symbol &&
      previous.closedAt == closedAt) {
    return previous;
  }

  final entry = lastH1.c;
  final atr = _atrLast(h1, ind.atrPeriod);
  if (atr == null || atr <= 0) return null;

  // --- Lõi theo chiến lược ---
  final swing = _swingCore(h1: h1, h4: h4, m15: m15, ind: ind, atr: atr);
  late final _Core core;
  switch (strategy) {
    case AiStrategy.swing:
      core = swing;
      break;
    case AiStrategy.volumebs:
      core = _vpCore(
        h1: h1,
        m15: m15,
        ind: ind,
        entry: entry,
        atr: atr,
        poc: poc,
        vah: vah,
        val: val,
        step: step,
        deltaPct: deltaPct,
      );
      break;
    case AiStrategy.ai:
      core = _aiCore(
        swing: swing,
        vp: _vpCore(
          h1: h1,
          m15: m15,
          ind: ind,
          entry: entry,
          atr: atr,
          poc: poc,
          vah: vah,
          val: val,
          step: step,
          deltaPct: deltaPct,
        ),
        h1: h1,
        ind: ind,
      );
      break;
  }

  // --- SL / TP / RR (§3.3) ---
  double? sl;
  double? tp;
  if (core.action == 'BUY') {
    sl = entry - ind.slMult * atr;
    tp = entry + ind.tpMult * atr;
  } else if (core.action == 'SELL') {
    sl = entry + ind.slMult * atr;
    tp = entry - ind.tpMult * atr;
  }
  final rr = ind.rr;

  // --- Trend đa khung + Price Action → % tin cậy (§4.3) ---
  final byTf = <String, TrendInfo>{};
  for (final tf in ['M5', 'M15', 'H1', 'H4', 'D1']) {
    byTf[tf] = trendForTf(closedByTf[tf] ?? const <RawCandle>[], ind);
  }
  final wantUp = core.action == 'BUY'
      ? true
      : core.action == 'SELL'
          ? false
          : core.bias == 'bullish';
  final trend = multiTrend(byTf, wantUp);
  final pa = computePriceAction(
    m15: m15,
    m5: m5,
    h1: h1,
    ind: ind,
    livePrice: livePrice,
  );
  final paIdx = pa.index(wantUp);
  var conf = (core.baseConf * 0.5 + trend.index * 0.25 + paIdx * 0.25).round();
  if (core.action == 'WAIT') conf = math.min(conf, 62); // trần WAIT 62%
  conf = conf.clamp(5, 97);

  // --- Điểm vào tối ưu + thang TP ---
  final closesH1 = h1.map((c) => c.c).toList();
  final e20h1 = _emaLast(closesH1, ind.emaFast);
  final optimalAction = core.action == 'WAIT'
      ? (core.bias == 'bullish' ? 'BUY' : 'SELL')
      : core.action;
  final optimal = computeOptimal(
    action: optimalAction,
    entry: entry,
    sl: sl,
    tp: tp,
    atr: atr,
    levels: pa.levels,
    e20h1: e20h1,
    paIndex: paIdx,
  );

  return StaticSignal(
    symbol: symbol,
    action: core.action,
    entry: entry,
    sl: sl,
    tp: tp,
    rr: rr,
    atr: atr,
    baseConf: core.baseConf,
    trendIndex: trend.index,
    paIndex: paIdx,
    conf: conf,
    bias: core.bias,
    reasons: core.reasons.take(6).toList(),
    closedAt: closedAt,
    trendAligned: trend.aligned,
    trendAvail: trend.avail,
    paAligned: wantUp ? pa.bull : pa.bear,
    paOpposed: wantUp ? pa.bear : pa.bull,
    paTotal: pa.total,
    optimal: optimal,
    levels: sigLevels(core.action, entry, sl, tp),
  );
}

// ---------------------------------------------------------------------------
// Giờ lên / giờ dừng (§3.5) + hủy lệnh sớm (§3.4)
// ---------------------------------------------------------------------------

/// Giờ lên (= closedAt) + giờ dừng của tín hiệu.
/// - Có [closedMatch] → giờ dừng THẬT kèm lý do + giá đóng.
/// - Còn hiệu lực → giờ dừng DỰ KIẾN = closedAt + 1 giờ (nến H1 tiếp theo đóng).
/// - WAIT → hết hiệu lực khi nến H1 tiếp theo đóng.
String sigStopInfo(StaticSignal sg, {HistClose? closedMatch}) {
  final up = vnDateStr(sg.closedAt);
  if (closedMatch != null) {
    return 'Lên lúc $up — Đã dừng lúc ${vnDateStr(closedMatch.exitAt)} — '
        '${closedMatch.reason} tại giá ${fmtPrice(closedMatch.exitPrice)}.';
  }
  final stopAt = sg.closedAt + 3600000;
  if (sg.action == 'WAIT') {
    return 'Lên lúc $up — Tín hiệu WAIT — hết hiệu lực ${vnDateStr(stopAt)} '
        'khi nến H1 tiếp theo đóng.';
  }
  return 'Lên lúc $up — Chưa dừng — hiệu lực tới ${vnDateStr(stopAt)} '
      '(nến H1 tiếp theo đóng); dừng sớm ngay khi giá chạm TP/SL hoặc '
      'tín hiệu đảo chiều.';
}

/// Ghi lệnh cũ bị hủy sớm khi tín hiệu đảo chiều (§3.4).
/// exit = giá live lúc đảo chiều (chưa có giá live thì lấy entry).
/// Chỉ ghi khi lệnh cũ là BUY/SELL và có SL; ngược lại trả null.
/// [reason]: 'Đảo chiều sang SELL — hủy lệnh sớm' /
/// 'Mất điều kiện (về WAIT) — hủy lệnh sớm' /
/// 'Đổi chiến lược/thông số — hủy lệnh sớm'.
Invalidation? makeInvalidation(
    StaticSignal old, double? livePrice, String reason) {
  if (old.action == 'WAIT' || old.sl == null) return null;
  final exit = livePrice ?? old.entry;
  final d = old.action == 'BUY' ? exit - old.entry : old.entry - exit;
  final pips = d / pipSize(old.symbol);
  final pct = d / old.entry * 100;
  return Invalidation(
    symbol: old.symbol,
    oldAction: old.action,
    entry: old.entry,
    sl: old.sl,
    exit: exit,
    exitAt: DateTime.now().millisecondsSinceEpoch,
    pips: pips,
    pct: pct,
    reason: reason,
  );
}
