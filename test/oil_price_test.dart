// Test gia dau Yahoo CL=F (doi nguon 18/11) + phat hien gia cu:
//  - CNBC @CL.1 tra gia cham ~1,5-2,5h so voi thi truong (18/11: Exness
//    83,7 trong khi app van LIVE o 85,2) -> doi nguon chinh sang Yahoo
//    CL=F (cung nguon voi nen dau), CNBC chi lam du phong.
//  - Badge LIVE truoc day chi nghia la fetch thanh cong; gio neu gio cua
//    bao gia (src) cu hon 5 phut thi danh dau DU LIEU CU.
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/engine.dart';

Map<String, dynamic> yahooOilJson({
  List<int> timestamps = const <int>[1763430000, 1763430060, 1763430120],
  List<dynamic> closes = const <dynamic>[85.4, 85.3, 85.2],
  double? prevClose = 86.01,
  String? shortName = 'Crude Oil Dec 26',
}) {
  return <String, dynamic>{
    'chart': <String, dynamic>{
      'result': <dynamic>[
        <String, dynamic>{
          'meta': <String, dynamic>{
            'chartPreviousClose': prevClose,
            'regularMarketPrice': 85.2,
            'shortName': shortName,
          },
          'timestamp': timestamps,
          'indicators': <String, dynamic>{
            'quote': <dynamic>[
              <String, dynamic>{
                'open': <dynamic>[85.5, 85.4, 85.3],
                'high': <dynamic>[85.6, 85.5, 85.4],
                'low': <dynamic>[85.3, 85.2, 85.1],
                'close': closes,
                'volume': <dynamic>[100, 120, 90],
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
  group('parseYahooOilQuote', () {
    test('lay gia dong nen 1 phut moi nhat + gio nen + % vs dong phien truoc',
        () {
      final YahooOilQuote? q =
          MockEngine.parseYahooOilQuote(yahooOilJson());
      expect(q, isNotNull);
      expect(q!.price, 85.2);
      expect(
        q.quoteTime,
        DateTime.fromMillisecondsSinceEpoch(1763430120 * 1000),
      );
      // (85.2 - 86.01) / 86.01 * 100 = -0.9418...%
      expect(q.chgPct, closeTo(-0.9418, 0.001));
      // Thang hop dong tu meta.shortName "Crude Oil Dec 26".
      expect(q.contractLabel, 'T12/26');
    });

    test('khong co shortName thi van parse gia, contractLabel null', () {
      final YahooOilQuote? q =
          MockEngine.parseYahooOilQuote(yahooOilJson(shortName: null));
      expect(q, isNotNull);
      expect(q!.price, 85.2);
      expect(q.contractLabel, isNull);
    });

    test('thieu chart -> null, khong throw', () {
      expect(MockEngine.parseYahooOilQuote(<String, dynamic>{}), isNull);
      expect(
        MockEngine.parseYahooOilQuote(<String, dynamic>{
          'chart': <String, dynamic>{'result': <dynamic>[], 'error': null},
        }),
        isNull,
      );
    });

    test('gia dong dang chuoi so van parse duoc', () {
      final YahooOilQuote? q = MockEngine.parseYahooOilQuote(
        yahooOilJson(closes: <dynamic>['85.4', '85.3', '85.2']),
      );
      expect(q, isNotNull);
      expect(q!.price, 85.2);
    });

    test('nen co OHLC null thi bo qua, lay nen day du cuoi cung', () {
      final Map<String, dynamic> j = yahooOilJson();
      final List<dynamic> quote = ((((j['chart']
              as Map<String, dynamic>)['result'] as List<dynamic>)
          .first as Map<String, dynamic>)['indicators']
          as Map<String, dynamic>)['quote'] as List<dynamic>;
      // Nen cuoi null toan bo OHLC -> phai lay nen ke truoc (85.3).
      (quote.first as Map<String, dynamic>)['close'] =
          <dynamic>[85.4, 85.3, null];
      (quote.first as Map<String, dynamic>)['open'] =
          <dynamic>[85.5, 85.4, null];
      (quote.first as Map<String, dynamic>)['high'] =
          <dynamic>[85.6, 85.5, null];
      (quote.first as Map<String, dynamic>)['low'] =
          <dynamic>[85.3, 85.2, null];
      final YahooOilQuote? q = MockEngine.parseYahooOilQuote(j);
      expect(q, isNotNull);
      expect(q!.price, 85.3);
    });
  });

  group('isQuoteStale', () {
    test('bao gia 1 phut truoc -> chua cu', () {
      final DateTime now = DateTime(2026, 11, 18, 10, 31);
      expect(
        MockEngine.isQuoteStale(now.subtract(const Duration(minutes: 1)),
            now: now),
        isFalse,
      );
    });

    test('bao gia dung 5 phut truoc -> cu', () {
      final DateTime now = DateTime(2026, 11, 18, 10, 31);
      expect(
        MockEngine.isQuoteStale(now.subtract(const Duration(minutes: 5)),
            now: now),
        isTrue,
      );
    });

    test('bao gia 2 gio truoc (truong hop CNBC 18/11) -> cu', () {
      final DateTime now = DateTime(2026, 11, 18, 10, 31);
      expect(
        MockEngine.isQuoteStale(now.subtract(const Duration(hours: 2)),
            now: now),
        isTrue,
      );
    });

    test('nguon khong kem gio (src null) -> khong ket luan cu', () {
      expect(MockEngine.isQuoteStale(null), isFalse);
    });
  });

  group('parseContractMonth', () {
    test('"Crude Oil Dec 26" -> "T12/26"', () {
      expect(
        MockEngine.parseContractMonth('Crude Oil Dec 26'),
        'T12/26',
      );
    });

    test('"Crude Oil Jan 27" -> "T1/27"', () {
      expect(
        MockEngine.parseContractMonth('Crude Oil Jan 27'),
        'T1/27',
      );
    });

    test('ten khong co thang/nam -> null', () {
      expect(MockEngine.parseContractMonth('WTI Crude'), isNull);
      expect(MockEngine.parseContractMonth(null), isNull);
      expect(MockEngine.parseContractMonth(''), isNull);
    });
  });
}
