// Theme trắng TradeSignal AI — đúng spec §16.1.
// Font mặc định hệ thống (không thêm font ngoài).
import 'package:flutter/material.dart';

class AppColors {
  static const Color bg = Color(0xFFEDF1F8);
  static const Color bg2 = Color(0xFFF3F5FA);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color panel2 = Color(0xFFEDF2FA);
  static const Color line = Color(0xFFD7E0EF);
  static const Color line2 = Color(0xFFA9BCDC);
  static const Color txt = Color(0xFF0A1E42);
  static const Color mut = Color(0xFF46587A);
  static const Color mut2 = Color(0xFF68799C);
  static const Color up = Color(0xFF0DA271);
  static const Color dn = Color(0xFFE0334E);
  static const Color gold = Color(0xFFD97E06);
  static const Color blue = Color(0xFF2F7BFF);
  static const Color org = Color(0xFFFF7D1F);
  static const Color navy = Color(0xFF0A1E42);
  static const Color navy2 = Color(0xFF123A7D);
  static const Color panic = Color(0xFFD61F38);
  static const Color emaFast = Color(0xFFF0B90B);
  static const Color emaSlow = Color(0xFF4DA3FF);
  static const Color ema34 = Color(0xFFFF7A1A);

  static Color actionColor(String action) {
    switch (action) {
      case 'BUY':
        return up;
      case 'SELL':
        return dn;
      default:
        return mut2;
    }
  }
}

ThemeData appTheme() {
  const Color primary = Color(0xFF1F6BFF);
  return ThemeData.light().copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    cardColor: AppColors.panel,
    primaryColor: primary,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: AppColors.org,
      surface: AppColors.panel,
      onSurface: AppColors.txt,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.panel,
      foregroundColor: AppColors.txt,
      elevation: 0,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.panel,
      selectedItemColor: AppColors.blue,
      unselectedItemColor: AppColors.mut2,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      unselectedLabelStyle: TextStyle(fontSize: 11),
    ),
    cardTheme: CardTheme(
      color: AppColors.panel,
      elevation: 2,
      shadowColor: AppColors.txt.withOpacity(0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.panel2,
      selectedColor: primary,
      labelStyle: const TextStyle(color: AppColors.txt),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
    ),
    dividerColor: AppColors.line,
    textTheme: ThemeData.light().textTheme.apply(
          bodyColor: AppColors.txt,
          displayColor: AppColors.txt,
        ),
  );
}

/// Khối thu gọn mặc định (nút Ẩn/Hiện) — dùng cho bảng điểm, Trend/gauge,
/// phân tích theo từng cặp (spec §16.5).
class Collapsible extends StatefulWidget {
  const Collapsible({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = false,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyOpen;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    _open ? 'Ẩn ▲' : 'Hiện ▼',
                    style: const TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            const Divider(height: 1),
          if (_open)
            Padding(
              padding: const EdgeInsets.all(14),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// Tiêu đề mục trong tab.
Widget sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.txt,
      ),
    ),
  );
}

/// Dòng key–value.
Widget kvRow(String k, String v, {Color? vColor, bool boldValue = true}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(k, style: const TextStyle(color: AppColors.mut)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: boldValue ? FontWeight.bold : FontWeight.normal,
              color: vColor ?? AppColors.txt,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Badge hướng BUY/SELL/WAIT.
Widget actionBadge(String action, {double fontSize = 15}) {
  final Color c = AppColors.actionColor(action);
  final String label =
      action == 'BUY' ? 'BUY · Long' : action == 'SELL' ? 'SELL · Short' : 'WAIT';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.withOpacity(0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: c),
    ),
    child: Text(
      label,
      style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: fontSize),
    ),
  );
}

/// Thanh % tin cậy (≥75 xanh, 55–74 vàng cam, <55 xám).
Widget confBar(int conf, {bool showLabel = true}) {
  final Color c = conf >= 75
      ? AppColors.up
      : conf >= 55
          ? AppColors.gold
          : AppColors.mut2;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Độ tin cậy',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            '$conf%',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: c, fontSize: 16),
          ),
        ],
      ),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: conf / 100,
          minHeight: 10,
          backgroundColor: AppColors.line,
          valueColor: AlwaysStoppedAnimation<Color>(c),
        ),
      ),
      if (showLabel)
        const SizedBox(height: 2),
    ],
  );
}

/// Thẻ ghi chú nhỏ (màu nền nhạt).
Widget noteCard(String text, {Color? bg, Color? fg}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: bg ?? AppColors.panel2,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: fg ?? AppColors.mut),
    ),
  );
}
