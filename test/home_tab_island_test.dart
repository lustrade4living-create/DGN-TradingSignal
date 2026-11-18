// Widget test cho 2 viec sua ngay 18/11 (khong nang version):
//  1) HomeTab render day du voi engine moi tinh (chua co gia live / nen
//     that / tin hieu) — hero + thong ke + the tin hieu cho + dai tin
//     hieu + statusbar + pair-strip + chart, khong bao gio trang tron.
//  2) DynamicIsland hien gia cua cap dang chon, khong con nut mui ten,
//     chuyen cap bang vuot ngang.
//
// Luu y ve moi truong test:
//  - MockEngine khoi tao Timer.periodic + hen gio warmup (Future.delayed
//    0–3,3s) nen test phai pump them thoi gian de het timer treo, roi
//    go widget + dispose engine TRONG test (truoc khi test ket thuc).
//  - Trong test, HttpClient luon tra HTTP 400 (gioi han cua
//    TestWidgetsFlutterBinding) nen warmup that bai; loi nay thoat ra
//    khoi `whenComplete` trong CandleCache.ensureCandles thanh loi
//    async khong bat duoc. Vi vay engine duoc tao trong runZonedGuarded
//    de gom cac loi mang gia lap nay, khong de chung lam hong test.
//    Tren may that cac fetch nay chay binh thuong nen khong anh huong app.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_signal_ai/engine.dart';
import 'package:trade_signal_ai/main.dart';
import 'package:trade_signal_ai/widgets/dynamic_island.dart';
import 'package:trade_signal_ai/widgets/hero_widget.dart';

/// Tao engine trong zone rieng de gom loi HTTP 400 gia lap cua moi
/// truong test (xem ghi chu dau file). Tra ve engine + danh sach loi da gom.
MockEngine _createEngine(List<Object> zoneErrors) {
  late MockEngine engine;
  runZonedGuarded(
    () => engine = MockEngine(),
    (Object e, StackTrace s) => zoneErrors.add(e),
  );
  return engine;
}

/// Ket thuc sach: go widget (huy clock cua DynamicIsland), dispose
/// engine (huy Timer.periodic), roi pump them 6s de cac timeout 5s cua
/// fetch dang chay duoc kich hoat va ket thuc — khong con timer treo.
Future<void> _cleanUp(WidgetTester tester, MockEngine engine) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  engine.dispose();
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  testWidgets('HomeTab render du voi engine rong (khong gia/nenn/tin hieu)',
      (tester) async {
    // Viewport cao de toan bo HomeTab (ListView) duoc build, khong can cuon.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<Object> errors = <Object>[];
    final FlutterExceptionHandler? old = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      errors.add(d.exception);
    };

    final List<Object> zoneErrors = <Object>[];
    final MockEngine engine = _createEngine(zoneErrors);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(engine: engine, onGoSignals: (_, {String? symbol}) {}),
        ),
      ),
    );
    await tester.pump();
    FlutterError.onError = old;

    expect(errors, isEmpty, reason: 'HomeTab khong duoc throw khi du lieu rong');
    // Hero (logo DGN + founder) render duoc — truoc day vo layout vi
    // Row(stretch) trong Stack o ListView (BoxConstraints infinite height).
    expect(find.byType(HeroWidget), findsOneWidget);
    expect(find.text('DGN'), findsWidgets);
    expect(find.text('Tín hiệu 8 cặp'), findsOneWidget);
    // The tin hieu cho (chua co tin hieu BUY/SELL) + dai tin hieu cho.
    expect(find.textContaining('Đang quét 8 cặp'), findsWidgets);
    // Chart: chua co tin hieu tinh cho cap dang chon.
    expect(find.textContaining('ĐANG TẢI'), findsWidgets);
    // Statusbar + pair-strip hien trang thai gia.
    expect(find.textContaining('DỮ LIỆU CŨ'), findsWidgets);
    expect(find.text('XAUUSD'), findsWidgets);

    await _cleanUp(tester, engine);
  });

  testWidgets('DynamicIsland hien gia, khong nut mui ten, vuot doi cap',
      (tester) async {
    final List<Object> zoneErrors = <Object>[];
    final MockEngine engine = _createEngine(zoneErrors);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [DynamicIsland(engine: engine)],
          ),
        ),
      ),
    );
    await tester.pump();

    // Cap dang chon mac dinh la XAUUSD + gia live (mock) cua no.
    final String expectedPrice =
        engine.fmt(engine.priceOf('XAUUSD'), 'XAUUSD');
    expect(find.text('XAUUSD'), findsOneWidget);
    expect(find.text(expectedPrice), findsOneWidget);
    // Khong con 2 nut mui ten ‹ ›.
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    // Vuot ngang sang trai -> cap ke tiep (EURUSD), gia doi theo.
    await tester.drag(find.byType(DynamicIsland), const Offset(-300, 0));
    await tester.pump();
    expect(find.text('EURUSD'), findsOneWidget);
    expect(
      find.text(engine.fmt(engine.priceOf('EURUSD'), 'EURUSD')),
      findsOneWidget,
    );
    expect(find.byType(IconButton), findsNothing);

    await _cleanUp(tester, engine);
  });
}
