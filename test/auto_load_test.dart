// Test tự tải lại dữ liệu (sửa lỗi 18/11: app không tự load dữ liệu,
// phải tắt hẳn đi bật lại mới load được).
//
// Hai nguyên nhân gốc đã xác định bằng đọc code:
//  1) CandleCache.ensureCandles dùng `future.whenComplete(...)` để dọn
//     _loading: whenComplete trả về 1 future mới cũng lỗi theo, không ai
//     await -> lỗi văng ra zone, main.dart thay cả app bằng màn hình
//     "App gặp lỗi khi mở" mỗi khi 1 lần tải nến lỗi.
//  2) Warmup chỉ chạy 1 lần lúc mở app, không code nào khác gọi
//     ensureCandles, không có xử lý resume -> lần tải đầu lỗi là nến
//     không bao giờ về, tín hiệu kẹt mãi ở "ĐANG TẢI".
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/engine.dart';
import 'package:trade_signal_ai/main.dart';
import 'package:trade_signal_ai/market_data.dart';

/// Fetcher giả: lỗi [failTimes] lần đầu cho MỖI series (cặp × khung),
/// sau đó trả nến giả lập 300 nến/khung (đủ để chốt tín hiệu tĩnh:
/// H1 đã đóng ≥ 55, ATR > 0).
class _FlakyFetcher extends CandleFetcher {
  _FlakyFetcher({required this.failTimes});

  final int failTimes;
  final Map<String, int> calls = <String, int>{};

  int get totalCalls =>
      calls.values.fold<int>(0, (int a, int b) => a + b);

  @override
  Future<List<RawCandle>> fetchCandles(String symbol, String tf) async {
    final String key = '$symbol|$tf';
    calls[key] = (calls[key] ?? 0) + 1;
    if (calls[key]! <= failTimes) {
      throw Exception('mang loi gia lap ($key lan ${calls[key]})');
    }
    return _fakeSeries(tf);
  }

  List<RawCandle> _fakeSeries(String tf) {
    final int stepMin = tfMinutes[tf] ?? 5;
    final int stepMs = stepMin * 60 * 1000;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int lastStart = (nowMs ~/ stepMs) * stepMs;
    final Random rand = Random(42);
    double price = 3800;
    final List<RawCandle> out = <RawCandle>[];
    for (int i = 299; i >= 0; i--) {
      final int t = lastStart - i * stepMs;
      final double o = price;
      final double drift = (rand.nextDouble() - 0.48) * 4;
      double c = o + drift;
      if (c <= 0) c = o;
      out.add(RawCandle(
        t: t,
        o: o,
        h: max(o, c) + rand.nextDouble(),
        l: min(o, c) - rand.nextDouble(),
        c: c,
        v: 100 + rand.nextDouble() * 50,
      ));
      price = c;
    }
    return out;
  }
}

void main() {
  group('CandleRetryPolicy — backoff', () {
    test('nhip doi dan: 10s, 20s, 40s, toi da 60s', () {
      expect(
        CandleRetryPolicy.delayForFailures(0),
        const Duration(seconds: 10),
      );
      expect(
        CandleRetryPolicy.delayForFailures(1),
        const Duration(seconds: 20),
      );
      expect(
        CandleRetryPolicy.delayForFailures(2),
        const Duration(seconds: 40),
      );
      expect(
        CandleRetryPolicy.delayForFailures(3),
        const Duration(seconds: 60),
      );
      expect(
        CandleRetryPolicy.delayForFailures(10),
        const Duration(seconds: 60),
      );
    });

    test('chua thu lan nao thi thu ngay; chua qua nhip thi doi', () {
      final DateTime now = DateTime(2026, 11, 18, 11, 0, 0);
      expect(
        CandleRetryPolicy.shouldRetry(
          lastAttempt: null,
          consecutiveFailures: 0,
          now: now,
        ),
        isTrue,
      );
      expect(
        CandleRetryPolicy.shouldRetry(
          lastAttempt: now.subtract(const Duration(seconds: 5)),
          consecutiveFailures: 0,
          now: now,
        ),
        isFalse,
      );
      expect(
        CandleRetryPolicy.shouldRetry(
          lastAttempt: now.subtract(const Duration(seconds: 10)),
          consecutiveFailures: 0,
          now: now,
        ),
        isTrue,
      );
      // Loi lien tiep 2 lan -> nhip 40s: moi 30s thi chua du.
      expect(
        CandleRetryPolicy.shouldRetry(
          lastAttempt: now.subtract(const Duration(seconds: 30)),
          consecutiveFailures: 2,
          now: now,
        ),
        isFalse,
      );
      expect(
        CandleRetryPolicy.shouldRetry(
          lastAttempt: now.subtract(const Duration(seconds: 40)),
          consecutiveFailures: 2,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('CandleCache.ensureCandles — loi khong vang ra zone', () {
    test('loi fetch khong tao future loi moi coi (hoi quy whenComplete)',
        () async {
      // Truoc khi sua (market_data.dart dung whenComplete): test nay
      // ROT vi 2 loi async khong bat duoc, deu tro ve dong whenComplete
      // trong ensureCandles (da kiem chung 18/11).
      final CandleCache cache =
          CandleCache(fetcher: _FlakyFetcher(failTimes: 99));
      await expectLater(
        cache.ensureCandles('XAUUSD', 'H1'),
        throwsA(isA<Exception>()),
      );
      // Cho future don dep chay xong: neu van con future loi moi coi
      // thi flutter_test se bao loi async khong duoc xu ly ngay tai day.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Thu lai van duoc (khong ket trong _loading) va van loi nhu cu.
      await expectLater(
        cache.ensureCandles('XAUUSD', 'H1'),
        throwsA(isA<Exception>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      cache.dispose();
    });
  });

  group('tu tai lai khong can khoi dong lai (fakeAsync)', () {
    test('warmup loi -> timer tu thu lai -> nen + tin hieu hien ra', () {
      fakeAsync((FakeAsync async) {
        final MockEngine engine = MockEngine(
          cache: CandleCache(fetcher: _FlakyFetcher(failTimes: 1)),
        );
        // Warmup: 8 cap cach nhau 350ms, moi cap 5 khung; lan dau loi het.
        async.elapse(const Duration(seconds: 4));
        expect(engine.hasRealCandles('XAUUSD', 'H1'), isFalse);
        expect(engine.staticSignals['XAUUSD'], isNull);
        expect(engine.candlesStuck, isTrue);
        // Timer thu lai 10 giay/nhip (backoff 10s sau lan loi dau):
        // elapse them 12 giay -> quet lai, lan nay fetcher tra nen that.
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();
        expect(engine.hasRealCandles('XAUUSD', 'H1'), isTrue);
        expect(engine.staticSignals['XAUUSD'], isNotNull);
        expect(engine.vpScan['XAUUSD'], isNotNull);
        expect(engine.hasMissingCandles, isFalse);
        engine.dispose();
      });
    });

    test('resume tu nen kich hoat lam moi du lieu', () {
      fakeAsync((FakeAsync async) {
        final _FlakyFetcher fetcher = _FlakyFetcher(failTimes: 1);
        final MockEngine engine = MockEngine(
          cache: CandleCache(fetcher: fetcher),
        );
        async.elapse(const Duration(seconds: 4));
        expect(engine.hasRealCandles('XAUUSD', 'H1'), isFalse);
        final int callsBefore = fetcher.totalCalls;
        // Mo phong app tu nen quay lai foreground (chua toi nhip 10s
        // cua timer thu lai nen chi co resume moi gay ra lan goi moi).
        engine.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        expect(fetcher.totalCalls, greaterThan(callsBefore));
        expect(engine.hasRealCandles('XAUUSD', 'H1'), isTrue);
        expect(engine.staticSignals['XAUUSD'], isNotNull);
        engine.dispose();
      });
    });

    test('tick sau dispose khong nem loi (timer song sot qua loi notify)',
        () {
      fakeAsync((FakeAsync async) {
        final MockEngine engine = MockEngine(
          cache: CandleCache(fetcher: _FlakyFetcher(failTimes: 99)),
        );
        engine.dispose();
        expect(() => engine.tick(), returnsNormally);
        async.elapse(const Duration(seconds: 2));
      });
    });
  });

  group('nut "Thu lai ngay" tren tab Tin hieu', () {
    testWidgets('bam nut -> tai lai du lieu, het "DANG TAI"', (tester) async {
      final MockEngine engine = MockEngine(
        cache: CandleCache(fetcher: _FlakyFetcher(failTimes: 1)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: engine,
              builder: (context, _) => SignalsTab(
                engine: engine,
                onGoChart: (_, {String? symbol}) {},
              ),
            ),
          ),
        ),
      );
      // Warmup 4 giay: lan tai dau loi het -> chua co tin hieu.
      await tester.pump(const Duration(seconds: 4));
      expect(find.textContaining('ĐANG TẢI'), findsWidgets);
      expect(find.text('Thử lại ngay'), findsOneWidget);
      // Bam nut (tong thoi gian pump < 10s nen timer thu lai chua kip
      // chay — chinh nut nay phai la thu tai du lieu ve).
      await tester.tap(find.text('Thử lại ngay'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Thử lại ngay'), findsNothing);
      expect(engine.staticSignals['XAUUSD'], isNotNull);
      // Dọn sạch trong thân test (theo mẫu home_tab_island_test): gỡ
      // widget, dispose engine (hủy Timer.periodic), pump thêm 6s để
      // các timeout 5s của fetch đang chạy được kích hoạt và kết thúc —
      // không còn timer treo khi framework kiểm tra bất biến.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      engine.dispose();
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
