# AUDIT — TradeSignal AI (Flutter) + Pipeline Build Tay

- **Ngày audit:** 17/11/2026 (kiểm tra trực tiếp trên máy, không sửa code nguồn)
- **Phạm vi:** `~/workspace/TradeSignalApp` — toàn bộ `lib/`, `pubspec.yaml`, `android/`, `manual/`
- **Mục đích:** làm tài liệu nền cho coordinator lên kế hoạch port 15 nhóm tính năng web (file web đối chiếu: `~/workspace/your_files/tradesignal-ai-phase-1/tradesignal-ai-phase-1.html`, 1.653.631 byte, xuất 17/11 13:35) sang Flutter, build APK v1.2.0+3 bằng pipeline tay không Gradle.
- **Kết quả kiểm tra nhanh:**
  - `~/flutter/bin/flutter --version` → Flutter **3.24.5** (stable, revision dec2ee5c1f, 2024-11-13), Dart **3.5.4**. Chạy được (cảnh báo "run as root" — không ảnh hưởng).
  - `~/jdk17/bin/java -version` → OpenJDK **17.0.21** Temurin. Chạy được.
  - `flutter analyze --no-pub` trên project → **No issues found!** (7,1 giây).
  - APK v1.1.0 hiện tại `build/manual/TradeSignalAI-v1.1.0.apk` (53.353.041 byte, 16/11 06:11): `apksigner verify --verbose` → **v1/v2/v3 = true** (v3.1/v4 = false, bình thường với apksigner build-tools 34); `aapt2 dump badging` → `package: name='com.tradesignal.ai' versionCode='2' versionName='1.1.0'`, minSdk 21, targetSdk 34.
  - **Lưu ý:** `apksigner` là script shell cần `java` trong PATH — chạy trực tiếp thất bại (`java: not found`) khi PATH chưa có `~/jdk17/bin`; phải `export PATH=~/jdk17/bin:$PATH` trước. `which apksigner/aapt2/zipalign` (PATH mặc định) → **không có**; các tool chỉ nằm ở `~/Android/sdk/build-tools/34.0.0/` (đã kiểm tra có đủ `aapt2`, `apksigner`, `zipalign`, `d8`).

---

## 1. KIẾN TRÚC HIỆN TẠI

### 1.1. Tổng quan

| File | Dòng | Vai trò |
|---|---|---|
| `lib/main.dart` | 1.961 | Toàn bộ UI: splash/intro, HomeScreen, 6 tab, Auto-Trade, VolumeB/S UI |
| `lib/engine.dart` | 1.419 | Model + chỉ báo + `MockEngine` (giá live, tín hiệu, rule engine, lịch/news mock, auto-trade mock) |
| `lib/chart.dart` | 672 | Chart nến `CustomPaint` + vẽ tay |
| `lib/volume_profile.dart` | 446 | Phân tích Volume Profile TonyD (POC/VAH/VAL, HVN/LVN, Delta ước tính, mô hình A/B/C, chấm 10đ) |
| `pubspec.yaml` | — | `name: trade_signal_ai`, `version: 1.1.0+2`, **không có plugin nào** (chỉ `flutter` + `flutter_test`), 1 asset |

**State management: `ChangeNotifier` + `setState`, không dùng Provider/Riverpod/Bloc/Stream.**
- `MockEngine extends ChangeNotifier` (`engine.dart:379`). Mọi màn hình đọc engine qua `ListenableBuilder(listenable: engine, ...)` ở `HomeScreen` (`main.dart:178`) và gọi `engine.notifyListeners()`.
- State cục bộ của từng tab dùng `setState` trong `StatefulWidget` (VD `_ChartTabState._drawings`, `_SettingsTabState` controllers, `_SplashGateState._done`).
- Engine được tạo **một lần** trong `TradeSignalApp.build()` (`main.dart:52`: `final engine = MockEngine();`) rồi truyền xuống qua constructor — không có DI container, không có singleton global.

### 1.2. `lib/main.dart` (1.961 dòng) — UI

- `main()` (dòng 9–36): `runZonedGuarded` + `WidgetsFlutterBinding.ensureInitialized()`; nếu crash lúc khởi động thì hiện màn hình lỗi text thay vì crash trắng.
- `TradeSignalApp extends StatelessWidget` (dòng 38–71): tạo `MockEngine`, `MaterialApp`, **`ThemeData.dark()`** — nền scaffold `0xFF0E1117`, card `0xFF1A1F2E`, AppBar `0xFF0A1F44` (navy), primary cam `0xFFFF6A00`, secondary xanh lá `0xFF00C853`.
- `_SplashGate` (dòng 76–151): intro logo DGN — nền navy `0xFF0A1F44`, logo trong thẻ trắng viền cam, chữ "TradeSignal AI" + "DGN • Tín hiệu Swing XAUUSD", tự chuyển sau **`Timer(2500ms)`**, chạm để bỏ qua (`GestureDetector.onTap`).
- `_HomeScreenState` (dòng 159–310): `ListenableBuilder` bao toàn bộ `Scaffold`.
  - AppBar: logo DGN 30×30 (`Image.asset('assets/dgn_logo.jpg')`) + chữ "TradeSignal AI" + Chip `LIVE` / `DỮ LIỆU CŨ` (theo `engine.hasLive`).
  - Banner cam khi `engine.offline` ("Chế độ Offline — dữ liệu có thể cũ") hoặc khi mất live ("DỮ LIỆU CŨ — chưa lấy được giá live…").
  - Nút **PANIC STOP** (`FloatingActionButton.extended`, nền đỏ) chỉ hiện khi `engine.autoTrade == true` (dòng 227–250); bấm → `engine.panicStop()` + SnackBar "Đã đóng tất cả lệnh mock và tắt Auto-Trade".
  - Body: `IndexedStack` 6 tab (giữ cả 6 tab mounted cùng lúc) + `BottomNavigationBar` fixed 6 mục.
- Các tab (theo thứ tự `IndexedStack`, dòng 258–276):
  1. `DashboardTab` (dòng 317–445): thẻ "Tín hiệu mạnh nhất" (`_StrongestSignalCard`, chọn signal có `confidence` cao nhất trong 8 cặp) + danh sách 8 cặp (`ListTile`: giá `engine.fmt(...)`, nguồn giá + giờ cập nhật + trạng thái LIVE/CŨ, action BUY/SELL + % confidence, sao theo dõi; bấm → `selectSymbol` + sang tab Biểu đồ).
  2. `ChartTab` (dòng 512–713): chip chọn cặp (ngang), chip khung giờ M1/M5/M15/H1/H4/D1, banner nguồn giá, nút vẽ (Trend/Ngang/Fib/Hộp/Chữ/Xóa), `CandleChart` cao 320px, panel tín hiệu cặp đang chọn (`_SignalDetailRows`: Entry/SL/TP/RR/Confidence/Bias + reasons + nút Theo dõi).
  3. `CalendarTab` (dòng 720–881): lọc High/Medium/Low, chọn ngày ‹ ›, cảnh báo cam khi có tin High/goldImpact, `ListView` sự kiện (giờ, nước, impact, forecast/actual/previous).
  4. `NewsTab` (dòng 888–1026): ô tìm kiếm + chip từ khóa cố định `gold, XAU, Fed, inflation, DXY, treasury`; list tin có tag sentiment Tích cực/Tiêu cực/Trung tính (`_sentimentTag`).
  5. `SettingsTab` (dòng 1033–1470): 6 mục — (1) Giá & dữ liệu, (2) Giả lập Offline (`SwitchListTile`), (3) Đăng nhập Exness (MOCK), (4) Rule Engine (TextField JSON + nút "Chạy Rule"), (5) Auto-Trade (MOCK DEMO), (6) Lệnh đang mở (mock) + Lịch sử lệnh đã đóng + Hiệu suất từng cặp. Dialog xác nhận `_confirmAutoTrade()` (dòng 1094–1169): bắt gõ đúng `"TÔI ĐỒNG Ý"`, `barrierDismissible: false`.
  6. `VolumeProfileTab` (dòng 1473–1961): xem §1.5.
- `_SignalDetailRows` (dòng 493–511): hiển thị Entry/SL/TP/RR/Confidence/Bias dạng text thuần, không format theo decimals của cặp (in số double thô).

### 1.3. `lib/engine.dart` (1.419 dòng) — Engine

**Model (dòng 16–195):**
- `Candle(o,h,l,c,vol,time)` + getter bí danh `open/high/low/close` (cho `chart.dart`).
- `SymbolInfo(code, name, base, tick, decimals)`; `symbols` (dòng 44–53): 8 cặp với **giá neo ~16/11/2026** — BTCUSD 65100, XAUUSD 3880, EURUSD 1.1025, GBPUSD 1.3210, USDCAD 1.4270, USDCHF 0.8390, USDJPY 159.70, USOIL 88.30. Giá neo chỉ là điểm xuất phát cho nến mock trước khi giá live về.
- `Signal` (dòng 60–94): `symbol, timeframe, action (BUY/SELL/WAIT), bias, mode='SWING', status='open', id='${symbol}_${millisecondsSinceEpoch}', entry, sl, tp, rr, confidence, atr, reasons, time`. **Không có trường giờ lên/giờ dừng, không có lý do hủy/cắt lỗ.**
- `IndicatorSet` (dòng 96–120): `ema20/50/200, rsi, macd, macdSignal, atr, bbUp/bbMid/bbLow`.
- `Trade` (dòng 122–152): `id, symbol, action, status open/closed, entry, sl, tp, lot, opened, closePrice, pnl`; getter `profit` (chuỗi USD).
- `EconEvent` (dòng 154–174), `GoldNews` (dòng 176–195).

**Chỉ báo kỹ thuật — hàm top-level, tham số CỐ ĐỊNH (dòng 197–365):**
- `ema(closes, period)` (197): null tới khi đủ period, nến đầu = SMA, k = 2/(period+1).
- `rsi(closes, period)` (215): Wilder, mặc định gọi với 14.
- `atr(cs, period)` (243): True Range Wilder, mặc định 14.
- `macdLine` (271): EMA12 − EMA26 (cố định); `macdSignal` (283): EMA9 của MACD.
- `_bollinger(closes, period, mult)` (302): SMA ± 2σ; wrapper `bollingerUp/Mid/Low` gọi với (20, 2) cố định.
- `computeIndicators(cs)` (340): trả đủ EMA20/50/200, RSI14, MACD(12,26,9), ATR14, Bollinger(20,2). **Không có EMA34, không có RSI9, không có MACD(34,58,12), không có tham số tùy chỉnh — mọi con số hardcode.**
- `_lastValue(values)` (356): giá trị non-null cuối cùng.

**`MockEngine extends ChangeNotifier` (dòng 379–1419) — các khối chính:**

| Khối | Dòng | Nội dung |
|---|---|---|
| State giá live | 384–448 | `liveSource/liveUpdated/liveOk` theo từng cặp; `hasLive` = có ≥1 cặp cập nhật trong 10 giây; `priceStatus()` = LIVE / DỮ LIỆU CŨ (ngưỡng 10s); `priceSource()`, `updatedLabel()` (HH:MM:SS) |
| State giao dịch | 449–476 | `prices`, `signals` (Map 8 cặp), `followed` (Set), `autoTrade=false`, `demoOnly=true`, `demoStarted`, `exnessConnected/exnessAccount`, `openTrades/closedTrades`, `dailyPnl`, `riskPct=1`, `fixedLot=0.01`, `useFixedLot=true`, `maxOpen=3`, `maxDrawdownPct=5`, `minConfidence=70`, `allowedSymbols={XAUUSD, BTCUSD}`, `tradeStart='08:00'`, `tradeEnd='22:00'`, `ruleJson='{"rsi_lt":30,"close_gt_ema":200}'`, `ruleResult='Chưa chạy'` |
| Constructor + Timer | 455–476 | Sinh 300 nến M1/cặp; `_timer = Timer.periodic(1s, tick())`; `_liveTimer = Timer.periodic(2s, _fetchLivePrices())`; gọi `_fetchLivePrices()` ngay |
| Giá live | 477–720 | `_getJsonPrice()` (HttpClient, timeout 5s/lần); `_applyLivePrice()` (neo nến M1 cuối vào giá live, tính lại signal); `_fetchLivePrices()` (tuần tự 5 nguồn — xem §2) |
| Sinh nến | 722–803 | `_generateM1(s)` (300 nến, `Random(s.code.hashCode)`, step theo cặp); `_aggregate(m1, minutes)` (gộp theo bucket giờ chuẩn); `candlesFor(symbol, tf)` (M1/M5/M15/H1/H4/D1, **tối đa 200 nến cuối**) |
| Tick 1 giây | 839–882 | `tick()`: random-walk nến M1 cuối mỗi cặp (trừ cặp đang LIVE <10s); **cứ 15 tick (15 giây) tính lại toàn bộ signal 8 cặp** (`computeSignal`); nếu action đổi → `maybeAutoTrade()`; `notifyListeners()` **mỗi giây** |
| Tín hiệu | 884–1000 | `computeSignal(symbol)` — xem §1.4 |
| Rule Engine | 1002–1134 | `evaluateRule(jsonText, symbol)`: khóa hỗ trợ `rsi_lt, rsi_gt, close_gt_ema, close_lt_ema (20/50/200), ema20_gt_ema50, ema20_lt_ema50 (bool), action`; tất cả đúng → BUY (hoặc SELL nếu chỉ có điều kiện giảm); sai → WAIT; lỗi → chuỗi `'Lỗi: ...'` |
| Exness | 1136–1160 | `connectExness(key, secret)`: chỉ kiểm tra non-empty, **không lưu key/secret**; chỉ giữ `exnessAccount = 'DEMO ••••${4 ký tự cuối key}'`; `disconnectExness()` tắt luôn auto-trade |
| Auto-trade mock | 1162–1245 | `enableAutoTrade()` (set `demoStarted` lần đầu), `maybeAutoTrade()` (mở lệnh mock nếu confidence ≥ minConfidence, cặp trong allowedSymbols, chưa đủ maxOpen, chưa có lệnh mở cùng cặp), `_settleTrade()` (PnL = (giá − entry) × hướng × lot × `_contractSize`: XAU 100, BTC 1, dầu 1000, forex 100.000), `closeTrade()`, `panicStop()` (đóng hết lệnh mở theo giá hiện tại, `autoTrade=false`) |
| Thống kê | 1247–1303 | `winRate/profitFactor/avgRr(symbol)`: nếu chưa có lệnh đóng thì trả **số mock theo hash** — `winRate = 58 + hashCode%15`, `profitFactor = 1.2 + (hash%8)/10`, `avgRr = 1.8 + (hash%3)/10` (**không phải dữ liệu thật**, hash có thể đổi giữa các lần chạy) |
| Lịch + news mock | 1305–1395 | `eventsFor(day)`: **7 sự kiện cố định mỗi ngày** (CPI 08:30, PMI 09:30, PPI 10:00, GDP 13:30, NFP 15:30, FOMC 19:00, phát biểu Fed 21:00 — giờ cố định, không theo lịch thật); `allNews()`: **8 tin GoldNews hardcode** (Kitco/FXStreet/Reuters, giá vàng 2.400–2.450 USD — đã lỗi thời so với giá live ~3.880); `filteredNews(keyword)` lọc chuỗi |
| Format | 1397–1419 | `fmt(v, symbol)` = `toStringAsFixed(decimals)` |

### 1.4. Cách sinh tín hiệu — `computeSignal()` (`engine.dart:884–1000`)

- Khung: Swing **M15** (EMA20/50 + RSI14 trên M15), xác nhận H4 chỉ nằm trong `reasons` ("Chờ xác nhận H4") — **không có logic H4 thật**.
- **BUY** nếu `EMA20 > EMA50` và `RSI < 70`; **SELL** nếu `EMA20 < EMA50` và `RSI > 30`; còn lại **WAIT**. Nếu EMA null (thiếu nến) thì fallback so sánh giá đóng hiện tại với giá 6 nến trước.
- **Entry = giá hiện tại** (`priceOf(symbol)` — giá live hoặc giá mock tick).
- **ATR:** `_lastValue(indH1.atr) ?? _lastValue(indM15.atr) ?? price * 0.0015`.
  - ⚠️ **Hạn chế dữ liệu:** chỉ có 300 nến M1 → gộp được **5 nến H1** và **2 nến H4**. ATR14/EMA20 trên H1 **luôn null** (cần ≥14 nến) nên thực tế ATR lấy từ M15, hoặc fallback `price*0.0015`. EMA200 cũng luôn null trên mọi khung (tối đa 200 nến, cần 200 nến để có 1 giá trị).
- **SL = Entry ∓ 1.5×ATR; TP = Entry ± 3×ATR; RR = 2.0 cố định.** WAIT thì SL = TP = Entry.
- **Confidence 55–92:** `55 + (|EMA20−EMA50| / ATR) × 8`, +8 nếu RSI <30 hoặc >70, +4 nếu |RSI−50| > 15, clamp [55, 92]. **Không liên quan Trend hay Price Action.**
- `reasons`: 4 dòng cố định theo action (VD BUY: "EMA20 > EMA50", "RSI … chưa quá mua", "ATR SL động …", "Xu hướng M15 tăng").
- **Tín hiệu KHÔNG tĩnh:** `computeSignal` được gọi lại (a) mỗi lần `_applyLivePrice` (mỗi lần giá live về, tối đa 2 giây/lần/cặp), (b) mỗi 15 tick trong `tick()` (15 giây). `Signal.id` và `Signal.time` = thời điểm tính → **Entry/SL/TP/confidence đổi theo giá live**. Đây là điểm web đã sửa (chốt theo nến H1 đóng) mà Flutter chưa có.

### 1.5. `lib/chart.dart` (672 dòng) — Vẽ chart

- `Pt(x, y)` (dòng 4–8): điểm dữ liệu (x = chỉ số nến, có thể lẻ; y = giá).
- `DrawTool` (11): `none, trend, horizontal, fib, rect, text`. `Drawing(tool, pts, text)` (15–20).
- Hằng số (22–34): `_kExtraSlots = 20` (ô dự trữ phải cho đường SL/TP), `_kPriceAxisWidth = 56`, `_kTimeAxisHeight = 20`, `_kMaxVisibleCandles = 80`.
- `dataToPixel / pixelToData` (36–69): chuyển đổi tọa độ dữ liệu ↔ pixel (dùng chung cho vẽ + gesture).
- `_priceRange` (71–105): biên giá từ nến hiển thị + EMA20/50 + Entry/SL/TP (đệm 6%).
- `CandleChart extends StatefulWidget` (139–161) nhận `candles, signal, ema20, ema50, drawings, tool, onDrawingAdded, decimals`. `_CandleChartState` (163–353): cắt 80 nến cuối (`_chartData`), gesture `onPanStart/Update/End` (kéo vẽ trend/fib/rect), `onTapUp` (đường ngang/chữ — chữ mở `AlertDialog` nhập text), preview khi kéo dở. **Chưa có kéo/pan xem nến quá khứ** (chỉ hiện 80 nến cuối, không có offset cửa sổ, không có nút lùi/tới/về Live).
- `_ChartPainter extends CustomPainter` (355–672), `shouldRepaint` luôn `true`:
  - Nền `0xFF0B1220`; lưới 5 đường ngang + đường dọc mỗi 10 nến; nến xanh `0xFF22C55E` / đỏ `0xFFEF4444`, thân rộng 70% slot (clamp 1–24px).
  - **Chỉ vẽ EMA20 (cam `0xFFF59E0B`) và EMA50 (xanh `0xFF3B82F6`)** — không có EMA34/EMA200, không có MACD/RSI panel dưới chart, không có Bollinger (dù `computeIndicators` đã tính BB).
  - `_drawSignal` (478–514): mũi tên BUY/SELL tại nến cuối + đường SL đỏ đứt nét / TP xanh đứt nét kéo dài 20 nến + nhãn giá.
  - Vẽ tay: trend (đường vàng + 2 chấm), ngang (tím + nhãn giá), Fib (0/38.2/50/61.8/100%), hộp (cyan mờ), chữ (vàng đậm).
  - Trục giá phải (5 mức) + trục thời gian dưới (HH:MM, 6 nhãn).

### 1.6. `lib/volume_profile.dart` (446 dòng) — Volume Profile TonyD

- `VpBin(mid, low, high, volume)`, `ScoreItem(label, points, met)`, `VolumeSetup` (33 trường: model/action/poc/vah/val/bins/hvn/lvn/delta/deltaPct/buyVol/sellVol/entry/sl/tp1/tp2/rr/scoreItems/score/verdict/notes/h1Trend/tenkan/kijun/senkouA/senkouB/ema20H1/sweepBuy/sweepSell/chochBuy/chochSell/price).
- `analyzeVolumeProfile({m15, h1, h4})` (dòng 94–446) — hàm **thuần, không phụ thuộc symbol** (nhận series nến làm tham số), nên về mặt kỹ thuật có thể gọi cho 8 cặp:
  - **Ichimoku H1** (qua `_donchianMid`, dòng 86–92): Tenkan(9)/Kijun(26)/SenkouA=(T+K)/2/SenkouB(52); trend TANG nếu giá > mây + > EMA20 H1 + Tenkan > Kijun (ngược lại GIAM, còn lại SIDEWAY). ⚠️ Với chỉ 5 nến H1, Donchian 52 lấy toàn bộ 5 nến; `ema20H1` **luôn = 0** (EMA20 cần 20 nến) nên điều kiện `price > ema20H1` luôn đúng — trend H1 hiện tại bị lệch.
  - **Volume Profile M15, lookback 200 nến, 20 bin** (dòng 148–193): bin theo giá đóng (`binVol[idx] += c.vol` — toàn bộ volume nến đổ vào bin chứa giá đóng); POC = bin volume lớn nhất; vùng giá trị **70%** mở rộng từ POC ra 2 phía; **HVN** = bin > 1.5× volume trung bình, **LVN** = bin < 0.5×.
  - **Delta ƯỚC TÍNH từ nến** (dòng 200–219): nến tăng → BuyVol += vol×(0.5+0.5×|body|/range); nến giảm ngược lại. **Không phải tick Delta thật** (ghi rõ trong code + UI).
  - **Sweep/CHoCH/BOS trên 20 nến M15 cuối** (dòng 231–260): so với swing 10 nến trước đó; `sweepBuy` = quét đáy rồi đóng lại trên đáy cũ; `chochBuy` = đóng trên đỉnh gần nhất (không phải sweep).
  - **Mô hình A/B/C** (dòng 270–306): A = Buy tại POC/HVN sau sweep đáy (H1 không GIAM); B = Sell tại POC/HVN sau sweep đỉnh; C = phá LVN theo trend H1. Entry = giá hiện tại; SL = swing ± 0.3×ATR; TP1 = swing đối diện (ép RR ≥ 1:2), TP2 = HVN/VAH/VAL gần nhất (ép TP2 xa hơn TP1).
  - **Bảng chấm 10đ** (dòng 323–353): H1 cùng trend +2, tại POC/HVN (trong 0.5 ATR) +2, Sweep +2, CHoCH/BOS +2, Volume ủng hộ +1, RR ≥ 1:2 +1. Verdict: ≥8 XEM XÉT, 6–7 CHỜ THÊM, <6 KHÔNG GIAO DỊCH (nhưng nếu action WAIT thì verdict tối đa CHỜ THÊM).
- UI `VolumeProfileTab` (`main.dart:1473–1961`): **hardcode `'XAUUSD'`** — `analyzeVolumeProfile(m15: engine.candlesFor('XAUUSD','M15'), h1: ..., h4: ...)` (dòng 1590–1594). Hiển thị: thẻ kết quả (mô hình/xu hướng H1/điểm/kết luận), Ichimoku H1, profile 20 thanh ngang (POC cam), setup Entry/SL/TP1/TP2/RR, bảng chấm, quản trị vốn + **máy tính lot XAUUSD** (vốn VND mặc định 10.000.000, rủi ro 0,5%, SL 5 USD, tỷ giá 26.000; 1 lot = 100 oz; lot tối thiểu 0,01), ghi chú (gồm cảnh báo Delta ước tính + giá H4).

---

## 2. TÍNH NĂNG HIỆN CÓ (v1.1.0)

### 2.1. 6 tab (BottomNavigationBar, `main.dart:277–310`)

| # | Tab | Label | Nội dung chính |
|---|---|---|---|
| 1 | `DashboardTab` | Dashboard | Tín hiệu mạnh nhất + 8 cặp + theo dõi |
| 2 | `ChartTab` | Biểu đồ | Chart nến + vẽ tay + panel tín hiệu |
| 3 | `CalendarTab` | Lịch | Lịch kinh tế mock (7 sự kiện/ngày) |
| 4 | `NewsTab` | News | 8 tin vàng mock + tìm kiếm/lọc từ khóa |
| 5 | `SettingsTab` | Cài đặt | Offline, Exness mock, Rule Engine, Auto-Trade demo, lệnh + hiệu suất |
| 6 | `VolumeProfileTab` | VolumeB/S | TonyD Volume Profile **chỉ XAUUSD** + máy tính lot |

### 2.2. Giá live — nguồn, tần suất, cơ chế

- **Tần suất:** `Timer.periodic(2 giây)` → `_fetchLivePrices()` (`engine.dart:463–466`); cộng `Timer.periodic(1 giây)` → `tick()` random-walk cho cặp chưa LIVE.
- **Cơ chế:** `HttpClient` thuần Dart (`dart:io`), **không plugin, không WebSocket** — đây là HTTP polling, không phải WebSocket 1 giây như đặc tả gốc. Mỗi lần fetch tạo `HttpClient` mới rồi `client.close()` (không tái dùng kết nối keep-alive).
- **5 nguồn, gọi TUẦN TỰ (await nối tiếp), mỗi nguồn timeout 5s** (`engine.dart:537–720`):

| Cặp | URL | Ghi chú |
|---|---|---|
| XAUUSD | `https://api.gold-api.com/price/XAU` (lấy `price`) | Nguồn `gold-api.com` |
| BTCUSD | `https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT` | Nguồn `Binance` |
| EURUSD/GBPUSD/USDCAD/USDCHF/USDJPY | `https://open.er-api.com/v6/latest/USD` (neo ngày, `rates`, đảo 1/rate cho EUR/GBP) | Nguồn `open.er-api.com` |
| EURUSD/GBPUSD/USDCAD/USDCHF/USDJPY | `https://api.kraken.com/0/public/Ticker?pair=EURUSD,GBPUSD,USDJPY,USDCAD,USDCHF` (lấy `result[*].c[0]`, match key chứa base+quote) | Nguồn `Kraken`, **ghi đè** giá er-api nếu lấy được |
| USOIL | `https://query1.finance.yahoo.com/v8/finance/chart/CL=F` (lấy `chart.result[0].meta.regularMarketPrice`, header User-Agent `Mozilla/5.0 (Linux; Android 13) TradeSignalAI/1.1.0`) | Nguồn `Yahoo Finance (CL=F)` |

- **Không có OKX** trong code Flutter (đã grep toàn bộ `lib/` — không có chuỗi `okx`). Kết nối `www.okx.com:443` báo ở bản web không xuất phát từ code Flutter này (chưa xác minh nguồn web).
- **Fallback:** nguồn nào lỗi → giữ giá cũ, cặp đó hiện `DỮ LIỆU CŨ` (không bịa giá). Cờ `_fetchingLive` chặn chạy chồng; nhưng vì 5 nguồn gọi tuần tự, trường hợp xấu 1 chu kỳ có thể kéo dài tới ~25 giây (5×5s timeout) trong khi timer 2 giây cứ bắn — các lần bắn giữa chừng bị bỏ qua nhờ cờ.
- **Hiển thị:** Chip LIVE/CŨ ở AppBar, banner cam khi offline/mất live, mỗi cặp hiện nguồn + giờ cập nhật (HH:MM:SS) + trạng thái.

### 2.3. VolumeB/S hiện tại

- **Chỉ XAUUSD** (hardcode ở `main.dart:1590–1594`). Logic `analyzeVolumeProfile()` thì không gắn symbol, có thể tái dùng cho cặp khác — nhưng UI, máy tính lot (1 lot = 100 oz, vốn VND, tỷ giá) và mọi nhãn đều viết riêng cho vàng.
- Có: POC/VAH/VAL 70%, HVN/LVN, Delta ước tính + Buy/Sell Vol, Ichimoku H1 + EMA20 H1, Sweep/CHoCH/BOS, mô hình A/B/C, Entry/SL/TP1/TP2 + RR, bảng chấm 10đ, quản trị vốn + máy tính lot, ghi chú H4.
- Chưa có: quét nhiều cặp, điểm vào tối ưu, thang TP Inv/T1–T4, theo dõi tầng, cảnh báo Xung/TURN, thư viện mẫu hình nến.

### 2.4. Logo DGN / Intro

- Asset duy nhất: `assets/dgn_logo.jpg` — **828×551 px, 30.022 byte, JPEG RGB** (nền trắng, không trong suốt — kiểm tra bằng `file` + PIL).
- Intro (`_SplashGate`, `main.dart:76–151`): nền navy `0xFF0A1F44`, logo trong thẻ trắng bo tròn viền cam 3px, rộng 260px, chữ "TradeSignal AI" + "DGN • Tín hiệu Swing XAUUSD", tự chuyển sau **2,5 giây**, chạm bỏ qua. **Không có hiệu ứng lắp ghép, không có âm thanh, không có logo trong suốt.**
- Header: logo 30×30 `BoxFit.cover` trong `ClipRRect` bo 6px (`main.dart:190–198`).
- Icon app: `android/app/src/main/res/mipmap-*/ic_launcher.png` (mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192) + `mipmap-xxxhdpi/launch_image.png` (72.372 byte trong APK). Nội dung icon/launch image là ảnh logo DGN (theo MEMORY 16/11; chưa đối chiếu pixel-by-pixel với `dgn_logo.jpg` trong đợt audit này — ghi nhận theo hồ sơ build v1.1.0).

### 2.5. Auto-Trade demo + PANIC STOP

- Bật ở `SettingsTab` → `SwitchListTile` → dialog `_confirmAutoTrade()` bắt gõ đúng `TÔI ĐỒNG Ý` (`main.dart:1094–1169`), sau đó `engine.enableAutoTrade()` (ghi `demoStarted` lần đầu; `demoOnly = true` cố định, **LIVE bị khóa** — không có UI mở Live).
- `maybeAutoTrade()` (`engine.dart:1185–1215`): mở lệnh **mock** khi signal mới có confidence ≥ `minConfidence` (mặc định 70), cặp trong `allowedSymbols` (mặc định XAUUSD + BTCUSD), chưa đủ `maxOpen` (mặc định 3, slider 1–5), chưa có lệnh mở cùng cặp. Lot cố định mặc định 0,01; % rủi ro mặc định 1%; giờ giao dịch 08:00–22:00 (lưu chuỗi, **không có code kiểm tra giờ** — `tradeStart/tradeEnd` chỉ hiển thị/chỉnh, chưa dùng để chặn lệnh — đã kiểm tra: không có chỗ nào đọc 2 field này ngoài UI).
- **PANIC STOP:** nút đỏ `FloatingActionButton.extended` hiện trên mọi tab khi `autoTrade == true` (`main.dart:227–250`); `panicStop()` (`engine.dart:1232–1245`) đóng toàn bộ lệnh mở theo giá hiện tại (chốt PnL mock) và tắt auto-trade.
- **Exness:** form API Key + Secret, bấm Kết nối → chỉ kiểm tra non-empty, **xóa trắng controller ngay** (`main.dart:1247–1253`), không lưu key/secret vào field/file/log; chỉ giữ tên hiển thị `DEMO ••••<4 ký tự cuối>` trong phiên. Không gọi API thật.

### 2.6. Theme hiện tại

- **Dark theme toàn app** (`ThemeData.dark()`, `main.dart:57–70`): nền `0xFF0E1117`, card `0xFF1A1F2E`, AppBar navy `0xFF0A1F44`, cam `0xFFFF6A00`, xanh lá `0xFF00C853`; nền chart `0xFF0B1220`. **Không phải theme trắng của bản web.**

### 2.7. Những gì KHÔNG có trong v1.1.0 (đã xác minh bằng grep + đọc code)

- Không có `MethodChannel`, không có `shared_preferences`, không có plugin nào (`pubspec.yaml` chỉ có `flutter`); **không có bất kỳ khả năng lưu trữ bền vững nào** — tắt app là mất hết: cặp theo dõi, rule JSON, cấu hình auto-trade, lịch sử lệnh, tín hiệu.
- Không có backtest, không có chiến lược AI chuyển đổi, không có Price Action, không có mẫu hình nến, không có gauge, không có thang TP nhiều tầng, không có tin live, không có phân tích vĩ mô, không có Dynamic Island, không có hero CEO.
- Lịch kinh tế + tin tức là **mock hardcode** (7 sự kiện/ngày giống nhau mọi ngày; 8 tin vàng với giá 2.400–2.450 USD đã lỗi thời).
- Thống kê hiệu suất khi chưa có lệnh đóng là **số mock theo hash** (`engine.dart:1249–1303`).

---

## 3. GAP SO VỚI BẢN WEB (15 nhóm)

Đối chiếu với file web xuất ra `~/workspace/your_files/tradesignal-ai-phase-1/tradesignal-ai-phase-1.html` (đã grep từ khóa để xác nhận từng nhóm có mặt trong web: "Tín hiệu tĩnh" 2, "Price Action" 31, "Mẫu hình nến" 3, "Cộng hưởng" 2, "Chiến lược AI" 10, "Backtest" 24, "phương pháp" 24, "Dynamic Island" 5, "CEO" 9, "FXStreet" 8, "TỔNG TOÀN PHIÊN" 2, "EMA 34" 2, "RSI 9" 7, "Xung" 6, "TURN" 13). Mức độ: ✅ Có / 🟡 Một phần / ❌ Chưa có.

| # | Nhóm tính năng web | Flutter v1.1.0 | Mức độ | Ghi chú cụ thể |
|---|---|---|---|---|
| 1 | Tín hiệu tĩnh + giờ lên/dừng | Signal tính lại mỗi lần giá live về (≤2s) + mỗi 15s trong `tick()`; `Signal.time` = lúc tính, không có giờ lên/dừng, không có lý do hủy/cắt lỗ | ❌ Chưa có | Cần kiến trúc mới: chốt signal theo **nến H1 đã đóng**, lưu `issuedAt`, tính `stopTime` (TP/SL chạm hoặc nến H1 kế đóng; hủy sớm ghi giá cắt + pip/%). `computeSignal()` hiện tại (`engine.dart:884`) phải tách thành "tính" vs "chốt". |
| 2 | VolumeB/S quét 8 cặp | Logic `analyzeVolumeProfile()` không gắn symbol, nhưng UI hardcode XAUUSD (`main.dart:1590`); máy tính lot chỉ cho vàng | 🟡 Một phần (~30%) | Cần: vòng lặp 8 cặp + UI danh sách kết quả + máy tính lot theo từng cặp (contract size đã có `_contractSize()` ở `engine.dart:1218`). Rào cản dữ liệu: H1 chỉ 5 nến, H4 chỉ 2 nến (xem §8). |
| 3 | Trend pill 5 khung (M5/M15/H1/H4/D1) + điểm Trend | Không có trend đa khung; chỉ có trend M15 ẩn trong `computeSignal` (EMA20/50) và trend H1 trong VolumeB/S | ❌ Chưa có | Có thể tái dùng `ema()` + `candlesFor(tf)`; nhưng H1/H4/D1 thiếu nến trầm trọng (D1 = 1 nến từ 300 M1) nên trend H4/D1 hiện không tính được. |
| 4 | Price Action 2 mức (Cơ bản/Nâng cao) + công thức 50/25/25 + điểm vào tối ưu | Không có PA trong tín hiệu; confidence hiện 55–92 theo độ tách EMA/ATR (`engine.dart:965`). Sweep/CHoCH chỉ tồn tại trong `volume_profile.dart`, không feeding vào signal | ❌ Chưa có | Cần module PA mới (Pin Bar, Engulfing, Inside Bar, Doji, phá đỉnh/đáy; Sweep, BOS, CHoCH, FVG, Order Block, Retest, xác nhận M5) + đổi công thức confidence + UI "Điểm vào chuẩn & đẹp". |
| 5 | Thư viện mẫu hình nến ~15 mẫu + thống kê số lần xuất hiện | Không có phát hiện mẫu hình nào | ❌ Chưa có | Cần detector mới trên nến đã đóng + đếm từ series nến đang tải (tối đa 200 nến — mẫu thống kê sẽ ít). |
| 6 | Gauge cộng hưởng đa khung | Không có | ❌ Chưa có | Phụ thuộc (3): cần trend 5 khung trước. |
| 7 | Thang TP Inv/T1–T4 + theo dõi mô phỏng từng tầng + "Chênh mở phòng" | Chỉ có TP đơn trong signal + TP1/TP2 trong VolumeB/S (`volume_profile.dart:270–306`) | 🟡 Một phần (~20%) | Cần: tính Inv/T1–T4 từ ATR/Fib, state theo dõi từng tầng (đã chạm/chưa, pullback), lưu trạng thái. |
| 8 | Cảnh báo Xung đa khung + TURN đồng bộ | Không có | ❌ Chưa có | Cần định nghĩa lại "Xung" (xung lực nến/volatility spike) và "TURN" (đồng bộ đảo chiều đa khung) — web có logic, Flutter chưa có gì tương đương. |
| 9 | Chiến lược AI 3 lựa chọn (Swing / VolumeB/S TonyD / AI hợp nhất) + lưu lựa chọn | Chỉ có 1 chiến lược Swing cố định + Rule Engine JSON riêng lẻ (`evaluateRule`, `engine.dart:1002`); không có khái niệm strategy, không lưu | ❌ Chưa có | Cần enum strategy + switch tính lại signal + persistence (xem §5). Rule Engine hiện tại có thể giữ làm lớp bổ sung. |
| 10 | Backtest + khung nhập phương pháp giao dịch | Không có backtest; lịch sử chỉ là lệnh mock đã đóng + winrate mock theo hash (`engine.dart:1249`) | ❌ Chưa có | Cần engine backtest mới chạy trên series nến thật + UI nhập/lưu phương pháp. Rào cản lớn: dữ liệu quá khứ (xem §8). |
| 11 | Theme trắng + hero CEO + intro logo + Dynamic Island | Theme dark; intro tĩnh 2,5s; không có ảnh CEO; không có island; asset `dgn-mark-clear.png` / `ceo-founder.jpg` **không có** trong `assets/` | ❌ Chưa có | Cần đổi toàn bộ `ThemeData` + thêm asset + widget island (kéo ngang 8 cặp) + intro mới. Chime xem §6. |
| 12 | Phase Phân tích 3 khối (vĩ mô / tin tài chính 8 cặp / biến động cá mập) | Không có tab Phân tích; "phân tích 3 lớp" cũ (TA/LLM/Rule) chỉ còn là `reasons` trong signal + Rule Engine; không có nhận định vĩ mô | ❌ Chưa có | Cần tab mới + nội dung nhận định (web ghi rõ "không có dữ liệu vị thế thật" — Flutter cũng phải ghi rõ tương tự, không bịa). |
| 13 | Tin Live FXStreet quét 1s + lịch sử tổng toàn phiên | News mock 8 tin hardcode (`engine.dart:1360`); lịch mock 7 sự kiện/ngày; lịch sử lệnh có list nhưng **không có thẻ tổng toàn phiên** (winrate/PF/RR/tổng R) | ❌ Chưa có | Cần RSS client + parse XML (xem §8 rủi ro) + aggregate lịch sử từ tín hiệu đã chốt (phụ thuộc (1)). |
| 14 | Thông số chỉ báo tùy chỉnh có lưu (EMA/MACD/RSI/ATR/SL-TP/Bollinger) | Mọi tham số hardcode trong `computeIndicators()` (`engine.dart:340`); không có UI chỉnh; không có lưu trữ | ❌ Chưa có | Cần: model `IndicatorParams` + UI cài đặt + persistence (§5) + tính lại chart/signal/backtest khi đổi. Đây là nhóm dễ port nhất về mặt code Dart (chỉ cần tham số hóa hàm có sẵn). |
| 15 | Giữ nguyên v1.1.0 | Toàn bộ §2 (chart + vẽ tay, giá live 5 nguồn, VolumeB/S XAUUSD, auto-trade demo + PANIC STOP, Rule Engine, offline mode, theo dõi cặp) | ✅ Có | Yêu cầu port: không làm mất tính năng cũ; đặc biệt giữ nguyên nguồn giá (không OKX) và cơ chế xóa key Exness. |

**Tóm tắt gap:** 1/15 có đủ (15), 2/15 một phần (2, 7), 12/15 chưa có. Phần lớn công việc là **code mới hoàn toàn** (PA, mẫu hình, gauge, backtest, RSS, strategy, island, theme), không phải sửa code cũ — trừ (14) tham số hóa chỉ báo và (2) mở rộng VolumeB/S vốn đã có hàm lõi dùng được.

---

## 4. PIPELINE BUILD TAY

### 4.1. File và vị trí

- Script: `manual/build_apk.sh` — **118 dòng**, `set -e`, tự export `JAVA_HOME=~/jdk17`, `ANDROID_HOME=~/Android/sdk`, `PATH=~/jdk17/bin:~/flutter/bin:$PATH`.
- Thư mục làm việc: `WORK=$PROJ/build/manual`; `STAGE=$WORK/stage`; `INTER=$WORK/intermediate`; build-tools `34.0.0`; `ANDROID_JAR=platforms/android-34/android.jar`.
- APK cuối: `$WORK/TradeSignalAI-v1.1.0.apk` (51 MB, 3 ABI, ký debug keystore tự tạo `build/manual/debug.keystore`).
- Các file trung gian trong `build/manual/`: `assemble-{armeabi-v7a,arm64-v8a,x86_64}/` (mỗi cái `app.so` + `flutter_assets/`), `intermediate/` (app.so 3 ABI + flutter_assets gộp), `stage/` (manifest đã sửa + res + gen + assets), `compiled_res.zip`, `unsigned.apk`, `classes/`, `app-classes.jar`, `dex/` (classes.dex), `aligned.apk`, `sources.txt`, `debug.keystore`.
- `manual/r8.jar` (18.273.598 byte, R8 **8.13.25**) + `manual/libs/` (**27 file .jar**: androidx activity/annotation/collection/core/fragment/lifecycle/savedstate/startup/tracing/versionedparcelable/window, `kotlin-stdlib-2.0.20.jar`, kotlinx-coroutines, `annotations-24.0.1.jar`…). Lưu ý: script KHÔNG dùng `d8` kèm build-tools 34 (d8 crash NPE với class androidx mới — ghi trong comment của script SheepLand; TradeSignal dùng R8 ngay từ đầu).

### 4.2. Từng bước trong `manual/build_apk.sh`

| Bước | Lệnh / việc | Chi tiết |
|---|---|---|
| 0 | `flutter pub get --offline` | Không tải pub (không có dependency ngoài). |
| 0 | `flutter assemble` × 3 ABI | Lần lượt `android-arm` → `armeabi-v7a`, `android-arm64` → `arm64-v8a`, `android-x64` → `x86_64`; mỗi lần `-dTargetPlatform=$ABI -dTargetFile=lib/main.dart -dBuildMode=release -dTreeShakeIcons=true -dDartObfuscation=false -dTrackWidgetCreation=false android_aot_bundle_release_$ABI`; output `--output=$WORK/assemble-$DIR`. Mỗi lần sinh `app.so` + `flutter_assets/`. Sau đó copy 3 `app.so` vào `intermediate/<abi>/`, copy `flutter_assets` của arm64 làm bản gộp. |
| 1 | Manifest + assets | `sed` trên `android/app/src/main/AndroidManifest.xml`: thêm `package="com.tradesignal.ai" android:versionCode="2" android:versionName="1.1.0"` vào thẻ `<manifest>`, thay `android:name="${applicationName}"` → `io.flutter.app.FlutterApplication` + `android:extractNativeLibs="true"`. Copy `android/app/src/main/res` → stage, `intermediate/flutter_assets` → `stage/assets/flutter_assets`. |
| 2 | `aapt2 compile` + `aapt2 link` | Compile toàn bộ `res/` → `compiled_res.zip`; link → `unsigned.apk` với `--min-sdk-version 21 --target-sdk-version 34 --version-code 2 --version-name 1.1.0 -A stage/assets -R compiled_res.zip --auto-add-overlay`; sinh `R.java` vào `stage/gen`. |
| 3 | `javac` | `find manual/src/com manual/src/io stage/gen -name "*.java"` → `sources.txt`; `javac -nowarn -encoding UTF-8 -source 8 -target 8 -cp flutter.jar:android.jar:libs/* -d classes`. `FLUTTER_JAR` lấy từ `~/flutter/bin/cache/artifacts/engine/android-arm64-release/flutter.jar` (chỉ dùng bản arm64 cho classpath — đủ vì API Java giống nhau mọi ABI). ⚠️ `find` **không** bao gồm `manual/src/androidx/` (stub Keep/NonNull/Nullable) — các stub này không được biên dịch; annotation lấy từ `annotation.jar` trong `manual/libs/` (comment trong script ghi rõ: biên dịch cả 2 sẽ khiến R8 báo "defined multiple times"). |
| 4 | R8/D8 | Đóng `classes/` thành `app-classes.jar`; `java -cp manual/r8.jar com.android.tools.r8.D8 --release --min-api 21 --output dex --lib android.jar app-classes.jar flutter.jar <tất cả libs/*.jar>` → `dex/classes.dex` (6.210.504 byte trong APK v1.1.0). |
| 5 | Ghép dex + native lib (Python inline) | Mở `unsigned.apk` (ZIP_STORED), thêm mọi `*.dex` ở gốc APK; với mỗi ABI thêm `lib/<abi>/libapp.so` (từ `intermediate/`) và `lib/<abi>/libflutter.so` (giải nén từ `flutter.jar` tương ứng của từng engine `android-arm-release / android-arm64-release / android-x64-release`). |
| 6 | `zipalign` + ký | `zipalign -f 4 unsigned.apk aligned.apk`; nếu chưa có `debug.keystore` thì `keytool -genkeypair` (RSA 2048, validity 10000 ngày, alias `androiddebugkey`, pass `android`, CN=Android Debug); `apksigner sign --ks debug.keystore --out TradeSignalAI-v1.1.0.apk aligned.apk`; cuối cùng `apksigner verify --verbose` + `aapt2 dump badging | head -12` + `ls -lh` + echo `MANUAL_BUILD_OK`. |

### 4.3. Version lấy từ đâu — và cách nâng lên 1.2.0+3

- `pubspec.yaml`: `version: 1.1.0+2`. Script **không đọc pubspec** để lấy version (ngoại trừ `flutter assemble`/`pub get` dùng version cho metadata Dart — không ảnh hưởng APK).
- Version APK được **hardcode ở 3 chỗ trong `manual/build_apk.sh`**:
  1. Dòng `sed` manifest: `android:versionCode="2" android:versionName="1.1.0"`.
  2. Dòng `aapt2 link`: `--version-code 2 --version-name 1.1.0`.
  3. Tên file output: `TradeSignalAI-v1.1.0.apk` (cả lệnh `sign --out` và 2 lệnh kiểm tra sau đó).
- **Để nâng lên 1.2.0+3, phải sửa 4 chỗ:** `pubspec.yaml` (`version: 1.2.0+3`) **+ cả 3 chỗ hardcode trong script** (versionCode `2`→`3`, versionName `1.1.0`→`1.2.0` ở 2 chỗ, tên file output → `TradeSignalAI-v1.2.0.apk`). Quên 1 chỗ sẽ cho ra APK mà `aapt2 dump badging` báo version cũ (hoặc tên file lệch version). Khuyến nghị: khi port, đưa version thành biến đầu script (`VER=1.2.0`, `CODE=3`) và dùng biến ở cả 3 chỗ — sửa 1 dòng duy nhất cho lần sau.
- ⚠️ **Lệch package name giữa 2 đường build:** build tay dùng package **`com.tradesignal.ai`** (sed trong script; `manual/src/com/tradesignal/ai/MainActivity.java`); còn Gradle dùng `applicationId = "com.tradesignal.trade_signal_ai"` + namespace `com.tradesignal.trade_signal_ai` (`android/app/build.gradle:29`, `MainActivity.kt` package `com.tradesignal.trade_signal_ai`). Hai đường build cho ra **2 package khác nhau** — không được chạy `flutter build apk` (Gradle) để thay thế build tay, và khi cài đè APK 1.2.0 lên máy đã có 1.1.0 build tay thì package phải giữ `com.tradesignal.ai` (nếu không Android coi là app khác).
- ⚠️ **Lệch `GeneratedPluginRegistrant`:** bản Gradle (`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`) là file do Flutter tool sinh (rỗng, vì không có plugin); bản tay (`manual/src/io/flutter/plugins/GeneratedPluginRegistrant.java`) là file viết tay, hiện cũng rỗng ("Không có plugin nào"). Khi thêm MethodChannel (§5), **chỉ sửa bản trong `manual/src/`**; bản trong `android/` sẽ bị Flutter tool ghi đè nếu ai chạy `flutter pub get`/`flutter build` — cần ghi chú này vào script hoặc README để không ai "đồng bộ" nhầm.

### 4.4. Thời gian build ước tính

- **Chưa đo trực tiếp trong đợt audit này** (không chạy lại build — task chỉ audit). Ước tính từ dấu vết lần build 16/11: các thư mục `assemble-*` có timestamp 06:09/06:10/06:11 (mỗi ABI ~1 phút, gồm `flutter assemble`), toàn bộ script từ `assemble` tới `apksigner verify` xong trong khoảng **3–6 phút** trên máy này (APK 51 MB, R8 dex ~6 MB). Con số chính xác cần đo ở lần build 1.2.0 đầu tiên.
- Lần build sau nhanh hơn lần đầu nhờ cache: `flutter assemble` cache, `debug.keystore` đã có sẵn (không tạo lại).

### 4.5. Lệnh kiểm tra APK (đã xác minh tool có sẵn)

| Lệnh | Vị trí | Kết quả kiểm tra 17/11 |
|---|---|---|
| `~/Android/sdk/build-tools/34.0.0/apksigner verify --verbose <apk>` | build-tools 34.0.0 | ✅ v1/v2/v3 true, 1 signer (cần `~/jdk17/bin` trong PATH, xem §4 đầu) |
| `~/Android/sdk/build-tools/34.0.0/aapt2 dump badging <apk>` | build-tools 34.0.0 | ✅ package `com.tradesignal.ai` v2/1.1.0, sdk 21, target 34 |
| `unzip -l <apk>` | hệ thống | ✅ liệt kê được; phát hiện **thừa 1 bản copy `flutter_assets`** (xem §7.3) |
| `~/flutter/bin/flutter analyze` | `~/flutter/bin` | ✅ No issues found |
| `which apksigner/aapt2/zipalign` (PATH mặc định) | — | ❌ Không có — luôn dùng đường dẫn đầy đủ `~/Android/sdk/build-tools/34.0.0/` hoặc export PATH trong script (script đã export) |

---

## 5. METHODCHANNEL + LƯU TRỮ KHÔNG PLUGIN

### 5.1. Mẫu SheepLand đã xác minh (đối chiếu trực tiếp)

- **Plugin Java:** `~/workspace/SheepMathApp/manual/src/com/sheepland/math/sheep_math/ProgressPlugin.java` (đã đọc toàn bộ). Class `ProgressPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler`:
  - `onAttachedToEngine`: lấy `binding.getApplicationContext()`, tạo `MethodChannel(binding.getBinaryMessenger(), "sheepland/progress")`, `setMethodCallHandler(this)`.
  - `onDetachedFromEngine`: gỡ handler, null channel.
  - `progressFile()` = `new File(context.getFilesDir(), "progress.json")` — tức `/data/data/com.sheepland.math.sheep_math/files/progress.json` (bộ nhớ riêng của app, private, **giữ lại khi cập nhật app, mất khi gỡ app/xóa dữ liệu**, không cần quyền gì).
  - `onMethodCall`: `"load"` → đọc file, không có file thì `result.success(null)`; `"save"` → ghi `call.argument("json")` (UTF-8); lỗi → `result.error("ERR", ...)`.
- **Đăng ký — KHÔNG phải trong MainActivity:** `SheepMathApp/manual/src/com/sheepland/math/sheep_math/MainActivity.java` là class rỗng `extends FlutterActivity` (đã đọc). Đăng ký nằm trong **`manual/src/io/flutter/plugins/GeneratedPluginRegistrant.java`** của SheepLand:
  ```java
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
    try {
      flutterEngine.getPlugins().add(new com.sheepland.math.sheep_math.ProgressPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin ProgressPlugin", e);
    }
  }
  ```
  (Flutter engine tự gọi `GeneratedPluginRegistrant.registerWith` khi khởi động — đây là cơ chế chuẩn của embedding v2.)
- **Phía Dart** (`SheepMathApp/lib/main.dart:277–285` trở đi): `static const _ch = MethodChannel('sheepland/progress');` rồi `await _ch.invokeMethod<String>('load')` / `invokeMethod('save', {'json': ...})`, `jsonDecode`/`jsonEncode` ở Dart.
- **Pipeline:** script build SheepLand (`manual/build_apk.sh`, 96 dòng) biên dịch plugin tự động vì lệnh `find "$PROJ/manual/src/com" "$PROJ/manual/src/io" "$STAGE/gen" -name "*.java"` quét **toàn bộ** `manual/src/com` — thêm file `.java` mới vào đó là được biên dịch, không cần sửa script. TradeSignal dùng đúng câu `find` này (`manual/build_apk.sh` dòng ~80). Classpath đã có sẵn `flutter.jar` (cung cấp `FlutterPlugin`, `MethodChannel`, `MethodCall`) + `annotation.jar` (cung cấp `@Keep/@NonNull`).

### 5.2. Cách thêm MethodChannel vào TradeSignalApp — từng bước chính xác

1. **Tạo file Java mới:** `manual/src/com/tradesignal/ai/StoragePlugin.java` (cùng package `com.tradesignal.ai` với `MainActivity.java` hiện tại). Nội dung sao theo mẫu ProgressPlugin, đổi tên kênh và tên file, ví dụ:
   - Kênh: `"tradesignal/storage"`.
   - File: `settings.json` trong `context.getFilesDir()` (tức `/data/data/com.tradesignal.ai/files/settings.json`).
   - 2 method `load`/`save` y hệt mẫu (load trả `null` nếu chưa có file; save nhận `{'json': ...}`).
   - Nâng cấp nhỏ so với mẫu (khuyến nghị, không bắt buộc): thêm tham số `file` để dùng chung 1 plugin cho nhiều file (VD `settings.json`, `backtest_methods.json`), hoặc giữ 1 file JSON duy nhất chứa đủ 3 nhóm — xem §5.3.
2. **Đăng ký trong `manual/src/io/flutter/plugins/GeneratedPluginRegistrant.java`** (file hiện tại 12 dòng, `registerWith` rỗng): thêm dòng `flutterEngine.getPlugins().add(new com.tradesignal.ai.StoragePlugin());` trong `try/catch` giống mẫu SheepLand. **Không sửa `MainActivity.java`** (giữ nguyên class rỗng `extends FlutterActivity`) và **không sửa** bản `android/app/src/main/java/.../GeneratedPluginRegistrant.java` (file đó do Flutter tool quản lý, xem §4.3).
3. **Phía Dart — tạo file mới `lib/storage.dart`** (không nhét vào `engine.dart` vốn đã 1.419 dòng):
   ```dart
   import 'dart:convert';
   import 'package:flutter/services.dart';
   class AppStorage {
     static const _ch = MethodChannel('tradesignal/storage');
     static Future<Map<String, dynamic>?> loadJson() async {
       final s = await _ch.invokeMethod<String>('load');
       if (s == null || s.isEmpty) return null;
       return jsonDecode(s) as Map<String, dynamic>;
     }
     static Future<void> saveJson(Map<String, dynamic> m) =>
         _ch.invokeMethod('save', {'json': jsonEncode(m)});
   }
   ```
   `MockEngine` (hoặc một `SettingsStore` mới) gọi `loadJson()` lúc khởi động (trước `runApp` xong hoặc trong constructor rồi `notifyListeners()` khi load xong) và `saveJson()` mỗi khi người dùng bấm Áp dụng/lưu.
4. **Không cần sửa:** `pubspec.yaml` (không thêm dependency), `manual/build_apk.sh` (câu `find` đã quét `manual/src/com`), `AndroidManifest.xml` (không cần quyền mới — `getFilesDir()` là bộ nhớ nội bộ), `manual/libs/` (không cần jar mới).
5. **Kiểm thử bắt buộc:** sau khi build, mở app → đổi 1 thông số → bấm Áp dụng → **tắt hẳn app (swipe khỏi recent) → mở lại** → thông số còn. Nếu mất: kiểm tra (a) plugin có được đăng ký không (logcat `Error registering plugin`), (b) Dart có `MissingPluginException` không (kênh sai tên), (c) file `settings.json` có được tạo trong `files/` không (`adb run-as com.tradesignal.ai ls files/`).

### 5.3. Đánh giá khả thi cho 3 nhu cầu lưu trữ

| Nhu cầu | Khả thi? | Cách làm |
|---|---|---|
| (a) Thông số chỉ báo (EMA nhanh/chậm/34/200, MACD 34/58/12, RSI 9/14, ATR, hệ số SL/TP, Bollinger) | ✅ Khả thi, dễ nhất | 1 object JSON (VD `{"emaFast":20,"emaSlow":50,"ema34":34,"ema200":200,"macdFast":34,"macdSlow":58,"macdSignal":12,"rsiChart":9,"rsiSignal":14,"atr":14,"slMult":1.5,"tpMult":3.0,"bbPeriod":20,"bbMult":2.0}`) trong `settings.json`; `computeIndicators()` đổi sang nhận tham số thay vì hardcode; load trước khi tính signal đầu tiên. Dung lượng vài trăm byte. |
| (b) Chiến lược AI đã chọn (Swing / VolumeB/S / AI hợp nhất) | ✅ Khả thi, rất dễ | 1 chuỗi trong cùng `settings.json` (VD `{"strategy":"swing"}`); load lúc khởi động, tính lại signal khi đổi. |
| (c) Phương pháp backtest (tên + mô tả/quy tắc, nhiều phương pháp) | ✅ Khả thi | 1 mảng JSON trong cùng file hoặc file riêng `backtest_methods.json` (khuyến nghị file riêng nếu danh sách dài, để `settings.json` không phình). Lưu ý: chỉ lưu **tên + mô tả + tham số chọn sẵn** (VD strategy + khung + khoảng); **không** tự chuyển văn bản tự do thành quy tắc chạy được — web cũng ghi rõ giới hạn này, Flutter giữ nguyên giới hạn. |
| ⚠️ Không dùng cách này cho | ❌ Cấm | **API key/secret Exness**: chính sách hiện tại là chỉ giữ trong bộ nhớ phiên, không ghi file/log. MethodChannel file JSON là plaintext trong `files/` — ai có quyền đọc device (root/backup) đều đọc được. Giữ nguyên `connectExness()` như hiện tại. |

**Kết luận §5:** Cách làm của SheepLand **áp dụng được nguyên vẹn cho TradeSignalApp**, không cần plugin Flutter, không cần Gradle/Kotlin, không cần sửa script build. Rủi ro chính là nhầm file `GeneratedPluginRegistrant` (bản `manual/` vs bản `android/`) và quên kiểm thử "tắt hẳn app rồi mở lại".

---

## 6. CHIME INTRO BẰNG METHODCHANNEL

### 6.1. Kết luận trước: **KHẢ THI** — với `AudioTrack` (khuyến nghị) hoặc `ToneGenerator` (chỉ tiếng đơn)

Không cần thêm plugin Flutter, không cần file âm thanh asset nếu dùng 1 trong 2 API Android có sẵn trong `android.jar` (API 34). Không cần quyền nào (xem §6.2).

### 6.2. `ToneGenerator` (`android.media.ToneGenerator`)

- **Quyền:** **không cần quyền nào**. `ToneGenerator` phát qua `AudioManager.STREAM_MUSIC` (hoặc `STREAM_ALARM`/`STREAM_NOTIFICATION`) — không thuộc nhóm quyền nguy hiểm, không cần khai báo trong `AndroidManifest.xml`.
- **Luồng:** `new ToneGenerator(streamType, volume)` + `startTone(toneType, durationMs)` có thể gọi từ **bất kỳ luồng nào**; `MethodChannel` của Flutter gọi `onMethodCall` trên **platform thread = main thread** nên gọi trực tiếp là an toàn. `startTone` không block (phát bất đồng bộ trong `durationMs` rồi tự dừng); phải giữ tham chiếu instance và gọi `release()` khi xong, nếu không sẽ rò rỉ (tối đa ~ số lượng ToneGenerator đồng thời có hạn).
- **Hạn chế quyết định:** `ToneGenerator` chỉ phát **các tone cố định** trong bảng `TONE_*` (DTMF 0–9, `TONE_CDMA_*`, `TONE_SUP_*`…) — **không chỉnh được tần số**. Web dùng Web Audio API phát **8 nốt sine ở tần số tự chọn** (hợp âm chime). ToneGenerator **không tái tạo được** giai điệu đó; tối đa chỉ phát được 1–2 tiếng "bíp" đơn (VD `TONE_CDMA_PIP` hoặc DTMF) — nghe như tiếng bấm phím, không "trong trẻo" như yêu cầu.
- **Kết luận riêng ToneGenerator:** khả thi về mặt kỹ thuật nhưng **không đạt yêu cầu âm thanh** (chỉ 1 tiếng bíp đơn điệu).

### 6.3. `AudioTrack` — phương án khuyến nghị (không cần asset)

- **Quyền:** **không cần quyền nào** (phát âm thanh qua loa là hoạt động bình thường, không cần `MODIFY_AUDIO_SETTINGS` nếu chỉ dùng `STREAM_MUSIC` với volume mặc định).
- **Cách làm:** sinh sóng sine bằng code Java (không cần file asset): với mỗi nốt (tần số `f`, thời lượng `t`), tạo mảng PCM 16-bit `sample = sin(2π·f·n / sampleRate) × envelope` (envelope tăng/giảm dần để tiếng "tinh" không bị cụt), ghi vào `AudioTrack` (`MODE_STREAM`, `STREAM_MUSIC`, sample rate 44100, mono) rồi `play()`. Chạy trên luồng nền (`new Thread(...)`) để không block main thread khi phát chuỗi 8 nốt (~2 giây).
- **Ưu điểm:** tái tạo đúng chime 8 nốt sine của web (chỉ cần copy tần số/thời lượng từ code web), không cần asset, không tăng kích thước APK, không cần quyền.
- **Lưu ý:** (1) Nếu máy đang ở chế độ im lặng / volume media = 0 thì không nghe thấy — giống mọi app khác, không phải lỗi; nên có nút bật/tắt âm như web đã có. (2) Trình duyệt chặn tự phát không áp dụng cho app native — chime phát được ngay khi intro hiện, không cần chờ chạm. (3) `AudioTrack` cần `release()` sau khi phát xong. (4) Phải kiểm thử trên máy thật (không nghe được qua emulator headless/CI).

### 6.4. Phương án `MediaPlayer` + asset (không khuyến nghị)

- `MediaPlayer.create(context, R.raw.chime)` cần file âm thanh đặt trong `res/raw/` — pipeline tay **có** copy `res/` nên làm được, nhưng cần thêm file asset âm thanh (mp3/wav) vào repo, tăng kích thước APK, và phải tạo/ghi âm file chime trước. Chỉ dùng nếu sau này muốn tiếng chime thu sẵn thay vì sine tổng hợp.

### 6.5. Phác thảo code tối thiểu (phương án AudioTrack)

**Java — thêm vào cùng `StoragePlugin.java` hoặc file riêng `manual/src/com/tradesignal/ai/ChimePlugin.java` (khuyến nghị file riêng, kênh riêng `"tradesignal/chime"`):**

```java
package com.tradesignal.ai;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class ChimePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private MethodChannel channel;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    channel = new MethodChannel(binding.getBinaryMessenger(), "tradesignal/chime");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (channel != null) { channel.setMethodCallHandler(null); channel = null; }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    if (call.method.equals("playChime")) {
      // Nốt: tần số (Hz) + thời lượng (ms). Lấy đúng dãy nốt từ code web.
      new Thread(() -> playNotes(new double[]{880, 1046.5, 1318.5, 1568}, 220)).start();
      result.success(null);
    } else {
      result.notImplemented();
    }
  }

  private void playNotes(double[] freqs, int msPerNote) {
    final int sr = 44100;
    AudioTrack track = new AudioTrack.Builder()
        .setAudioAttributes(new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        .setAudioFormat(new AudioFormat.Builder()
            .setSampleRate(sr).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
        .setTransferMode(AudioTrack.MODE_STREAM).build();
    track.play();
    for (double f : freqs) {
      int n = sr * msPerNote / 1000;
      short[] buf = new short[n];
      for (int i = 0; i < n; i++) {
        double env = Math.min(1.0, i / (sr * 0.01)) * (1.0 - (double) i / n); // attack 10ms + decay
        buf[i] = (short) (Math.sin(2 * Math.PI * f * i / sr) * env * Short.MAX_VALUE * 0.5);
      }
      track.write(buf, 0, n);
    }
    track.stop();
    track.release();
  }
}
```

Đăng ký thêm 1 dòng trong `manual/src/io/flutter/plugins/GeneratedPluginRegistrant.java`: `flutterEngine.getPlugins().add(new com.tradesignal.ai.ChimePlugin());`

**Dart — trong `_SplashGateState.initState()` (`main.dart:80–86`), sau khi intro hiện:**

```dart
import 'package:flutter/services.dart';
// ...
static const _chime = MethodChannel('tradesignal/chime');
Future<void> _playChime() async {
  try { await _chime.invokeMethod('playChime'); } catch (_) { /* không có tiếng thì app vẫn chạy */ }
}
```

Lưu ý: `AudioTrack.Builder` + `AudioAttributes` yêu cầu API ≥ 23 (minSdk của app là 21) — cần 1 trong 2 cách: (a) dùng constructor cũ `new AudioTrack(AudioManager.STREAM_MUSIC, sr, CHANNEL_OUT_MONO, ENCODING_PCM_16BIT, bufferSize, MODE_STREAM)` (API 3+, chạy được trên minSdk 21, bị deprecate nhưng vẫn chạy); hoặc (b) giữ `Builder` và guard `if (Build.VERSION.SDK_INT >= 23)`. Khuyến nghị (a) cho đơn giản, vì app hỗ trợ từ Android 5.0.

---

## 7. ASSETS

### 7.1. Assets hiện có

| Asset | Kích thước | Dùng ở đâu |
|---|---|---|
| `assets/dgn_logo.jpg` | **828×551 px, 30.022 byte, JPEG RGB** (không trong suốt) | Intro `_SplashGate` rộng 260px (`main.dart:116`); AppBar 30×30 (`main.dart:190`) |
| `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | 48/72/96/144/192 px | Icon app (qua `aapt2 link` từ `res/`) |
| `android/app/src/main/res/mipmap-xxxhdpi/launch_image.png` | (72.372 byte trong APK) | Ảnh chờ mở app (launch screen) |
| `android/app/src/main/res/drawable[-v21]/launch_background.xml`, `values/styles.xml` | — | LaunchTheme/NormalTheme |

`pubspec.yaml` khai báo đúng 1 asset: `assets/dgn_logo.jpg` (`flutter: assets:`). Không có `dgn-mark-clear.png`, không có `ceo-founder.jpg`, không có asset âm thanh.

### 7.2. Cách thêm asset mới (logo trong suốt PNG, ảnh CEO JPG)

1. Copy file vào `assets/`, VD `assets/dgn-mark-clear.png`, `assets/ceo-founder.jpg`.
2. Thêm 2 dòng vào `pubspec.yaml` dưới `flutter: assets:`:
   ```yaml
   flutter:
     uses-material-design: true
     assets:
       - assets/dgn_logo.jpg
       - assets/dgn-mark-clear.png
       - assets/ceo-founder.jpg
   ```
3. Dùng trong Dart: `Image.asset('assets/dgn-mark-clear.png')` (header/island/intro — PNG trong suốt nên không lộ ô đen trên nền trắng), `Image.asset('assets/ceo-founder.jpg')` (hero Trang chủ).
4. **Không cần bước riêng trong pipeline tay:** `flutter assemble` tự sinh lại `flutter_assets/` (gồm `AssetManifest.json/bin` + file asset) mỗi lần build; script đã copy toàn bộ `intermediate/flutter_assets` → `stage/assets/flutter_assets` rồi đưa vào APK bằng `aapt2 link -A`. Chỉ cần chạy lại `manual/build_apk.sh` là asset mới có trong APK.
5. **Icon/launch image:** nếu đổi logo icon thì phải thay 5 file `mipmap-*/ic_launcher.png` + `launch_image.png` (tự sinh từ ảnh gốc bằng Android Studio/ImageMagick, đúng kích thước 48/72/96/144/192); script copy toàn bộ `res/` nên không cần sửa script. Lưu ý `launch_image.png` hiện chỉ có ở `mipmap-xxxhdpi` (không có ở các mật độ khác — giữ nguyên cấu trúc này khi thay).
6. **Lưu ý chất lượng ảnh:** `dgn_logo.jpg` hiện 828×551 (tỉ lệ ~3:2, không vuông) — khi dùng làm icon/header vuông 30×30 với `BoxFit.cover` sẽ bị cắt 2 bên; logo trong suốt mới nên xuất bản vuông (VD 512×512, nền trong suốt) để dùng chung cho header, island (mini) và intro mà không méo/cắt.

### 7.3. Vấn đề phát hiện trong APK v1.1.0: `flutter_assets` bị nhân đôi

`unzip -l TradeSignalAI-v1.1.0.apk` cho thấy **cả 2 đường dẫn** tồn tại song song:
- `assets/flutter_assets/AssetManifest.json`, `.../fonts/...`, `.../shaders/...` (bản ở gốc — **thiếu file `assets/dgn_logo.jpg`** ở đây), và
- `assets/flutter_assets/flutter_assets/AssetManifest.json`, `.../assets/dgn_logo.jpg`, `.../fonts/...` (bản lồng trong — có đủ logo).

Nguyên nhân: script copy `intermediate/flutter_assets` (vốn đã là thư mục `flutter_assets`) vào `stage/assets/flutter_assets`, rồi `aapt2 link -A stage/assets` lại đóng gói toàn bộ `stage/assets/` thành `assets/...` trong APK → thành `assets/flutter_assets/flutter_assets/...`. Bản ở gốc (`assets/flutter_assets/...` không có logo) có thể là do `aapt2` tự sinh từ `flutter_assets` của lần assemble khác hoặc do `-A` + asset mặc định — **chưa xác minh chính xác nguồn của bản gốc** (cần kiểm tra `stage/assets/` sau 1 lần build). App vẫn chạy được (Flutter tìm thấy asset ở bản lồng trong — đã có logo trong APK), nhưng APK **thừa ~90 KB** (AssetManifest, NOTICES.Z 84 KB, fonts, shaders bị trùng 2 lần). Khuyến nghị khi port: sửa script thành `cp -r "$INTER/flutter_assets/." "$STAGE/assets/flutter_assets/"` hoặc copy nội dung thay vì cả thư mục, rồi kiểm tra `unzip -l` chỉ còn 1 bản.

---

## 8. RỦI RO + LƯU Ý KHI PORT

### 8.1. Rủi ro kỹ thuật (xếp theo mức độ)

1. **Thiếu dữ liệu nến quá khứ — rào cản lớn nhất cho (3)(10)(2).** Engine chỉ sinh **300 nến M1**/cặp bằng random walk (`_generateM1`, `engine.dart:732`), rồi gộp lên: M5 = 60 nến, M15 = 20 nến, H1 = **5 nến**, H4 = **2 nến**, D1 = **1 nến**. Hệ quả:
   - Trend H4/D1, Ichimoku 52, EMA200, ATR14 H1 **không tính được** (toàn null hoặc suy biến — VD `ema20H1` luôn = 0, xem §1.6).
   - Backtest web yêu cầu ≥90 nến: với dữ liệu hiện tại chỉ M1 (300) và M5 (60) là đủ tối thiểu; M15 chỉ 20 nến — **không đủ chạy backtest M15/H1**. Cần hoặc (a) tăng số nến M1 sinh ra (VD 2000+ nến ≈ 33 giờ M1 → đủ H1 ~33 nến, vẫn thiếu cho EMA200/Ichimoku 52), hoặc (b) lấy nến quá khứ thật từ API (Binance klines cho BTC, nhưng forex/vàng không có nguồn nến miễn phí tương đương trong code hiện tại — **chưa xác minh** nguồn nào dùng được), hoặc (c) backtest chỉ chạy trên M1/M5 với dữ liệu mock và ghi rõ giới hạn. Quyết định này phải chốt trước khi code backtest.
   - Volume Profile lookback 200 nến M15 hiện chỉ có 20 nến M15 thật → `analyzeVolumeProfile` đang chạy trên **20 nến** chứ không phải 200 (hàm tự cắt `sublist` nếu thiếu, `volume_profile.dart:104`).
2. **Tín hiệu tĩnh đòi đổi kiến trúc, không phải vá UI.** `computeSignal()` hiện bị gọi từ 2 nơi (`_applyLivePrice` + `tick()` mỗi 15s) và dùng giá hiện tại làm Entry. Muốn chốt theo nến H1 đóng cần: theo dõi thời điểm nến H1 đóng (từ `Candle.time` + bucket H1), chỉ tính signal mới khi có nến H1 mới, lưu `issuedAt/stopTime`, tách "signal đang mở" khỏi "giá live". Đồng thời lịch sử tín hiệu + tổng toàn phiên (13) phải ghi từ signal đã chốt, không dùng `winRate` mock theo hash nữa.
3. **Tin Live FXStreet quét 1s — 3 vấn đề:**
   - **Parse RSS:** RSS là XML; project **không có package XML** nào và ràng buộc port là "không plugin mới" — phải tự parse XML bằng string/regex trong Dart thuần (dễ vỡ khi FXStreet đổi format) hoặc viết parser tối giản. (Dart `dart:convert` chỉ có JSON.)
   - **Rate limit:** web đã gặp vấn đề với rss2json/allorigins khi quét 1s (theo MEMORY 17/11 20:08: proxy có thể giới hạn tần suất, đã phải giãn nhịp 2s→60s). Flutter `HttpClient` gọi trực tiếp `feeds.fxstreet.com` (hoặc qua proxy) với tần suất 1s cũng có nguy cơ bị chặn 429; cần cơ chế backoff + cache + chỉ cập nhật khi có tin mới (như web đã làm).
   - **HttpClient hiện tại tạo mới mỗi lần gọi** (`_getJsonPrice` + 2 closure inline ở `engine.dart:554, 596`): 1s/lần × nhiều nguồn = churn kết nối, tốn pin/CPU; nên tái dùng 1 `HttpClient` instance cho cả app.
4. **Hiệu năng khi `notifyListeners()` mỗi giây + tính toán ×8 cặp.** `tick()` gọi `notifyListeners()` **mỗi giây** → `HomeScreen` (`ListenableBuilder`) rebuild toàn bộ cây, `IndexedStack` giữ cả 6 tab mounted nên `ChartTab.build` chạy `computeIndicators()` (EMA/BB trên ≤200 nến — Bollinger O(n×20) ≈ 4.000 phép tính) + `VolumeProfileTab.build` chạy `analyzeVolumeProfile()` (200 nến × 20 bin) **mỗi giây**. Hiện tại 1 cặp đã thế; quét VolumeB/S 8 cặp + trend 5 khung + PA + mẫu hình nến (đều chạy trên mỗi tick) có thể gây jank trên máy yếu. Cần: (a) chỉ tính lại khi có nến mới hoặc khi giá đổi đáng kể, (b) cache kết quả theo (symbol, timeframe, lastCandleTime), (c) tách `notifyListeners()` theo từng vùng (không rebuild toàn bộ HomeScreen mỗi giây).
5. **`main.dart` 1.961 dòng, 1 file chứa toàn bộ UI.** Port 15 nhóm sẽ thêm ~1.500–2.500 dòng nữa nếu nhét tiếp vào đây — rủi ro conflict/merge và khó review. Khuyến nghị tách trước khi port: `lib/tabs/` (mỗi tab 1 file), `lib/widgets/` (island, gauge, signal card), `lib/analysis/` (PA, patterns, backtest), `lib/storage.dart`, `lib/strategy.dart`. Việc tách file không đổi hành vi, nên làm ở commit riêng trước khi thêm tính năng.
6. **Timer 1 giây trong Flutter:** `Timer.periodic` vẫn chạy khi app ở nền (không bị hệ thống kill ngay) nhưng Android có thể doze; tin quét 1s + giá 2s khi app nền sẽ tốn pin và có thể bị hệ thống hạn chế (Doze/App Standby). Không phải blocker cho bản demo, nhưng không nên quảng cáo "quét 1s liên tục" khi app nền.
7. **Version hardcode 3 chỗ (§4.3) + lệch package name 2 đường build (§4.3).** Quên sửa 1 chỗ là APK báo version cũ; chạy nhầm `flutter build apk` là ra package khác, không cài đè được.
8. **Chưa có test nào:** thư mục `test/` tồn tại nhưng **chưa xác minh** có test case nào không (không nằm trong danh sách file đọc của task). `computeSignal`/`analyzeVolumeProfile` là hàm thuần — rất phù hợp viết unit test trước khi port (đặc biệt công thức 50/25/25, chấm 10đ, backtest). Khuyến nghị thêm test cho các hàm lõi trước khi sửa chúng.
9. **Kích thước APK:** v1.1.0 đã **51 MB** (3 ABI, mỗi ABI ~5–7 MB `libapp.so` + ~7–10 MB `libflutter.so`). Thêm asset CEO + logo PNG + code mới sẽ tăng thêm vài MB. Không phải blocker, nhưng nếu vượt ~100 MB thì Play Store (nếu sau này đưa lên) và link tải trực tiếp đều nặng hơn.
10. **Ký debug keystore:** APK hiện ký bằng **debug keystore tự tạo** (`build/manual/debug.keystore`, pass `android`). Cài trực tiếp được, nhưng không phải release keystore — nếu sau này đổi key thì người dùng phải gỡ app cũ mới cài được. Không đổi key trong đợt port này (đổi key = mất khả năng cập nhật đè).

### 8.2. Lưu ý khác

- **Giữ nguyên nguồn giá, không thêm OKX:** code Flutter không có OKX; khi port RSS/tin tức, không dùng nguồn giá mới nếu chưa được duyệt.
- **Không lưu key Exness** (xem §5.3) — mọi chỗ lưu trữ mới chỉ dùng cho cài đặt/phương pháp, không cho credential.
- **Số liệu mock còn sót:** `winRate/profitFactor/avgRr` fallback theo hash (`engine.dart:1249–1303`), 8 tin vàng giá 2.400 USD, 7 sự kiện lịch cố định — khi port (12)(13), các số này phải được thay bằng dữ liệu thật hoặc ghi rõ "chưa có dữ liệu", không để số mock lẫn với số thật.
- **`tradeStart/tradeEnd` chưa được dùng** để chặn lệnh (xem §2.5) — nếu web có logic giờ giao dịch thì đây là gap nhỏ cần bổ sung khi port Auto-Trade.
- **Chưa xác minh:** (a) thời gian build chính xác (§4.4); (b) nguồn gốc bản `flutter_assets` thừa trong APK (§7.3); (c) nội dung pixel của `ic_launcher.png`/`launch_image.png` có đúng logo DGN 3D mới không (chỉ xác minh theo hồ sơ build 16/11); (d) có test nào trong `test/` không; (e) hành vi thực tế trên máy thật (chưa chạy thử APK trong đợt audit — task chỉ yêu cầu đọc code).

---

## 9. XẾP HẠNG 5 VIỆC KHÓ NHẤT KHI PORT

| Hạng | Việc | Vì sao khó nhất |
|---|---|---|
| 🥇 1 | **Backtest trên nến thật + khung nhập phương pháp (nhóm 10)** | Thiếu dữ liệu gốc: chỉ 300 nến M1 → M15 có 20 nến, H1 có 5 nến — không đủ chạy backtest đúng nghĩa; cần quyết định nguồn nến quá khứ (API mới) hoặc tăng dữ liệu mock (và ghi rõ giới hạn). Ngoài ra phải xây engine backtest mới (vào/ra lệnh, tính R, drawdown, winrate/PF) + UI nhập/lưu phương pháp. |
| 🥈 2 | **Tín hiệu tĩnh + giờ lên/dừng + lịch sử tổng toàn phiên có thật (nhóm 1 + 13-phần lịch sử)** | Đổi kiến trúc lõi: tách "tính" khỏi "chốt" signal, neo theo nến H1 đóng, lưu lịch sử tín hiệu bền vững, thay toàn bộ thống kê mock theo hash bằng số liệu từ tín hiệu đã chốt; mọi màn hình (Dashboard, Chart, Lịch sử, Auto-Trade) đều bị ảnh hưởng. |
| 🥉 3 | **VolumeB/S quét 8 cặp + Trend 5 khung + Price Action 50/25/25 + điểm vào tối ưu (nhóm 2+3+4)** | Khối lượng tính toán ×8 cặp ×5 khung + module PA mới hoàn toàn (2 mức, ~13 pattern hành vi) + đổi công thức confidence; lại vướng thiếu nến H1/H4/D1; hiệu năng tick 1 giây có thể jank nếu không cache. |
| 4 | **Tin Live FXStreet quét 1s (nhóm 13-phần tin)** | RSS là XML mà project không có parser (phải tự viết, dễ vỡ); quét 1s dễ bị proxy/nguồn chặn 429 (web đã gặp); cần backoff + cache + chỉ cập nhật khi có tin mới; `HttpClient` hiện tại tạo mới mỗi lần gọi. |
| 5 | **Theme trắng + hero CEO + Dynamic Island + intro chime (nhóm 11)** | Đổi toàn bộ `ThemeData` dark → trắng (mọi màu hardcode trong `main.dart`/`chart.dart` phải rà lại), thêm asset mới (logo PNG trong suốt, ảnh CEO), widget island kéo ngang 8 cặp (gesture + giá live), và MethodChannel `AudioTrack` mới (Java + Dart + đăng ký plugin) — nhiều mảnh nhỏ, dễ sót, và chime/intro chỉ kiểm chứng được trên máy thật. |

---

## 10. PHỤ LỤC — THAM CHIẾU NHANH CHO COORDINATOR

- **File cần sửa nhiều nhất khi port:** `lib/main.dart` (UI, 1.961 dòng — nên tách file trước), `lib/engine.dart` (signal, chỉ báo, giá live, lịch/news).
- **File lõi dùng lại được gần như nguyên vẹn:** `lib/volume_profile.dart` (`analyzeVolumeProfile`), `lib/chart.dart` (khung vẽ + `dataToPixel/pixelToData`), các hàm `ema/rsi/atr/macd/_bollinger` trong `engine.dart` (chỉ cần tham số hóa).
- **File mới cần tạo (dự kiến):** `lib/storage.dart` (MethodChannel wrapper), `lib/strategy.dart` (enum + switch chiến lược), `lib/price_action.dart`, `lib/patterns.dart` (mẫu hình nến), `lib/backtest.dart`, `lib/news_live.dart` (RSS), `lib/widgets/dynamic_island.dart` (+ gauge), `manual/src/com/tradesignal/ai/StoragePlugin.java`, `manual/src/com/tradesignal/ai/ChimePlugin.java`.
- **File phải sửa (không được quên):** `pubspec.yaml` (version 1.2.0+3 + assets mới), `manual/build_apk.sh` (versionCode 3 / versionName 1.2.0 / tên file APK — 3 chỗ), `manual/src/io/flutter/plugins/GeneratedPluginRegistrant.java` (đăng ký 2 plugin mới).
- **Không sửa:** `android/app/src/main/java/.../GeneratedPluginRegistrant.java` (do Flutter tool quản lý), `android/app/build.gradle` (không dùng đường Gradle), key Exness (không lưu).
- **Lệnh kiểm tra sau mỗi lần build:** `~/Android/sdk/build-tools/34.0.0/apksigner verify --verbose build/manual/TradeSignalAI-v1.2.0.apk` (nhớ `export PATH=~/jdk17/bin:$PATH` trước), `aapt2 dump badging` (kiểm tra versionCode 3 / versionName 1.2.0), `unzip -l` (kiểm tra chỉ còn 1 bản `flutter_assets` + có asset mới), `~/flutter/bin/flutter analyze`.

*— Hết báo cáo audit. Mọi khẳng định "chưa xác minh" trong báo cáo là những điểm audit chưa đọc/chưa chạy được, không phải kết luận chắc chắn.*
