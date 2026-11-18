// Gauge cộng hưởng đa khung (spec §7) — vẽ bằng CustomPaint:
// cung đỏ (Giảm) / xám (Ngang) / xanh (Tăng), kim theo score.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../gauge_ladder.dart';

class GaugeWidget extends StatelessWidget {
  const GaugeWidget({super.key, required this.gauge});

  final GaugeData gauge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 130,
          width: double.infinity,
          child: CustomPaint(
            painter: _GaugePainter(gauge),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _count('▲ Tăng', gauge.upN, AppColors.up),
            _count('◆ Ngang', gauge.flatN, AppColors.mut2),
            _count('▼ Giảm', gauge.dnN, AppColors.dn),
            Text(
              '${gauge.avail}/5 khung',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppColors.mut),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(gauge.verdict, style: const TextStyle(color: AppColors.mut)),
      ],
    );
  }

  Widget _count(String label, int n, Color c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: c, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text('$n',
            style: TextStyle(color: c, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.gauge);

  final GaugeData gauge;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height - 12);
    final double r = math.min(size.width / 2 - 8, size.height - 20);
    // Cung màu: đỏ 180°→126°, xám 124°→56°, xanh 54°→0° (góc vẽ: 180° trái).
    void arc(double startDeg, double sweepDeg, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 13
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        startDeg * math.pi / 180,
        sweepDeg * math.pi / 180,
        false,
        paint,
      );
    }

    arc(180, -54, AppColors.dn); // 180°→126°
    arc(124, -68, AppColors.mut2); // 124°→56°
    arc(54, -54, AppColors.up); // 54°→0°
    // Kim: theta = 90° − score × 78° (đo từ trục x, ngược chiều kim đồng hồ
    // trong hệ tọa độ canvas: dùng góc âm).
    final double thetaDeg = 90 - gauge.score * 78;
    final double theta = -thetaDeg * math.pi / 180;
    final Offset tip = center +
        Offset(math.cos(theta) * (r - 18), math.sin(theta) * (r - 18));
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = AppColors.txt
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 6, Paint()..color = AppColors.txt);
    // Nhãn GIẢM / NGANG / TĂNG
    _label(canvas, 'GIẢM', Offset(center.dx - r - 2, center.dy - 14),
        AppColors.dn);
    _label(canvas, 'NGANG', Offset(center.dx - 22, center.dy - r - 18),
        AppColors.mut2);
    _label(canvas, 'TĂNG', Offset(center.dx + r - 30, center.dy - 14),
        AppColors.up);
  }

  void _label(Canvas canvas, String text, Offset offset, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.gauge.score != gauge.score ||
      old.gauge.upN != gauge.upN ||
      old.gauge.dnN != gauge.dnN ||
      old.gauge.avail != gauge.avail;
}
