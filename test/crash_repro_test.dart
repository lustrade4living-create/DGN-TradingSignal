// Test tai hien 2 loi crash mo app v1.2.0 (17/11) + kiem chung fix:
//  Loi 1: "type 'String' is not a subtype of type 'List<dynamic>?'"
//        — Kraken ticker tra 'o' (gia mo hom nay) la CHUOI, code cu ep
//          thanh List -> no ngay khi Kraken tra ve OK.
//  Loi 2: "type 'String' is not a subtype of type 'num?'"
//        — Kraken OHLC / Binance klines tra OHLCV dang CHUOI,
//          code cu ep `(v as num?)` -> no ngay khi tai nen.
// Ca 2 test dung du lieu mau dung dinh dang that cua API.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/engine.dart';
import 'package:trade_signal_ai/market_data.dart';
import 'package:trade_signal_ai/safe_json.dart';

void main() {
  group('safe_json helpers', () {
    test('numD nhan ca so lan chuoi so', () {
      expect(numD(65000.0), 65000.0);
      expect(numD(42), 42.0);
      expect(numD('65000.00'), 65000.0);
      expect(numD(' 3882.50 '), 3882.5);
      expect(numD(null), isNull);
      expect(numD('abc'), isNull);
      expect(numD(''), isNull);
      expect(numD(true), isNull);
    });
    test('numI nhan ca so lan chuoi so', () {
      expect(numI(1763419200), 1763419200);
      expect(numI('1763419200'), 1763419200);
      expect(numI('42.9'), 42);
      expect(numI(null), isNull);
      expect(numI('x'), isNull);
    });
    test('asList chi nhan List', () {
      expect(asList([1, 2]), [1, 2]);
      expect(asList('rate limited'), isNull); // truong list chua chuoi bao loi
      expect(asList(null), isNull);
      expect(asList({'a': 1}), isNull);
    });
    test('asMap chi nhan Map', () {
      expect(asMap({'a': 1}), {'a': 1});
      expect(asMap('hello'), isNull);
      expect(asMap(null), isNull);
    });
    test('strOf khong throw khi gap so', () {
      expect(strOf(123), '123');
      expect(strOf(null), '');
      expect(strOf(null, 'mac dinh'), 'mac dinh');
      expect(strOf('abc'), 'abc');
    });
  });

  group('loi 1: Kraken ticker o la chuoi', () {
    test('ep cu no TypeError (chung minh nguyen nhan)', () {
      const Object? o = '64800.00';
      expect(() => o as List<dynamic>?, throwsA(isA<TypeError>()));
    });
    test('parseKrakenTicker parse duoc payload that', () {
      final Map<String, dynamic> decoded = jsonDecode('''
        {"error": [], "result": {
          "XXBTZUSD": {"a": ["65000.10", "1", "1.000"], "b": ["64990.20", "1", "1.000"],
                       "c": ["65000.00", "0.01000000"], "o": "64800.00"},
          "XETHZUSD": {"a": ["3500.00", "1", "1.000"], "b": ["3499.00", "1", "1.000"],
                       "c": ["3499.50", "0.5"], "o": "3400.00"}
        }}''') as Map<String, dynamic>;
      final Map<String, (double, double?)> res =
          MockEngine.parseKrakenTicker(
              decoded['result'] as Map<String, dynamic>);
      expect(res['XXBTZUSD']!.$1, closeTo(64995.15, 0.001));
      expect(res['XXBTZUSD']!.$2, closeTo(0.3086, 0.001));
      expect(res['XETHZUSD']!.$1, closeTo(3499.5, 0.001));
    });
    test('parseKrakenTicker bo qua muc loi thay vi throw', () {
      final Map<String, (double, double?)> res =
          MockEngine.parseKrakenTicker(<String, dynamic>{
        'XXBTZUSD': 'EGeneral:Invalid arguments',
        'XETHZUSD': <String, dynamic>{
          'a': ['3500.00', '1', '1.000'],
          'b': ['3499.00', '1', '1.000'],
          'c': ['3499.50', '0.5'],
          'o': '3400.00',
        },
      });
      expect(res.containsKey('XXBTZUSD'), isFalse);
      expect(res['XETHZUSD']!.$1, closeTo(3499.5, 0.001));
    });
  });

  group('loi 2: OHLCV dang chuoi', () {
    test('ep cu no TypeError (chung minh nguyen nhan)', () {
      const Object? v = '3882.50';
      expect(() => (v as num?)?.toDouble(), throwsA(isA<TypeError>()));
    });
    test('parseOhlcRows Kraken: OHLCV chuoi, t la giay', () {
      final List<dynamic> rows = jsonDecode('''
        [[1763419200, "3882.50", "3885.00", "3880.00", "3884.00", "3883.00", "12.5", 42],
         [1763419260, "3884.00", "3886.00", "3883.00", "3885.50", "3884.50", "9.25", 38]]''') as List<dynamic>;
      final List<RawCandle> out =
          CandleFetcher.parseOhlcRows(rows, 6, timeIsSeconds: true);
      expect(out.length, 2);
      expect(out[0].t, 1763419200000);
      expect(out[0].o, 3882.5);
      expect(out[0].h, 3885.0);
      expect(out[0].v, 12.5);
      expect(out[1].c, 3885.5);
    });
    test('parseOhlcRows Binance: OHLCV chuoi, t la ms', () {
      final List<dynamic> rows = jsonDecode('''
        [[1763419200000, "65000.00", "65100.00", "64900.00", "65050.00", "123.45", 1763419259999, "1", 100, "2", "3", "0"],
         [1763419260000, "65050.00", "65200.00", "65000.00", "65100.00", "98.76", 1763419319999, "1", 90, "2", "3", "0"]]''') as List<dynamic>;
      final List<RawCandle> out =
          CandleFetcher.parseOhlcRows(rows, 5, timeIsSeconds: false);
      expect(out.length, 2);
      expect(out[0].t, 1763419200000);
      expect(out[0].o, 65000.0);
      expect(out[0].v, 123.45);
    });
    test('parseOhlcRows bo hang loi thay vi throw', () {
      final List<dynamic> rows = <dynamic>[
        <dynamic>[
          1763419200,
          'khong phai so',
          '3885.00',
          '3880.00',
          '3884.00',
          '3883.00',
          '12.5',
          42
        ],
        'loi mang',
        <dynamic>[
          1763419260,
          '3884.00',
          '3886.00',
          '3883.00',
          '3885.50',
          '3884.50',
          '9.25',
          38
        ],
      ];
      final List<RawCandle> out =
          CandleFetcher.parseOhlcRows(rows, 6, timeIsSeconds: true);
      expect(out.length, 1);
      expect(out[0].c, 3885.5);
    });
    test('parseYahooChart: OHLC so + null van parse duoc', () {
      final Map<String, dynamic> decoded = jsonDecode('''
        {"chart": {"result": [{"timestamp": [1763419200, 1763419260],
          "indicators": {"quote": [{"open": [88.1, null], "high": [88.5, 88.9],
          "low": [87.9, 88.0], "close": [88.4, 88.7], "volume": [1000, 1200]}]}}],
          "error": null}}''') as Map<String, dynamic>;
      final List<RawCandle> out = CandleFetcher.parseYahooChart(decoded);
      expect(out.length, 1); // nen thu 2 co open null -> bo qua
      expect(out[0].o, 88.1);
      expect(out[0].c, 88.4);
    });
  });

  group('gia live dang chuoi (gold-api/Binance)', () {
    test('numD parse price dang chuoi', () {
      final Map<String, dynamic> j1 =
          jsonDecode('{"price": "3882.74"}') as Map<String, dynamic>;
      expect(numD(j1['price']), 3882.74);
      final Map<String, dynamic> j2 =
          jsonDecode('{"price": 3882.74}') as Map<String, dynamic>;
      expect(numD(j2['price']), 3882.74);
      final Map<String, dynamic> j3 =
          jsonDecode('{"error": "limit"}') as Map<String, dynamic>;
      expect(numD(j3['price']), isNull);
    });
  });

  group('tin tuc: truong items chua chuoi bao loi', () {
    test('asList tra null thay vi throw', () {
      final Map<String, dynamic> data = jsonDecode(
              '{"status": "error", "message": "Feed not found"}')
          as Map<String, dynamic>;
      expect(asList(data['items']), isNull);
      final Map<String, dynamic> data2 = jsonDecode(
              '{"status": "ok", "items": "rate limited"}')
          as Map<String, dynamic>;
      expect(asList(data2['items']), isNull);
    });
  });
}
