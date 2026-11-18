// signal_status.dart — Trạng thái vào lệnh của tín hiệu: VÀO NGAY (NOW) /
// CHỜ LIMIT / KHÔNG NÊN VÀO NỮA (EXPIRED), cập nhật theo giá live.
//
// Thuần Dart, không phụ thuộc Flutter/engine — phân loại test được.
// KHÔNG đổi logic chốt tín hiệu tĩnh: Entry/SL/TP vẫn khóa theo nến H1
// đã đóng; file này chỉ ĐỌC Entry/SL/TP/ATR/closedAt và so với giá live.
//
// Quy tắc mặc định (ngưỡng theo ATR(H1)):
//   - NOW: giá live trong vùng Entry ±0,25×ATR(H1), HOẶC giá live đang ở
//     phía có lợi hơn Entry (BUY mà giá live < Entry, SELL mà giá live
//     > Entry). Trường hợp giá tốt hơn Entry thì kèm nhãn "giá tốt hơn Entry".
//   - LIMIT: giá live đã chạy xa khỏi Entry theo hướng có lợi
//     (BUY: > Entry + 0,25×ATR; SELL: < Entry − 0,25×ATR) và tín hiệu
//     còn hiệu lực — chờ giá hồi về Entry rồi đặt lệnh limit tại Entry.
//   - EXPIRED: giá đã chạm/vượt TP1, HOẶC cách Entry quá 1,0×ATR,
//     HOẶC đã quá thời gian hiệu lực (giờ ra tín hiệu + 1 giờ).
// Thứ tự ưu tiên khi nhiều điều kiện cùng đúng: EXPIRED trước, rồi NOW,
// rồi LIMIT.
//
// TP1 (mức TP đầu tiên): lấy từ thang TP (LadderLevels.t1) khi có; nếu
// chưa có TP1 riêng thì dùng TP1 = Entry ± 1×ATR theo hướng (BUY: Entry +
// 1×ATR; SELL: Entry − 1×ATR) và đánh dấu [tp1FromFallback] = true để UI
// và báo cáo ghi rõ lựa chọn này.
// Giờ hết hiệu lực dự kiến = giờ ra tín hiệu (closedAt) + 1 giờ (nến H1
// tiếp theo đóng), cùng quy ước với sigStopInfo() trong signal_core.dart.
import 'indicators.dart';
import 'signal_core.dart';

/// Ngưỡng vào ngay: ±0,25×ATR(H1) quanh Entry.
const double kNowAtr = 0.25;

/// Ngưỡng hết hiệu lực theo khoảng cách: quá 1,0×ATR(H1) khỏi Entry.
const double kExpiredAtr = 1.0;

/// Thời gian hiệu lực dự kiến của 1 tín hiệu (ms) = 1 giờ.
const int kSignalValidityMs = 3600000;

/// Giờ hết hiệu lực dự kiến từ giờ ra tín hiệu (closedAt, ms).
int signalExpiryMs(int issuedAtMs) => issuedAtMs + kSignalValidityMs;

/// TP1 mặc định khi chưa có TP1 riêng: Entry ± 1×ATR theo hướng.
double fallbackTp1(String action, double entry, double atr) =>
    action == 'SELL' ? entry - atr : entry + atr;

enum SignalStatus {
  /// Vào ngay được (trong vùng Entry hoặc giá đang tốt hơn Entry).
  now,

  /// Chờ giá hồi về Entry rồi đặt limit tại Entry.
  limit,

  /// Không nên vào nữa (chạm/vượt TP1, xa Entry quá 1 ATR, hết hiệu lực).
  expired,

  /// Tín hiệu WAIT — chưa có lệnh để vào.
  wait,

  /// Chưa phân loại được (chưa có giá live / ATR / Entry hợp lệ).
  unknown,
}

/// Kết quả phân loại trạng thái 1 tín hiệu tại 1 thời điểm.
class SignalStatusResult {
  final SignalStatus status;

  /// Nhãn hiển thị, vd 'VÀO NGAY (NOW)'.
  final String label;

  /// Lý do ngắn gọn của trạng thái hiện tại (để user tự kiểm chứng).
  final String reason;

  /// true khi giá live đang ở phía có lợi hơn Entry
  /// (BUY: live < Entry; SELL: live > Entry).
  final bool betterThanEntry;

  /// TP1 thực dùng để xét chạm/vượt.
  final double tp1;

  /// true khi TP1 suy ra từ Entry ± 1×ATR (chưa có TP1 riêng).
  final bool tp1FromFallback;

  /// Khoảng cách giá live − Entry, tính bằng pip (có dấu; null nếu
  /// chưa có giá live).
  final double? distPips;

  /// Khoảng cách giá live − Entry, tính bằng % so với Entry
  /// (có dấu; null nếu chưa có giá live).
  final double? distPct;

  /// Khoảng cách giá live − Entry, tính bằng bội số ATR(H1)
  /// (có dấu; null nếu chưa có giá live).
  final double? distAtr;

  /// Thời gian còn lại tới giờ hết hiệu lực (ms; âm = đã hết).
  final int remainingMs;

  const SignalStatusResult({
    required this.status,
    required this.label,
    required this.reason,
    required this.betterThanEntry,
    required this.tp1,
    required this.tp1FromFallback,
    required this.distPips,
    required this.distPct,
    required this.distAtr,
    required this.remainingMs,
  });
}

/// Định dạng thời gian còn lại: 'MM:SS' (dưới 1 giờ) hoặc 'H:MM:SS'.
/// Hết hiệu lực (<= 0) thì trả 'Đã hết hiệu lực'.
String formatRemaining(int remainingMs) {
  if (remainingMs <= 0) return 'Đã hết hiệu lực';
  final int totalSec = remainingMs ~/ 1000;
  final int h = totalSec ~/ 3600;
  final int m = (totalSec % 3600) ~/ 60;
  final int s = totalSec % 60;
  final String mm = m.toString().padLeft(2, '0');
  final String ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Phân loại trạng thái vào lệnh (pure — dùng được trong test).
///
/// [action]: 'BUY' | 'SELL' | 'WAIT'. [tp1]: mức TP đầu tiên; null thì
/// dùng TP1 = Entry ± 1×ATR theo hướng. [expiryAtMs]: giờ hết hiệu lực
/// dự kiến (thường = closedAt + 1 giờ). [nowMs]: thời điểm hiện tại (ms).
/// [pipSize]: kích thước 1 pip của cặp (xem pipSize() trong indicators.dart).
SignalStatusResult classifySignalStatus({
  required String action,
  required double entry,
  double? tp1,
  required double atr,
  required double? livePrice,
  required int issuedAtMs,
  required int expiryAtMs,
  required int nowMs,
  required double pipSize,
}) {
  final int remainingMs = expiryAtMs - nowMs;
  final double tp1Used = tp1 ?? fallbackTp1(action, entry, atr);
  final bool tp1Fallback = tp1 == null;

  SignalStatusResult build(
    SignalStatus status,
    String label,
    String reason, {
    bool better = false,
    double? distPips,
    double? distPct,
    double? distAtr,
  }) {
    return SignalStatusResult(
      status: status,
      label: label,
      reason: reason,
      betterThanEntry: better,
      tp1: tp1Used,
      tp1FromFallback: tp1Fallback,
      distPips: distPips,
      distPct: distPct,
      distAtr: distAtr,
      remainingMs: remainingMs,
    );
  }

  if (action == 'WAIT') {
    return build(
      SignalStatus.wait,
      'CHỜ — chưa có lệnh',
      'Tín hiệu WAIT: chưa có hướng BUY/SELL nên chưa có lệnh để vào.',
    );
  }
  if (action != 'BUY' && action != 'SELL') {
    return build(
      SignalStatus.unknown,
      'CHƯA RÕ TRẠNG THÁI',
      'Hướng tín hiệu không phải BUY/SELL/WAIT.',
    );
  }
  if (entry <= 0 || atr <= 0 || pipSize <= 0) {
    return build(
      SignalStatus.unknown,
      'CHƯA RÕ TRẠNG THÁI',
      'Chưa có Entry/ATR(H1) hợp lệ để so với giá live.',
    );
  }
  if (livePrice == null || livePrice <= 0) {
    return build(
      SignalStatus.unknown,
      'CHƯA CÓ GIÁ LIVE',
      'Chưa lấy được giá live nên chưa so được với Entry.',
    );
  }

  final double live = livePrice;
  final bool isBuy = action == 'BUY';
  // Khoảng cách có dấu theo hướng giao dịch: dương = giá đã chạy theo
  // hướng có lợi, âm = giá đang ngược hướng (xấu hơn Entry).
  final double signedDist = isBuy ? live - entry : entry - live;
  final double distPips = (live - entry) / pipSize;
  final double distPct = (live - entry) / entry * 100;
  final double distAtr = (live - entry) / atr;
  // "Giá tốt hơn Entry": BUY mà live < Entry, SELL mà live > Entry.
  final bool better = signedDist < 0;
  final String distTxt =
      '${distPips >= 0 ? '+' : ''}${distPips.toStringAsFixed(1)} pip '
      '(${distPct >= 0 ? '+' : ''}${distPct.toStringAsFixed(2)}%)';

  // Ưu tiên 1 — EXPIRED: hết giờ, chạm/vượt TP1, hoặc xa Entry quá 1 ATR.
  if (remainingMs <= 0) {
    return build(
      SignalStatus.expired,
      'KHÔNG NÊN VÀO NỮA',
      'Đã quá giờ hết hiệu lực (ra lúc ${vnTimeStr(issuedAtMs)} + 1 giờ).',
      better: better,
      distPips: distPips,
      distPct: distPct,
      distAtr: distAtr,
    );
  }
  final bool hitTp1 = isBuy ? live >= tp1Used : live <= tp1Used;
  if (hitTp1) {
    return build(
      SignalStatus.expired,
      'KHÔNG NÊN VÀO NỮA',
      'Giá live đã chạm/vượt TP1 (${fmtPrice(tp1Used)}) — lệnh này coi như đã chạy xong.',
      better: better,
      distPips: distPips,
      distPct: distPct,
      distAtr: distAtr,
    );
  }
  if (signedDist.abs() > kExpiredAtr * atr) {
    return build(
      SignalStatus.expired,
      'KHÔNG NÊN VÀO NỮA',
      'Giá live cách Entry ${distTxt} — quá 1,0×ATR(H1) nên không còn vào được.',
      better: better,
      distPips: distPips,
      distPct: distPct,
      distAtr: distAtr,
    );
  }

  // Ưu tiên 2 — NOW: trong vùng Entry ±0,25 ATR, hoặc giá tốt hơn Entry.
  if (signedDist.abs() <= kNowAtr * atr || better) {
    return build(
      SignalStatus.now,
      'VÀO NGAY (NOW)',
      better
          ? 'Giá live đang tốt hơn Entry ($distTxt) — vào ngay được với giá tốt hơn dự kiến.'
          : 'Giá live đang trong vùng Entry ±0,25×ATR(H1) ($distTxt).',
      better: better,
      distPips: distPips,
      distPct: distPct,
      distAtr: distAtr,
    );
  }

  // Ưu tiên 3 — LIMIT: giá đã chạy xa theo hướng có lợi, chờ hồi về Entry.
  return build(
    SignalStatus.limit,
    'CHỜ LIMIT',
    'Giá live đã chạy xa Entry theo hướng có lợi ($distTxt, quá 0,25×ATR) — '
        'chờ giá hồi về Entry rồi đặt lệnh limit tại Entry.',
    better: better,
    distPips: distPips,
    distPct: distPct,
    distAtr: distAtr,
  );
}

/// Phân loại cho 1 tín hiệu Swing tĩnh ([StaticSignal]).
/// TP1 lấy từ thang TP (levels.t1) khi có; chưa có thì dùng
/// Entry ± 1×ATR theo hướng (xem [fallbackTp1]).
/// Giờ hết hiệu lực = closedAt + 1 giờ.
SignalStatusResult classifyStaticSignal(
  StaticSignal sg, {
  required double? livePrice,
  required int nowMs,
}) {
  return classifySignalStatus(
    action: sg.action,
    entry: sg.entry,
    tp1: sg.levels?.t1,
    atr: sg.atr,
    livePrice: livePrice,
    issuedAtMs: sg.closedAt,
    expiryAtMs: signalExpiryMs(sg.closedAt),
    nowMs: nowMs,
    pipSize: pipSize(sg.symbol),
  );
}
