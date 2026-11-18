// Tin tức LIVE (FXStreet RSS) + Lịch kinh tế (ForexFactory) — TradeSignal AI.
//
// Port từ bản web (spec §14). Thuần Dart, không plugin, không package mới.
// Nguyên tắc: KHÔNG BAO GIỜ hiện số giả làm số thật. Tin/lịch lấy không
// được thì hiện rõ trạng thái lỗi, KHÔNG nhúng snapshot tin/lịch cũ
// (bản web có NEWS_SNAP / CAL_SNAP ngày 13–20/11/2026 — Flutter KHÔNG
// nhúng snapshot này). Khi chưa lấy được thì giữ dữ liệu đã lấy được
// trong phiên (nếu có) và ghi rõ là có thể đã cũ.
//
// Nguồn tin: FXStreet RSS — https://www.fxstreet.com/rss/news
//   (1) qua rss2json, (2) dự phòng qua allorigins (parse XML bằng regex
//   thủ công vì project không có package XML — dễ vỡ nếu FXStreet đổi
//   format, xem ghi chú cuối file).
// Nguồn lịch: https://nfs.faireconomy.media/ff_calendar_thisweek.json
//   (ForexFactory). Lỗi -> throw Exception, UI hiện
//   "CHƯA LẤY ĐƯỢC LỊCH TRỰC TIẾP".

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'safe_json.dart';

/// Một tin tức lấy từ FXStreet RSS.
class NewsItem {
  const NewsItem({
    required this.title,
    required this.link,
    required this.summary,
    required this.pubDate,
    required this.goldTag,
    this.source = 'FXStreet',
  });

  /// Tiêu đề tin.
  final String title;

  /// Link bài gốc.
  final String link;

  /// Tóm tắt đã strip HTML, tối đa 300 ký tự.
  final String summary;

  /// Giờ đăng (giờ gốc của nguồn; hiển thị thì dùng [NewsService.fmtDayTimeVN]).
  final DateTime pubDate;

  /// Tác động với vàng: 'pos' (tích cực) / 'neg' (tiêu cực) / 'neu' (trung tính).
  final String goldTag;

  /// Luôn là 'FXStreet'.
  final String source;

  /// Nhãn hiển thị của [goldTag].
  String get goldTagLabel {
    switch (goldTag) {
      case 'pos':
        return 'Tích cực cho vàng';
      case 'neg':
        return 'Tiêu cực cho vàng';
      default:
        return 'Trung tính';
    }
  }
}

/// Một sự kiện trong lịch kinh tế (ForexFactory).
class CalEvent {
  const CalEvent({
    required this.title,
    required this.country,
    required this.impact,
    required this.time,
    this.forecast,
    this.previous,
    this.actual,
  });

  /// Tên sự kiện.
  final String title;

  /// Mã nước, vd 'USD'.
  final String country;

  /// Mức độ: 'High' / 'Medium' / 'Low'.
  final String impact;

  /// Thời điểm diễn ra (có offset trong JSON gốc; hiển thị giờ VN bằng
  /// [NewsService.fmtDayTimeVN] / [NewsService.fmtHourMinuteVN]).
  final DateTime time;

  /// Dự báo / kỳ trước / thực tế (thiếu -> null, UI hiện "—").
  final String? forecast;
  final String? previous;
  final String? actual;

  /// Tin vàng: nước USD và tên khớp CPI/PPI/GDP/NFP/FOMC/Fed...
  /// (đúng spec §14.2: c == "USD" và regex
  /// /cpi|ppi|gdp|nonfarm|non-farm|payroll|fomc|federal funds|fed chair|powell|speaks/i).
  bool get isGold {
    if (country.trim().toUpperCase() != 'USD') return false;
    return _goldEventRe.hasMatch(title);
  }

  static final RegExp _goldEventRe = RegExp(
    r'cpi|ppi|gdp|nonfarm|non-farm|payroll|fomc|federal funds|fed chair|powell|speaks',
    caseSensitive: false,
  );
}

/// Service quét tin LIVE + tải lịch kinh tế.
///
/// Dùng chung 1 [HttpClient], timeout 8 giây/lần gọi. Quét tin theo ticker
/// 1 giây với giãn nhịp khi lỗi: 1s -> 2s -> 4s -> 8s -> ... -> tối đa 60s
/// (đúng spec §14.1: delay = failCount <= 0 ? 1000 : min(60000, 1000 * 2^failCount) ms).
class NewsService extends ChangeNotifier {
  NewsService() {
    _client.connectionTimeout = const Duration(seconds: 8);
  }

  static const String _rssUrl = 'https://www.fxstreet.com/rss/news';
  static const String _calendarUrl =
      'https://nfs.faireconomy.media/ff_calendar_thisweek.json';

  /// Từ khóa lọc tin cố định (chip trên UI, đúng spec §14.1).
  static const List<String> filterKeywords = <String>[
    'Tất cả',
    'gold',
    'XAU',
    'Federal Reserve',
    'inflation',
    'dollar',
    'DXY',
    'treasury yield',
  ];

  final HttpClient _client = HttpClient();

  /// Danh sách tin đang hiển thị (tối đa 30 tin). Lỗi quét KHÔNG xóa
  /// danh sách này — giữ tin đã lấy được, UI ghi rõ có thể đã cũ.
  List<NewsItem> items = <NewsItem>[];

  /// Giờ quét gần nhất (mỗi lần thử lấy tin, kể cả thất bại).
  DateTime? lastScanAt;

  /// Giờ lấy tin thành công gần nhất.
  DateTime? lastSuccessAt;

  /// Số lần quét thất bại liên tiếp (thành công 1 lần -> về 0).
  int failCount = 0;

  /// Lịch tuần lấy trực tiếp thành công gần nhất, giữ trong bộ nhớ phiên.
  /// Lỗi tải lịch -> giữ nguyên danh sách này, UI hiện
  /// "CHƯA LẤY ĐƯỢC LỊCH TRỰC TIẾP".
  List<CalEvent> lastGood = <CalEvent>[];

  Timer? _timer;
  DateTime? _lastAttempt;
  bool _fetching = false;
  String _combinedKey = '';

  /// true khi lần quét gần nhất thành công (chưa từng lỗi kể từ đó).
  bool get isLive => lastSuccessAt != null && failCount == 0;

  /// Nhịp giãn hiện tại (ms) theo [failCount].
  int get delayMs {
    if (failCount <= 0) return 1000;
    var d = 1000;
    for (var i = 0; i < failCount && d < 60000; i++) {
      d *= 2;
    }
    return math.min(60000, d);
  }

  /// Nhịp giãn hiện tại (giây, làm tròn xuống).
  int get delaySeconds => delayMs ~/ 1000;

  /// Trạng thái hiển thị cho UI (đúng 3 dạng của spec §14.1).
  String get statusText {
    if (lastSuccessAt == null && items.isEmpty) {
      return 'CHƯA LẤY ĐƯỢC TIN LIVE';
    }
    if (_fetching) return 'Đang quét nguồn tin…';
    if (failCount > 0) {
      return 'Nguồn lỗi — đã giãn nhịp, lần quét sau sau ~$delaySeconds giây';
    }
    return 'Đang quét mỗi 1 giây';
  }

  /// Dòng "Quét gần nhất: HH:MM:SS (giờ VN)" để UI hiển thị kèm [statusText].
  String get scanInfo {
    if (lastScanAt == null) return 'Chưa quét lần nào';
    return 'Quét gần nhất: ${fmtTimeVN(lastScanAt!)} (giờ VN)';
  }

  /// Nhãn LIVE cho header: tin lấy trực tiếp từ FXStreet RSS + giờ lấy mới nhất.
  String get liveLabel {
    if (lastSuccessAt == null) return 'CHƯA LẤY ĐƯỢC TIN LIVE';
    return '● LIVE — tin lấy trực tiếp từ FXStreet RSS, '
        'dữ liệu mới nhất lấy lúc ${fmtTimeVN(lastSuccessAt!)} (giờ VN)';
  }

  // ---------------------------------------------------------------------------
  // Quét tin
  // ---------------------------------------------------------------------------

  /// Bắt đầu ticker quét 1 giây. Gọi 1 lần khi vào phase Tin tức
  /// (gọi lại không tạo thêm timer).
  void startScanning() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_scanTick());
    });
  }

  /// Dừng ticker quét.
  void stopScanning() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _scanTick() async {
    if (_fetching) return; // đang fetch thì bỏ qua tick này
    final now = DateTime.now();
    if (_lastAttempt != null &&
        now.difference(_lastAttempt!).inMilliseconds < delayMs) {
      return; // chưa tới lúc (đang giãn nhịp)
    }
    await fetchOnce();
  }

  /// Một lần thử lấy tin: rss2json trước, allorigins dự phòng.
  /// Thành công -> failCount = 0, lastSuccessAt = now; thất bại cả 2
  /// đường -> failCount++, KHÔNG xóa tin cũ.
  Future<void> fetchOnce() async {
    if (_fetching) return;
    _fetching = true;
    _lastAttempt = DateTime.now();
    lastScanAt = _lastAttempt;

    List<NewsItem>? fresh;
    try {
      fresh = await _fetchViaRss2Json();
    } catch (_) {
      fresh = null;
    }
    if (fresh == null) {
      try {
        fresh = await _fetchViaAllOrigins();
      } catch (_) {
        fresh = null;
      }
    }

    final hadFailures = failCount > 0;
    if (fresh == null || fresh.isEmpty) {
      failCount++;
      _fetching = false;
      notifyListeners();
      return;
    }

    failCount = 0;
    lastSuccessAt = DateTime.now();
    final capped = fresh.take(30).toList();
    final combinedKey = capped.map(_newsKey).join('\n');
    _fetching = false;
    // Chỉ thay danh sách + notify khi key tổng khác key tổng cũ
    // (quét 1 giây mà không có tin mới thì giữ nguyên, không nhấp nháy).
    if (combinedKey != _combinedKey) {
      _combinedKey = combinedKey;
      items = capped;
      notifyListeners();
    } else if (hadFailures) {
      // Tin không đổi nhưng vừa hồi phục sau chuỗi lỗi -> cập nhật trạng thái.
      notifyListeners();
    }
  }

  static String _newsKey(NewsItem n) => '${n.link}|${n.title}';

  /// Đường 1: rss2json. Yêu cầu status == "ok" và items không rỗng.
  Future<List<NewsItem>> _fetchViaRss2Json() async {
    final url =
        'https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(_rssUrl)}';
    final body = await _getText(url);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('rss2json trả về không phải JSON object');
    }
    if (data['status'] != 'ok') {
      throw FormatException('rss2json status != ok: ${data['status']}');
    }
    final List<dynamic>? rawItems = asList(data['items']);
    if (rawItems == null || rawItems.isEmpty) {
      throw const FormatException('rss2json items rỗng');
    }
    final out = <NewsItem>[];
    final seen = <String>{};
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final title = strOf(raw['title']).trim();
      final link = strOf(raw['link']).trim();
      if (title.isEmpty) continue;
      if (!seen.add('$link|$title')) continue; // dedupe theo url|title
      final summary =
          _truncate(_stripHtml(strOf(raw['description'])), 300);
      out.add(NewsItem(
        title: title,
        link: link,
        summary: summary,
        pubDate: _parsePubDate(strOf(raw['pubDate'])),
        goldTag: goldTagFor(title, summary),
      ));
    }
    if (out.isEmpty) {
      throw const FormatException('rss2json không có tin hợp lệ');
    }
    return out;
  }

  /// Đường 2 (dự phòng): allorigins trả XML RSS gốc, parse bằng regex
  /// thủ công (không có package XML). Dễ vỡ nếu FXStreet đổi format.
  Future<List<NewsItem>> _fetchViaAllOrigins() async {
    final url =
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(_rssUrl)}';
    final xml = await _getText(url);
    final itemRe = RegExp(r'<item(?:\s[^>]*)?>(.*?)</item>', dotAll: true);
    final out = <NewsItem>[];
    final seen = <String>{};
    for (final m in itemRe.allMatches(xml)) {
      final block = m.group(1)!;
      final title = _tagText(block, 'title');
      final link = _tagText(block, 'link');
      if (title.isEmpty) continue;
      if (!seen.add('$link|$title')) continue;
      final summary =
          _truncate(_stripHtml(_tagText(block, 'description')), 300);
      out.add(NewsItem(
        title: title,
        link: link,
        summary: summary,
        pubDate: _parsePubDate(_tagText(block, 'pubDate')),
        goldTag: goldTagFor(title, summary),
      ));
    }
    if (out.isEmpty) {
      throw const FormatException('allorigins: không parse được item nào');
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Tag tác động với vàng + lọc tin
  // ---------------------------------------------------------------------------

  static const List<String> _negKeywords = <String>[
    'rate hike',
    'hawkish',
    'stronger dollar',
    'dollar strengthens',
    'dollar holds gains',
    'yields rise',
    'higher yields',
    'supports usd',
    'support usd',
    'firm dollar',
    'strong dollar',
  ];

  static const List<String> _posKeywords = <String>[
    'rate cut',
    'safe-haven',
    'safe haven',
    'weaker dollar',
    'dollar falls',
    'dollar declines',
    'dovish',
    'easing bets',
    'gold rises',
    'gold gains',
    'gold climbs',
    'gold surges',
  ];

  /// Tag tác động với vàng từ tiêu đề + tóm tắt (chữ thường).
  /// Cả hai phe hoặc không có từ khóa nào -> 'neu'.
  String goldTagFor(String title, String summary) {
    final text = '$title $summary'.toLowerCase();
    final hasNeg = _negKeywords.any(text.contains);
    final hasPos = _posKeywords.any(text.contains);
    if (hasNeg == hasPos) return 'neu';
    return hasPos ? 'pos' : 'neg';
  }

  /// Lọc tin theo chuỗi con (không phân biệt hoa thường) trong tiêu đề
  /// + tóm tắt. Từ khóa 'Tất cả' (hoặc rỗng) -> trả toàn bộ.
  List<NewsItem> filter(String keyword) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty || kw == 'tất cả') {
      return List<NewsItem>.unmodifiable(items);
    }
    return items
        .where((n) => '${n.title} ${n.summary}'.toLowerCase().contains(kw))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Lịch kinh tế
  // ---------------------------------------------------------------------------

  /// Tải lịch tuần trực tiếp từ ForexFactory.
  /// Thành công -> cập nhật [lastGood] + trả danh sách (đã sort theo giờ).
  /// Lỗi -> throw [Exception], để UI hiện "CHƯA LẤY ĐƯỢC LỊCH TRỰC TIẾP"
  /// (giữ [lastGood] cũ trong phiên).
  Future<List<CalEvent>> fetchCalendar() async {
    final body = await _getText(_calendarUrl);
    final data = jsonDecode(body);
    if (data is! List) {
      throw const FormatException('Lịch ForexFactory không phải danh sách');
    }
    final events = <CalEvent>[];
    for (final raw in data) {
      if (raw is! Map<String, dynamic>) continue;
      final time = DateTime.tryParse(strOf(raw['date']).trim());
      if (time == null) continue;
      events.add(CalEvent(
        title: strOf(raw['title']).trim(),
        country: strOf(raw['country']).trim(),
        impact: strOf(raw['impact']).trim(),
        time: time,
        forecast: _strOrNull(raw['forecast']),
        previous: _strOrNull(raw['previous']),
        actual: _strOrNull(raw['actual']),
      ));
    }
    events.sort((a, b) => a.time.compareTo(b.time));
    lastGood = events;
    notifyListeners();
    return events;
  }

  /// Sự kiện vàng mức High có 0 < (time − now) <= 15 phút (sớm nhất).
  /// UI dùng để hiện banner đỏ (xem [strongGoldBanner]).
  CalEvent? nextStrongGoldEvent(List<CalEvent> events, DateTime now) {
    CalEvent? best;
    for (final e in events) {
      if (!e.isGold) continue;
      if (e.impact.toLowerCase() != 'high') continue;
      final diff = e.time.difference(now);
      if (diff <= Duration.zero ||
          diff > const Duration(minutes: 15)) {
        continue;
      }
      if (best == null || e.time.isBefore(best.time)) best = e;
    }
    return best;
  }

  /// Nội dung banner đỏ khi sắp có tin mạnh ảnh hưởng vàng
  /// (đúng câu chữ spec §14.2).
  static String strongGoldBanner(CalEvent event, DateTime now) {
    final diff = event.time.difference(now);
    final mins = (diff.inSeconds + 59) ~/ 60; // làm tròn lên, tránh hiện 0 phút
    return 'Sắp có tin mạnh ảnh hưởng vàng: ${event.title} '
        '(${event.country}) lúc ${fmtHourMinuteVN(event.time)} — '
        'còn $mins phút. Cân nhắc đóng lệnh hoặc giảm rủi ro.';
  }

  // ---------------------------------------------------------------------------
  // HTTP + parse phụ trợ
  // ---------------------------------------------------------------------------

  /// GET text qua HttpClient dùng chung, timeout 8 giây/lần.
  /// Status != 200 -> throw.
  Future<String> _getText(String url) async {
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'TradeSignalAI/1.2.0 (Dart HttpClient)',
    );
    req.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/xml, */*',
    );
    final resp = await req.close().timeout(const Duration(seconds: 8));
    final body = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode} — $url',
          uri: Uri.parse(url));
    }
    return body;
  }

  static String? _strOrNull(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Bỏ tag HTML, giải entity, gọn khoảng trắng.
  static String _stripHtml(String s) {
    var out = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
    out = _decodeEntities(out);
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Giải các HTML entity thường gặp (&amp; &lt; &gt; &quot; &#39; &nbsp;
  /// và entity số &#...;).
  static String _decodeEntities(String s) {
    var out = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return out;
  }

  /// Lấy nội dung của <tag>...</tag> trong 1 block <item>, hiểu CDATA.
  static String _tagText(String block, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>(.*?)</$tag>', dotAll: true)
        .firstMatch(block);
    if (m == null) return '';
    var v = m.group(1)!.trim();
    if (v.startsWith('<![CDATA[') && v.endsWith(']]>')) {
      v = v.substring(9, v.length - 3);
    }
    return _decodeEntities(v).trim();
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return s.substring(0, max);
  }

  /// Parse ngày đăng tin. Chấp nhận:
  /// - ISO "2026-11-16 04:04:15" (rss2json) -> chuẩn hóa thành ISO UTC;
  /// - ISO 8601 có offset;
  /// - RFC 2822 "Mon, 16 Nov 2026 04:04:15 GMT" (RSS gốc qua allorigins).
  /// Không parse được -> giờ hiện tại (không để tin mất ngày).
  static DateTime _parsePubDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return DateTime.now();
    // ISO dạng "YYYY-MM-DD HH:MM[:SS]" (không múi giờ) -> coi là UTC.
    final isoLike =
        RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?(\.\d+)?$');
    if (isoLike.hasMatch(s)) {
      final normalized = s.replaceFirst(' ', 'T');
      final parsed = DateTime.tryParse('${normalized}Z');
      if (parsed != null) return parsed;
    }
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // RFC 2822: "Mon, 16 Nov 2026 04:04:15 GMT" / "+0200".
    final rfc = RegExp(
      r'^(?:\w{3},\s*)?(\d{1,2})\s+(\w{3})\s+(\d{4})\s+'
      r'(\d{2}):(\d{2})(?::(\d{2}))?\s+([+-]\d{4}|GMT|UTC|UT|Z)?',
    ).firstMatch(s);
    if (rfc != null) {
      const months = <String, int>{
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final month = months[rfc.group(2)!];
      if (month != null) {
        var utc = DateTime.utc(
          int.parse(rfc.group(3)!),
          month,
          int.parse(rfc.group(1)!),
          int.parse(rfc.group(4)!),
          int.parse(rfc.group(5)!),
          int.parse(rfc.group(6) ?? '0'),
        );
        final zone = rfc.group(7);
        if (zone != null && zone.startsWith(RegExp(r'[+-]'))) {
          final sign = zone[0] == '-' ? -1 : 1;
          final offH = int.parse(zone.substring(1, 3));
          final offM = int.parse(zone.substring(3, 5));
          utc = utc.subtract(
              Duration(minutes: sign * (offH * 60 + offM)));
        }
        return utc;
      }
    }
    return DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // Giờ hiển thị VN (máy user đặt múi giờ VN) — KHÔNG dùng package intl.
  // ---------------------------------------------------------------------------

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// HH:MM:SS (giờ địa phương của máy).
  static String fmtTimeVN(DateTime dt) {
    final l = dt.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
  }

  /// HH:MM (giờ địa phương của máy).
  static String fmtHourMinuteVN(DateTime dt) {
    final l = dt.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  /// DD/MM HH:MM (giờ địa phương của máy).
  static String fmtDayTimeVN(DateTime dt) {
    final l = dt.toLocal();
    return '${_two(l.day)}/${_two(l.month)} '
        '${_two(l.hour)}:${_two(l.minute)}';
  }

  /// Thứ…, DD/MM/YYYY (giờ địa phương của máy) — tiêu đề nhóm ngày lịch.
  static String fmtDayVN(DateTime dt) {
    const weekdays = <String>[
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    final l = dt.toLocal();
    return '${weekdays[l.weekday - 1]}, '
        '${_two(l.day)}/${_two(l.month)}/${l.year}';
  }

  @override
  void dispose() {
    stopScanning();
    _client.close();
    super.dispose();
  }
}
