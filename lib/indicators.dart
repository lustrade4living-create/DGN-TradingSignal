// indicators.dart — Chỉ báo kỹ thuật cho TradeSignal AI (port spec §13).
//
// Công thức theo đúng spec §13.2 của bản web:
//   - EMA: hạt giống SMA tại index period-1, k = 2/(period+1).
//   - RSI: TRUNG BÌNH ĐƠN GIẢN (không phải Wilder smoothing).
//   - ATR: trung bình đơn giản của True Range.
//   - MACD: line = EMA(fast) - EMA(slow); signal = EMA(line hợp lệ, sig).
//
// Lưu ý theo spec §13.4: ema200 và Bollinger (bbPeriod/bbMult) ở bản web
// CHỈ LƯU TRỮ — web không dùng chúng trong bất kỳ công thức hay hình vẽ
// nào. File này vẫn cung cấp hàm Bollinger sẵn để dùng khi cần, nhưng
// KHÔNG tự ý đưa ema200/Bollinger vào tín hiệu.
library;

import 'dart:math' as math;

import 'market_data.dart';

/// Thông số chỉ báo tùy chỉnh (spec §13.1).
/// Mặc định + giới hạn min-max đúng bảng IND_DEFAULT của web.
class IndicatorParams {
  final int emaFast;
  final int emaSlow;
  final int ema34;
  final int ema200;
  final int macdF;
  final int macdS;
  final int macdSig;
  final int rsiChart;
  final int rsiSig;
  final int atrPeriod;
  final double slMult;
  final double tpMult;
  final int bbPeriod;
  final double bbMult;

  const IndicatorParams({
    this.emaFast = 20,
    this.emaSlow = 50,
    this.ema34 = 34,
    this.ema200 = 200,
    this.macdF = 34,
    this.macdS = 58,
    this.macdSig = 12,
    this.rsiChart = 9,
    this.rsiSig = 14,
    this.atrPeriod = 14,
    this.slMult = 1.5,
    this.tpMult = 3.0,
    this.bbPeriod = 20,
    this.bbMult = 2.0,
  });

  static const IndicatorParams defaults = IndicatorParams();

  /// RR kế hoạch = tpMult / slMult (mặc định 3.0 / 1.5 = 1 : 2.0).
  double get rr => tpMult / slMult;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'emaFast': emaFast,
        'emaSlow': emaSlow,
        'ema34': ema34,
        'ema200': ema200,
        'macdF': macdF,
        'macdS': macdS,
        'macdSig': macdSig,
        'rsiChart': rsiChart,
        'rsiSig': rsiSig,
        'atrPeriod': atrPeriod,
        'slMult': slMult,
        'tpMult': tpMult,
        'bbPeriod': bbPeriod,
        'bbMult': bbMult,
      };

  /// Chỉ nhận key có trong mặc định, số hữu hạn, clamp vào min-max
  /// (spec §13.3: loadIndSettings). Key lạ / giá trị không hợp lệ bị bỏ qua.
  factory IndicatorParams.fromJson(Map<String, dynamic> json) {
    int i(String key, int def, int min, int max) {
      final Object? v = json[key];
      if (v is num && v.isFinite) {
        return v.round().clamp(min, max);
      }
      return def;
    }

    double d(String key, double def, double min, double max) {
      final Object? v = json[key];
      if (v is num && v.isFinite) {
        return v.toDouble().clamp(min, max);
      }
      return def;
    }

    return IndicatorParams(
      emaFast: i('emaFast', 20, 2, 400),
      emaSlow: i('emaSlow', 50, 3, 400),
      ema34: i('ema34', 34, 2, 400),
      ema200: i('ema200', 200, 10, 400),
      macdF: i('macdF', 34, 2, 200),
      macdS: i('macdS', 58, 3, 300),
      macdSig: i('macdSig', 12, 2, 100),
      rsiChart: i('rsiChart', 9, 2, 50),
      rsiSig: i('rsiSig', 14, 2, 50),
      atrPeriod: i('atrPeriod', 14, 2, 60),
      slMult: d('slMult', 1.5, 0.3, 6),
      tpMult: d('tpMult', 3.0, 0.5, 12),
      bbPeriod: i('bbPeriod', 20, 5, 100),
      bbMult: d('bbMult', 2.0, 0.5, 5),
    );
  }

  IndicatorParams copyWith({
    int? emaFast,
    int? emaSlow,
    int? ema34,
    int? ema200,
    int? macdF,
    int? macdS,
    int? macdSig,
    int? rsiChart,
    int? rsiSig,
    int? atrPeriod,
    double? slMult,
    double? tpMult,
    int? bbPeriod,
    double? bbMult,
  }) {
    return IndicatorParams(
      emaFast: (emaFast ?? this.emaFast).clamp(2, 400),
      emaSlow: (emaSlow ?? this.emaSlow).clamp(3, 400),
      ema34: (ema34 ?? this.ema34).clamp(2, 400),
      ema200: (ema200 ?? this.ema200).clamp(10, 400),
      macdF: (macdF ?? this.macdF).clamp(2, 200),
      macdS: (macdS ?? this.macdS).clamp(3, 300),
      macdSig: (macdSig ?? this.macdSig).clamp(2, 100),
      rsiChart: (rsiChart ?? this.rsiChart).clamp(2, 50),
      rsiSig: (rsiSig ?? this.rsiSig).clamp(2, 50),
      atrPeriod: (atrPeriod ?? this.atrPeriod).clamp(2, 60),
      slMult: (slMult ?? this.slMult).clamp(0.3, 6),
      tpMult: (tpMult ?? this.tpMult).clamp(0.5, 12),
      bbPeriod: (bbPeriod ?? this.bbPeriod).clamp(5, 100),
      bbMult: (bbMult ?? this.bbMult).clamp(0.5, 5),
    );
  }
}

/// EMA trên toàn bộ series (spec §13.2).
/// Hạt giống = SMA của `period` giá đầu tiên tại index period-1,
/// sau đó e = price * k + e * (1-k), k = 2/(period+1).
/// Cần values.length >= period, ngược lại toàn null.
List<double?> emaSeries(List<double> values, int period) {
  final List<double?> out =
      List<double?>.filled(values.length, null, growable: false);
  if (period < 1 || values.length < period) {
    return out;
  }
  double sum = 0;
  for (int i = 0; i < period; i++) {
    sum += values[i];
  }
  double prev = sum / period;
  out[period - 1] = prev;
  final double k = 2 / (period + 1);
  for (int i = period; i < values.length; i++) {
    prev = values[i] * k + prev * (1 - k);
    out[i] = prev;
  }
  return out;
}

/// Giá trị EMA cuối cùng; null nếu không đủ nến (length < period).
double? emaLast(List<double> values, int period) {
  if (values.length < period) return null;
  return emaSeries(values, period).last;
}

/// RSI theo TRUNG BÌNH ĐƠN GIẢN — KHÔNG phải Wilder (spec §13.2).
/// gain/loss trên `period` chênh lệch gần nhất; loss == 0 -> 100;
/// RSI = 100 - 100/(1+rs), rs = (gain/period)/(loss/period).
/// Cần length >= period+1, ngược lại null.
double? rsiLast(List<double> values, int period) {
  if (period < 1 || values.length < period + 1) {
    return null;
  }
  double gain = 0;
  double loss = 0;
  for (int i = values.length - period; i < values.length; i++) {
    final double d = values[i] - values[i - 1];
    if (d > 0) {
      gain += d;
    } else {
      loss += -d;
    }
  }
  if (loss == 0) return 100;
  final double rs = (gain / period) / (loss / period);
  return 100 - 100 / (1 + rs);
}

/// RSI (trung bình đơn giản) trên toàn bộ series.
/// Index < period là null; giá trị đầu tiên có tại index == period.
List<double?> rsiSeries(List<double> closes, int period) {
  final List<double?> out =
      List<double?>.filled(closes.length, null, growable: false);
  if (period < 1 || closes.length < period + 1) {
    return out;
  }
  for (int i = period; i < closes.length; i++) {
    double gain = 0;
    double loss = 0;
    for (int j = i - period + 1; j <= i; j++) {
      final double d = closes[j] - closes[j - 1];
      if (d > 0) {
        gain += d;
      } else {
        loss += -d;
      }
    }
    if (loss == 0) {
      out[i] = 100;
    } else {
      final double rs = (gain / period) / (loss / period);
      out[i] = 100 - 100 / (1 + rs);
    }
  }
  return out;
}

/// True Range của nến [i] so với nến trước:
/// max(h-l, |h-prevClose|, |l-prevClose|).
double _trueRange(List<RawCandle> cs, int i) {
  final RawCandle c = cs[i];
  final double prevClose = cs[i - 1].c;
  return math.max(
    c.h - c.l,
    math.max((c.h - prevClose).abs(), (c.l - prevClose).abs()),
  );
}

/// ATR theo trung bình đơn giản của True Range (spec §13.2).
/// Trung bình trên `period` nến gần nhất; cần length >= period+1.
double? atrLast(List<RawCandle> cs, int period) {
  if (period < 1 || cs.length < period + 1) {
    return null;
  }
  double sum = 0;
  for (int i = cs.length - period; i < cs.length; i++) {
    sum += _trueRange(cs, i);
  }
  return sum / period;
}

/// Kết quả MACD: line / signal / hist (cùng độ dài với số nến đầu vào,
/// null ở các vị trí chưa đủ dữ liệu).
class MacdResult {
  final List<double?> line;
  final List<double?> signal;
  final List<double?> hist;

  const MacdResult({
    required this.line,
    required this.signal,
    required this.hist,
  });
}

/// MACD (spec §13.2): line = EMA(fast) - EMA(slow);
/// signal = EMA(line hợp lệ, sig) tính trên các giá trị line không null;
/// hist = line - signal.
/// Web ghi: cần trên macdS + macdSig + 2 nến mới đủ hiển thị đầy đủ.
MacdResult macdSeries(List<RawCandle> cs, int fast, int slow, int sig) {
  final int n = cs.length;
  final List<double> closes = cs.map((c) => c.c).toList(growable: false);
  final List<double?> emaFast = emaSeries(closes, fast);
  final List<double?> emaSlow = emaSeries(closes, slow);
  final List<double?> line =
      List<double?>.filled(n, null, growable: false);
  for (int i = 0; i < n; i++) {
    final double? f = emaFast[i];
    final double? s = emaSlow[i];
    if (f != null && s != null) {
      line[i] = f - s;
    }
  }
  // Signal: EMA(sig) trên các giá trị line hợp lệ, giữ nguyên vị trí index.
  final List<double> validLine = <double>[];
  final List<int> validIdx = <int>[];
  for (int i = 0; i < n; i++) {
    final double? v = line[i];
    if (v != null) {
      validLine.add(v);
      validIdx.add(i);
    }
  }
  final List<double?> sigOnValid = emaSeries(validLine, sig);
  final List<double?> signal =
      List<double?>.filled(n, null, growable: false);
  for (int j = 0; j < validIdx.length; j++) {
    signal[validIdx[j]] = sigOnValid[j];
  }
  final List<double?> hist =
      List<double?>.filled(n, null, growable: false);
  for (int i = 0; i < n; i++) {
    final double? l = line[i];
    final double? s = signal[i];
    if (l != null && s != null) {
      hist[i] = l - s;
    }
  }
  return MacdResult(line: line, signal: signal, hist: hist);
}

/// Kết quả Bollinger: middle (SMA), upper, lower (cùng độ dài đầu vào,
/// null ở các vị trí chưa đủ `period` nến).
class BollingerResult {
  final List<double?> upper;
  final List<double?> middle;
  final List<double?> lower;

  const BollingerResult({
    required this.upper,
    required this.middle,
    required this.lower,
  });
}

/// Bollinger Bands: SMA ± mult * độ lệch chuẩn (mẫu, chia cho period).
/// GHI CHÚ (spec §13.4): bản web chỉ LƯU TRỮ bbPeriod/bbMult, không vẽ
/// và không dùng Bollinger trong tín hiệu. Hàm này cung cấp sẵn để dùng
/// khi cần, không tự ý đưa vào công thức tín hiệu.
BollingerResult bollinger(
  List<double> closes,
  int period,
  double mult,
) {
  final int n = closes.length;
  final List<double?> upper =
      List<double?>.filled(n, null, growable: false);
  final List<double?> middle =
      List<double?>.filled(n, null, growable: false);
  final List<double?> lower =
      List<double?>.filled(n, null, growable: false);
  if (period < 1 || n < period) {
    return BollingerResult(upper: upper, middle: middle, lower: lower);
  }
  for (int i = period - 1; i < n; i++) {
    double sum = 0;
    for (int j = i - period + 1; j <= i; j++) {
      sum += closes[j];
    }
    final double sma = sum / period;
    double sq = 0;
    for (int j = i - period + 1; j <= i; j++) {
      final double d = closes[j] - sma;
      sq += d * d;
    }
    final double sd = math.sqrt(sq / period);
    middle[i] = sma;
    upper[i] = sma + mult * sd;
    lower[i] = sma - mult * sd;
  }
  return BollingerResult(upper: upper, middle: middle, lower: lower);
}

/// Kích thước 1 pip của từng cặp (spec §3.4).
double pipSize(String symbol) {
  switch (symbol) {
    case 'BTCUSD':
      return 1;
    case 'XAUUSD':
      return 0.1;
    case 'USOIL':
    case 'USDJPY':
      return 0.01;
    default:
      return 0.0001;
  }
}
