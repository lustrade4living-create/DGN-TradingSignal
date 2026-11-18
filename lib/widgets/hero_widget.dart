// Hero Trang chủ (spec §16.3): panel navy gradient, trái logo DGN +
// khẩu hiệu + gạch cam + khối founder; phải ảnh CEO đứng trực tiếp trên
// nền hero KHÔNG khung ảnh, mép trái mờ dần (ShaderMask gradient).
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../engine.dart';

class HeroWidget extends StatelessWidget {
  const HeroWidget({super.key, required this.engine});

  final MockEngine engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123A7D), Color(0xFF081F49), Color(0xFF051633)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF051633).withOpacity(0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Vệt sáng radial (xanh góc trên phải, cam góc dưới trái).
            Positioned(
              right: -40,
              top: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2F8CFF).withOpacity(0.25),
                ),
              ),
            ),
            Positioned(
              left: -50,
              bottom: -70,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF7D1F).withOpacity(0.20),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 8, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              'assets/dgn-mark-clear.png',
                              width: 66,
                              height: 66,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 66,
                                height: 66,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'DGN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 31,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Trade Signals — Smarter. Faster.',
                          style: TextStyle(
                            color: Color(0xFFB9CDF2),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF8A1E), Color(0xFFFFB347)],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.only(left: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                  color: Color(0xFFFF7D1F), width: 3),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Our founder',
                                style: TextStyle(
                                  color: Color(0xFFB9CDF2),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'DGN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'TradeSignal AI · Tín hiệu 8 cặp theo giá live thật, chốt tĩnh theo nến đóng · đổi chiến lược & backtest ở mục Chiến lược AI / Backtest',
                                style: TextStyle(
                                  color: Color(0xFFB9CDF2),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Ảnh CEO — đứng trực tiếp trên nền hero, mép trái mờ dần.
                Expanded(
                  flex: 4,
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Colors.transparent, Colors.black],
                        stops: [0.0, 0.26],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstIn,
                    child: Image.asset(
                      'assets/ceo-founder.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dải thống kê 3 ô bằng SỐ LIỆU THẬT (spec §16.3).
class HeroStatsRow extends StatelessWidget {
  const HeroStatsRow({super.key, required this.engine});

  final MockEngine engine;

  @override
  Widget build(BuildContext context) {
    final int liveCount = symbols
        .where((s) => engine.priceStatus(s.code) == 'LIVE')
        .length;
    final double? wr = engine.history.winRate;
    final int recorded = engine.history.entries.length;
    final int openCount = engine.history.openCount;

    Widget cell(String label, String value) {
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.txt,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.mut),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            cell('Tỷ lệ thắng (phiên)', wr == null ? '—' : '${wr.toStringAsFixed(1)}%'),
            cell('Tín hiệu đã ghi', '$recorded'),
            cell('Đang mở', '$openCount'),
            cell('Cặp có giá live', '$liveCount/8'),
          ],
        ),
        const Text(
          'Ba con số trên được tính trực tiếp từ lịch sử tín hiệu app ghi được trong phiên đang mở và nguồn giá live hiện tại — đóng app là tính lại từ đầu.',
          style: TextStyle(fontSize: 11, color: AppColors.mut2),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
