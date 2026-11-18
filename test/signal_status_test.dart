// Test phân loại trạng thái vào lệnh: VÀO NGAY (NOW) / CHỜ LIMIT /
// KHÔNG NÊN VÀO NỮA (EXPIRED) — xem lib/signal_status.dart.
// Ngưỡng: NOW trong Entry ±0,25×ATR hoặc giá tốt hơn Entry;
// LIMIT khi giá chạy xa theo hướng có lợi (>0,25×ATR) nhưng chưa quá
// 1,0×ATR và còn hiệu lực; EXPIRED khi chạm/vượt TP1, xa Entry quá
// 1,0×ATR, hoặc quá giờ hiệu lực. Ưu tiên: EXPIRED > NOW > LIMIT.
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/signal_core.dart';
import 'package:trade_signal_ai/signal_status.dart';

void main() {
  // Entry 100, ATR 2 → vùng NOW: 99,5–100,5; xa quá 1 ATR: ngoài 98–102.
  const double entry = 100;
  const double atr = 2;
  const int issuedAt = 1700000000000;
  final int expiryAt = signalExpiryMs(issuedAt);
  final int now = issuedAt + 10 * 60 * 1000; // còn 50 phút hiệu lực

  SignalStatusResult classify({
    String action = 'BUY',
    double? live,
    double? tp1,
    int atMs = 0,
  }) {
    return classifySignalStatus(
      action: action,
      entry: entry,
      tp1: tp1,
      atr: atr,
      livePrice: live,
      issuedAtMs: issuedAt,
      expiryAtMs: expiryAt,
      nowMs: issuedAt + atMs,
      pipSize: 0.01,
    );
  }

  test('NOW khi giá live trong Entry ±0,25 ATR', () {
    final r = classify(live: 100.4); // +0,2 ATR
    expect(r.status, SignalStatus.now);
    expect(r.label, contains('NOW'));
    expect(r.betterThanEntry, isFalse);
    expect(r.distPips, closeTo(40, 0.001)); // 0,4 / 0,01
  });

  test('NOW + nhãn giá tốt hơn Entry: BUY giá live < Entry', () {
    final r = classify(live: 99.0);
    expect(r.status, SignalStatus.now);
    expect(r.betterThanEntry, isTrue);
  });

  test('NOW + nhãn giá tốt hơn Entry: SELL giá live > Entry', () {
    final r = classify(action: 'SELL', live: 101.0);
    expect(r.status, SignalStatus.now);
    expect(r.betterThanEntry, isTrue);
  });

  test('LIMIT khi BUY giá đã chạy xa theo hướng có lợi', () {
    final r = classify(live: 101.0); // +0,5 ATR
    expect(r.status, SignalStatus.limit);
    expect(r.label, contains('LIMIT'));
    expect(r.betterThanEntry, isFalse);
  });

  test('LIMIT khi SELL giá đã chạy xa theo hướng có lợi', () {
    final r = classify(action: 'SELL', live: 99.0); // −0,5 ATR
    expect(r.status, SignalStatus.limit);
  });

  test('EXPIRED khi chạm TP1 (BUY live >= TP1)', () {
    final r = classify(live: 102.0, tp1: 102.0);
    expect(r.status, SignalStatus.expired);
  });

  test('EXPIRED khi vượt TP1 (SELL live <= TP1)', () {
    final r = classify(action: 'SELL', live: 97.5, tp1: 98.0);
    expect(r.status, SignalStatus.expired);
  });

  test('EXPIRED khi cách Entry quá 1,0 ATR', () {
    final r = classify(live: 102.5); // +1,25 ATR, chưa tới TP1 nào
    expect(r.status, SignalStatus.expired);
  });

  test('EXPIRED khi quá giờ hiệu lực dù giá đang tại Entry', () {
    final r = classify(live: 100.0, atMs: 3600000 + 1000);
    expect(r.status, SignalStatus.expired);
    expect(r.remainingMs, lessThan(0));
  });

  test('Biên ±0,25 ATR: đúng 0,25 ATR thì NOW, hơn 0,25 ATR thì LIMIT', () {
    expect(classify(live: 100.5).status, SignalStatus.now); // đúng +0,5 = 0,25 ATR
    expect(classify(live: 100.51).status, SignalStatus.limit);
  });

  test('Biên 1,0 ATR: đúng 1,0 ATR thì LIMIT, hơn 1,0 ATR thì EXPIRED', () {
    // TP1 mặc định (không truyền tp1) = Entry + 1 ATR = 102 nên giá 102
    // chạm TP1 trước — truyền tp1 xa ra để chỉ xét riêng biên 1,0 ATR.
    final atEdge = classifySignalStatus(
      action: 'BUY',
      entry: entry,
      tp1: 110.0,
      atr: atr,
      livePrice: 102.0,
      issuedAtMs: issuedAt,
      expiryAtMs: expiryAt,
      nowMs: now,
      pipSize: 0.01,
    );
    expect(atEdge.status, SignalStatus.limit);
    final beyond = classifySignalStatus(
      action: 'BUY',
      entry: entry,
      tp1: 110.0,
      atr: atr,
      livePrice: 102.01,
      issuedAtMs: issuedAt,
      expiryAtMs: expiryAt,
      nowMs: now,
      pipSize: 0.01,
    );
    expect(beyond.status, SignalStatus.expired);
  });

  test('TP1 mặc định khi chưa có TP1 riêng: Entry ± 1 ATR, chạm là EXPIRED', () {
    final r = classify(live: 102.0); // đúng Entry + 1 ATR, tp1 null
    expect(r.tp1FromFallback, isTrue);
    expect(r.tp1, 102.0);
    expect(r.status, SignalStatus.expired);
    final rSell = classify(action: 'SELL', live: 98.0);
    expect(rSell.tp1, 98.0);
    expect(rSell.tp1FromFallback, isTrue);
    expect(rSell.status, SignalStatus.expired);
  });

  test('Ưu tiên EXPIRED trước NOW: giá tốt hơn Entry nhưng đã quá giờ', () {
    final r = classify(live: 99.0, atMs: 3600000 + 1000);
    expect(r.status, SignalStatus.expired);
  });

  test('WAIT thì chưa có lệnh; chưa có giá live thì unknown', () {
    expect(classify(action: 'WAIT', live: 100.0).status, SignalStatus.wait);
    expect(classify(live: null).status, SignalStatus.unknown);
  });

  test('formatRemaining: MM:SS và hết hiệu lực', () {
    expect(formatRemaining(23 * 60 * 1000 + 45 * 1000), '23:45');
    expect(formatRemaining(0), 'Đã hết hiệu lực');
    expect(formatRemaining(-5000), 'Đã hết hiệu lực');
  });

  test('classifyStaticSignal: TP1 lấy từ thang TP (levels.t1)', () {
    final sg = StaticSignal(
      symbol: 'EURUSD',
      action: 'BUY',
      entry: 1.1000,
      sl: 1.0980,
      tp: 1.1040,
      rr: 2.0,
      atr: 0.0010,
      baseConf: 80,
      trendIndex: 80,
      paIndex: 80,
      conf: 80,
      bias: 'bullish',
      reasons: const <String>[],
      closedAt: issuedAt,
      levels: LadderLevels(
        inv: 1.0980,
        t1: 1.1010,
        t2: 1.1020,
        t3: 1.1030,
        t4: 1.1040,
        entry: 1.1000,
      ),
    );
    final r = classifyStaticSignal(
      sg,
      livePrice: 1.1010, // chạm đúng T1
      nowMs: now,
    );
    expect(r.tp1, 1.1010);
    expect(r.tp1FromFallback, isFalse);
    expect(r.status, SignalStatus.expired);
    final r2 = classifyStaticSignal(
      sg,
      livePrice: 1.1001, // trong vùng ±0,25 ATR
      nowMs: now,
    );
    expect(r2.status, SignalStatus.now);
  });
}
