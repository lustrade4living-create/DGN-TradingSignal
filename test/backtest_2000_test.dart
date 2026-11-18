// Backtest tối đa 2000 nến (task 18/11) — smoke test không cần mạng.
// Nến mẫu sinh sẵn bằng code (Random có seed cố định): xu hướng lên
// + sóng sin để EMA cắt nhau và sinh lệnh, kèm nhiễu.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/backtest.dart';
import 'package:trade_signal_ai/indicators.dart';
import 'package:trade_signal_ai/market_data.dart';

/// Nến H1 mẫu: giá khởi điểm 100, drift dương + sin(i/25) để EMA
/// fast/slow cắt nhau nhiều lần, nhiễu nhỏ. [t] tăng đều 1 giờ/nến.
List<RawCandle> synthCandles(int n, {int seed = 42}) {
  final math.Random rnd = math.Random(seed);
  final List<RawCandle> out = <RawCandle>[];
  double price = 100.0;
  const int stepMs = 60 * 60 * 1000;
  const int t0 = 1700000000000;
  for (int i = 0; i < n; i++) {
    final double drift = 0.02 + 0.15 * math.sin(i / 25.0);
    final double chg = drift + (rnd.nextDouble() - 0.5) * 0.6;
    final double o = price;
    final double c = (price + chg).clamp(10.0, 10000.0);
    final double h = math.max(o, c) + rnd.nextDouble() * 0.2;
    final double l = math.min(o, c) - rnd.nextDouble() * 0.2;
    out.add(RawCandle(
      t: t0 + i * stepMs,
      o: o,
      h: h,
      l: l,
      c: c,
      v: 100 + rnd.nextDouble() * 50,
    ));
    price = c;
  }
  return out;
}

/// JSON giả dạng Yahoo chart v8 với [n] nến giờ (timestamp tăng 1h).
Map<String, dynamic> yahooJson(int n) {
  final List<int> ts = <int>[
    for (int i = 0; i < n; i++) 1700000000 + i * 3600,
  ];
  List<double> series(double base) =>
      <double>[for (int i = 0; i < n; i++) base + i * 0.1];
  return <String, dynamic>{
    'chart': <String, dynamic>{
      'result': <dynamic>[
        <String, dynamic>{
          'timestamp': ts,
          'indicators': <String, dynamic>{
            'quote': <dynamic>[
              <String, dynamic>{
                'open': series(100),
                'high': series(101),
                'low': series(99),
                'close': series(100.5),
                'volume': series(1000),
              },
            ],
          },
        },
      ],
      'error': null,
    },
  };
}

void main() {
  test('runBacktest chay duoc tren 2000 nen va ghi dung so nen da dung', () {
    final List<RawCandle> candles = synthCandles(2000);
    final BacktestResult r = runBacktest(
      symbol: 'XAUUSD',
      candles: candles,
      tf: 'H1',
      range: 2000,
      strategy: 'swing',
      ind: IndicatorParams.defaults,
      methodName: 'Test 2000',
    );
    expect(r.error, isNull);
    // 2000 nến tải về -> 1999 nến đã đóng; startI = max(80, 1999-2000)
    // = 80 -> quét 1999 - 80 = 1919 nến.
    expect(r.candleCount, 1999);
    expect(r.testedCandles, 1919);
    expect(r.methodName, 'Test 2000');
    expect(r.strategyUsed, 'swing');
    expect(r.winRate, inInclusiveRange(0, 100));
    expect(r.trades.length, greaterThan(0));
    expect(r.wins + r.losses, r.trades.length);
  });

  test('range kep toi da 2000 va range nho chi test dung so nen do', () {
    final List<RawCandle> candles = synthCandles(2000);
    final BacktestResult big = runBacktest(
      symbol: 'XAUUSD',
      candles: candles,
      tf: 'H1',
      range: 5000, // vượt trần -> kẹp về 2000
      strategy: 'swing',
      ind: IndicatorParams.defaults,
      methodName: 'Test',
    );
    expect(big.error, isNull);
    expect(big.testedCandles, 1919);

    final BacktestResult small = runBacktest(
      symbol: 'XAUUSD',
      candles: candles,
      tf: 'H1',
      range: 200,
      strategy: 'swing',
      ind: IndicatorParams.defaults,
      methodName: 'Test',
    );
    // startI = max(80, 1999-200) = 1799 -> quét đúng 200 nến.
    expect(small.testedCandles, 200);
    expect(small.candleCount, 1999);
  });

  test('duoi 90 nen da dong thi tra loi, khong crash', () {
    final BacktestResult r = runBacktest(
      symbol: 'XAUUSD',
      candles: synthCandles(50),
      tf: 'H1',
      range: 2000,
      strategy: 'swing',
      ind: IndicatorParams.defaults,
      methodName: 'Test',
    );
    expect(r.error, isNotNull);
    expect(r.error, contains('90'));
    expect(r.trades, isEmpty);
    expect(r.testedCandles, 0);
    expect(r.candleCount, 49); // 50 nến tải về -> 49 nến đã đóng
  });

  test('BacktestResult.error factory dung cho loi tai nen', () {
    final BacktestResult r = BacktestResult.error(
      methodName: 'M',
      strategyUsed: 'swing',
      candleCount: 0,
      error: 'Không tải được nến',
    );
    expect(r.error, 'Không tải được nến');
    expect(r.trades, isEmpty);
    expect(r.testedCandles, 0);
    expect(r.candleCount, 0);
  });

  test('runBacktestAsync (isolate) cho ket qua giong ban dong bo', () async {
    final List<RawCandle> candles = synthCandles(2000);
    final BacktestResult r = await runBacktestAsync(
      symbol: 'XAUUSD',
      candles: candles,
      tf: 'H1',
      range: 2000,
      strategy: 'swing',
      ind: IndicatorParams.defaults,
      methodName: 'Test 2000',
    );
    expect(r.error, isNull);
    expect(r.candleCount, 1999);
    expect(r.testedCandles, 1919);
    expect(r.trades.length, greaterThan(0));
  });

  group('logic phan trang (khong can mang)', () {
    test('Binance: endTime trang sau = nen cu nhat - 1ms (endTime bao ham)',
        () {
      expect(binanceNextEndTimeMs(1700000000000), 1699999999999);
      expect(binanceNextEndTimeMs(1700000000001), 1700000000000);
    });

    test('Kraken: since trang sau lui dung 1 trang 720 nen', () {
      // oldest 1700000000000 ms = 1700000000 s; H1: tru 720 * 3600 s.
      expect(
        krakenNextSinceSec(
            oldestCandleMs: 1700000000000, intervalMin: 60),
        1700000000 - 720 * 3600,
      );
      // M15: tru 720 * 15 * 60 s.
      expect(
        krakenNextSinceSec(
            oldestCandleMs: 1700000000000, intervalMin: 15),
        1700000000 - 720 * 15 * 60,
      );
    });

    test('Yahoo: range/interval lich su theo khung', () {
      final m5 = yahooHistoryRangeInterval('M5');
      expect((m5.range, m5.interval, m5.aggregateH4), ('60d', '5m', false));
      final m15 = yahooHistoryRangeInterval('M15');
      expect(
          (m15.range, m15.interval, m15.aggregateH4), ('60d', '15m', false));
      final h1 = yahooHistoryRangeInterval('H1');
      expect((h1.range, h1.interval, h1.aggregateH4), ('2y', '60m', false));
      final h4 = yahooHistoryRangeInterval('H4');
      expect((h4.range, h4.interval, h4.aggregateH4), ('2y', '60m', true));
      final d1 = yahooHistoryRangeInterval('D1');
      expect((d1.range, d1.interval, d1.aggregateH4), ('max', '1d', false));
      expect(() => yahooHistoryRangeInterval('M1'), throwsException);
    });
  });

  group('parseYahooChart ton trong maxCandles', () {
    test('mac dinh van cat 300 nen (giu hanh vi cu)', () {
      final List<RawCandle> out = CandleFetcher.parseYahooChart(
        yahooJson(301),
      );
      expect(out.length, 300);
      // Giữ 300 nến MỚI NHẤT.
      expect(out.first.t, (1700000000 + 1 * 3600) * 1000);
      expect(out.last.t, (1700000000 + 300 * 3600) * 1000);
    });

    test('maxCandles 2000 lay het khi it hon 2000; cat dung khi vuot', () {
      final List<RawCandle> all = CandleFetcher.parseYahooChart(
        yahooJson(5),
        maxCandles: 2000,
      );
      expect(all.length, 5);
      final List<RawCandle> cut = CandleFetcher.parseYahooChart(
        yahooJson(5),
        maxCandles: 3,
      );
      expect(cut.length, 3);
      expect(cut.last.t, (1700000000 + 4 * 3600) * 1000);
    });
  });
}
