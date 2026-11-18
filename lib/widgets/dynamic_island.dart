// Dynamic Island — chỉ hiện ở các tab NGOÀI Trang chủ (spec §16.7).
// Nền navy, logo mini, chấm live, cặp + giá live + % thay đổi,
// 8 chấm chỉ vị trí, ngày giờ VN cập nhật mỗi giây.
// Chuyển cặp CHỈ bằng kéo/vuốt ngang (ngưỡng ~42px); không có nút mũi tên.
// CHỈ đổi cặp hiển thị trên island, không đổi cặp đang chọn của app.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../engine.dart';

class DynamicIsland extends StatefulWidget {
  const DynamicIsland({super.key, required this.engine});

  final MockEngine engine;

  @override
  State<DynamicIsland> createState() => _DynamicIslandState();
}

class _DynamicIslandState extends State<DynamicIsland> {
  late int _idx;
  Timer? _clock;
  DateTime _now = DateTime.now();
  double _dragDx = 0;

  MockEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _idx = symbols.indexWhere((s) => s.code == engine.selectedSymbol);
    if (_idx < 0) _idx = 1;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _step(int d) {
    setState(() {
      _idx = (_idx + d) % symbols.length;
      if (_idx < 0) _idx += symbols.length;
    });
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final SymbolInfo sym = symbols[_idx];
    final double price = engine.priceOf(sym.code);
    final double? chg = engine.chg24h[sym.code];
    final bool live = engine.priceStatus(sym.code) == 'LIVE';
    final Color chgColor =
        (chg ?? 0) >= 0 ? const Color(0xFF17C964) : const Color(0xFFFF5C72);
    final String dateStr =
        '${_two(_now.day)}/${_two(_now.month)} · ${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}';

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        _dragDx += details.delta.dx;
      },
      onHorizontalDragEnd: (details) {
        // Ưu tiên ngang hơn dọc (ngưỡng 42px, như web).
        if (_dragDx.abs() >= 42) {
          _step(_dragDx > 0 ? -1 : 1);
        }
        _dragDx = 0;
      },
      onHorizontalDragCancel: () => _dragDx = 0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF051633).withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(2),
                child: Image.asset(
                  'assets/dgn-mark-clear.png',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: Text('D',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: live ? const Color(0xFF17C964) : Colors.amber,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              sym.code,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                engine.fmt(price, sym.code),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              chg == null ? '—' : engine.fmtPct(chg),
              style: TextStyle(
                color: chg == null ? Colors.white70 : chgColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(symbols.length, (i) {
                return Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: i == _idx ? Colors.white : Colors.white38,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
            const SizedBox(width: 6),
            Container(width: 1, height: 18, color: Colors.white24),
            const SizedBox(width: 6),
            Text(
              dateStr,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
