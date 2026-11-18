// TonyD Volume Profile Buy/Sell — phan tich XAUUSD.
// H4 Market Map, H1 Trend Filter (Ichimoku + EMA20/POC), M15 Setup
// (Volume Profile lookback 200), M5 Execution (Sweep / CHoCH / BOS / Retest).
// Delta o day la UOC TINH tu nen (nen tang ~ phan lon volume la Buy,
// nen giam ~ phan lon volume la Sell), KHONG phai tick Delta that.
import 'dart:math';

import 'engine.dart';

class VpBin {
  final double mid;
  final double low;
  final double high;
  final double volume;
  const VpBin({
    required this.mid,
    required this.low,
    required this.high,
    required this.volume,
  });
}

class ScoreItem {
  final String label;
  final int points;
  final bool met;
  const ScoreItem({
    required this.label,
    required this.points,
    required this.met,
  });
}

class VolumeSetup {
  final String model; // 'A' | 'B' | 'C' | 'NONE'
  final String action; // 'BUY' | 'SELL' | 'WAIT'
  final double poc;
  final double vah;
  final double val;
  final List<VpBin> bins;
  final List<double> hvn;
  final List<double> lvn;
  final double delta;
  final double deltaPct;
  final double buyVol;
  final double sellVol;
  final double entry;
  final double sl;
  final double tp1;
  final double tp2;
  final double rr;
  final List<ScoreItem> scoreItems;
  final int score;
  final String verdict; // 'XEM XET' | 'CHO THEM' | 'KHONG GIAO DICH'
  final List<String> notes;
  final String h1Trend; // 'TANG' | 'GIAM' | 'SIDEWAY'
  final double tenkan;
  final double kijun;
  final double senkouA;
  final double senkouB;
  final double ema20H1;
  final bool sweepBuy;
  final bool sweepSell;
  final bool chochBuy;
  final bool chochSell;
  final double price;

  const VolumeSetup({
    required this.model,
    required this.action,
    required this.poc,
    required this.vah,
    required this.val,
    required this.bins,
    required this.hvn,
    required this.lvn,
    required this.delta,
    required this.deltaPct,
    required this.buyVol,
    required this.sellVol,
    required this.entry,
    required this.sl,
    required this.tp1,
    required this.tp2,
    required this.rr,
    required this.scoreItems,
    required this.score,
    required this.verdict,
    required this.notes,
    required this.h1Trend,
    required this.tenkan,
    required this.kijun,
    required this.senkouA,
    required this.senkouB,
    required this.ema20H1,
    required this.sweepBuy,
    required this.sweepSell,
    required this.chochBuy,
    required this.chochSell,
    required this.price,
  });
}

double _donchianMid(List<Candle> cs, int period) {
  if (cs.isEmpty) return 0;
  final List<Candle> tail =
      cs.length > period ? cs.sublist(cs.length - period) : cs;
  double hi = tail.first.h;
  double lo = tail.first.l;
  for (final Candle c in tail) {
    if (c.h > hi) hi = c.h;
    if (c.l < lo) lo = c.l;
  }
  return (hi + lo) / 2;
}

/// Phan tich Volume Profile cho XAUUSD tu nen M15 (lookback 200),
/// loc xu huong H1 (Ichimoku) va cau truc H4.
VolumeSetup analyzeVolumeProfile({
  required List<Candle> m15,
  required List<Candle> h1,
  required List<Candle> h4,
}) {
  final List<Candle> lookback =
      m15.length > 200 ? m15.sublist(m15.length - 200) : m15;
  final double price = lookback.isNotEmpty ? lookback.last.c : 0;
  final List<String> notes = <String>[];

  // --- Ichimoku H1 ---
  final double tenkan = _donchianMid(h1, 9);
  final double kijun = _donchianMid(h1, 26);
  final double senkouA = (tenkan + kijun) / 2;
  final double senkouB = _donchianMid(h1, 52);
  final double kumoTop = max(senkouA, senkouB);
  final double kumoBot = min(senkouA, senkouB);
  final List<double> h1Closes = h1.map((Candle c) => c.c).toList();
  final List<double?> e20h1 = ema(h1Closes, 20);
  double ema20H1 = 0;
  for (int i = e20h1.length - 1; i >= 0; i--) {
    if (e20h1[i] != null) {
      ema20H1 = e20h1[i]!;
      break;
    }
  }

  String h1Trend;
  if (price > kumoTop && price > ema20H1 && tenkan > kijun) {
    h1Trend = 'TANG';
  } else if (price < kumoBot && price < ema20H1 && tenkan < kijun) {
    h1Trend = 'GIAM';
  } else {
    h1Trend = 'SIDEWAY';
  }

  // --- Volume Profile M15: 20 bin gia ---
  double lo = lookback.first.l;
  double hi = lookback.first.h;
  for (final Candle c in lookback) {
    if (c.l < lo) lo = c.l;
    if (c.h > hi) hi = c.h;
  }
  const int binCount = 20;
  final double span = (hi - lo) <= 0 ? 1 : hi - lo;
  final double binH = span / binCount;
  final List<double> binVol = List<double>.filled(binCount, 0);
  for (final Candle c in lookback) {
    int idx = ((c.c - lo) / binH).floor().clamp(0, binCount - 1);
    binVol[idx] += c.vol;
  }
  final List<VpBin> bins = List<VpBin>.generate(binCount, (int i) {
    final double bLo = lo + i * binH;
    return VpBin(
      mid: bLo + binH / 2,
      low: bLo,
      high: bLo + binH,
      volume: binVol[i],
    );
  });
  int pocIdx = 0;
  for (int i = 1; i < binCount; i++) {
    if (binVol[i] > binVol[pocIdx]) pocIdx = i;
  }
  final double poc = bins[pocIdx].mid;
  final double totalVol = binVol.fold(0, (a, b) => a + b);
  // Vung gia tri 70%: mo rong tu POC ra 2 phia cho toi khi du 70% volume.
  double vaVol = binVol[pocIdx];
  int up = pocIdx;
  int dn = pocIdx;
  while (vaVol < totalVol * 0.7 && (up < binCount - 1 || dn > 0)) {
    final double upVol = up < binCount - 1 ? binVol[up + 1] : -1;
    final double dnVol = dn > 0 ? binVol[dn - 1] : -1;
    if (upVol >= dnVol && up < binCount - 1) {
      up++;
      vaVol += binVol[up];
    } else if (dn > 0) {
      dn--;
      vaVol += binVol[dn];
    } else {
      break;
    }
  }
  final double vah = bins[up].high;
  final double val = bins[dn].low;

  // HVN: bin volume > 1.5x trung binh; LVN: < 0.5x trung binh.
  final double meanVol = totalVol / binCount;
  final List<double> hvn = <double>[];
  final List<double> lvn = <double>[];
  for (final VpBin b in bins) {
    if (b.volume > meanVol * 1.5) hvn.add(b.mid);
    if (b.volume < meanVol * 0.5) lvn.add(b.mid);
  }

  // --- Delta uoc tinh tu nen ---
  double buyVol = 0;
  double sellVol = 0;
  for (final Candle c in lookback) {
    final double range = (c.h - c.l).abs();
    final double body = (c.c - c.o).abs();
    final double frac = range <= 0 ? 0.5 : (body / range).clamp(0, 1);
    if (c.c >= c.o) {
      buyVol += c.vol * (0.5 + 0.5 * frac);
      sellVol += c.vol * (0.5 - 0.5 * frac);
    } else {
      sellVol += c.vol * (0.5 + 0.5 * frac);
      buyVol += c.vol * (0.5 - 0.5 * frac);
    }
  }
  final double delta = buyVol - sellVol;
  final double deltaPct =
      totalVol > 0 ? delta / totalVol * 100 : 0;

  // --- ATR M15 de do khoang cach ---
  final List<double?> atrs = atr(lookback, 14);
  double atrVal = 0;
  for (int i = atrs.length - 1; i >= 0; i--) {
    if (atrs[i] != null) {
      atrVal = atrs[i]!;
      break;
    }
  }
  if (atrVal <= 0) atrVal = price * 0.0015;
  final double near = atrVal * 0.5; // "tai POC/HVN" = trong 0.5 ATR.

  bool nearLevel(double level) => (price - level).abs() <= near;
  final bool atPocHvn =
      nearLevel(poc) || hvn.any((double h) => nearLevel(h));

  // --- Sweep / CHoCH / BOS tren M15 (20 nen gan nhat) ---
  final List<Candle> recent =
      lookback.length > 20 ? lookback.sublist(lookback.length - 20) : lookback;
  double swingLow = recent.first.l;
  double swingHigh = recent.first.h;
  for (final Candle c in recent) {
    if (c.l < swingLow) swingLow = c.l;
    if (c.h > swingHigh) swingHigh = c.h;
  }
  // Swing truoc do (nen 20-10) lam moc so sanh.
  final List<Candle> prev = recent.length > 10
      ? recent.sublist(0, recent.length - 10)
      : recent;
  double prevLow = prev.first.l;
  double prevHigh = prev.first.h;
  for (final Candle c in prev) {
    if (c.l < prevLow) prevLow = c.l;
    if (c.h > prevHigh) prevHigh = c.h;
  }
  final Candle last = recent.last;
  final bool sweepBuy =
      last.l < prevLow && last.c > prevLow; // quet day roi dong lai tren
  final bool sweepSell =
      last.h > prevHigh && last.c < prevHigh; // quet dinh roi dong lai duoi
  final bool chochBuy =
      last.c > prevHigh && !sweepBuy; // pha dinh gan nhat (BOS/CHoCH mua)
  final bool chochSell =
      last.c < prevLow && !sweepSell; // pha day gan nhat (BOS/CHoCH ban)

  // LVN gan nhat tren/duoi gia de lam mo hinh C.
  double? lvnAbove;
  double? lvnBelow;
  for (final double l in lvn) {
    if (l > price && (lvnAbove == null || l < lvnAbove)) lvnAbove = l;
    if (l < price && (lvnBelow == null || l > lvnBelow)) lvnBelow = l;
  }

  // --- Chon mo hinh ---
  String model = 'NONE';
  String action = 'WAIT';
  double entry = price;
  double sl = price;
  double tp1 = price;
  double tp2 = price;
  bool volOkBuy = delta > 0;
  bool volOkSell = delta < 0;

  if (sweepBuy && atPocHvn && h1Trend != 'GIAM') {
    model = 'A';
    action = 'BUY';
    entry = price;
    sl = min(last.l, swingLow) - atrVal * 0.3;
    tp1 = swingHigh;
    tp2 = hvn.firstWhere((double h) => h > price, orElse: () => vah);
    if (tp2 <= entry) tp2 = entry + 2 * (entry - sl).abs();
  } else if (sweepSell && atPocHvn && h1Trend != 'TANG') {
    model = 'B';
    action = 'SELL';
    entry = price;
    sl = max(last.h, swingHigh) + atrVal * 0.3;
    tp1 = swingLow;
    tp2 = hvn.lastWhere((double h) => h < price, orElse: () => val);
    if (tp2 >= entry) tp2 = entry - 2 * (sl - entry).abs();
  } else if (chochBuy && lvnAbove != null && h1Trend == 'TANG') {
    model = 'C';
    action = 'BUY';
    entry = price;
    sl = lvnAbove - atrVal * 0.3; // ben kia LVN vua pha
    tp1 = swingHigh + atrVal;
    tp2 = vah;
    if (tp2 <= entry) tp2 = entry + 2 * (entry - sl).abs();
  } else if (chochSell && lvnBelow != null && h1Trend == 'GIAM') {
    model = 'C';
    action = 'SELL';
    entry = price;
    sl = lvnBelow + atrVal * 0.3;
    tp1 = swingLow - atrVal;
    tp2 = val;
    if (tp2 >= entry) tp2 = entry - 2 * (sl - entry).abs();
  }

  // Dam bao RR toi thieu 1:2 cho TP1, neu khong thi day TP1 ra.
  if (action == 'BUY') {
    final double risk = (entry - sl).abs();
    if (risk > 0 && (tp1 - entry) < 2 * risk) tp1 = entry + 2 * risk;
    if ((tp2 - entry) < (tp1 - entry)) tp2 = tp1 + risk;
  } else if (action == 'SELL') {
    final double risk = (sl - entry).abs();
    if (risk > 0 && (entry - tp1) < 2 * risk) tp1 = entry - 2 * risk;
    if ((entry - tp2) < (entry - tp1)) tp2 = tp1 - risk;
  }
  final double risk = (entry - sl).abs();
  final double reward = action == 'BUY'
      ? (tp1 - entry).abs()
      : (entry - tp1).abs();
  final double rr = risk > 0 ? reward / risk : 0;

  // --- Bang cham diem 10 ---
  final bool trendOk = (action == 'BUY' && h1Trend == 'TANG') ||
      (action == 'SELL' && h1Trend == 'GIAM') ||
      (action == 'WAIT' && h1Trend != 'SIDEWAY');
  final bool sweepOk = (action == 'BUY' && sweepBuy) ||
      (action == 'SELL' && sweepSell) ||
      (action == 'WAIT' && (sweepBuy || sweepSell));
  final bool chochOk = (action == 'BUY' && (chochBuy || sweepBuy)) ||
      (action == 'SELL' && (chochSell || sweepSell)) ||
      (action == 'WAIT' && (chochBuy || chochSell));
  final bool volOk = (action == 'BUY' && volOkBuy) ||
      (action == 'SELL' && volOkSell) ||
      (action == 'WAIT' && delta.abs() > totalVol * 0.02);
  final bool rrOk = rr >= 2;

  final List<ScoreItem> scoreItems = <ScoreItem>[
    ScoreItem(
      label: 'H1 cùng xu hướng (Ichimoku + EMA20)',
      points: 2,
      met: trendOk,
    ),
    ScoreItem(
      label: 'Tại POC / HVN (trong 0.5 ATR)',
      points: 2,
      met: atPocHvn,
    ),
    ScoreItem(label: 'Sweep đáy/đỉnh', points: 2, met: sweepOk),
    ScoreItem(label: 'CHoCH / BOS xác nhận', points: 2, met: chochOk),
    ScoreItem(
      label: 'Volume ủng hộ (Delta cùng chiều)',
      points: 1,
      met: volOk,
    ),
    ScoreItem(label: 'RR tối thiểu 1:2', points: 1, met: rrOk),
  ];
  int score = 0;
  for (final ScoreItem s in scoreItems) {
    if (s.met) score += s.points;
  }
  String verdict;
  if (score >= 8) {
    verdict = 'XEM XÉT';
  } else if (score >= 6) {
    verdict = 'CHỜ THÊM';
  } else {
    verdict = 'KHÔNG GIAO DỊCH';
  }
  if (action == 'WAIT' || model == 'NONE') {
    verdict = score >= 8 ? 'CHỜ THÊM' : 'KHÔNG GIAO DỊCH';
  }

  if (model == 'A') {
    notes.add('Mô hình A: Buy tại POC/HVN sau khi quét đáy.');
  } else if (model == 'B') {
    notes.add('Mô hình B: Sell tại POC/HVN sau khi quét đỉnh.');
  } else if (model == 'C') {
    notes.add('Mô hình C: Phá vỡ LVN theo xu hướng H1.');
  } else {
    notes.add('Chưa đủ điều kiện mô hình A/B/C — chờ Sweep hoặc phá LVN.');
  }
  notes.add('H4: giá ${h4.isNotEmpty ? h4.last.c.toStringAsFixed(2) : '—'} '
      '— dùng làm bản đồ thị trường, không vào lệnh trực tiếp từ H4.');
  if (hvn.isEmpty) notes.add('Chưa thấy HVN rõ trong 200 nến M15.');
  if (lvn.isEmpty) notes.add('Chưa thấy LVN rõ trong 200 nến M15.');
  notes.add('Delta là ước tính từ nến, không phải tick Delta thật.');

  return VolumeSetup(
    model: model,
    action: action,
    poc: poc,
    vah: vah,
    val: val,
    bins: bins,
    hvn: hvn,
    lvn: lvn,
    delta: delta,
    deltaPct: deltaPct,
    buyVol: buyVol,
    sellVol: sellVol,
    entry: entry,
    sl: sl,
    tp1: tp1,
    tp2: tp2,
    rr: rr,
    scoreItems: scoreItems,
    score: score,
    verdict: verdict,
    notes: notes,
    h1Trend: h1Trend,
    tenkan: tenkan,
    kijun: kijun,
    senkouA: senkouA,
    senkouB: senkouB,
    ema20H1: ema20H1,
    sweepBuy: sweepBuy,
    sweepSell: sweepSell,
    chochBuy: chochBuy,
    chochSell: chochSell,
    price: price,
  );
}

// ---------------------------------------------------------------------------
// Quet VolumeB/S da cap — them ngay 17/11/2026 (port spec-web §10.5).
// Chi THEM moi, khong doi ham analyzeVolumeProfile o tren.
// Luu y: helper profile o day dung cach chia bin theo GIA DONG (giong
// analyzeVolumeProfile hien co, 20 bin) chu KHONG dung cach chia volume
// theo ti le chong lap cua web (§10.1) — de POC/VAH/VAL nhat quan trong
// app Flutter. Delta thi dung cong thuc web (§10.1):
// buyFrac = clamp((c-l)/(h-l), 0, 1) — van la UOC TINH tu nen, khong phai
// tick Delta that (khac cong thuc delta cu trong analyzeVolumeProfile).
// ---------------------------------------------------------------------------

/// Ket qua quet nhanh 1 cap (spec §10.5). [symbol] do vong lap quet o
/// ngoai gan sau khi goi [vpScanFor] (ham quet khong nhan symbol).
class VpScanResult {
  String symbol;
  String action; // 'BUY' | 'SELL' | 'WAIT'
  int score; // toi da 5
  double? poc;
  double? vah;
  double? val;
  double? deltaPct;
  String h1Trend; // 'up' | 'down' | 'neutral'
  bool nearPoc;
  double price;

  VpScanResult({
    this.symbol = '',
    this.action = 'WAIT',
    this.score = 0,
    this.poc,
    this.vah,
    this.val,
    this.deltaPct,
    this.h1Trend = 'neutral',
    this.nearPoc = false,
    this.price = 0,
  });
}

class _VpScanProfile {
  final double? poc;
  final double? vah;
  final double? val;
  final double? deltaPct;
  final double step;
  const _VpScanProfile({
    this.poc,
    this.vah,
    this.val,
    this.deltaPct,
    this.step = 0,
  });
}

/// Profile gon dung chung cho [vpScanFor] va [vpLevels]: lookback toi da
/// 200 nen, [rows] hang gia, vung gia tri 70% mo rong tu POC.
/// Tra null cho poc/vah/val/deltaPct khi [cs] rong.
_VpScanProfile _vpScanProfile(List<Candle> cs, int rows) {
  final List<Candle> lookback =
      cs.length > 200 ? cs.sublist(cs.length - 200) : cs;
  if (lookback.isEmpty || rows < 1) {
    return const _VpScanProfile();
  }
  double lo = lookback.first.l;
  double hi = lookback.first.h;
  for (final Candle c in lookback) {
    if (c.l < lo) lo = c.l;
    if (c.h > hi) hi = c.h;
  }
  final double span = hi - lo;
  final double step = span <= 0 ? 0 : span / rows;
  if (step <= 0) {
    // Ca cua so gia bang nhau: POC = gia chung, khong co step.
    return _VpScanProfile(poc: lo, vah: hi, val: lo, deltaPct: 0, step: 0);
  }
  final List<double> binVol = List<double>.filled(rows, 0);
  double buyVol = 0;
  double sellVol = 0;
  double totalVol = 0;
  for (final Candle c in lookback) {
    final double v = c.vol <= 0 ? 1 : c.vol;
    final int idx = ((c.c - lo) / step).floor().clamp(0, rows - 1);
    binVol[idx] += v;
    totalVol += v;
    final double range = c.h - c.l;
    final double buyFrac = range <= 0
        ? (c.c >= c.o ? 1 : 0)
        : ((c.c - c.l) / range).clamp(0, 1).toDouble();
    buyVol += v * buyFrac;
    sellVol += v * (1 - buyFrac);
  }
  int pocIdx = 0;
  for (int i = 1; i < rows; i++) {
    if (binVol[i] > binVol[pocIdx]) pocIdx = i;
  }
  double vaVol = binVol[pocIdx];
  int up = pocIdx;
  int dn = pocIdx;
  while (vaVol < totalVol * 0.7 && (up < rows - 1 || dn > 0)) {
    final double upVol = up < rows - 1 ? binVol[up + 1] : -1;
    final double dnVol = dn > 0 ? binVol[dn - 1] : -1;
    if (upVol >= dnVol && up < rows - 1) {
      up++;
      vaVol += binVol[up];
    } else if (dn > 0) {
      dn--;
      vaVol += binVol[dn];
    } else {
      break;
    }
  }
  final double delta = buyVol - sellVol;
  return _VpScanProfile(
    poc: lo + pocIdx * step + step / 2,
    vah: lo + (up + 1) * step,
    val: lo + dn * step,
    deltaPct: totalVol > 0 ? delta / totalVol * 100 : 0,
    step: step,
  );
}

/// POC / VAH / VAL + step cua profile M15 (24 hang, lookback 200 nen).
/// De module tin hieu dung cho vpCore khi can POC.
/// Tra poc/vah/val = null khi khong co nen.
({double? poc, double? vah, double? val, double step}) vpLevels(
  List<Candle> m15,
) {
  final _VpScanProfile p = _vpScanProfile(m15, 24);
  return (poc: p.poc, vah: p.vah, val: p.val, step: p.step);
}

/// Quet nhanh 1 cap theo spec §10.5: profile M15 rieng (200 nen, 24 hang)
/// + trend Ichimoku H1 + Delta gan nhat (profile 20 nen, 8 hang).
/// - trend: gia tren may -> up, duoi may -> down, trong may -> neutral.
///   Chi dung fallback EMA20 H1 so voi gia khi H1 khong du 52 nen de tinh
///   day du Ichimoku (SenkouB can 52 nen); EMA20 cung khong co -> neutral.
/// - nearPoc = |price - POC| <= step x 1.5 (step = (hi-lo)/24).
/// - Diem (toi da 5): trend != neutral +2; nearPoc +2; Delta gan nhat
///   cung dau xu huong +1.
/// - action = trend up -> BUY, down -> SELL, neutral -> WAIT;
///   score < 3 -> WAIT.
/// Khong sinh so gia: thieu nen thi POC/Delta = null, diem thap -> WAIT.
VpScanResult vpScanFor({
  required List<Candle> m15,
  required List<Candle> h1,
  required double price,
}) {
  final _VpScanProfile prof = _vpScanProfile(m15, 24);

  String trend = 'neutral';
  if (h1.length >= 52) {
    final double tenkan = _donchianMid(h1, 9);
    final double kijun = _donchianMid(h1, 26);
    final double senkouA = (tenkan + kijun) / 2;
    final double senkouB = _donchianMid(h1, 52);
    final double kumoTop = max(senkouA, senkouB);
    final double kumoBot = min(senkouA, senkouB);
    if (price > kumoTop) {
      trend = 'up';
    } else if (price < kumoBot) {
      trend = 'down';
    } else {
      trend = 'neutral';
    }
  } else {
    // Fallback: EMA20 H1 so voi gia.
    final List<double?> e20 = ema(h1.map((Candle c) => c.c).toList(), 20);
    double? ema20;
    for (int i = e20.length - 1; i >= 0; i--) {
      if (e20[i] != null) {
        ema20 = e20[i];
        break;
      }
    }
    if (ema20 != null) {
      if (price > ema20) {
        trend = 'up';
      } else if (price < ema20) {
        trend = 'down';
      }
    }
  }

  // Delta gan nhat: profile 20 nen M15 gan nhat, 8 hang.
  final List<Candle> recent20 =
      m15.length > 20 ? m15.sublist(m15.length - 20) : m15;
  final _VpScanProfile recent = _vpScanProfile(recent20, 8);
  final double? deltaPct = recent.deltaPct;

  final bool nearPoc = prof.poc != null && prof.step > 0
      ? (price - prof.poc!).abs() <= prof.step * 1.5
      : prof.poc != null && price == prof.poc;

  int score = 0;
  if (trend != 'neutral') score += 2;
  if (nearPoc) score += 2;
  if (deltaPct != null) {
    if ((trend == 'up' && deltaPct > 0) ||
        (trend == 'down' && deltaPct < 0)) {
      score += 1;
    }
  }

  String action;
  if (trend == 'up') {
    action = 'BUY';
  } else if (trend == 'down') {
    action = 'SELL';
  } else {
    action = 'WAIT';
  }
  if (score < 3) action = 'WAIT';

  return VpScanResult(
    action: action,
    score: score,
    poc: prof.poc,
    vah: prof.vah,
    val: prof.val,
    deltaPct: deltaPct,
    h1Trend: trend,
    nearPoc: nearPoc,
    price: price,
  );
}
