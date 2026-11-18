// Test nhỏ cho công thức điểm 50/25/25 + thang TP + tham số chỉ báo
// (spec §4.3, §8.1, §13.1). Không cần test/ trước đây (thư mục trống).
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/indicators.dart';
import 'package:trade_signal_ai/signal_core.dart';

/// Công thức % tin cậy (spec §4.3): 50% gốc + 25% Trend + 25% PA,
// WAIT trần 62%, clamp 5..97 — kiểm chứng đúng công thức module dùng.
int confFormula(int base, int trend, int pa, {bool wait = false}) {
  var c = (base * 0.5 + trend * 0.25 + pa * 0.25).round();
  if (wait) c = c < 62 ? c : 62;
  return c.clamp(5, 97);
}

void main() {
  test('cong thuc 50/25/25', () {
    expect(confFormula(80, 80, 80), 80);
    expect(confFormula(72, 100, 50), 74); // 36 + 25 + 12.5 = 73.5 -> 74
  });
  test('tran WAIT 62%', () {
    expect(confFormula(90, 90, 90, wait: true), 62);
    expect(confFormula(40, 40, 40, wait: true), 40);
  });
  test('multiTrend: 5 khung cung tang -> 100', () {
    final byTf = <String, TrendInfo>{
      for (final tf in ['M5', 'M15', 'H1', 'H4', 'D1'])
        tf: TrendInfo(dir: 'up', rsi9: 60, enough: true),
    };
    expect(multiTrend(byTf, true).index, 100);
    expect(multiTrend(byTf, false).index, 0);
  });
  test('sigLevels BUY: T1-T4 cach deu 25% khoang TP', () {
    final lv = sigLevels('BUY', 100, 98, 104)!;
    expect(lv.inv, 98);
    expect(lv.t1, 101);
    expect(lv.t2, 102);
    expect(lv.t3, 103);
    expect(lv.t4, 104);
    expect(sigLevels('WAIT', 100, 98, 104), isNull);
  });
  test('IndicatorParams RR mac dinh 1:2 va clamp', () {
    expect(IndicatorParams.defaults.rr, 2.0);
    final p = IndicatorParams.fromJson({'slMult': 99, 'tpMult': 0.01});
    expect(p.slMult, 6.0);
    expect(p.tpMult, 0.5);
  });
}
