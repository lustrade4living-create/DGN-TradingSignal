// Chart nến TradeSignal AI — nền sáng (theme trắng), EMA nhanh/chậm/34,
// thang TP Inv/T1–T4, mũi tên tín hiệu, kéo ngang xem nến quá khứ,
// công cụ vẽ tay (giữ nguyên v1.1.0).
import 'package:flutter/material.dart';

import 'engine.dart';
import 'signal_core.dart';

/// Một điểm dữ liệu trên chart. [x] là chỉ số nến, [y] là giá.
class Pt {
  final double x, y;
  const Pt(this.x, this.y);
}

enum DrawTool { none, trend, horizontal, fib, rect, text }

class Drawing {
  DrawTool tool;
  List<Pt> pts;
  String text;
  Drawing({required this.tool, required this.pts, this.text = ''});
}

const int _kExtraSlots = 20;
const double _kPriceAxisWidth = 56;
const double _kTimeAxisHeight = 20;

/// Số nến hiển thị cùng lúc (spec §13.5: 64 nến).
const int kVisibleCandles = 64;

Offset dataToPixel(Pt p, Size size, double minP, double maxP, int count) {
  final plotW = size.width - _kPriceAxisWidth;
  final plotH = size.height - _kTimeAxisHeight;
  if (plotW <= 0 || plotH <= 0) return Offset.zero;
  final totalSlots = count + _kExtraSlots;
  final x = (p.x + 0.5) / totalSlots * plotW;
  final span = maxP - minP;
  final safeSpan = span.abs() < 1e-12 ? 1.0 : span;
  final y = plotH - (p.y - minP) / safeSpan * plotH;
  return Offset(x, y);
}

Pt pixelToData(Offset o, Size size, double minP, double maxP, int count) {
  final plotW = size.width - _kPriceAxisWidth;
  final plotH = size.height - _kTimeAxisHeight;
  if (plotW <= 0 || plotH <= 0) return Pt(0, minP);
  final totalSlots = count + _kExtraSlots;
  final x = o.dx / plotW * totalSlots - 0.5;
  final span = maxP - minP;
  final safeSpan = span.abs() < 1e-12 ? 1.0 : span;
  final y = minP + (plotH - o.dy) / plotH * safeSpan;
  return Pt(x, y);
}

(double, double) _priceRange(
  List<Candle> candles,
  List<List<double?>> emas,
  StaticSignal? signal,
) {
  if (candles.isEmpty) return (0.0, 1.0);
  var minP = candles.first.low;
  var maxP = candles.first.high;
  for (final c in candles) {
    if (c.low < minP) minP = c.low;
    if (c.high > maxP) maxP = c.high;
  }
  for (final series in emas) {
    for (final v in series) {
      if (v == null || v.isNaN) continue;
      if (v < minP) minP = v;
      if (v > maxP) maxP = v;
    }
  }
  if (signal != null) {
    for (final v in <double>[
      signal.entry,
      if (signal.sl != null) signal.sl!,
      if (signal.tp != null) signal.tp!,
      if (signal.levels != null) ...<double>[
        signal.levels!.inv,
        signal.levels!.t1,
        signal.levels!.t2,
        signal.levels!.t3,
        signal.levels!.t4,
      ],
    ]) {
      if (v.isNaN) continue;
      if (v < minP) minP = v;
      if (v > maxP) maxP = v;
    }
  }
  final span = maxP - minP;
  if (span <= 0) {
    return (minP - 0.5, maxP + 0.5);
  }
  final pad = span * 0.06;
  return (minP - pad, maxP + pad);
}

class _VisibleData {
  final List<Candle> candles;
  final List<double?> emaFast;
  final List<double?> emaSlow;
  final List<double?> ema34;
  final double minP;
  final double maxP;
  const _VisibleData({
    required this.candles,
    required this.emaFast,
    required this.emaSlow,
    required this.ema34,
    required this.minP,
    required this.maxP,
  });
  int get count => candles.length;
}

class CandleChart extends StatefulWidget {
  const CandleChart({
    super.key,
    required this.candles,
    required this.signal,
    required this.emaFast,
    required this.emaSlow,
    required this.ema34,
    required this.tool,
    required this.drawings,
    required this.onDrawingAdded,
    required this.decimals,
    this.tierHits,
    this.pan = 0,
    this.onPanChanged,
  });

  final List<Candle> candles;
  final StaticSignal? signal;
  final List<double?> emaFast;
  final List<double?> emaSlow;
  final List<double?> ema34;
  final DrawTool tool;
  final List<Drawing> drawings;
  final void Function(Drawing) onDrawingAdded;
  final int decimals;

  /// Tầng nào đã chạm (key 'T1'..'T4','Inv') — nhãn thang TP hiện ✓.
  final Map<String, bool>? tierHits;

  /// Số nến đang lùi về quá khứ (0 = live). Tối đa candles.length − 20.
  final int pan;
  final void Function(int pan)? onPanChanged;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  Drawing? _preview;
  Pt? _dragStart;
  Pt? _dragCurrent;
  double _panAccum = 0;

  int get _maxPan =>
      widget.candles.length > 20 ? widget.candles.length - 20 : 0;

  _VisibleData _chartData() {
    final all = widget.candles;
    final int pan = widget.pan.clamp(0, _maxPan);
    final int end = all.length - pan;
    final int start =
        end > kVisibleCandles ? end - kVisibleCandles : 0;
    final visible = all.sublist(start, end);
    List<double?> slice(List<double?> src) =>
        List<double?>.generate(visible.length, (i) {
          final gi = start + i;
          return gi < src.length ? src[gi] : null;
        });
    final eFast = slice(widget.emaFast);
    final eSlow = slice(widget.emaSlow);
    final e34 = slice(widget.ema34);
    final range = _priceRange(visible, [eFast, eSlow, e34], widget.signal);
    return _VisibleData(
      candles: visible,
      emaFast: eFast,
      emaSlow: eSlow,
      ema34: e34,
      minP: range.$1,
      maxP: range.$2,
    );
  }

  Pt _clampPt(Pt p, _VisibleData data) {
    final x = p.x.clamp(-0.5, data.count + _kExtraSlots - 0.5);
    final y = p.y.clamp(data.minP, data.maxP);
    return Pt(x, y);
  }

  void _onPanStart(DragStartDetails details, Size size, _VisibleData data) {
    final tool = widget.tool;
    if (tool == DrawTool.none ||
        tool == DrawTool.horizontal ||
        tool == DrawTool.text) {
      return;
    }
    final pt = _clampPt(
      pixelToData(details.localPosition, size, data.minP, data.maxP, data.count),
      data,
    );
    setState(() {
      _dragStart = pt;
      _dragCurrent = pt;
      _preview = Drawing(tool: tool, pts: [pt, pt]);
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size size, _VisibleData data) {
    // Chế độ Chọn (tool none): kéo ngang xem nến quá khứ.
    if (widget.tool == DrawTool.none) {
      final plotW = size.width - _kPriceAxisWidth;
      final totalSlots = data.count + _kExtraSlots;
      final slotW = plotW / totalSlots;
      if (slotW > 0) {
        _panAccum += details.delta.dx;
        final int steps = (_panAccum / slotW).truncate();
        if (steps != 0) {
          _panAccum -= steps * slotW;
          final int next =
              (widget.pan - steps).clamp(0, _maxPan);
          widget.onPanChanged?.call(next);
        }
      }
      return;
    }
    if (_dragStart == null) return;
    final pt = _clampPt(
      pixelToData(details.localPosition, size, data.minP, data.maxP, data.count),
      data,
    );
    setState(() {
      _dragCurrent = pt;
      _preview = Drawing(tool: widget.tool, pts: [_dragStart!, pt]);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _panAccum = 0;
    final start = _dragStart;
    if (start == null) return;
    final end = _dragCurrent ?? start;
    final tool = widget.tool;
    setState(() {
      _preview = null;
      _dragStart = null;
      _dragCurrent = null;
    });
    widget.onDrawingAdded(Drawing(tool: tool, pts: [start, end]));
  }

  void _onTapUp(TapUpDetails details, Size size, _VisibleData data) {
    final tool = widget.tool;
    if (tool != DrawTool.horizontal && tool != DrawTool.text) return;
    final pt = _clampPt(
      pixelToData(details.localPosition, size, data.minP, data.maxP, data.count),
      data,
    );
    if (tool == DrawTool.horizontal) {
      widget.onDrawingAdded(Drawing(tool: tool, pts: [pt]));
    } else {
      _askText(pt);
    }
  }

  Future<void> _askText(Pt pt) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi chú'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nhập ghi chú...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final text = result.trim().isEmpty ? 'Ghi chú' : result.trim();
    widget.onDrawingAdded(
      Drawing(tool: DrawTool.text, pts: [pt], text: text),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return const Center(child: Text('Chưa có dữ liệu nến'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0;
        final size = Size(width, height);
        final data = _chartData();
        return GestureDetector(
          onPanStart: (d) => _onPanStart(d, size, data),
          onPanUpdate: (d) => _onPanUpdate(d, size, data),
          onPanEnd: _onPanEnd,
          onTapUp: (d) => _onTapUp(d, size, data),
          child: CustomPaint(
            size: size,
            painter: _ChartPainter(
              candles: data.candles,
              signal: widget.signal,
              emaFast: data.emaFast,
              emaSlow: data.emaSlow,
              ema34: data.ema34,
              drawings: widget.drawings,
              preview: _preview,
              decimals: widget.decimals,
              minP: data.minP,
              maxP: data.maxP,
              tierHits: widget.tierHits,
            ),
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<Candle> candles;
  final StaticSignal? signal;
  final List<double?> emaFast;
  final List<double?> emaSlow;
  final List<double?> ema34;
  final List<Drawing> drawings;
  final Drawing? preview;
  final int decimals;
  final double minP;
  final double maxP;
  final Map<String, bool>? tierHits;

  _ChartPainter({
    required this.candles,
    required this.signal,
    required this.emaFast,
    required this.emaSlow,
    required this.ema34,
    required this.drawings,
    required this.preview,
    required this.decimals,
    required this.minP,
    required this.maxP,
    this.tierHits,
  });

  static const Color _upColor = Color(0xFF0DA271);
  static const Color _downColor = Color(0xFFE0334E);
  static const Color _gridColor = Color(0xFFD7E0EF);
  static const Color _axisTextColor = Color(0xFF68799C);
  static const Color _bgColor = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _kPriceAxisWidth;
    final plotH = size.height - _kTimeAxisHeight;
    if (plotW <= 0 || plotH <= 0 || candles.isEmpty) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = _bgColor);

    _drawGrid(canvas, size, plotW, plotH);
    _drawCandles(canvas, size, plotW);
    _drawEma(canvas, size, emaFast, const Color(0xFFF0B90B));
    _drawEma(canvas, size, emaSlow, const Color(0xFF4DA3FF));
    _drawEma(canvas, size, ema34, const Color(0xFFFF7A1A));
    _drawSignal(canvas, size, plotW);
    for (final d in drawings) {
      _drawDrawing(canvas, size, plotW, plotH, d);
    }
    if (preview != null) {
      _drawDrawing(canvas, size, plotW, plotH, preview!);
    }
    _drawPriceAxis(canvas, size, plotW, plotH);
    _drawTimeAxis(canvas, size, plotW, plotH);
  }

  void _drawGrid(Canvas canvas, Size size, double plotW, double plotH) {
    final paint = Paint()..color = _gridColor..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plotH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(plotW, y), paint);
    }
    final totalSlots = candles.length + _kExtraSlots;
    const step = 10;
    for (var i = 0; i <= totalSlots; i += step) {
      final x = (i + 0.5) / totalSlots * plotW;
      canvas.drawLine(Offset(x, 0), Offset(x, plotH), paint);
    }
    canvas.drawLine(
      Offset(plotW, 0),
      Offset(plotW, plotH),
      Paint()..color = const Color(0xFFA9BCDC),
    );
  }

  void _drawCandles(Canvas canvas, Size size, double plotW) {
    final totalSlots = candles.length + _kExtraSlots;
    final slotW = plotW / totalSlots;
    final bodyW = (slotW * 0.7).clamp(1.0, 24.0);
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final up = c.close >= c.open;
      final color = up ? _upColor : _downColor;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.2;
      final cx = (i + 0.5) / totalSlots * plotW;
      final highY = dataToPixel(Pt(i.toDouble(), c.high), size, minP, maxP, candles.length).dy;
      final lowY = dataToPixel(Pt(i.toDouble(), c.low), size, minP, maxP, candles.length).dy;
      final openY = dataToPixel(Pt(i.toDouble(), c.open), size, minP, maxP, candles.length).dy;
      final closeY = dataToPixel(Pt(i.toDouble(), c.close), size, minP, maxP, candles.length).dy;
      canvas.drawLine(Offset(cx, highY), Offset(cx, lowY), paint);
      final top = openY < closeY ? openY : closeY;
      final bottom = openY > closeY ? openY : closeY;
      final bodyH = (bottom - top).abs() < 1.0 ? 1.0 : bottom - top;
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH),
        Paint()..color = color,
      );
    }
  }

  void _drawEma(Canvas canvas, Size size, List<double?> values, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final path = Path();
    var started = false;
    for (var i = 0; i < values.length && i < candles.length; i++) {
      final v = values[i];
      if (v == null || v.isNaN) {
        started = false;
        continue;
      }
      final p = dataToPixel(Pt(i.toDouble(), v), size, minP, maxP, candles.length);
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  /// Mũi tên tín hiệu tại nến tín hiệu (sigIdx = visible.length − 22,
  /// tối thiểu 2) + thang TP từ nến đó kéo dài 20 nến về phải.
  void _drawSignal(Canvas canvas, Size size, double plotW) {
    final s = signal;
    if (s == null) return;
    final isBuy = s.action == 'BUY';
    final isSell = s.action == 'SELL';
    if (!isBuy && !isSell) return;
    if (candles.isEmpty) return;

    final int sigIdx =
        (candles.length - 22).clamp(2, candles.length - 1);
    final c = candles[sigIdx];
    final cx = dataToPixel(
      Pt(sigIdx.toDouble(), c.close),
      size, minP, maxP, candles.length,
    ).dx;

    final arrowColor = isBuy ? _upColor : _downColor;
    final anchorY = isBuy
        ? dataToPixel(Pt(sigIdx.toDouble(), c.low), size, minP, maxP, candles.length).dy
        : dataToPixel(Pt(sigIdx.toDouble(), c.high), size, minP, maxP, candles.length).dy;
    final arrow = Path();
    if (isBuy) {
      arrow.moveTo(cx, anchorY + 8);
      arrow.lineTo(cx - 6, anchorY + 18);
      arrow.lineTo(cx + 6, anchorY + 18);
    } else {
      arrow.moveTo(cx, anchorY - 8);
      arrow.lineTo(cx - 6, anchorY - 18);
      arrow.lineTo(cx + 6, anchorY - 18);
    }
    arrow.close();
    canvas.drawPath(arrow, Paint()..color = arrowColor);

    final int endX = (sigIdx + _kExtraSlots).clamp(0, candles.length + _kExtraSlots - 1);
    final lv = s.levels;
    if (lv != null) {
      _drawLadderLine(canvas, size, lv.entry, sigIdx, endX,
          const Color(0xFF68799C), 'Entry', dashed: true, hit: false);
      _drawLadderLine(canvas, size, lv.inv, sigIdx, endX,
          const Color(0xFFF6465D), 'Inv (SL)',
          hit: tierHits?['Inv'] == true);
      _drawLadderLine(canvas, size, lv.t1, sigIdx, endX,
          const Color(0xFF3ECF8E), 'T1', hit: tierHits?['T1'] == true);
      _drawLadderLine(canvas, size, lv.t2, sigIdx, endX,
          const Color(0xFF17C784), 'T2', hit: tierHits?['T2'] == true);
      _drawLadderLine(canvas, size, lv.t3, sigIdx, endX,
          const Color(0xFF0DA271), 'T3', hit: tierHits?['T3'] == true);
      _drawLadderLine(canvas, size, lv.t4, sigIdx, endX,
          const Color(0xFF0B7A55), 'T4', hit: tierHits?['T4'] == true);
    } else {
      if (s.sl != null) {
        _drawLadderLine(canvas, size, s.sl!, sigIdx, endX,
            _downColor, 'SL', hit: false);
      }
      if (s.tp != null) {
        _drawLadderLine(canvas, size, s.tp!, sigIdx, endX,
            _upColor, 'TP', hit: false);
      }
    }
  }

  void _drawLadderLine(
    Canvas canvas,
    Size size,
    double price,
    int fromIndex,
    int toIndex,
    Color color,
    String label, {
    bool dashed = false,
    bool hit = false,
  }) {
    final a = dataToPixel(Pt(fromIndex.toDouble(), price), size, minP, maxP, candles.length);
    final b = dataToPixel(Pt(toIndex.toDouble(), price), size, minP, maxP, candles.length);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    if (dashed) {
      _drawDashedLine(canvas, a, b, paint);
    } else {
      canvas.drawLine(a, b, paint);
    }
    final text = '$label ${price.toStringAsFixed(decimals)}${hit ? ' ✓ đã chạm' : ''}';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelX = (b.dx - tp.width - 6).clamp(0.0, size.width - tp.width - 4);
    final labelY = a.dy - tp.height - 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX - 3, labelY - 2, tp.width + 6, tp.height + 4),
        const Radius.circular(3),
      ),
      Paint()..color = color.withOpacity(0.85),
    );
    tp.paint(canvas, Offset(labelX, labelY));
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final end = (drawn + dash).clamp(0.0, total);
      canvas.drawLine(a + dir * drawn, a + dir * end, paint);
      drawn += dash + gap;
    }
  }

  void _drawDrawing(
    Canvas canvas,
    Size size,
    double plotW,
    double plotH,
    Drawing d,
  ) {
    if (d.pts.isEmpty) return;
    switch (d.tool) {
      case DrawTool.trend:
        if (d.pts.length < 2) return;
        final a = dataToPixel(d.pts[0], size, minP, maxP, candles.length);
        final b = dataToPixel(d.pts[1], size, minP, maxP, candles.length);
        final paint = Paint()
          ..color = Colors.amber
          ..strokeWidth = 2;
        canvas.drawLine(a, b, paint);
        canvas.drawCircle(a, 3, Paint()..color = Colors.amber);
        canvas.drawCircle(b, 3, Paint()..color = Colors.amber);
        break;
      case DrawTool.horizontal:
        final y = dataToPixel(d.pts[0], size, minP, maxP, candles.length).dy;
        canvas.drawLine(
          Offset(0, y),
          Offset(plotW, y),
          Paint()
            ..color = Colors.purpleAccent
            ..strokeWidth = 1.8,
        );
        _drawText(
          canvas,
          d.pts[0].y.toStringAsFixed(decimals),
          Offset(4, y - 14),
          Colors.purpleAccent,
          10,
        );
        break;
      case DrawTool.fib:
        if (d.pts.length < 2) return;
        const levels = <(double, String)>[
          (0.0, '0%'),
          (0.382, '38.2%'),
          (0.5, '50%'),
          (0.618, '61.8%'),
          (1.0, '100%'),
        ];
        final x1 = dataToPixel(d.pts[0], size, minP, maxP, candles.length).dx;
        final x2 = dataToPixel(d.pts[1], size, minP, maxP, candles.length).dx;
        final left = x1 < x2 ? x1 : x2;
        final right = x1 > x2 ? x1 : x2;
        for (final (ratio, label) in levels) {
          final price = d.pts[0].y + (d.pts[1].y - d.pts[0].y) * ratio;
          final y = dataToPixel(Pt(0, price), size, minP, maxP, candles.length).dy;
          canvas.drawLine(
            Offset(left, y),
            Offset(right, y),
            Paint()
              ..color = Colors.black54
              ..strokeWidth = 1.2,
          );
          _drawText(canvas, label, Offset(left + 4, y - 13), Colors.black87, 10);
        }
        break;
      case DrawTool.rect:
        if (d.pts.length < 2) return;
        final a = dataToPixel(d.pts[0], size, minP, maxP, candles.length);
        final b = dataToPixel(d.pts[1], size, minP, maxP, candles.length);
        final rect = Rect.fromPoints(a, b);
        canvas.drawRect(rect, Paint()..color = Colors.cyan.withOpacity(0.12));
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.cyan
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
        break;
      case DrawTool.text:
        final p = dataToPixel(d.pts[0], size, minP, maxP, candles.length);
        _drawText(canvas, d.text, p, Colors.amber.shade800, 12,
            weight: FontWeight.bold);
        break;
      case DrawTool.none:
        break;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    FontWeight weight = FontWeight.normal,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  void _drawPriceAxis(Canvas canvas, Size size, double plotW, double plotH) {
    for (var i = 0; i <= 4; i++) {
      final price = minP + (maxP - minP) * i / 4;
      final y = plotH * (4 - i) / 4;
      final tp = TextPainter(
        text: TextSpan(
          text: price.toStringAsFixed(decimals),
          style: const TextStyle(color: _axisTextColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotW + 4, (y - tp.height / 2).clamp(0.0, plotH)));
    }
  }

  void _drawTimeAxis(Canvas canvas, Size size, double plotW, double plotH) {
    if (candles.isEmpty) return;
    final step = (candles.length / 6).ceil().clamp(1, candles.length);
    for (var i = 0; i < candles.length; i += step) {
      final dt = DateTime.fromMillisecondsSinceEpoch(candles[i].time);
      final label =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      final x = dataToPixel(
        Pt(i.toDouble(), minP),
        size, minP, maxP, candles.length,
      ).dx;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: _axisTextColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((x - tp.width / 2).clamp(0.0, plotW - tp.width), plotH + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
