// market_data.dart — Nến thật cho TradeSignal AI (port từ bản web, spec §2).
//
// Nguồn nến (giữ nguyên v1.1.0, KHÔNG dùng OKX dưới mọi hình thức):
//   - BTCUSD, XAUUSD : Binance klines (BTCUSDT, PAXGUSDT)
//   - 5 cặp forex     : Kraken OHLC
//   - USOIL (dầu WTI): Yahoo Finance chart API (CL=F) — web dùng OKX cho
//     nến dầu nhưng Flutter KHÔNG được dùng OKX nên thay bằng Yahoo.
//   - Yahoo không có interval 4h: nến H4 được gộp từ nến 60m trong code.
//
// Chỉ import dart:async / dart:convert / dart:io / dart:math — không import
// engine.dart (tránh phụ thuộc vòng tròn), không plugin, không dependency mới.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'safe_json.dart';

/// Một nến OHLCV. `t` là epoch milliseconds (mốc mở nến, giờ UTC).
class RawCandle {
  final int t;
  final double o;
  final double h;
  final double l;
  final double c;
  final double v;

  const RawCandle({
    required this.t,
    required this.o,
    required this.h,
    required this.l,
    required this.c,
    required this.v,
  });

  RawCandle copyWith({
    int? t,
    double? o,
    double? h,
    double? l,
    double? c,
    double? v,
  }) {
    return RawCandle(
      t: t ?? this.t,
      o: o ?? this.o,
      h: h ?? this.h,
      l: l ?? this.l,
      c: c ?? this.c,
      v: v ?? this.v,
    );
  }

  @override
  String toString() => 'RawCandle(t: $t, o: $o, h: $h, l: $l, c: $c, v: $v)';
}

/// Số phút của mỗi khung (spec §2.5: TF_MIN).
const Map<String, int> tfMinutes = {
  'M5': 5,
  'M15': 15,
  'H1': 60,
  'H4': 240,
  'D1': 1440,
};

/// Interval Binance tương ứng từng khung.
const Map<String, String> _binanceIntervals = {
  'M5': '5m',
  'M15': '15m',
  'H1': '1h',
  'H4': '4h',
  'D1': '1d',
};

/// Mã cặp Kraken dùng trong query OHLC (spec §2.1).
const Map<String, String> _krakenPairs = {
  'EURUSD': 'EURUSD',
  'GBPUSD': 'GBPUSD',
  'USDCAD': 'USDCAD',
  'USDCHF': 'USDCHF',
  'USDJPY': 'USDJPY',
};

/// Mã Binance dùng cho BTCUSD / XAUUSD (spec §2.1).
const Map<String, String> _binanceSymbols = {
  'BTCUSD': 'BTCUSDT',
  'XAUUSD': 'PAXGUSDT',
};

/// Số nến tối đa tải về mỗi lần (spec §2.5: 300).
const int kMaxFetchCandles = 300;

/// Số nến tối đa cho backtest (task 18/11): 2000 nến.
/// CHỈ backtest dùng — cache tín hiệu/chart vẫn tối đa 300 nến
/// ([kMaxFetchCandles]) để không đổi hành vi các nơi đang gọi fetch.
const int kMaxBacktestCandles = 2000;

/// Giới hạn mỗi lần gọi của từng nguồn (dùng để phân trang backtest):
/// Binance klines tối đa 1000 nến/lần, Kraken OHLC tối đa 720 nến/lần.
const int kBinancePageLimit = 1000;
const int kKrakenPageLimit = 720;

/// endTime cho lần gọi Binance klines tiếp theo (phân trang lùi dần):
/// endTime của Binance là BAO HÀM — truyền đúng mốc nến cũ nhất sẽ trả
/// lại chính nến đó, nên trừ 1ms để trang sau chỉ chứa nến cũ hơn.
int binanceNextEndTimeMs(int oldestCandleMs) => oldestCandleMs - 1;

/// `since` (giây) cho lần gọi Kraken OHLC tiếp theo: lùi đúng 1 trang
/// (720 nến) trước nến cũ nhất đã có. Kraken trả tối đa 720 nến kể từ
/// `since`; nến nào trùng với trang trước sẽ bị loại khi gộp theo mốc `t`.
int krakenNextSinceSec({required int oldestCandleMs, required int intervalMin}) =>
    oldestCandleMs ~/ 1000 - kKrakenPageLimit * intervalMin * 60;

/// Range/interval Yahoo cho backtest — lớn hơn hẳn [CandleFetcher.fetchYahooCandles]
/// (5d/1mo/3mo/6mo) để có cơ hội đủ 2000 nến:
/// - M5/M15: 60d là giới hạn tối đa Yahoo cho interval phút.
/// - H1/H4: 2y/60m (giới hạn 730 ngày cho interval 60m; H4 gộp từ 60m).
/// - D1: max/1d.
/// Yahoo KHÔNG đảm bảo đủ 2000 nến cho mọi khung (dầu không giao dịch
/// 24/7, ngày nghỉ...): caller phải ghi rõ số nến thực dùng, không bịa thêm.
({String range, String interval, bool aggregateH4}) yahooHistoryRangeInterval(
  String tf,
) {
  switch (tf) {
    case 'M5':
      return (range: '60d', interval: '5m', aggregateH4: false);
    case 'M15':
      return (range: '60d', interval: '15m', aggregateH4: false);
    case 'H1':
      return (range: '2y', interval: '60m', aggregateH4: false);
    case 'H4':
      return (range: '2y', interval: '60m', aggregateH4: true);
    case 'D1':
      return (range: 'max', interval: '1d', aggregateH4: false);
    default:
      throw Exception('Yahoo Finance (CL=F): khung không hỗ trợ: $tf');
  }
}

/// Gộp map nến theo mốc thời gian: sắp xếp tăng dần, chỉ giữ [target]
/// nến mới nhất (dùng khi phân trang backtest).
List<RawCandle> _sortedTrimmed(Map<int, RawCandle> byTime, int target) {
  final List<RawCandle> all = byTime.values.toList()
    ..sort((a, b) => a.t.compareTo(b.t));
  if (all.length > target) return all.sublist(all.length - target);
  return all;
}

/// Số phần tử tối đa giữ trong cache mỗi series (spec §2.5: cắt 340).
const int kMaxCacheCandles = 340;

/// User-Agent dùng cho Yahoo Finance — giống code v1.1.0 (engine.dart)
/// đã dùng cho giá dầu.
const String _yahooUserAgent =
    'Mozilla/5.0 (Linux; Android 13) TradeSignalAI/1.1.0';

/// Tải nến thật từ Binance / Kraken / Yahoo. Dùng chung 1 [HttpClient],
/// timeout 5 giây mỗi lần gọi. Gọi [close] khi không dùng nữa.
class CandleFetcher {
  CandleFetcher({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 5);
  }

  final HttpClient _client;

  /// Đóng HttpClient dùng chung. Gọi 1 lần khi app/engine bị hủy.
  void close() {
    _client.close(force: true);
  }

  /// GET JSON, ném [Exception] ghi rõ nguồn khi lỗi/timeout/trạng thái != 200.
  Future<dynamic> _getJson(Uri uri, String source, {Map<String, String>? headers}) async {
    try {
      final HttpClientRequest req = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      if (headers != null) {
        headers.forEach(req.headers.set);
      }
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 5));
      final String body =
          await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        throw Exception('$source: HTTP ${resp.statusCode}');
      }
      return jsonDecode(body);
    } on TimeoutException {
      throw Exception('$source: hết thời gian chờ (5s)');
    } on Exception catch (e) {
      if (e is FormatException) {
        throw Exception('$source: dữ liệu trả về không phải JSON');
      }
      rethrow;
    }
  }

  /// Doi so thanh double: nhan ca num lan chuoi so.
  /// QUAN TRONG (loi crash mo app v1.2.0 #2): Kraken OHLC va Binance klines
  /// tra OHLCV duoi dang CHUOI ("3882.50", "65000.00"), khong phai so —
  /// code cu `(v as num?)` no ngay khi gap chuoi. Dung numD thay the.
  static double? _asDouble(Object? v) => numD(v);

  static int? _asInt(Object? v) => numI(v);

  /// Parse chung cho Kraken OHLC va Binance klines: hang la
  /// [t, o, h, l, c, ...] voi o/h/l/c/v la so HOAC chuoi so.
  /// [volIdx] = chi so cot volume (Kraken: 6, Binance: 5).
  /// [timeIsSeconds] = true neu t la giay (Kraken), false neu la ms
  /// (Binance). Hang nao thieu/khong parse duoc thi bo qua.
  /// Khong bao gio throw vi sai kieu.
  static List<RawCandle> parseOhlcRows(
    List<dynamic> rows,
    int volIdx, {
    required bool timeIsSeconds,
  }) {
    final List<RawCandle> out = <RawCandle>[];
    for (final Object? r in rows) {
      if (r is! List || r.length <= volIdx) continue;
      final int? t = _asInt(r[0]);
      final double? o = _asDouble(r[1]);
      final double? h = _asDouble(r[2]);
      final double? l = _asDouble(r[3]);
      final double? c = _asDouble(r[4]);
      final double? v = _asDouble(r[volIdx]);
      if (t == null || o == null || h == null || l == null || c == null) {
        continue;
      }
      out.add(RawCandle(
        t: timeIsSeconds ? t * 1000 : t,
        o: o,
        h: h,
        l: l,
        c: c,
        v: v ?? 0,
      ));
    }
    out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  /// Nến Kraken OHLC (tối đa 300 nến mới nhất — giữ nguyên hành vi cũ
  /// cho tín hiệu/chart; backtest dùng [fetchKrakenOHLCPaged] + phân trang).
  /// GET https://api.kraken.com/0/public/OHLC?pair=<pair>&interval=<phút>
  /// Trả về `[time, open, high, low, close, vwap, volume, count]`;
  /// lấy t = r[0]*1000, v = r[6].
  Future<List<RawCandle>> fetchKrakenOHLC(String pair, int intervalMin) async {
    final List<RawCandle> out =
        await fetchKrakenOHLCPaged(pair, intervalMin);
    if (out.length > kMaxFetchCandles) {
      return out.sublist(out.length - kMaxFetchCandles);
    }
    return out;
  }

  /// Nến Kraken OHLC KHÔNG cắt 300 (1 lần gọi, tối đa 720 nến).
  /// [sinceSec] != null thì thêm `&since=<giây>` để lấy trang cũ hơn
  /// (phân trang backtest — xem [krakenNextSinceSec]).
  Future<List<RawCandle>> fetchKrakenOHLCPaged(
    String pair,
    int intervalMin, {
    int? sinceSec,
  }) async {
    const source = 'Kraken OHLC';
    final StringBuffer sb = StringBuffer(
      'https://api.kraken.com/0/public/OHLC'
      '?pair=${Uri.encodeComponent(pair)}&interval=$intervalMin',
    );
    if (sinceSec != null) sb.write('&since=$sinceSec');
    final uri = Uri.parse(sb.toString());
    final dynamic decoded = await _getJson(uri, source);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('$source: dữ liệu trả về sai định dạng');
    }
    final Object? error = decoded['error'];
    if (error is List && error.isNotEmpty) {
      throw Exception('$source: ${error.join(', ')}');
    }
    final Object? result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw Exception('$source: không có trường result');
    }
    // result chứa 1 key là mã cặp (VD "ZEURZUSD") + key "last".
    // Lấy list đầu tiên không phải "last" để không phụ thuộc mã trả về.
    List<dynamic>? rows;
    for (final MapEntry<String, dynamic> e in result.entries) {
      if (e.key == 'last') continue;
      if (e.value is List) {
        rows = e.value as List<dynamic>;
        break;
      }
    }
    if (rows == null) {
      throw Exception('$source: không tìm thấy nến cho cặp $pair');
    }
    final List<RawCandle> out =
        parseOhlcRows(rows, 6, timeIsSeconds: true);
    // KHÔNG cắt 300 ở đây: fetchKrakenOHLC (bản giữ hành vi cũ) tự cắt
    // sau khi gọi hàm này; backtest cần đủ 720 nến/trang.
    return out;
  }

  /// Nến Binance klines (tối đa 300 nến mới nhất — giữ nguyên hành vi cũ
  /// cho tín hiệu/chart; backtest dùng [fetchBinanceKlinesPaged]).
  /// GET https://data-api.binance.vision/api/v3/klines?symbol=<sym>
  ///   &interval=<5m|15m|1h|4h|1d>&limit=300
  /// t = r[0], v = r[5].
  Future<List<RawCandle>> fetchBinanceKlines(String symbol, String interval) =>
      fetchBinanceKlinesPaged(symbol, interval, limit: kMaxFetchCandles);

  /// Nến Binance klines phân trang: [limit] mặc định 1000 (giới hạn
  /// Binance); [endTimeMs] != null thì thêm `&endTime=` để lấy trang cũ
  /// hơn (xem [binanceNextEndTimeMs]). Không cắt 300.
  Future<List<RawCandle>> fetchBinanceKlinesPaged(
    String symbol,
    String interval, {
    int limit = kBinancePageLimit,
    int? endTimeMs,
  }) async {
    const source = 'Binance klines';
    final StringBuffer sb = StringBuffer(
      'https://data-api.binance.vision/api/v3/klines'
      '?symbol=${Uri.encodeComponent(symbol)}'
      '&interval=${Uri.encodeComponent(interval)}'
      '&limit=$limit',
    );
    if (endTimeMs != null) sb.write('&endTime=$endTimeMs');
    final dynamic decoded = await _getJson(Uri.parse(sb.toString()), source);
    if (decoded is! List) {
      throw Exception('$source: dữ liệu trả về sai định dạng');
    }
    return parseOhlcRows(decoded, 5, timeIsSeconds: false);
  }

  /// Nến dầu WTI (CL=F) từ Yahoo Finance chart API.
  /// Yahoo không có interval 4h nên H4 dùng interval 60m rồi gộp lên H4.
  /// range/interval theo khung:
  ///   M5: 5d/5m · M15: 5d/15m · H1: 1mo/60m · H4: 3mo/60m (gộp) · D1: 6mo/1d.
  Future<List<RawCandle>> fetchYahooCandles(String tf) async {
    const source = 'Yahoo Finance (CL=F)';
    final String range;
    final String interval;
    final bool aggregateH4;
    switch (tf) {
      case 'M5':
        range = '5d';
        interval = '5m';
        aggregateH4 = false;
      case 'M15':
        range = '5d';
        interval = '15m';
        aggregateH4 = false;
      case 'H1':
        range = '1mo';
        interval = '60m';
        aggregateH4 = false;
      case 'H4':
        range = '3mo';
        interval = '60m';
        aggregateH4 = true;
      case 'D1':
        range = '6mo';
        interval = '1d';
        aggregateH4 = false;
      default:
        throw Exception('$source: khung không hỗ trợ: $tf');
    }
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/CL=F'
      '?range=$range&interval=$interval',
    );
    final dynamic decoded = await _getJson(
      uri,
      source,
      headers: <String, String>{'User-Agent': _yahooUserAgent},
    );
    if (decoded is! Map<String, dynamic>) {
      throw Exception('$source: dữ liệu trả về sai định dạng');
    }
    return parseYahooChart(decoded, aggregateH4: aggregateH4);
  }

  /// Nến dầu WTI (CL=F) cho backtest: range lớn hơn (xem
  /// [yahooHistoryRangeInterval]) để có cơ hội đủ 2000 nến. Yahoo KHÔNG
  /// đảm bảo đủ 2000 cho mọi khung — trả tối đa lấy được, caller ghi rõ
  /// số nến thực dùng.
  Future<List<RawCandle>> fetchYahooCandlesHistory(
    String tf, {
    int maxCandles = kMaxBacktestCandles,
  }) async {
    const source = 'Yahoo Finance (CL=F)';
    final ({String range, String interval, bool aggregateH4}) spec =
        yahooHistoryRangeInterval(tf);
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/CL=F'
      '?range=${spec.range}&interval=${spec.interval}',
    );
    final dynamic decoded = await _getJson(
      uri,
      source,
      headers: <String, String>{'User-Agent': _yahooUserAgent},
    );
    if (decoded is! Map<String, dynamic>) {
      throw Exception('$source: dữ liệu trả về sai định dạng');
    }
    return parseYahooChart(
      decoded,
      aggregateH4: spec.aggregateH4,
      maxCandles: maxCandles.clamp(1, kMaxBacktestCandles),
    );
  }

  /// Parse JSON chart Yahoo (da decode): tra ve nen sap xep tang dan.
  /// Chi throw Exception khi thieu cau truc (caller bat va hien
  /// "DANG TAI"/"DU LIEU CU"); khong bao gio throw TypeError vi sai kieu.
  /// [maxCandles] mặc định 300 (giữ hành vi cũ); backtest truyền 2000.
  static List<RawCandle> parseYahooChart(
    Map<String, dynamic> decoded, {
    bool aggregateH4 = false,
    int maxCandles = kMaxFetchCandles,
  }) {
    const source = 'Yahoo Finance (CL=F)';
    final Map<String, dynamic>? chart = asMap(decoded['chart']);
    if (chart == null) {
      throw Exception('$source: không có trường chart');
    }
    final Map<String, dynamic>? error = asMap(chart['error']);
    if (error != null && error.isNotEmpty) {
      throw Exception(
          '$source: ${error['description'] ?? error['code'] ?? 'lỗi'}');
    }
    final List<dynamic>? result = asList(chart['result']);
    if (result == null ||
        result.isEmpty ||
        result.first is! Map<String, dynamic>) {
      throw Exception('$source: không có kết quả nến');
    }
    final Map<String, dynamic> first = result.first as Map<String, dynamic>;
    final List<dynamic>? timestamps = asList(first['timestamp']);
    final Map<String, dynamic>? indicators = asMap(first['indicators']);
    if (timestamps == null || indicators == null) {
      throw Exception('$source: thiếu timestamp/indicators');
    }
    final List<dynamic>? quoteList = asList(indicators['quote']);
    if (quoteList == null ||
        quoteList.isEmpty ||
        quoteList.first is! Map<String, dynamic>) {
      throw Exception('$source: thiếu quote');
    }
    final Map<String, dynamic> quote = quoteList.first as Map<String, dynamic>;
    final List<dynamic>? opens = asList(quote['open']);
    final List<dynamic>? highs = asList(quote['high']);
    final List<dynamic>? lows = asList(quote['low']);
    final List<dynamic>? closes = asList(quote['close']);
    final List<dynamic>? volumes = asList(quote['volume']);
    if (opens == null || highs == null || lows == null || closes == null) {
      throw Exception('$source: thiếu mảng OHLC');
    }
    final int n = math.min(
      timestamps.length,
      math.min(
        opens.length,
        math.min(highs.length, math.min(lows.length, closes.length)),
      ),
    );
    final List<RawCandle> out = <RawCandle>[];
    for (int i = 0; i < n; i++) {
      final int? tSec = _asInt(timestamps[i]);
      final double? o = _asDouble(opens[i]);
      final double? h = _asDouble(highs[i]);
      final double? l = _asDouble(lows[i]);
      final double? c = _asDouble(closes[i]);
      // Nến Yahoo có thể null OHLC (phiên chưa giao dịch) -> bỏ qua.
      if (tSec == null || o == null || h == null || l == null || c == null) {
        continue;
      }
      final double v =
          (volumes != null && i < volumes.length) ? (_asDouble(volumes[i]) ?? 0) : 0;
      out.add(RawCandle(t: tSec * 1000, o: o, h: h, l: l, c: c, v: v));
    }
    out.sort((a, b) => a.t.compareTo(b.t));
    if (aggregateH4) {
      return _aggregateToH4(out, maxCandles: maxCandles);
    }
    if (out.length > maxCandles) {
      return out.sublist(out.length - maxCandles);
    }
    return out;
  }

  /// Gộp nến 60m thành nến H4 theo biên giờ chuẩn (UTC).
  /// o = open nến đầu, h = max, l = min, c = close nến cuối, v = tổng volume.
  static List<RawCandle> _aggregateToH4(
    List<RawCandle> hourly, {
    int maxCandles = kMaxFetchCandles,
  }) {
    const int stepMs = 4 * 60 * 60 * 1000;
    final List<RawCandle> out = <RawCandle>[];
    for (final RawCandle c in hourly) {
      final int start = (c.t ~/ stepMs) * stepMs;
      if (out.isNotEmpty && out.last.t == start) {
        final RawCandle last = out.last;
        out[out.length - 1] = RawCandle(
          t: start,
          o: last.o,
          h: math.max(last.h, c.h),
          l: math.min(last.l, c.l),
          c: c.c,
          v: last.v + c.v,
        );
      } else {
        out.add(RawCandle(t: start, o: c.o, h: c.h, l: c.l, c: c.c, v: c.v));
      }
    }
    if (out.length > maxCandles) {
      return out.sublist(out.length - maxCandles);
    }
    return out;
  }

  /// Tải tối đa [maxCandles] nến cho backtest (mặc định 2000, kẹp tối đa
  /// 2000). Phân trang theo từng nguồn:
  /// - Binance: limit 1000/lần, lùi dần bằng endTime = nến cũ nhất - 1ms.
  /// - Kraken: tối đa 720 nến/lần, lùi bằng `since` = nến cũ nhất
  ///   trừ 720 khung.
  /// - Yahoo: 1 lần gọi với range lớn (xem [yahooHistoryRangeInterval]);
  ///   không đủ 2000 thì trả tối đa lấy được, KHÔNG bịa thêm.
  /// Trả về tăng dần theo thời gian, đã loại trùng, tối đa [maxCandles]
  /// nến MỚI NHẤT. [onProgress] báo (đã tải, mục tiêu) sau mỗi trang.
  /// KHÔNG chạm tới cache tín hiệu/chart (vẫn tối đa 300 nến).
  Future<List<RawCandle>> fetchCandlesHistory(
    String symbol,
    String tf, {
    int maxCandles = kMaxBacktestCandles,
    void Function(int loaded, int target)? onProgress,
  }) async {
    if (!tfMinutes.containsKey(tf)) {
      throw Exception('Khung không hỗ trợ: $tf');
    }
    final int target = maxCandles.clamp(1, kMaxBacktestCandles);
    if (_binanceSymbols.containsKey(symbol)) {
      return _fetchBinanceHistory(
        _binanceSymbols[symbol]!,
        _binanceIntervals[tf]!,
        target,
        onProgress,
      );
    }
    if (_krakenPairs.containsKey(symbol)) {
      return _fetchKrakenHistory(
        _krakenPairs[symbol]!,
        tfMinutes[tf]!,
        target,
        onProgress,
      );
    }
    if (symbol == 'USOIL') {
      final List<RawCandle> cs =
          await fetchYahooCandlesHistory(tf, maxCandles: target);
      onProgress?.call(cs.length, target);
      return cs;
    }
    throw Exception('Cặp không hỗ trợ nến thật: $symbol');
  }

  /// Lịch sử Binance: 1000 nến/trang -> tối đa 2 trang là đủ 2000;
  /// lấy tối đa 3 trang dự phòng khi có nến trùng/lệch biên.
  Future<List<RawCandle>> _fetchBinanceHistory(
    String binSymbol,
    String interval,
    int target,
    void Function(int loaded, int target)? onProgress,
  ) async {
    final Map<int, RawCandle> byTime = <int, RawCandle>{};
    int? endTimeMs;
    for (int page = 0; page < 3; page++) {
      final List<RawCandle> batch = await fetchBinanceKlinesPaged(
        binSymbol,
        interval,
        endTimeMs: endTimeMs,
      );
      if (batch.isEmpty) break;
      final int? prevOldest =
          byTime.isEmpty ? null : byTime.keys.reduce((a, b) => a < b ? a : b);
      for (final RawCandle c in batch) {
        byTime[c.t] = c;
      }
      onProgress?.call(
        byTime.length < target ? byTime.length : target,
        target,
      );
      if (byTime.length >= target) break;
      if (batch.length < kBinancePageLimit) break; // đã hết lịch sử
      final int oldest = byTime.keys.reduce((a, b) => a < b ? a : b);
      if (prevOldest != null && oldest >= prevOldest) break; // không tiến thêm
      endTimeMs = binanceNextEndTimeMs(oldest);
    }
    return _sortedTrimmed(byTime, target);
  }

  /// Lịch sử Kraken: 720 nến/trang -> 3 trang là đủ 2000; lấy tối đa
  /// 5 trang dự phòng khi có khoảng trống (forex nghỉ cuối tuần).
  Future<List<RawCandle>> _fetchKrakenHistory(
    String pair,
    int intervalMin,
    int target,
    void Function(int loaded, int target)? onProgress,
  ) async {
    final Map<int, RawCandle> byTime = <int, RawCandle>{};
    int? sinceSec;
    for (int page = 0; page < 5; page++) {
      final List<RawCandle> batch = await fetchKrakenOHLCPaged(
        pair,
        intervalMin,
        sinceSec: sinceSec,
      );
      if (batch.isEmpty) break;
      final int? prevOldest =
          byTime.isEmpty ? null : byTime.keys.reduce((a, b) => a < b ? a : b);
      for (final RawCandle c in batch) {
        byTime[c.t] = c;
      }
      onProgress?.call(
        byTime.length < target ? byTime.length : target,
        target,
      );
      if (byTime.length >= target) break;
      final int oldest = byTime.keys.reduce((a, b) => a < b ? a : b);
      if (prevOldest != null && oldest >= prevOldest) break; // không tiến thêm
      sinceSec = krakenNextSinceSec(
        oldestCandleMs: oldest,
        intervalMin: intervalMin,
      );
    }
    return _sortedTrimmed(byTime, target);
  }

  /// Điều phối tải nến theo cặp + khung (spec §2.5):
  ///   BTCUSD -> Binance BTCUSDT · XAUUSD -> Binance PAXGUSDT
  ///   5 cặp forex -> Kraken · USOIL -> Yahoo (CL=F).
  /// Trả về list tăng dần theo thời gian, tối đa 300 nến.
  /// Lỗi thì throw [Exception] với message ghi rõ nguồn.
  Future<List<RawCandle>> fetchCandles(String symbol, String tf) async {
    if (!tfMinutes.containsKey(tf)) {
      throw Exception('Khung không hỗ trợ: $tf');
    }
    if (_binanceSymbols.containsKey(symbol)) {
      return fetchBinanceKlines(_binanceSymbols[symbol]!, _binanceIntervals[tf]!);
    }
    if (_krakenPairs.containsKey(symbol)) {
      return fetchKrakenOHLC(_krakenPairs[symbol]!, tfMinutes[tf]!);
    }
    if (symbol == 'USOIL') {
      return fetchYahooCandles(tf);
    }
    throw Exception('Cặp không hỗ trợ nến thật: $symbol');
  }
}

/// Cache nến theo key "SYM|TF", chống tải trùng, cập nhật nến đang chạy
/// theo giá live và căn mức series 1 lần (spec §2.5).
class CandleCache {
  CandleCache({CandleFetcher? fetcher}) : fetcher = fetcher ?? CandleFetcher();

  final CandleFetcher fetcher;

  final Map<String, List<RawCandle>> _series = <String, List<RawCandle>>{};
  final Set<String> _shifted = <String>{};
  final Map<String, Future<List<RawCandle>>> _loading =
      <String, Future<List<RawCandle>>>{};

  /// Lỗi tải gần nhất của từng series ("SYM|TF" -> message), null nếu chưa lỗi.
  final Map<String, String?> lastError = <String, String?>{};

  static String keyOf(String symbol, String tf) => '$symbol|$tf';

  /// Lấy nến cho cặp + khung: có cache thì trả ngay, đang tải thì await
  /// chung 1 future (chống tải trùng), chưa có thì fetch từ nguồn.
  Future<List<RawCandle>> ensureCandles(String symbol, String tf) {
    final String key = keyOf(symbol, tf);
    final List<RawCandle>? cached = _series[key];
    if (cached != null) {
      return Future<List<RawCandle>>.value(cached);
    }
    final Future<List<RawCandle>>? inFlight = _loading[key];
    if (inFlight != null) {
      return inFlight;
    }
    final Future<List<RawCandle>> future = fetcher.fetchCandles(symbol, tf).then(
      (List<RawCandle> cs) {
        _series[key] = cs;
        lastError[key] = null;
        return cs;
      },
    ).catchError((Object e) {
      lastError[key] = e.toString();
      throw e;
    });
    _loading[key] = future;
    // Dọn future khỏi _loading khi xong (thành công hay lỗi) để lần sau
    // có thể thử lại. KHÔNG dùng whenComplete ở đây: whenComplete trả về
    // 1 future mới cũng lỗi theo, không ai await -> lỗi văng ra zone và
    // main.dart thay cả app bằng màn hình "App gặp lỗi khi mở" mỗi khi
    // 1 lần tải nến lỗi (đây là 1 trong 2 nguyên nhân gốc của lỗi "phải
    // tắt mở lại mới load được", xác nhận bằng test 18/11). Dùng then()
    // kèm onError để tự xử lý lỗi, future dẫn xuất không bao giờ lỗi nữa.
    // LƯU Ý (đã kiểm chứng bằng thí nghiệm Dart 18/11): callback onError
    // PHẢI trả void (dạng block-body) — nếu trả về giá trị khác void
    // (VD `=> _loading.remove(key)` trả bool) thì lỗi gốc vẫn bị báo
    // ra zone như lỗi không bắt được, dù caller đã try/catch.
    unawaited(future.then<void>(
      (_) {
        _loading.remove(key);
      },
      onError: (Object _, StackTrace __) {
        _loading.remove(key);
      },
    ));
    return future;
  }

  /// Series đã tải (null nếu chưa tải).
  List<RawCandle>? seriesOrNull(String symbol, String tf) =>
      _series[keyOf(symbol, tf)];

  /// Nến đã đóng = cache bỏ phần tử cuối (nến đang chạy).
  /// Trả [] nếu chưa tải hoặc < 3 nến (spec web: null nếu < 3 nến).
  List<RawCandle> closed(String symbol, String tf) {
    final List<RawCandle>? cs = _series[keyOf(symbol, tf)];
    if (cs == null || cs.length < 3) {
      return <RawCandle>[];
    }
    return cs.sublist(0, cs.length - 1);
  }

  /// Cập nhật nến đang chạy theo giá live mới (spec §2.5).
  /// Biên khung: start = (nowMs ~/ stepMs) * stepMs.
  /// Nến cuối có t < start -> push nến mới {t: start, o: close nến trước,
  /// h/l/c: giá}; ngược lại cập nhật c = giá, mở rộng h/l nếu vượt.
  /// Cắt cache tối đa 340 phần tử.
  void patchForming(String symbol, String tf, double price, int nowMs) {
    final int? stepMin = tfMinutes[tf];
    if (stepMin == null || price.isNaN || price <= 0) return;
    final List<RawCandle>? cs = _series[keyOf(symbol, tf)];
    if (cs == null || cs.isEmpty) return;
    final int stepMs = stepMin * 60 * 1000;
    final int start = (nowMs ~/ stepMs) * stepMs;
    final RawCandle last = cs.last;
    if (last.t < start) {
      cs.add(RawCandle(t: start, o: last.c, h: price, l: price, c: price, v: 0));
    } else {
      cs[cs.length - 1] = RawCandle(
        t: last.t,
        o: last.o,
        h: math.max(last.h, price),
        l: math.min(last.l, price),
        c: price,
        v: last.v,
      );
    }
    if (cs.length > kMaxCacheCandles) {
      cs.removeRange(0, cs.length - kMaxCacheCandles);
    }
  }

  /// Căn mức series theo giá live lần đầu (spec §2.5, maybeShiftSeries):
  /// f = livePrice / close nến cuối; nếu |f-1| > 0,0004 thì nhân toàn bộ
  /// o,h,l,c của series với f. Chỉ làm 1 lần/series.
  /// BỎ QUA với BTCUSD (nến và giá cùng Binance).
  void maybeShift(String symbol, String tf, double livePrice) {
    if (symbol == 'BTCUSD') return;
    if (livePrice.isNaN || livePrice <= 0) return;
    final String key = keyOf(symbol, tf);
    if (_shifted.contains(key)) return;
    final List<RawCandle>? cs = _series[key];
    if (cs == null || cs.isEmpty) return;
    final double lastClose = cs.last.c;
    if (lastClose <= 0) return;
    final double f = livePrice / lastClose;
    _shifted.add(key);
    if ((f - 1).abs() <= 0.0004) return;
    for (int i = 0; i < cs.length; i++) {
      final RawCandle c = cs[i];
      cs[i] = RawCandle(
        t: c.t,
        o: c.o * f,
        h: c.h * f,
        l: c.l * f,
        c: c.c * f,
        v: c.v,
      );
    }
  }

  /// Xóa cache của 1 series (để tải lại từ đầu, kèm reset cờ đã căn mức).
  void invalidate(String symbol, String tf) {
    final String key = keyOf(symbol, tf);
    _series.remove(key);
    _shifted.remove(key);
    lastError.remove(key);
  }

  /// Đóng HttpClient của fetcher.
  void dispose() {
    fetcher.close();
  }
}
