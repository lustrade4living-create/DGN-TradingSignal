// gauge_ladder.dart — Gauge cộng hưởng đa khung (§7) + thang TP nhiều tầng
// và theo dõi mô phỏng từng tầng (§8.2) + "Chênh mở phòng" (§8.3).
import 'market_data.dart';
import 'signal_core.dart';

// ---------------------------------------------------------------------------
// Gauge cộng hưởng đa khung (§7)
// ---------------------------------------------------------------------------

class GaugeData {
  int upN;
  int flatN;
  int dnN;
  int avail;
  double score; // (upN − dnN) / avail, −1..1
  double needleAngleDeg; // 90 − score × 78 (độ)
  String verdict;

  GaugeData({
    required this.upN,
    required this.flatN,
    required this.dnN,
    required this.avail,
    required this.score,
    required this.needleAngleDeg,
    required this.verdict,
  });
}

/// Gộp Trend 5 khung (M5/M15/H1/H4/D1). Chỉ đếm khung đã đủ nến (enough).
GaugeData gaugeFromTrends(Map<String, TrendInfo> byTf) {
  var upN = 0;
  var flatN = 0;
  var dnN = 0;
  var avail = 0;
  for (final tf in ['M5', 'M15', 'H1', 'H4', 'D1']) {
    final t = byTf[tf];
    if (t == null || !t.enough) continue;
    avail++;
    if (t.dir == 'up') {
      upN++;
    } else if (t.dir == 'dn') {
      dnN++;
    } else {
      flatN++;
    }
  }
  final score = avail > 0 ? (upN - dnN) / avail : 0.0;
  final angle = 90 - score * 78;
  String verdict;
  if (avail == 0) {
    verdict = 'Đang tải nến các khung…';
  } else if (upN > dnN && upN >= flatN) {
    verdict = 'Phe Tăng đang chiếm đa số — $upN/$avail khung cùng nghiêng tăng'
        '${dnN > 0 ? ', còn $dnN khung ngược chiều nên vẫn cần xác nhận ở khung lớn (H1/H4)' : ' và không có khung nào ngược chiều'}.';
  } else if (dnN > upN && dnN >= flatN) {
    verdict = 'Phe Giảm đang chiếm đa số — $dnN/$avail khung cùng nghiêng giảm'
        '${upN > 0 ? ', còn $upN khung ngược chiều nên vẫn cần xác nhận ở khung lớn (H1/H4)' : ' và không có khung nào ngược chiều'}.';
  } else if (upN == dnN && upN > 0) {
    verdict = 'Hai phe cân bằng — $upN khung tăng / $dnN khung giảm, chưa có '
        'cộng hưởng rõ, ưu tiên chờ thêm một khung đổi chiều.';
  } else {
    verdict = 'Đa số khung đang đi ngang ($flatN/$avail) — thị trường chưa '
        'chọn hướng, gauge ở vùng trung tính.';
  }
  if (avail > 0 && avail < 5) {
    verdict +=
        ' (Mới có $avail/5 khung đủ nến đã đóng — gauge chỉ tổng hợp các khung đã tải.)';
  }
  return GaugeData(
    upN: upN,
    flatN: flatN,
    dnN: dnN,
    avail: avail,
    score: score,
    needleAngleDeg: angle,
    verdict: verdict,
  );
}

// ---------------------------------------------------------------------------
// Theo dõi mô phỏng từng tầng thang TP (§8.2)
// ---------------------------------------------------------------------------

class TierStatus {
  bool hit;
  int? at; // giờ đóng nến chạm (hoặc nowMs khi giá live vượt tầng)
  double? price; // = mức tầng
  String note;

  TierStatus({this.hit = false, this.at, this.price, this.note = 'Chưa chạm'});
}

String _fmtPips(double pips) =>
    pips.toStringAsFixed(1).replaceAll('.', ',');

/// Theo dõi tầng cho 1 lệnh mô phỏng (đang mở trong Lịch sử).
/// [startAt] = closedAt của tín hiệu (fallback openAt).
class TierTracker {
  final LadderLevels levels;
  final String action; // 'BUY' | 'SELL'
  final int startAt;
  final Map<String, TierStatus> _tiers = {};

  TierTracker({
    required this.levels,
    required this.action,
    required this.startAt,
  }) {
    for (final k in ['T1', 'T2', 'T3', 'T4', 'Inv']) {
      _tiers[k] = TierStatus();
    }
  }

  Map<String, TierStatus> get tiers => Map.unmodifiable(_tiers);

  double _levelFor(String key) => switch (key) {
        'T1' => levels.t1,
        'T2' => levels.t2,
        'T3' => levels.t3,
        'T4' => levels.t4,
        'Inv' => levels.inv,
        _ => levels.entry,
      };

  String _hitNote(String key, int at) => key == 'Inv'
      ? 'Đã chạm Inv lúc ${vnTimeStr(at)} — tín hiệu đã vô hiệu'
      : '✓ Đã chạm $key lúc ${vnTimeStr(at)}';

  bool _touchedByCandle(String key, double h, double l) {
    final lvl = _levelFor(key);
    if (key == 'Inv') {
      // Inv nằm ngược hướng TP: BUY chạm khi giá rơi xuống SL, SELL ngược lại.
      return action == 'BUY' ? l <= lvl : h >= lvl;
    }
    return action == 'BUY' ? h >= lvl : l <= lvl;
  }

  bool _touchedByPrice(String key, double price) {
    final lvl = _levelFor(key);
    if (key == 'Inv') {
      return action == 'BUY' ? price <= lvl : price >= lvl;
    }
    return action == 'BUY' ? price >= lvl : price <= lvl;
  }

  void _mark(String key, int at) {
    final st = _tiers[key]!;
    st.hit = true;
    st.at = at;
    st.price = _levelFor(key);
    st.note = _hitNote(key, at);
  }

  /// Quét nến M5/M15 từ startAt − 15 phút, rồi kiểm tra giá live.
  /// BUY chạm tầng khi h >= lvl, SELL khi l <= lvl (Inv ngược hướng).
  /// at = t nến + step khung (giờ đóng nến chạm); nếu giá live đã vượt tầng
  /// mà nến chưa ghi thì ghi chạm ngay (at = nowMs).
  void checkCandles(
      List<RawCandle> m5, List<RawCandle> m15, double? livePrice, int nowMs) {
    final from = startAt - 15 * 60 * 1000;
    final events = <({int t, double h, double l, int step})>[];
    for (final c in m5) {
      if (c.t >= from) events.add((t: c.t, h: c.h, l: c.l, step: 300000));
    }
    for (final c in m15) {
      if (c.t >= from) events.add((t: c.t, h: c.h, l: c.l, step: 900000));
    }
    events.sort((a, b) => a.t.compareTo(b.t));
    const keys = ['T1', 'T2', 'T3', 'T4', 'Inv'];
    for (final e in events) {
      for (final key in keys) {
        final st = _tiers[key]!;
        if (st.hit) continue;
        if (_touchedByCandle(key, e.h, e.l)) _mark(key, e.t + e.step);
      }
    }
    if (livePrice != null) {
      for (final key in keys) {
        final st = _tiers[key]!;
        if (st.hit) continue;
        if (_touchedByPrice(key, livePrice)) _mark(key, nowMs);
      }
    }
  }

  /// Trạng thái hiển thị 1 tầng (§8.2).
  /// [pip] = pipSize của cặp. Đã chạm → giờ chạm + giá tầng (+ pullback nếu
  /// giá live đã hồi ngược qua tầng); chưa chạm → khoảng cách pip từ giá live.
  String tierNote(String key, double? livePrice, double pip) {
    final st = _tiers[key];
    if (st == null) return '';
    final lvl = _levelFor(key);
    if (st.hit) {
      var s = key == 'Inv'
          ? 'Đã chạm Inv lúc ${vnTimeStr(st.at!)} — tín hiệu đã vô hiệu (dừng lỗ)'
          : '✓ Đã chạm $key lúc ${vnTimeStr(st.at!)}';
      s += ' · giá ${fmtPrice(lvl)}';
      if (livePrice != null && key != 'Inv') {
        final back =
            action == 'BUY' ? lvl - livePrice : livePrice - lvl;
        if (back > 0) {
          s += ' · giá live đã hồi ${_fmtPips(back / pip)} pip (pullback)';
        }
      }
      return s;
    }
    if (livePrice == null) {
      return key == 'Inv'
          ? 'Chưa chạm — giá chạm mức này là tín hiệu vô hiệu'
          : 'Chưa chạm';
    }
    final dist = (lvl - livePrice).abs() / pip;
    if (key == 'Inv') {
      return 'Chưa chạm · còn ~${_fmtPips(dist)} pip từ giá live — '
          'giá chạm mức này là tín hiệu vô hiệu';
    }
    return 'Chưa chạm · còn ~${_fmtPips(dist)} pip từ giá live';
  }
}

// ---------------------------------------------------------------------------
// "Chênh mở phòng" — Sim Diff (§8.3)
// ---------------------------------------------------------------------------

/// So giá mở mô phỏng với Entry tĩnh.
/// |pips| < 0.05 → 'khớp Entry'; ngược lại 'thuận lợi hơn Entry' /
/// 'kém hơn Entry' theo hướng lệnh.
({double pips, double pct, String verdict}) simDiff(
    double openPrice, double entry, String action, double pip) {
  final diff = openPrice - entry;
  final pips = diff / pip;
  final pct = diff / entry * 100;
  final String verdict;
  if (pips.abs() < 0.05) {
    verdict = 'khớp Entry';
  } else if ((action == 'BUY' ? -pips : pips) >= 0) {
    verdict = 'thuận lợi hơn Entry';
  } else {
    verdict = 'kém hơn Entry';
  }
  return (pips: pips, pct: pct, verdict: verdict);
}
