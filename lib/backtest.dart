// Backtest — chay tren series nen THAT da tai (khong sinh nen gia).
// Port spec-web §12. Chi dung nen da dong (bo phan tu cuoi = nen dang chay).
// Khong tinh phi / truot gia. Khong bao gio bia so: thieu nen thi tra
// BacktestResult.error, khong sinh lenh gia.
//
// QUAN TRONG — phu thuoc song song:
// File nay import RawCandle tu lib/market_data.dart va IndicatorParams +
// cac ham chi bao (emaLast/rsiLast/atrLast/macdSeries) tu
// lib/indicators.dart. Ichimoku + Volume Profile gon thi tu viet trong
// file nay tren RawCandle (indicators.dart khong co 2 ham nay).
// Backtest KHONG import engine.dart (tranh phu thuoc vong tron).
import 'dart:isolate';
import 'dart:math';

import 'indicators.dart';
import 'market_data.dart';
import 'safe_json.dart';

/// Ghi chu bat buoc hien thi kem ket qua backtest (spec §12.2).
const String btPastDisclaimer =
    'Kết quả quá khứ không đảm bảo kết quả tương lai';

/// Số nến đã đóng tối thiểu để chạy backtest (dưới mức này thì trả lỗi,
/// không sinh lệnh giả).
const int kMinBacktestCandles = 90;

/// Phuong phap giao dich do nguoi dung dat ten + ghi chu quy tac.
/// CHI LU ten + mo ta + chien luoc engine chay — trang/app CHUA tu chuyen
// van ban tu do thanh quy tac chay duoc (spec §12.3): engine van chay theo
// [strategy] da chon cung thong so chi bao hien tai.
class BtMethod {
  String name;
  String desc;
  String strategy; // 'swing' | 'volumebs' | 'ai'

  BtMethod({required this.name, required this.desc, required this.strategy});

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'name': name, 'desc': desc, 'strategy': strategy};

  factory BtMethod.fromJson(Map<String, dynamic> json) => BtMethod(
        name: strOf(json['name']),
        desc: strOf(json['desc']),
        strategy: strOf(json['strategy'], 'swing'),
      );
}

class BtTrade {
  final String symbol;
  final String action; // 'BUY' | 'SELL'
  final String result; // 'win' | 'loss'
  final double entry;
  final double sl;
  final double tp;
  final double exit;
  final double r;
  final int openAt; // epoch ms, thoi gian mo nen vao lenh
  final int closeAt; // epoch ms, thoi gian dong nen dong lenh
  final String note; // 'Chạm TP' | 'Chạm SL' | 'Đóng hết hạn giữ (120 nến)'

  const BtTrade({
    required this.symbol,
    required this.action,
    required this.result,
    required this.entry,
    required this.sl,
    required this.tp,
    required this.exit,
    required this.r,
    required this.openAt,
    required this.closeAt,
    required this.note,
  });
}

class BacktestResult {
  /// Toan bo lenh theo thu tu thoi gian (cu -> moi). UI cat lay toi da
  /// 80 lenh gan nhat (moi nhat len dau) khi hien thi (spec §12.2).
  final List<BtTrade> trades;
  final int wins;
  final int losses;
  final double winRate; // % (0 khi khong co lenh)
  /// Sigma R thang / Sigma |R thua|. double.infinity khi khong co lenh
  /// thua ma co R thang (UI hien "∞"); double.nan khi khong co R thang
  /// (UI hien "—").
  final double profitFactor;
  /// R thang TB / |R thua TB|; double.nan khi thieu mot phia (UI hien "—").
  final double avgRealRr;
  final double avgR;
  final double maxDrawdownR;
  final double totalR;
  final String methodName;
  final String strategyUsed;
  final int candleCount; // so nen da dong dung de test
  /// Số nến đã đóng thực sự được quét (candleCount - startI, với
  /// startI = max(80, candleCount - range)); 0 khi lỗi.
  final int testedCandles;
  /// != null khi chua du nen (hoac chien luoc khong ho tro): khong co lenh.
  final String? error;

  const BacktestResult({
    required this.trades,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.profitFactor,
    required this.avgRealRr,
    required this.avgR,
    required this.maxDrawdownR,
    required this.totalR,
    required this.methodName,
    required this.strategyUsed,
    required this.candleCount,
    required this.testedCandles,
    this.error,
  });

  /// Kết quả lỗi (chưa đủ nến / chiến lược không hỗ trợ / tải nến thất
  /// bại): không có lệnh, [testedCandles] = 0, UI hiện [error] trong
  /// khung kết quả thay vì crash.
  factory BacktestResult.error({
    required String methodName,
    required String strategyUsed,
    required int candleCount,
    required String error,
  }) {
    return BacktestResult(
      trades: const <BtTrade>[],
      wins: 0,
      losses: 0,
      winRate: 0,
      profitFactor: double.nan,
      avgRealRr: double.nan,
      avgR: 0,
      maxDrawdownR: 0,
      totalR: 0,
      methodName: methodName,
      strategyUsed: strategyUsed,
      candleCount: candleCount,
      testedCandles: 0,
      error: error,
    );
  }
}

// ---------------------------------------------------------------------------
// EMA/RSI/ATR/MACD lay tu lib/indicators.dart (emaLast/rsiLast/atrLast/
// macdSeries — cong thuc spec §13.2). Chi Ichimoku + Profile gon la
// tu viet o day vi indicators.dart khong co 2 ham nay.
// ---------------------------------------------------------------------------

/// Gia tri non-null cuoi cung cua mot chuoi chi bao (null neu chua co).
double? _lastNonNull(List<double?> values) {
  for (int i = values.length - 1; i >= 0; i--) {
    if (values[i] != null) return values[i];
  }
  return null;
}

double _donchianMidRaw(List<RawCandle> cs, int period) {
  if (cs.isEmpty) return 0;
  final List<RawCandle> tail =
      cs.length > period ? cs.sublist(cs.length - period) : cs;
  double hi = tail.first.h;
  double lo = tail.first.l;
  for (final RawCandle c in tail) {
    if (c.h > hi) hi = c.h;
    if (c.l < lo) lo = c.l;
  }
  return (hi + lo) / 2;
}

/// Ichimoku tren RawCandle: 'up' (gia tren may) / 'down' (duoi may) /
/// 'neutral' (trong may). null khi khong du 52 nen cho SenkouB.
String? _ichiTrendRaw(List<RawCandle> cs) {
  if (cs.length < 52) return null;
  final double tenkan = _donchianMidRaw(cs, 9);
  final double kijun = _donchianMidRaw(cs, 26);
  final double senkouA = (tenkan + kijun) / 2;
  final double senkouB = _donchianMidRaw(cs, 52);
  final double top = max(senkouA, senkouB);
  final double bot = min(senkouA, senkouB);
  final double price = cs.last.c;
  if (price > top) return 'up';
  if (price < bot) return 'down';
  return 'neutral';
}

/// Profile gon tren RawCandle (24 hang, lookback toi da 200 nen):
/// chia volume theo bin chua GIA DONG (giong volume_profile.dart),
/// POC = bin volume lon nhat, VAH/VAL = vung gia tri 70% mo rong tu POC.
/// Tra null khi khong du nen.
({double? poc, double? vah, double? val, double step}) _btProfile(
  List<RawCandle> cs,
) {
  const int rows = 24;
  final List<RawCandle> lookback =
      cs.length > 200 ? cs.sublist(cs.length - 200) : cs;
  if (lookback.isEmpty) {
    return (poc: null, vah: null, val: null, step: 0);
  }
  double lo = lookback.first.l;
  double hi = lookback.first.h;
  for (final RawCandle c in lookback) {
    if (c.l < lo) lo = c.l;
    if (c.h > hi) hi = c.h;
  }
  final double span = hi - lo;
  if (span <= 0) {
    return (poc: lo, vah: hi, val: lo, step: 0);
  }
  final double step = span / rows;
  final List<double> binVol = List<double>.filled(rows, 0);
  double totalVol = 0;
  for (final RawCandle c in lookback) {
    final double v = c.v <= 0 ? 1 : c.v;
    final int idx = ((c.c - lo) / step).floor().clamp(0, rows - 1);
    binVol[idx] += v;
    totalVol += v;
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
  return (
    poc: lo + pocIdx * step + step / 2,
    vah: lo + (up + 1) * step,
    val: lo + dn * step,
    step: step,
  );
}

BacktestResult _errorResult({
  required String symbol,
  required String strategy,
  required String methodName,
  required int candleCount,
  required String error,
}) {
  return BacktestResult.error(
    methodName: methodName,
    strategyUsed: strategy,
    candleCount: candleCount,
    error: error,
  );
}

/// Chay backtest tren series nen that [candles] (da bao gom ca nen dang
/// chay o cuoi — ham tu bo no, chi test nen da dong).
/// - [tf]: khung cua series (chi de ghi nhan / hien thi; series da duoc
///   chon theo khung nay truoc khi goi ham).
/// - [range]: so nen test toi da (startI = max(80, closed.length - range)).
/// - [strategy]: 'swing' | 'volumebs' | 'ai'.
/// - [ind]: thong so chi bao hien tai (EMA/MACD/RSI/ATR/SL-TP).
BacktestResult runBacktest({
  required String symbol,
  required List<RawCandle> candles,
  required String tf,
  required int range,
  required String strategy,
  required IndicatorParams ind,
  required String methodName,
}) {
  // Chi dung nen da dong.
  final List<RawCandle> closed =
      candles.length > 1 ? candles.sublist(0, candles.length - 1) : <RawCandle>[];
  if (closed.length < kMinBacktestCandles) {
    return _errorResult(
      symbol: symbol,
      strategy: strategy,
      methodName: methodName,
      candleCount: closed.length,
      error: 'Chưa đủ nến $symbol ($tf) — có ${closed.length} nến đã đóng, '
          'cần tối thiểu ~$kMinBacktestCandles nến. Hãy thử khung khác hoặc chờ tải xong.',
    );
  }
  if (strategy != 'swing' && strategy != 'volumebs' && strategy != 'ai') {
    return _errorResult(
      symbol: symbol,
      strategy: strategy,
      methodName: methodName,
      candleCount: closed.length,
      error: 'Chiến lược không hỗ trợ: $strategy.',
    );
  }
  // Range kẹp tối đa 2000 nến (kMaxBacktestCandles): chạy được trên toàn
  // bộ lịch sử đã tải, không giới hạn ngầm ở ~300 như trước.
  final int safeRange = range.clamp(1, kMaxBacktestCandles);
  final int startI = max(80, closed.length - safeRange);
  final int testedCandles = closed.length - startI;

  final List<BtTrade> trades = <BtTrade>[];
  int i = startI;
  while (i < closed.length) {
    final List<RawCandle> sub = closed.sublist(0, i + 1);
    final List<double> closes =
        sub.map((RawCandle c) => c.c).toList();
    final double? eF = emaLast(closes, ind.emaFast);
    final double? eS = emaLast(closes, ind.emaSlow);
    final double? atr = atrLast(sub, ind.atrPeriod);
    final double? rsi = rsiLast(closes, ind.rsiSig);
    final double entry = closed[i].c;

    // Thieu EMA/ATR (chua du nen cho chu ky tuy chinh) thi khong co
    // tin hieu o nen nay — bo qua, khong bia so.
    if (eF == null || eS == null || atr == null || atr <= 0) {
      i++;
      continue;
    }
    final double atrVal = atr;

    String? action; // 'BUY' | 'SELL' | null = khong co tin hieu
    {
      if (strategy == 'swing' || strategy == 'ai') {
        // Swing: KHONG dung bias H4 trong backtest (spec §12.1).
        if (eF > eS && (rsi == null || rsi < 78)) {
          action = 'BUY';
        } else if (eF < eS && (rsi == null || rsi > 22)) {
          action = 'SELL';
        }
        if (strategy == 'ai' && action != null) {
          // AI: loai tin hieu neu MACD hoac Ichimoku nguoc huong.
          final MacdResult macd =
              macdSeries(sub, ind.macdF, ind.macdS, ind.macdSig);
          final double? macdLine = _lastNonNull(macd.line);
          final double? macdSignal = _lastNonNull(macd.signal);
          bool filtered = false;
          if (macdLine != null && macdSignal != null) {
            if (action == 'BUY' && macdLine < macdSignal) {
              filtered = true;
            }
            if (action == 'SELL' && macdLine > macdSignal) {
              filtered = true;
            }
          }
          if (!filtered) {
            final String? ichi = _ichiTrendRaw(
              sub.length > 220 ? sub.sublist(sub.length - 220) : sub,
            );
            if (action == 'BUY' && ichi == 'down') filtered = true;
            if (action == 'SELL' && ichi == 'up') filtered = true;
          }
          if (filtered) action = null;
        }
      } else if (strategy == 'volumebs') {
        // VolumeB/S: profile kieu M15 tren chinh series khung test +
        // Ichimoku tren sub.slice(-220). Vao khi trend Ichimoku cung
        // huong va (gan POC hoac pha VAH/VAL).
        final String? ichi = _ichiTrendRaw(
          sub.length > 220 ? sub.sublist(sub.length - 220) : sub,
        );
        if (ichi == 'up' || ichi == 'down') {
          final ({double? poc, double? vah, double? val, double step})
              prof = _btProfile(sub);
          final double nearThresh =
              max(prof.step * 1.5, atrVal * 0.6);
          final bool nearPoc = prof.poc != null &&
              (entry - prof.poc!).abs() <= nearThresh;
          if (ichi == 'up' &&
              (nearPoc || (prof.vah != null && entry > prof.vah!))) {
            action = 'BUY';
          } else if (ichi == 'down' &&
              (nearPoc || (prof.val != null && entry < prof.val!))) {
            action = 'SELL';
          }
        }
      }
    }

    if (action == null) {
      i++;
      continue;
    }

    final double sl = action == 'BUY'
        ? entry - ind.slMult * atrVal
        : entry + ind.slMult * atrVal;
    final double tp = action == 'BUY'
        ? entry + ind.tpMult * atrVal
        : entry - ind.tpMult * atrVal;
    final double dist = (entry - sl).abs();
    if (dist <= 0) {
      i++;
      continue;
    }

    // Duyet nen sau i+1..min(len-1, i+120) de dong lenh.
    final int lastIdx = min(closed.length - 1, i + 120);
    double exit = closed[lastIdx].c;
    int exitIdx = lastIdx;
    String note = 'Đóng hết hạn giữ (120 nến)';
    bool closedByLevel = false;
    for (int j = i + 1; j <= lastIdx; j++) {
      final RawCandle cj = closed[j];
      if (action == 'BUY') {
        // Cham ca SL lan TP trong 1 nen thi tinh SL truoc.
        if (cj.l <= sl) {
          exit = sl;
          exitIdx = j;
          note = 'Chạm SL';
          closedByLevel = true;
          break;
        }
        if (cj.h >= tp) {
          exit = tp;
          exitIdx = j;
          note = 'Chạm TP';
          closedByLevel = true;
          break;
        }
      } else {
        if (cj.h >= sl) {
          exit = sl;
          exitIdx = j;
          note = 'Chạm SL';
          closedByLevel = true;
          break;
        }
        if (cj.l <= tp) {
          exit = tp;
          exitIdx = j;
          note = 'Chạm TP';
          closedByLevel = true;
          break;
        }
      }
    }
    if (!closedByLevel) {
      // Het han giu 120 nen: dong theo gia dong nen het han.
      exit = closed[exitIdx].c;
      note = 'Đóng hết hạn giữ (120 nến)';
    }

    final double r = action == 'BUY'
        ? (exit - entry) / dist
        : (entry - exit) / dist;
    trades.add(BtTrade(
      symbol: symbol,
      action: action,
      result: r > 0 ? 'win' : 'loss',
      entry: entry,
      sl: sl,
      tp: tp,
      exit: exit,
      r: r,
      openAt: closed[i].t,
      closeAt: closed[exitIdx].t,
      note: note,
    ));
    // Khong vao lenh chong: lenh tiep theo chi xet tu nen sau nen dong.
    i = exitIdx + 1;
  }

  int wins = 0;
  int losses = 0;
  double sumWinR = 0;
  double sumLossAbsR = 0;
  double totalR = 0;
  for (final BtTrade t in trades) {
    totalR += t.r;
    if (t.result == 'win') {
      wins++;
      sumWinR += t.r;
    } else {
      losses++;
      sumLossAbsR += t.r.abs();
    }
  }
  final double winRate =
      trades.isNotEmpty ? wins / trades.length * 100 : 0;
  final double profitFactor;
  if (sumWinR <= 0) {
    profitFactor = double.nan; // UI hien "—"
  } else if (sumLossAbsR <= 0) {
    profitFactor = double.infinity; // UI hien "∞"
  } else {
    profitFactor = sumWinR / sumLossAbsR;
  }
  final double avgWinR = wins > 0 ? sumWinR / wins : double.nan;
  final double avgLossAbsR =
      losses > 0 ? sumLossAbsR / losses : double.nan;
  final double avgRealRr = (avgWinR.isNaN || avgLossAbsR.isNaN)
      ? double.nan
      : avgWinR / avgLossAbsR;
  final double avgR = trades.isNotEmpty ? totalR / trades.length : 0;

  // Max drawdown theo R: do sut equity tich luy R lon nhat tu dinh.
  double equity = 0;
  double peak = 0;
  double maxDd = 0;
  for (final BtTrade t in trades) {
    equity += t.r;
    if (equity > peak) peak = equity;
    final double dd = peak - equity;
    if (dd > maxDd) maxDd = dd;
  }

  return BacktestResult(
    trades: trades,
    wins: wins,
    losses: losses,
    winRate: winRate,
    profitFactor: profitFactor,
    avgRealRr: avgRealRr,
    avgR: avgR,
    maxDrawdownR: maxDd,
    totalR: totalR,
    methodName: methodName,
    strategyUsed: strategy,
    candleCount: closed.length,
    testedCandles: testedCandles,
  );
}

/// Chạy backtest trên isolate riêng để UI không đơ khi test tới 2000 nến
/// (vòng lặp chính quét lại các chỉ báo trên toàn bộ sub-series mỗi lần
/// xét nến — O(n²) — chạy đồng bộ trên UI thread sẽ khựng vài trăm ms).
/// RawCandle / IndicatorParams / BacktestResult chỉ chứa số + chuỗi nên
/// gửi qua isolate được. Lỗi trong isolate sẽ ném lại cho caller
/// (UI bắt và hiện trong khung kết quả).
Future<BacktestResult> runBacktestAsync({
  required String symbol,
  required List<RawCandle> candles,
  required String tf,
  required int range,
  required String strategy,
  required IndicatorParams ind,
  required String methodName,
}) {
  return Isolate.run(() => runBacktest(
        symbol: symbol,
        candles: candles,
        tf: tf,
        range: range,
        strategy: strategy,
        ind: ind,
        methodName: methodName,
      ));
}
