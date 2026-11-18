// Menu 3 gạch (hamburger) — thay thanh nav dưới cũ (BottomNavigationBar).
// Icon ☰ cố định góc dưới bên trái (FloatingActionButton mini); bấm vào
// mở bottom sheet liệt kê đủ 10 mục, mục đang xem được tô sáng.
// Chọn mục nào thì chuyển tới mục đó và đóng menu; bấm ngoài sheet hoặc
// nút đóng thì đóng menu mà không đổi trang.
import 'package:flutter/material.dart';

/// Tên đầy đủ 10 mục trong menu. Thứ tự KHỚP _tabLabels / IndexedStack
/// trong main.dart: 0 Trang chủ … 9 Auto-Trade. (Riêng 'Lịch kinh tế'
/// viết đầy đủ, khác nhãn rút gọn 'Lịch KT' của tabbar trên.)
const List<String> hamburgerMenuLabels = <String>[
  'Trang chủ',
  'Tín hiệu',
  'Phân tích',
  'Lịch kinh tế',
  'Tin tức',
  'Lịch sử',
  'VolumeB/S',
  'Chiến lược AI',
  'Backtest',
  'Auto-Trade',
];

const List<IconData> hamburgerMenuIcons = <IconData>[
  Icons.home,
  Icons.signal_cellular_alt,
  Icons.analytics,
  Icons.calendar_month,
  Icons.newspaper,
  Icons.history,
  Icons.bar_chart,
  Icons.psychology,
  Icons.assessment,
  Icons.autorenew,
];

/// Nội dung menu: tiêu đề + nút đóng + 10 mục, mục đang xem được tô sáng
/// (nền nhạt + dấu tick).
class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text(
              'Menu',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Đóng menu',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: hamburgerMenuLabels.length,
              itemBuilder: (context, i) {
                final bool selected = i == currentIndex;
                return ListTile(
                  leading: Icon(hamburgerMenuIcons[i]),
                  title: Text(hamburgerMenuLabels[i]),
                  selected: selected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.12),
                  trailing:
                      selected ? const Icon(Icons.check) : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelect(i);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Mở menu dạng bottom sheet. Bấm ngoài sheet (barrier) hoặc nút đóng
/// thì chỉ đóng sheet, không gọi [onSelect] nên không đổi trang.
Future<void> showHamburgerMenu(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => HamburgerMenu(
      currentIndex: currentIndex,
      onSelect: onSelect,
    ),
  );
}
