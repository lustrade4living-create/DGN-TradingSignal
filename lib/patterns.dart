// patterns.dart — Thư viện mẫu hình nến, 15 mẫu (spec §6).
//
// Đếm số lần xuất hiện thật từ nến đã đóng của khung đang chọn,
// cửa sổ tối đa 200 nến gần nhất, yêu cầu tối thiểu 30 nến.
// Dung sai đỉnh/đáy kẹp: tol = avgRange × 0.15.
// Mỗi mẫu xuất hiện ở nến nào thì đếm 1 lần tại nến đó; ghi lastIndex
// (vị trí trong cửa sổ) và lastTime (thời gian nến).
// Lưu ý: Doji ở thư viện dùng ngưỡng 0.10 (khác Price Action cơ bản: 0.12).
import 'dart:math' as math;

import 'market_data.dart';

double _pBody(RawCandle c) => (c.c - c.o).abs();

double _pRange(RawCandle c) => math.max(1e-12, c.h - c.l);

double _pUpW(RawCandle c) => c.h - math.max(c.o, c.c);

double _pDnW(RawCandle c) => math.min(c.o, c.c) - c.l;

bool _isUp(RawCandle c) => c.c > c.o;

bool _isDown(RawCandle c) => c.c < c.o;

/// Thống kê 1 mẫu hình trong cửa sổ đếm.
/// [dir]: 'bull' | 'bear' | 'reversal-up' | 'reversal-down' | 'neutral'.
/// Với mẫu có hướng thay đổi theo nến (Pin Bar, Harami, Outside Bar),
/// [dir] là hướng của lần xuất hiện gần nhất; chưa xuất hiện lần nào → 'neutral'.
/// [fresh] = true khi xuất hiện ở 1 trong 2 nến đóng gần nhất (lastIndex >= n−2).
class PatternStat {
  String id;
  String nameVn;
  String nameEn;
  String dir;
  int count;
  int? lastIndex;
  int? lastTime;
  int windowLen;

  PatternStat({
    required this.id,
    required this.nameVn,
    required this.nameEn,
    required this.dir,
    this.count = 0,
    this.lastIndex,
    this.lastTime,
    this.windowLen = 0,
  });

  bool get fresh =>
      lastIndex != null && windowLen > 0 && lastIndex! >= windowLen - 2;
}

typedef _Detect = String? Function(List<RawCandle> w, int i, double tol);

class _PatDef {
  final String id;
  final String nameVn;
  final String nameEn;
  final String defaultDir;
  final _Detect detect;

  const _PatDef({
    required this.id,
    required this.nameVn,
    required this.nameEn,
    required this.defaultDir,
    required this.detect,
  });
}

bool _bodyInside(RawCandle inner, RawCandle outer) {
  final iLo = math.min(inner.o, inner.c);
  final iHi = math.max(inner.o, inner.c);
  final oLo = math.min(outer.o, outer.c);
  final oHi = math.max(outer.o, outer.c);
  return iLo >= oLo && iHi <= oHi;
}

final List<_PatDef> _defs = [
  // 1. Đỉnh kẹp (Tweezer Top)
  _PatDef(
    id: 'tweezer-top',
    nameVn: 'Đỉnh kẹp',
    nameEn: 'Tweezer Top',
    defaultDir: 'reversal-down',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      if (_isUp(a) && _isDown(b) && (a.h - b.h).abs() <= tol) {
        return 'reversal-down';
      }
      return null;
    },
  ),
  // 2. Đáy kẹp (Tweezer Bottom)
  _PatDef(
    id: 'tweezer-bottom',
    nameVn: 'Đáy kẹp',
    nameEn: 'Tweezer Bottom',
    defaultDir: 'reversal-up',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      if (_isDown(a) && _isUp(b) && (a.l - b.l).abs() <= tol) {
        return 'reversal-up';
      }
      return null;
    },
  ),
  // 3. Harami chữ thập (Cross Harami)
  _PatDef(
    id: 'cross-harami',
    nameVn: 'Harami chữ thập',
    nameEn: 'Cross Harami',
    defaultDir: 'neutral',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      if (_pBody(a) < 0.55 * _pRange(a)) return null;
      if (_pBody(b) > 0.12 * _pRange(b)) return null;
      if (!_bodyInside(b, a)) return null;
      if (_isUp(a)) return 'reversal-down';
      if (_isDown(a)) return 'reversal-up';
      return null;
    },
  ),
  // 4. Nến trong (Inside Bar)
  _PatDef(
    id: 'inside-bar',
    nameVn: 'Nến trong',
    nameEn: 'Inside Bar',
    defaultDir: 'neutral',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      if (b.h <= a.h && b.l >= a.l && (b.h < a.h || b.l > a.l)) {
        return 'neutral';
      }
      return null;
    },
  ),
  // 5. Nhân chìm tăng (Bullish Engulfing)
  _PatDef(
    id: 'bull-engulfing',
    nameVn: 'Nhân chìm tăng',
    nameEn: 'Bullish Engulfing',
    defaultDir: 'reversal-up',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      if (_isUp(b) && _isDown(a) && b.c >= a.o && b.o <= a.c) {
        return 'reversal-up';
      }
      return null;
    },
  ),
  // 6. Nhân chìm giảm (Bearish Engulfing)
  _PatDef(
    id: 'bear-engulfing',
    nameVn: 'Nhân chìm giảm',
    nameEn: 'Bearish Engulfing',
    defaultDir: 'reversal-down',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      if (_isDown(b) && _isUp(a) && b.c <= a.o && b.o >= a.c) {
        return 'reversal-down';
      }
      return null;
    },
  ),
  // 7. Xuyên thủng (Piercing Line)
  _PatDef(
    id: 'piercing',
    nameVn: 'Xuyên thủng',
    nameEn: 'Piercing Line',
    defaultDir: 'reversal-up',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      final midA = (a.o + a.c) / 2;
      if (_isDown(a) &&
          _pBody(a) >= 0.5 * _pRange(a) &&
          _isUp(b) &&
          b.o <= a.l + tol &&
          b.c > midA &&
          b.c < a.o) {
        return 'reversal-up';
      }
      return null;
    },
  ),
  // 8. Nến ngoài (Outside Bar)
  _PatDef(
    id: 'outside-bar',
    nameVn: 'Nến ngoài',
    nameEn: 'Outside Bar',
    defaultDir: 'neutral',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      if (b.h > a.h && b.l < a.l) {
        if (_isUp(b)) return 'bull';
        if (_isDown(b)) return 'bear';
        return 'neutral';
      }
      return null;
    },
  ),
  // 9. Sao băng (Shooting Star)
  _PatDef(
    id: 'shooting-star',
    nameVn: 'Sao băng',
    nameEn: 'Shooting Star',
    defaultDir: 'reversal-down',
    detect: (w, i, tol) {
      final b = w[i];
      final body = _pBody(b);
      final range = _pRange(b);
      if (body > 0 &&
          _pUpW(b) >= 2 * body &&
          _pDnW(b) <= 0.35 * range &&
          math.max(b.o, b.c) <= b.l + 0.45 * range) {
        return 'reversal-down';
      }
      return null;
    },
  ),
  // 10. Con quay (Spinning Top)
  _PatDef(
    id: 'spinning-top',
    nameVn: 'Con quay',
    nameEn: 'Spinning Top',
    defaultDir: 'neutral',
    detect: (w, i, tol) {
      final b = w[i];
      final range = _pRange(b);
      if (_pBody(b) <= 0.32 * range &&
          _pUpW(b) >= 0.2 * range &&
          _pDnW(b) >= 0.2 * range) {
        return 'neutral';
      }
      return null;
    },
  ),
  // 11. Marubozu tăng
  _PatDef(
    id: 'bull-marubozu',
    nameVn: 'Marubozu tăng',
    nameEn: 'Bullish Marubozu',
    defaultDir: 'bull',
    detect: (w, i, tol) {
      final b = w[i];
      if (_isUp(b) && _pBody(b) >= 0.85 * _pRange(b)) return 'bull';
      return null;
    },
  ),
  // 12. Marubozu giảm
  _PatDef(
    id: 'bear-marubozu',
    nameVn: 'Marubozu giảm',
    nameEn: 'Bearish Marubozu',
    defaultDir: 'bear',
    detect: (w, i, tol) {
      final b = w[i];
      if (_isDown(b) && _pBody(b) >= 0.85 * _pRange(b)) return 'bear';
      return null;
    },
  ),
  // 13. Mây đen che phủ (Dark Cloud Cover)
  _PatDef(
    id: 'dark-cloud',
    nameVn: 'Mây đen che phủ',
    nameEn: 'Dark Cloud Cover',
    defaultDir: 'reversal-down',
    detect: (w, i, tol) {
      final a = w[i - 1];
      final b = w[i];
      final midA = (a.o + a.c) / 2;
      if (_isUp(a) &&
          _pBody(a) >= 0.5 * _pRange(a) &&
          _isDown(b) &&
          b.o >= a.c - tol &&
          b.c < midA &&
          b.c > a.o) {
        return 'reversal-down';
      }
      return null;
    },
  ),
  // 14. Pin Bar (Hammer / Shooting) — cùng công thức với Price Action §5.1
  _PatDef(
    id: 'pin-bar',
    nameVn: 'Pin Bar',
    nameEn: 'Pin Bar',
    defaultDir: 'neutral',
    detect: (w, i, tol) {
      final b = w[i];
      final body = _pBody(b);
      final upW = _pUpW(b);
      final dnW = _pDnW(b);
      if (body > 0 && dnW > body * 2 && upW < body * 0.9) {
        return 'reversal-up';
      }
      if (body > 0 && upW > body * 2 && dnW < body * 0.9) {
        return 'reversal-down';
      }
      return null;
    },
  ),
  // 15. Doji — ngưỡng 0.10 (khác PA cơ bản 0.12)
  _PatDef(
    id: 'doji',
    nameVn: 'Doji',
    nameEn: 'Doji',
    defaultDir: 'neutral',
    detect: (w, i, tol) {
      final b = w[i];
      if (_pBody(b) <= 0.10 * _pRange(b)) return 'neutral';
      return null;
    },
  ),
];

/// Đủ nến để đếm mẫu hình chưa (tối thiểu 30 nến đã đóng).
bool enoughCandles(List<RawCandle> cs) => cs.length >= 30;

/// Đếm 15 mẫu hình trên cửa sổ tối đa [lookback] nến gần nhất.
/// Ít hơn 30 nến → trả [] (UI hiện "Chưa đủ nến").
List<PatternStat> countPatterns(List<RawCandle> closed, {int lookback = 200}) {
  if (closed.length < 30) return [];
  final w = closed.length > lookback
      ? closed.sublist(closed.length - lookback)
      : closed;
  final n = w.length;
  var rangeSum = 0.0;
  for (final c in w) {
    rangeSum += c.h - c.l;
  }
  final tol = (rangeSum / n) * 0.15;
  final stats = _defs
      .map((d) => PatternStat(
            id: d.id,
            nameVn: d.nameVn,
            nameEn: d.nameEn,
            dir: d.defaultDir,
            windowLen: n,
          ))
      .toList();
  for (var i = 1; i < n; i++) {
    for (var s = 0; s < _defs.length; s++) {
      final dir = _defs[s].detect(w, i, tol);
      if (dir != null) {
        stats[s].count++;
        stats[s].lastIndex = i;
        stats[s].lastTime = w[i].t;
        stats[s].dir = dir;
      }
    }
  }
  return stats;
}

/// Top [n] mẫu có số lần xuất hiện > 0, giảm dần theo count
/// (hòa nhau giữ nguyên thứ tự định nghĩa).
List<PatternStat> topPatterns(List<PatternStat> all, {int n = 6}) {
  final idx = <int>[];
  for (var i = 0; i < all.length; i++) {
    if (all[i].count > 0) idx.add(i);
  }
  idx.sort((a, b) {
    final byCount = all[b].count.compareTo(all[a].count);
    if (byCount != 0) return byCount;
    return a.compareTo(b);
  });
  return idx.take(n).map((i) => all[i]).toList();
}
