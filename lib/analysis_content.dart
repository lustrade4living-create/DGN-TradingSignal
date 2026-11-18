// Nội dung phân tích vĩ mô — TradeSignal AI (phase Phân tích, spec §16.6).
//
// Các hàm THUẦN: không gọi API, không import engine.dart, chỉ suy luận
// xác định trong app từ dữ liệu đã có (giá live, lịch, tin, kết quả quét
// VolumeB/S). Tất cả text tiếng Việt.
//
// Mọi khối đều ghi rõ là NHẬN ĐỊNH suy luận trong app — không phải sự
// thật đã xảy ra, không phải dự báo chắc chắn. Riêng khối dòng tiền lớn
// ghi rõ app không có dữ liệu lệnh hay vị thế thật của bất kỳ tổ chức,
// cá mập hay nhà cái nào.

import 'news_live.dart';

/// Một mục nhận định trong khối vĩ mô (tiêu đề + nội dung).
class MacroSection {
  const MacroSection({required this.title, required this.body});

  final String title;
  final String body;
}

const String _macroDisclaimer =
    'NHẬN ĐỊNH được suy luận ngay trong trang từ giá live thật — '
    'không phải sự thật đã xảy ra và không phải dự báo chắc chắn.';

const String _flowDisclaimer =
    'NHẬN ĐỊNH suy luận từ chỉ báo Volume Profile và Delta ước tính — '
    'app không có dữ liệu lệnh hay vị thế thật của bất kỳ tổ chức, '
    'cá mập hay nhà cái nào.';

String _fmtPct(double v) {
  final sign = v > 0 ? '+' : (v < 0 ? '−' : '');
  return '$sign${v.abs().toStringAsFixed(2).replaceAll('.', ',')}%';
}

String _fmtPrice(double v, [int dec = 2]) => v.toStringAsFixed(dec);

String _two(int v) => v.toString().padLeft(2, '0');

/// DD/MM HH:MM (giờ địa phương của máy, user đặt múi giờ VN).
String _fmtDayTime(DateTime dt) {
  final l = dt.toLocal();
  return '${_two(l.day)}/${_two(l.month)} '
      '${_two(l.hour)}:${_two(l.minute)}';
}

/// Nhận định vĩ mô — đúng spec §16.6 khối 1.
///
/// Sức mạnh USD suy từ % 24h của 5 cặp forex:
/// usdParts = [−chg(EURUSD), −chg(GBPUSD), +chg(USDJPY), +chg(USDCAD),
/// +chg(USDCHF)], trung bình -> > +0,15% "USD mạnh", < −0,15% "USD yếu",
/// còn lại "đi ngang". Cặp nào thiếu % 24h thì bỏ khỏi trung bình;
/// thiếu hết thì ghi rõ chưa đủ dữ liệu (không bịa).
///
/// [goldBias]: bias H4 của vàng, vd 'bullish' / 'bearish' / 'Tăng' / 'Giảm'.
/// [upcomingHigh]: sự kiện mức High (đã lọc sẵn từ lịch); chỉ lấy các
/// sự kiện trong 24h tới, tối đa 6.
List<MacroSection> macroCommentary({
  required Map<String, double> chg24h,
  required double goldPrice,
  required String goldBias,
  required double? btcChg,
  required double? oilPrice,
  required List<CalEvent> upcomingHigh,
}) {
  final now = DateTime.now();

  // --- Sức mạnh USD -------------------------------------------------------
  final usdParts = <String, double>{};
  double? _part(String sym, double Function(double) f) {
    final v = chg24h[sym];
    if (v == null) return null;
    return f(v);
  }

  final eurPart = _part('EURUSD', (v) => -v);
  final gbpPart = _part('GBPUSD', (v) => -v);
  final jpyPart = _part('USDJPY', (v) => v);
  final cadPart = _part('USDCAD', (v) => v);
  final chfPart = _part('USDCHF', (v) => v);
  if (eurPart != null) usdParts['EURUSD'] = eurPart;
  if (gbpPart != null) usdParts['GBPUSD'] = gbpPart;
  if (jpyPart != null) usdParts['USDJPY'] = jpyPart;
  if (cadPart != null) usdParts['USDCAD'] = cadPart;
  if (chfPart != null) usdParts['USDCHF'] = chfPart;

  double? usdAvg;
  String usdVerdict;
  String usdDetail;
  if (usdParts.isEmpty) {
    usdVerdict = 'chưa đủ dữ liệu để kết luận';
    usdDetail =
        'Chưa có % thay đổi 24h của cặp forex nào (EURUSD, GBPUSD, '
        'USDJPY, USDCAD, USDCHF) nên chưa suy được sức mạnh USD.';
  } else {
    usdAvg = usdParts.values.reduce((a, b) => a + b) / usdParts.length;
    if (usdAvg > 0.15) {
      usdVerdict = 'USD mạnh';
    } else if (usdAvg < -0.15) {
      usdVerdict = 'USD yếu';
    } else {
      usdVerdict = 'USD đi ngang';
    }
    final partsTxt = usdParts.entries
        .map((e) => '${e.key} đóng góp ${_fmtPct(e.value)}')
        .join(' · ');
    usdDetail = 'Trung bình 5 đóng góp: ${_fmtPct(usdAvg)} '
        '(${usdParts.length}/5 cặp có dữ liệu). $partsTxt.';
  }

  // --- Vàng ----------------------------------------------------------------
  final biasLower = goldBias.toLowerCase();
  final String goldDir;
  if (biasLower.contains('bull') || biasLower.contains('tăng')) {
    goldDir = 'tăng';
  } else if (biasLower.contains('bear') || biasLower.contains('giảm')) {
    goldDir = 'giảm';
  } else {
    goldDir = 'chưa rõ hướng';
  }
  final usdForGold = usdAvg == null
      ? ''
      : usdAvg > 0.15
          ? ' USD mạnh thường gây áp lực giảm lên vàng (vàng định giá bằng USD).'
          : usdAvg < -0.15
              ? ' USD yếu thường hỗ trợ giá vàng.'
              : ' USD đi ngang nên ít tạo áp lực một chiều lên vàng.';

  // --- Sự kiện High 24h tới ----------------------------------------------
  final upcoming = upcomingHigh
      .where((e) =>
          e.time.isAfter(now) &&
          e.time.difference(now) <= const Duration(hours: 24))
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  final upcomingTop = upcoming.take(6).toList();
  final eventsTxt = upcomingTop.isEmpty
      ? 'Không có sự kiện mức High nào trong 24 giờ tới (theo lịch đã tải).'
      : upcomingTop
          .map((e) =>
              '• ${_fmtDayTime(e.time)} — ${e.title} (${e.country}) · High')
          .join('\n');

  return <MacroSection>[
    MacroSection(
      title: 'Sức mạnh đồng USD',
      body: 'Kết luận: $usdVerdict. $usdDetail\n$_macroDisclaimer',
    ),
    MacroSection(
      title: 'Vàng (XAUUSD)',
      body: 'Giá live hiện tại ${_fmtPrice(goldPrice)} USD/oz. '
          'Bias H4: $goldBias (xu hướng $goldDir).$usdForGold\n'
          '$_macroDisclaimer',
    ),
    MacroSection(
      title: 'Bitcoin & khẩu vị rủi ro',
      body: btcChg == null
          ? 'Chưa có % thay đổi 24h của BTCUSD nên chưa nhận định được '
              'khẩu vị rủi ro từ Bitcoin.\n$_macroDisclaimer'
          : 'BTCUSD thay đổi ${_fmtPct(btcChg)} trong 24h. '
              '${btcChg > 0.5 ? 'Bitcoin tăng cho thấy khẩu vị rủi ro đang mở — dòng tiền chấp nhận rủi ro, có thể bớt tìm nơi trú ẩn như vàng.' : btcChg < -0.5 ? 'Bitcoin giảm cho thấy khẩu vị rủi ro đang thu hẹp — dòng tiền có xu hướng thận trọng, có thể tìm nơi trú ẩn.' : 'Bitcoin đi ngang nên chưa cho tín hiệu rõ về khẩu vị rủi ro.'}\n'
              '$_macroDisclaimer',
    ),
    MacroSection(
      title: 'Dầu WTI (USOIL)',
      body: oilPrice == null
          ? 'Chưa có giá live của dầu WTI nên chưa nhận định được diễn biến dầu.\n$_macroDisclaimer'
          : 'Giá dầu WTI live hiện tại ${_fmtPrice(oilPrice)} USD/thùng. '
              'Dầu tăng thường đi kèm kỳ vọng lạm phát cao hơn, có thể gián tiếp hỗ trợ vàng với vai trò chống lạm phát; dầu giảm thì áp lực đó nhẹ đi.\n'
              '$_macroDisclaimer',
    ),
    MacroSection(
      title: 'Sự kiện mạnh 24h tới',
      body: '${upcoming.length > 6 ? 'Có ${upcoming.length} sự kiện High trong 24h tới, hiện 6 sự kiện gần nhất:\n' : ''}$eventsTxt\n'
          'Các sự kiện High, nhất là tin vàng (CPI, NFP, FOMC, PPI, GDP Mỹ, phát biểu Fed), có thể gây biến động mạnh quanh giờ công bố — cân nhắc giảm rủi ro trước giờ tin.\n'
          '$_macroDisclaimer',
    ),
    MacroSection(
      title: 'Tổng hợp',
      body: 'USD: $usdVerdict. Vàng: giá ${_fmtPrice(goldPrice)} USD/oz, '
          'bias H4 $goldDir. '
          '${upcomingTop.isEmpty ? 'Không có sự kiện High nào trong 24h tới.' : 'Có ${upcoming.length} sự kiện High trong 24h tới — chú ý giờ tin trước khi vào lệnh mới.'}\n'
          '$_macroDisclaimer',
    ),
  ];
}

// ---------------------------------------------------------------------------
// Tin tức đang tác động lên từng cặp (spec §16.6 khối 2)
// ---------------------------------------------------------------------------

/// Từ khóa riêng từng cặp để ghép tin (khớp trong tiêu đề + tóm tắt,
/// không phân biệt hoa thường). Đúng spec §16.6.
const Map<String, List<String>> pairNewsKeywords = <String, List<String>>{
  'BTCUSD': <String>['bitcoin', 'btc', 'crypto'],
  'XAUUSD': <String>['gold', 'xau', 'silver'],
  'EURUSD': <String>['euro', 'ecb', 'eurozone'],
  'GBPUSD': <String>['pound', 'gbp', 'boe', 'bank of england', 'british'],
  'USDCAD': <String>['canadian', 'cad', 'bank of canada', 'usd/cad'],
  'USDCHF': <String>['swiss', 'chf', 'franc', 'snb'],
  'USDJPY': <String>['yen', 'jpy', 'boj', 'bank of japan', 'japan'],
  'USOIL': <String>['oil', 'crude', 'wti', 'opec'],
};

/// Từ khóa chung USD/Fed — yếu tố chung cho cả 8 cặp.
const List<String> _commonUsdFedKeywords = <String>[
  'federal reserve',
  'fed',
  'dollar',
  'inflation',
  'treasury',
  'yield',
  'rate hike',
  'rate cut',
  'fomc',
  'cpi',
  'powell',
];

/// Ghép tin cho từng cặp: tối đa 3 tin riêng (từ khóa của cặp) + tối đa
/// 2 tin chung USD/Fed, theo thứ tự tin mới nhất trong [news] (tin đã
/// ghép riêng thì không ghép lại ở nhóm chung).
Map<String, List<NewsItem>> pairNews(List<NewsItem> news) {
  final result = <String, List<NewsItem>>{};
  for (final entry in pairNewsKeywords.entries) {
    final own = <NewsItem>[];
    final common = <NewsItem>[];
    final usedKeys = <String>{};
    for (final n in news) {
      if (own.length >= 3) break;
      final hay = '${n.title} ${n.summary}'.toLowerCase();
      if (entry.value.any(hay.contains)) {
        own.add(n);
        usedKeys.add('${n.link}|${n.title}');
      }
    }
    for (final n in news) {
      if (common.length >= 2) break;
      final key = '${n.link}|${n.title}';
      if (usedKeys.contains(key)) continue;
      final hay = '${n.title} ${n.summary}'.toLowerCase();
      if (_commonUsdFedKeywords.any(hay.contains)) {
        common.add(n);
      }
    }
    result[entry.key] = <NewsItem>[...own, ...common];
  }
  return result;
}

// ---------------------------------------------------------------------------
// Nhận định biến động — dòng tiền lớn (spec §16.6 khối 3)
// ---------------------------------------------------------------------------

/// Ảnh chụp tối giản của một dòng quét VolumeB/S (TonyD) cho một cặp.
/// Module quét VP map kết quả quét của nó sang view này ở tầng tích hợp.
class VpScanView {
  const VpScanView({
    required this.symbol,
    required this.action,
    required this.h1Trend,
    required this.nearPoc,
    required this.price,
    this.poc,
    this.vah,
    this.val,
    this.deltaPct,
  });

  /// Mã cặp, vd 'XAUUSD'.
  final String symbol;

  /// Hướng quét: 'BUY' / 'SELL' / 'WAIT'.
  final String action;

  /// Xu hướng H1 (Ichimoku), vd 'Tăng' / 'Giảm' / 'Đi ngang'.
  final String h1Trend;

  /// Giá có đang tại vùng POC không.
  final bool nearPoc;

  /// Giá live hiện tại.
  final double price;

  /// POC / VAH / VAL của Volume Profile M15 (null nếu chưa tính được).
  final double? poc;
  final double? vah;
  final double? val;

  /// Delta ước tính từ nến (%, dương = phe mua áp đảo). KHÔNG phải
  /// Delta tick thật — chỉ ước tính từ vị trí đóng nến.
  final double? deltaPct;
}

/// Một dòng nhận định dòng tiền lớn cho một cặp.
class FlowNote {
  const FlowNote({required this.symbol, required this.text});

  final String symbol;
  final String text;
}

/// Nhận định biến động — dòng tiền lớn, đọc từ kết quả quét VolumeB/S
/// từng cặp (đúng spec §16.6 khối 3):
/// - ngay vùng POC -> tranh chấp;
/// - ngoài VAH/VAL -> phá vỡ thật hay quét thanh khoản;
/// - trong vùng giá trị + Delta dương/âm -> chấp nhận giá cao/thấp hay
///   hấp thụ/chốt lời.
/// Mỗi ghi chú kèm disclaimer: app không có dữ liệu lệnh hay vị thế thật
/// của bất kỳ tổ chức, cá mập hay nhà cái nào.
List<FlowNote> bigMoneyNotes(Map<String, VpScanView> scans) {
  final notes = <FlowNote>[];
  for (final scan in scans.values) {
    notes.add(FlowNote(symbol: scan.symbol, text: _flowText(scan)));
  }
  return notes;
}

String _flowText(VpScanView s) {
  final poc = s.poc;
  final vah = s.vah;
  final val = s.val;
  if (poc == null || vah == null || val == null) {
    return '${s.symbol}: chưa đủ dữ liệu Volume Profile M15 '
        '(POC/VAH/VAL) để nhận định dòng tiền. '
        'Xu hướng H1 hiện tại: ${s.h1Trend}. $_flowDisclaimer';
  }

  final buf = StringBuffer('${s.symbol}: ');
  buf.write('POC ${_fmtPrice(poc)} · vùng giá trị '
      '${_fmtPrice(val)} – ${_fmtPrice(vah)} · xu hướng H1 ${s.h1Trend} · '
      'quét VolumeB/S: ${s.action}. ');

  if (s.nearPoc) {
    buf.write('Giá đang ngay vùng POC — vùng tranh chấp: phe mua và phe '
        'bán đang giằng co quanh mức giá được giao dịch nhiều nhất. '
        'Chờ xác nhận (Sweep/CHoCH/BOS ở M5) rồi mới kết luận phe nào '
        'đang kiểm soát. ');
  } else if (s.price > vah) {
    buf.write('Giá đã vượt lên trên VAH (biên trên vùng giá trị) — nằm '
        'ngoài vùng giá trị: cần xem đây là phá vỡ thật (đóng nến vững '
        'trên VAH, Delta ủng hộ hướng lên) hay chỉ là quét thanh khoản '
        'rồi quay lại vùng giá trị. ');
  } else if (s.price < val) {
    buf.write('Giá đã rơi xuống dưới VAL (biên dưới vùng giá trị) — nằm '
        'ngoài vùng giá trị: cần xem đây là phá vỡ thật (đóng nến vững '
        'dưới VAL, Delta ủng hộ hướng xuống) hay chỉ là quét thanh khoản '
        'rồi quay lại vùng giá trị. ');
  } else {
    // Trong vùng giá trị.
    final d = s.deltaPct;
    if (d == null) {
      buf.write('Giá đang trong vùng giá trị, chưa có Delta ước tính để '
          'đọc thêm phe nào đang chủ động. ');
    } else if (d > 0) {
      buf.write('Giá đang trong vùng giá trị và Delta ước tính dương '
          '(${_fmtPct(d)}) — phe mua đang chấp nhận giá cao dần trong '
          'vùng, chưa thấy dấu hiệu hấp thụ hay chốt lời mạnh. ');
    } else if (d < 0) {
      buf.write('Giá đang trong vùng giá trị và Delta ước tính âm '
          '(${_fmtPct(d)}) — phe bán đang chấp nhận giá thấp dần trong '
          'vùng; có thể là hấp thụ dần hoặc chốt lời, chưa phải đảo '
          'chiều chắc chắn. ');
    } else {
      buf.write('Giá đang trong vùng giá trị và Delta ước tính gần 0 — '
          'chưa thấy phe nào áp đảo trong vùng. ');
    }
  }

  buf.write('Delta ở đây là ước tính từ nến (vị trí đóng nến trong biên), '
      'không phải Delta tick thật. $_flowDisclaimer');
  return buf.toString();
}
