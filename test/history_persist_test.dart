// Test viec 2 (v1.2.3): phan loai 5 loai ket qua thoat lenh, JSON
// round-trip va luu/tai ben qua MethodChannel 'tradesignal/storage'
// (mock bang TestDefaultBinaryMessengerBinding — khong can may that).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double pip(String _) => 0.0001;

  HistEntry openAndClose({
    required SessionHistory h,
    required String symbol,
    required String action,
    required double entry,
    double? sl,
    double? tp,
    int startAt = 1763400000000,
  }) {
    h.recordOpen(
      symbol: symbol,
      action: action,
      entry: entry,
      sl: sl,
      tp: tp,
      atr: 1.0,
      startAt: startAt,
      strategy: 'swing',
      conf: 75,
      rr: 2.0,
    );
    return h.entries.firstWhere(
        (HistEntry e) => e.symbol == symbol && e.status == 'open');
  }

  group('phan loai 5 loai ket qua (classifyExit) — BUY', () {
    test('TP: note Cham TP hoac gia thoat = TP', () {
      expect(
          classifyExit(
              action: 'BUY',
              entry: 100,
              sl: 99,
              tp: 102,
              exitPrice: 102,
              note: 'Chạm TP'),
          closeKindTP);
      expect(
          classifyExit(
              action: 'BUY',
              entry: 100,
              sl: 99,
              tp: 102,
              exitPrice: 102),
          closeKindTP);
    });
    test('SL: note Cham SL hoac gia thoat = SL', () {
      expect(
          classifyExit(
              action: 'BUY',
              entry: 100,
              sl: 99,
              tp: 102,
              exitPrice: 99,
              note: 'Chạm SL'),
          closeKindSL);
      expect(
          classifyExit(
              action: 'BUY',
              entry: 100,
              sl: 99,
              tp: 102,
              exitPrice: 99),
          closeKindSL);
    });
    test('Thoat tai Entry: dung gia Entry va trong dung sai 0,05%', () {
      expect(
          classifyExit(action: 'BUY', entry: 100, exitPrice: 100),
          closeKindEntry);
      // 100,04 lech 0,04% < 0,05% -> van la Entry.
      expect(
          classifyExit(action: 'BUY', entry: 100, exitPrice: 100.04),
          closeKindEntry);
      // 100,06 lech 0,06% > 0,05% -> khong con la Entry nua.
      expect(
          classifyExit(action: 'BUY', entry: 100, exitPrice: 100.06),
          closeKindEarlyProfit);
    });
    test('Cat lo som: BUY thoat duoi Entry vuot dung sai', () {
      expect(
          classifyExit(action: 'BUY', entry: 100, exitPrice: 99.5),
          closeKindEarlyLoss);
    });
    test('Cat lai som: BUY thoat tren Entry vuot dung sai', () {
      expect(
          classifyExit(action: 'BUY', entry: 100, exitPrice: 100.5),
          closeKindEarlyProfit);
    });
  });

  group('phan loai 5 loai ket qua (classifyExit) — SELL', () {
    test('TP/SL theo chieu SELL', () {
      expect(
          classifyExit(
              action: 'SELL',
              entry: 100,
              sl: 101,
              tp: 98,
              exitPrice: 98,
              note: 'Chạm TP'),
          closeKindTP);
      expect(
          classifyExit(
              action: 'SELL',
              entry: 100,
              sl: 101,
              tp: 98,
              exitPrice: 101,
              note: 'Chạm SL'),
          closeKindSL);
    });
    test('Thoat tai Entry: SELL dung gia Entry', () {
      expect(
          classifyExit(action: 'SELL', entry: 100, exitPrice: 100),
          closeKindEntry);
      expect(
          classifyExit(action: 'SELL', entry: 100, exitPrice: 99.96),
          closeKindEntry);
    });
    test('Cat lo som: SELL thoat tren Entry vuot dung sai', () {
      expect(
          classifyExit(action: 'SELL', entry: 100, exitPrice: 100.5),
          closeKindEarlyLoss);
    });
    test('Cat lai som: SELL thoat duoi Entry vuot dung sai', () {
      expect(
          classifyExit(action: 'SELL', entry: 100, exitPrice: 99.5),
          closeKindEarlyProfit);
    });
  });

  group('SessionHistory gan loai ket qua khi dong lenh', () {
    test('checkOutcomes: cham TP -> TP, cham SL -> SL', () {
      final SessionHistory h = SessionHistory();
      openAndClose(
          h: h, symbol: 'EURUSD', action: 'BUY', entry: 1.10, sl: 1.09, tp: 1.12);
      h.checkOutcomes(<String, double>{'EURUSD': 1.12}, pip);
      expect(h.entries.first.closeKind, closeKindTP);
      expect(h.closeKindCounts[closeKindTP], 1);

      final SessionHistory h2 = SessionHistory();
      openAndClose(
          h: h2, symbol: 'EURUSD', action: 'BUY', entry: 1.10, sl: 1.09, tp: 1.12);
      h2.checkOutcomes(<String, double>{'EURUSD': 1.09}, pip);
      expect(h2.entries.first.closeKind, closeKindSL);
      expect(h2.closeKindCounts[closeKindSL], 1);
    });

    test('closeReversal: dung Entry / lo / lai — ca BUY lan SELL', () {
      final SessionHistory h = SessionHistory();
      openAndClose(
          h: h, symbol: 'EURUSD', action: 'BUY', entry: 1.10, sl: 1.09, tp: 1.12);
      h.closeReversal('EURUSD', 1.10, 1763403600000, 'Đảo chiều sang SELL');
      expect(h.entries.first.closeKind, closeKindEntry);

      openAndClose(
          h: h, symbol: 'GBPUSD', action: 'BUY', entry: 1.30, sl: 1.29, tp: 1.32);
      h.closeReversal('GBPUSD', 1.295, 1763403600000, 'Đảo chiều sang SELL');
      expect(
          h.entries.firstWhere((e) => e.symbol == 'GBPUSD').closeKind,
          closeKindEarlyLoss);

      openAndClose(
          h: h, symbol: 'USDJPY', action: 'SELL', entry: 150, sl: 151, tp: 148);
      h.closeReversal('USDJPY', 149.0, 1763403600000, 'Đảo chiều sang BUY');
      expect(
          h.entries.firstWhere((e) => e.symbol == 'USDJPY').closeKind,
          closeKindEarlyProfit);
      expect(h.closeKindCounts[closeKindEntry], 1);
      expect(h.closeKindCounts[closeKindEarlyLoss], 1);
      expect(h.closeKindCounts[closeKindEarlyProfit], 1);
    });

    test('filter theo 5 loai ket qua + theo cap', () {
      final SessionHistory h = SessionHistory();
      openAndClose(
          h: h, symbol: 'EURUSD', action: 'BUY', entry: 1.10, sl: 1.09, tp: 1.12);
      h.checkOutcomes(<String, double>{'EURUSD': 1.12}, pip);
      openAndClose(
          h: h, symbol: 'XAUUSD', action: 'BUY', entry: 3800, sl: 3790, tp: 3820);
      h.closeReversal('XAUUSD', 3795, 1763403600000, 'Đảo chiều sang SELL');
      expect(h.filter(result: closeKindTP).length, 1);
      expect(h.filter(result: closeKindTP).first.symbol, 'EURUSD');
      expect(h.filter(result: closeKindEarlyLoss).length, 1);
      expect(h.filter(result: closeKindEarlyLoss).first.symbol, 'XAUUSD');
      expect(h.filter(symbol: 'XAUUSD', result: closeKindTP).length, 0);
      expect(h.filter(result: closeKindSL).length, 0);
    });
  });

  group('JSON round-trip', () {
    test('encode roi decode lai du truong', () {
      final SessionHistory h = SessionHistory();
      final HistEntry e = openAndClose(
          h: h, symbol: 'XAUUSD', action: 'BUY', entry: 3800, sl: 3790, tp: 3820);
      h.closeReversal('XAUUSD', 3810, 1763403600000, 'Đảo chiều sang SELL');
      final Map<String, dynamic> json = e.toJson();
      final String raw = jsonEncode(<String, dynamic>{
        'version': 1,
        'entries': <dynamic>[json],
      });
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      final List<HistEntry> back =
          SessionHistory.entriesFromPersistJson(decoded);
      expect(back.length, 1);
      final HistEntry r = back.first;
      expect(r.symbol, 'XAUUSD');
      expect(r.action, 'BUY');
      expect(r.entry, 3800);
      expect(r.sl, 3790);
      expect(r.tp, 3820);
      expect(r.exit, 3810);
      expect(r.exitAt, 1763403600000);
      expect(r.startAt, 1763400000000);
      expect(r.strategy, 'swing');
      expect(r.conf, 75);
      expect(r.closeKind, closeKindEarlyProfit);
      expect(r.exitPips, isNotNull);
      expect(r.exitPct, closeTo(0.263, 0.001));
      expect(r.status, 'closed');
    });

    test('bo qua ban ghi loi va trung id khi decode', () {
      final List<HistEntry> out = SessionHistory.entriesFromPersistJson(
        <String, dynamic>{
          'version': 1,
          'entries': <dynamic>[
            <String, dynamic>{
              'id': 1,
              'symbol': 'EURUSD',
              'action': 'BUY',
              'entry': 1.1,
              'openAt': 1,
              'startAt': 1,
              'planStop': 2,
              'conf': 70,
              'rr': 2.0,
              'atr': 0.001,
              'status': 'closed',
              'closeKind': 'TP',
            },
            <String, dynamic>{
              'id': 1, // trung id -> bo qua
              'symbol': 'EURUSD',
              'action': 'BUY',
              'entry': 1.1,
              'openAt': 1,
              'startAt': 1,
              'planStop': 2,
              'conf': 70,
              'rr': 2.0,
              'atr': 0.001,
            },
            'chuoi loi thay vi map',
            <String, dynamic>{'symbol': 'thieu truong bat buoc'},
          ],
        },
      );
      expect(out.length, 1);
      expect(out.first.closeKind, closeKindTP);
      expect(SessionHistory.entriesFromPersistJson(null), isEmpty);
      expect(SessionHistory.entriesFromPersistJson(<String, dynamic>{}),
          isEmpty);
    });
  });

  group('luu/tai ben qua MethodChannel (mock)', () {
    late Map<String, String> store;

    setUp(() {
      store = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('tradesignal/storage'),
        (MethodCall call) async {
          if (call.method == 'save') {
            final String file = (call.arguments as Map)['file'] as String;
            final String json = (call.arguments as Map)['json'] as String;
            store[file] = json;
            return null;
          }
          if (call.method == 'load') {
            final String file = (call.arguments as Map)['file'] as String;
            return store[file];
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('tradesignal/storage'), null);
    });

    test('ghi roi doc lai du ban ghi (mo lai app van thay)', () async {
      final SessionHistory h1 = SessionHistory();
      openAndClose(
          h: h1, symbol: 'EURUSD', action: 'BUY', entry: 1.10, sl: 1.09, tp: 1.12);
      h1.checkOutcomes(<String, double>{'EURUSD': 1.12}, pip);
      openAndClose(
          h: h1, symbol: 'XAUUSD', action: 'SELL', entry: 3800, sl: 3810, tp: 3780);
      h1.closeReversal('XAUUSD', 3800, 1763403600000, 'Đảo chiều sang BUY');
      expect(await h1.persist(), isTrue);
      expect(store.containsKey(SessionHistory.persistFile), isTrue);

      // Mo lai app: history moi, nap tu file.
      final SessionHistory h2 = SessionHistory();
      expect(await h2.loadPersisted(), isTrue);
      expect(h2.entries.length, 2);
      expect(h2.closedCount, 2);
      expect(
          h2.entries
              .firstWhere((e) => e.symbol == 'EURUSD')
              .closeKind,
          closeKindTP);
      expect(
          h2.entries
              .firstWhere((e) => e.symbol == 'XAUUSD')
              .closeKind,
          closeKindEntry);
      // Luu ban moi khong xoa ban cu: them 1 ban ghi roi luu lai.
      h2.recordOpen(
        symbol: 'BTCUSD',
        action: 'BUY',
        entry: 65000,
        sl: 64000,
        tp: 67000,
        atr: 500,
        startAt: 1763400000000,
        strategy: 'swing',
        conf: 80,
        rr: 2.0,
      );
      h2.closeReversal('BTCUSD', 64000, 1763403600000, 'Đảo chiều sang SELL');
      expect(await h2.persist(), isTrue);
      final SessionHistory h3 = SessionHistory();
      await h3.loadPersisted();
      expect(h3.entries.length, 3);
      expect(h3.closeKindCounts[closeKindSL], 1);
    });

    test('xoa toan bo: sach ca bo nho lan file', () async {
      final SessionHistory h1 = SessionHistory();
      openAndClose(
          h: h1, symbol: 'EURUSD', action: 'BUY', entry: 1.10, sl: 1.09, tp: 1.12);
      h1.checkOutcomes(<String, double>{'EURUSD': 1.12}, pip);
      await h1.persist();
      expect(await h1.clearAllPersisted(), isTrue);
      expect(h1.entries, isEmpty);
      final SessionHistory h2 = SessionHistory();
      await h2.loadPersisted();
      expect(h2.entries, isEmpty);
    });

    test('khong co file luu thi load tra false, khong crash', () async {
      final SessionHistory h = SessionHistory();
      expect(await h.loadPersisted(), isFalse);
      expect(h.entries, isEmpty);
    });
  });
}
