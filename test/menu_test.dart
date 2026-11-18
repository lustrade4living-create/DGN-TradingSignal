// Widget test cho menu 3 gach (thay thanh nav duoi cu):
//  1) HamburgerMenu dung: du 10 muc, muc dang xem duoc to sang,
//     chon muc thi goi onSelect dung chi so.
//  2) HomeScreen: khong con BottomNavigationBar; icon 3 gach mo menu;
//     chon muc thi doi tab dung va menu dong; nut dong thi dong menu
//     ma khong doi tab.
//
// Luu y ve moi truong test (giong home_tab_island_test.dart):
//  - MockEngine khoi tao Timer.periodic + hen gio warmup nen engine
//    duoc tao trong runZonedGuarded de gom loi HTTP 400 gia lap, va
//    dispose engine TRONG test (truoc khi test ket thuc).
//  - Khong dung pumpAndSettle (engine tick lien tuc lam no khong bao
//    gio on dinh); chi pump() + pump(duration) cho animation sheet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/engine.dart';
import 'package:trade_signal_ai/main.dart';
import 'package:trade_signal_ai/widgets/hamburger_menu.dart';

MockEngine _createEngine(List<Object> zoneErrors) {
  late MockEngine engine;
  runZonedGuarded(
    () => engine = MockEngine(),
    (Object e, StackTrace s) => zoneErrors.add(e),
  );
  return engine;
}

Future<void> _cleanUp(WidgetTester tester, MockEngine engine) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  engine.dispose();
  await tester.pump(const Duration(seconds: 6));
}

/// Tabbar tren hien thi dung tab dang chon: ChoiceChip cua tab do co
/// selected == true.
Finder _selectedTabChip(String label) => find.byWidgetPredicate(
      (Widget w) =>
          w is ChoiceChip &&
          w.selected &&
          (w.label as Text?)?.data == label,
    );

void main() {
  testWidgets('HamburgerMenu: du 10 muc, muc dang xem to sang, chon dung',
      (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HamburgerMenu(
            currentIndex: 1,
            onSelect: (i) => selected = i,
          ),
        ),
      ),
    );
    await tester.pump();

    for (final String label in hamburgerMenuLabels) {
      expect(find.text(label), findsOneWidget, reason: 'Thieu muc $label');
    }
    expect(hamburgerMenuLabels, hasLength(10));
    // Muc dang xem (Tín hiệu) duoc to sang + co dau tick.
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is ListTile &&
            w.selected &&
            (w.title as Text?)?.data == 'Tín hiệu',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Backtest'));
    await tester.pump();
    expect(selected, 8);
  });

  testWidgets(
      'HomeScreen: khong BottomNavigationBar, icon 3 gach mo menu, '
      'chon muc doi tab va dong menu', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<Object> zoneErrors = <Object>[];
    final MockEngine engine = _createEngine(zoneErrors);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(engine: engine)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Khong con thanh nav duoi cu trong cay widget.
    expect(find.byType(BottomNavigationBar), findsNothing);
    // Icon 3 gach co mat (FAB mini, tooltip 'Menu').
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    // Dang o tab Trang chu.
    expect(_selectedTabChip('Trang chủ'), findsOneWidget);

    // Mo menu.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Menu'), findsOneWidget);
    // Nhan day du 'Lịch kinh tế' chi co trong menu (tabbar ghi 'Lịch KT').
    expect(find.text('Lịch kinh tế'), findsOneWidget);
    for (final String label in hamburgerMenuLabels) {
      expect(find.text(label), findsWidgets, reason: 'Menu thieu $label');
    }

    // Chon 'Lịch sử' trong menu (co 2 text 'Lịch sử': tabbar + menu;
    // cai trong sheet nam sau trong cay widget).
    await tester.tap(find.text('Lịch sử').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Menu dong, tab da doi sang Lịch sử.
    expect(find.text('Lịch kinh tế'), findsNothing);
    expect(find.text('Menu'), findsNothing);
    expect(_selectedTabChip('Lịch sử'), findsOneWidget);

    await _cleanUp(tester, engine);
  });

  testWidgets('Menu: nut dong thi dong menu, khong doi tab',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<Object> zoneErrors = <Object>[];
    final MockEngine engine = _createEngine(zoneErrors);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(engine: engine)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Lịch kinh tế'), findsOneWidget);

    // Bam nut dong (khong chon muc nao).
    await tester.tap(find.byTooltip('Đóng menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Lịch kinh tế'), findsNothing);
    expect(find.text('Menu'), findsNothing);
    // Van o tab Trang chu.
    expect(_selectedTabChip('Trang chủ'), findsOneWidget);

    await _cleanUp(tester, engine);
  });
}
