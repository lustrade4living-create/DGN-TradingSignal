// alerts.dart — Cảnh báo Xung đa khung và TURN đồng bộ (spec §9).
//
// Chạy mỗi 5 giây cho cả 8 cặp (caller lo nhịp + ensureCandles đủ 5 khung).
// Điều kiện tiên quyết: phải có đủ Trend cả 5 khung (M5/M15/H1/H4/D1);
// thiếu khung nào → bỏ qua, không cảnh báo.
// Lần đầu chỉ lưu turnPrev, không cảnh báo.
// Cooldown 10 phút/cặp (TURN) và 10 phút/cặp/hướng (XUNG).
// Lưu tối đa 30 cảnh báo (mới nhất đầu), hiển thị tối đa 12.

class AlertItem {
  String kind; // 'XUNG' | 'TURN'
  String symbol;
  String text;
  int time; // ms

  AlertItem({
    required this.kind,
    required this.symbol,
    required this.text,
    required this.time,
  });
}

class AlertStore {
  final List<AlertItem> items = [];
  String? latestBanner;

  final Map<String, Map<String, String>> _prev = {};
  final Map<String, int> _cooldown = {};

  static const List<String> _tfs = ['M5', 'M15', 'H1', 'H4', 'D1'];
  static const int _coolMs = 10 * 60 * 1000;
  static const int _maxItems = 30;
  static const int _visibleCount = 12;

  List<AlertItem> get visible => items.take(_visibleCount).toList();

  void clearBanner() {
    latestBanner = null;
  }

  static String _dirVn(String dir) => switch (dir) {
        'up' => 'Tăng',
        'dn' => 'Giảm',
        _ => 'Ngang',
      };

  static String _kindLabel(String kind) =>
      kind == 'XUNG' ? 'XUNG ĐA KHUNG' : 'TURN ĐỒNG BỘ';

  void _add(AlertItem item) {
    items.insert(0, item);
    if (items.length > _maxItems) {
      items.removeRange(_maxItems, items.length);
    }
    latestBanner = '${_kindLabel(item.kind)} · ${item.symbol}: ${item.text}';
  }

  /// Kiểm tra 1 cặp tại [nowMs].
  /// [trendDirs]: map khung → dir ('up'/'dn'/'flat') cho cả 5 khung.
  /// Trả về danh sách cảnh báo MỚI tạo trong lần kiểm tra này (0–2 cái).
  List<AlertItem> check(
      String symbol, Map<String, String> trendDirs, int nowMs) {
    for (final tf in _tfs) {
      if (!trendDirs.containsKey(tf)) return [];
    }
    final cur = {for (final tf in _tfs) tf: trendDirs[tf]!};
    final prev = _prev[symbol];
    _prev[symbol] = Map.of(cur);
    if (prev == null) return []; // lần đầu chỉ lưu mốc nền

    final created = <AlertItem>[];

    // --- XUNG đa khung: cả 5 cùng up/dn và lần trước chưa toàn bộ cùng hướng đó ---
    for (final dir in ['up', 'dn']) {
      final allSame = cur.values.every((d) => d == dir);
      if (!allSame) continue;
      final prevSame = prev.values.every((d) => d == dir);
      if (prevSame) continue;
      final coolKey = '$symbol|xung|$dir';
      final last = _cooldown[coolKey];
      if (last != null && nowMs - last < _coolMs) continue;
      _cooldown[coolKey] = nowMs;
      final dirWord = dir == 'up' ? 'TĂNG' : 'GIẢM';
      final side = dir == 'up' ? 'phe mua' : 'phe bán';
      final prevDesc =
          _tfs.map((tf) => '$tf ${_dirVn(prev[tf]!)}').join(' · ');
      created.add(AlertItem(
        kind: 'XUNG',
        symbol: symbol,
        time: nowMs,
        text: 'Cả 5 khung M5/M15/H1/H4/D1 cùng $dirWord — xung đa khung '
            'nghiêng hẳn về $side. Ngay trước đó Trend từng khung là: $prevDesc',
      ));
    }

    // --- TURN đồng bộ: >= 2 khung đảo chiều Tăng↔Giảm (Ngang không tính) ---
    var flips = 0;
    final flipDesc = <String>[];
    for (final tf in _tfs) {
      final p = prev[tf]!;
      final c = cur[tf]!;
      if ((p == 'up' && c == 'dn') || (p == 'dn' && c == 'up')) {
        flips++;
        flipDesc.add('$tf ${_dirVn(p)} → ${_dirVn(c)}');
      }
    }
    if (flips >= 2) {
      const coolKeySuffix = 'turn';
      final last = _cooldown['$symbol|$coolKeySuffix'];
      if (last == null || nowMs - last >= _coolMs) {
        _cooldown['$symbol|$coolKeySuffix'] = nowMs;
        created.add(AlertItem(
          kind: 'TURN',
          symbol: symbol,
          time: nowMs,
          text: '$flips khung cùng đảo chiều trong cùng một lần kiểm tra: '
              '${flipDesc.join(' · ')}. Hướng Trend của $symbol đang đổi '
              'đồng loạt (TURN đồng bộ) — cân nhắc chờ gauge cộng hưởng ổn '
              'định lại trước khi vào lệnh mới theo hướng cũ.',
        ));
      }
    }

    // Mới nhất lên đầu; nếu cả 2 cùng tạo thì TURN đứng trước XUNG.
    created.sort((a, b) {
      if (a.kind == b.kind) return 0;
      return a.kind == 'TURN' ? -1 : 1;
    });
    for (final item in created.reversed) {
      _add(item);
    }
    return created;
  }
}
