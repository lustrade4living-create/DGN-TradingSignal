# SPEC PORT — TradeSignal AI (bản web → Flutter)

- **Nguồn:** `~/workspace/your_files/tradesignal-ai-phase-1/tradesignal-ai-phase-1.html`
- **Bản web:** 5.021 dòng, ~1,6 MB, 6 khối `<script>`, HTML + CSS + JS thuần (không framework, không build step).
- **Số dòng tham chiếu trong spec này** là số dòng của file HTML gốc (đã kiểm chứng bằng `grep -n`).
- **Ngôn ngữ UI:** tiếng Việt. **Múi giờ hiển thị:** `Asia/Ho_Chi_Minh` (hằng `VN_TZ`, dòng 2732). Định dạng số: `vi-VN` cho giờ/ngày, `en-US` cho giá (dấu phẩy ngăn cách nghìn, dấu chấm thập phân), riêng % thay đổi trong UI dùng dấu phẩy thập phân (vd `+1,25%`).
- **Nguyên tắc xuyên suốt của web (phải giữ khi port): KHÔNG BAO GIỜ hiện số giả làm số thật.** Cặp nào chưa có giá live thì hiện `CHƯA LẤY ĐƯỢC GIÁ LIVE`; nguồn lỗi thì hiện `DỮ LIỆU CŨ` kèm giờ của giá cuối. Mọi thứ ghi là "nhận định / suy luận xác định trong trang" thì **không gọi API thật** (xem §11, §14, §16).

## 0. Bản đồ file gốc (để đối chiếu khi cần)

| Đoạn | Nội dung |
|---|---|
| Dòng 1–11 | `<head>`, favicon inline, font Google Fonts: `Be Vietnam Pro` (400/500/600/700/800) + `JetBrains Mono` (400/500/700) |
| Dòng 12–488 | Toàn bộ CSS (`:root`, intro, island, hero, chart, panel, VP, gauge, ladder, pattern…) |
| Dòng 489–1264 | HTML tĩnh: intro, island, hero, statusbar, pair-strip, tabbar, 10 panel, bnav, PANIC STOP, modal |
| Dòng 1265–2722 | Script 1: live engine (giá + nến) + indicators + tín hiệu tĩnh + chart canvas + Trend + Price Action + pan/draw |
| Dòng 2723–3584 | Script 2: tabs, Phân tích vĩ mô, Lịch kinh tế, Tin tức LIVE, Lịch sử, Auto-Trade |
| Dòng 3585–3962 | Script 3: VolumeB/S (TonyD) |
| Dòng 3963–4193 | Script 4: intro/chime, bnav, thẻ nổi bật, thống kê thật, Dynamic Island |
| Dòng 4194–4631 | Script 5: Chiến lược AI, thông số chỉ báo, dải tín hiệu ngang, nút Ẩn/Hiện, Backtest |
| Dòng 4632–5018 | Script 6: Gauge, thang TP, thư viện mẫu hình nến, cảnh báo Xung/TURN, phân tích theo từng cặp |

---

## 1. TỔNG QUAN CẤU TRÚC

### 1.1. Các tab / phase (10 tab, `data-tab`, dòng 610–622)

| Tab (`data-tab`) | Panel DOM | Nội dung |
|---|---|---|
| `chart` — "Biểu đồ" (mặc định, cũng là Trang chủ) | `#panelChart` | Hero CEO + thống kê + thẻ nổi bật + dải tín hiệu ngang + statusbar + pair-strip + chart thuần |
| `signals` — "Tín hiệu" | `#panelSignals` | Thẻ tín hiệu 8 cặp (trên cùng) + panel tín hiệu cặp đang chọn + phân tích theo từng cặp + cảnh báo Xung/TURN + thẻ mạnh nhất + quy tắc Swing |
| `analysis` — "Phân tích vĩ mô" | `#panelAnalysis` | **CHỈ 3 khối** (xem §16.6) |
| `calendar` — "Lịch kinh tế" | `#panelCalendar` | Lịch tuần, lọc Hôm nay/Cả tuần, High/Medium/Low/Chỉ tin vàng |
| `news` — "Tin tức LIVE" | `#panelNews` | Tin FXStreet RSS, lọc từ khóa, quét 1 giây |
| `history` — "Lịch sử tín hiệu" | `#panelHistory` | Bảng hiệu suất + danh sách lịch sử (mặc định thu gọn) |
| `volumebs` — "VolumeB/S" | `#panelVolumeBS` | Quét 8 cặp + chi tiết VP + 3 mô hình + quy trình 5 bước + quản trị vốn + kế hoạch ngày |
| `strategy` — "Chiến lược AI" | `#panelStrategy` | Chọn chiến lược (3 radio) + dải tín hiệu + cài đặt thông số chỉ báo |
| `backtest` — "Backtest" | `#panelBacktest` | Form test + khung nhập phương pháp + kết quả + danh sách lệnh |
| `auto` — "Auto-Trade" (có chấm đỏ `#autoDot` khi đang bật) | `#panelAuto` | Kết nối Exness (mô phỏng) + cấu hình + lệnh DEMO + nhật ký |

### 1.2. Cách chuyển tab (hàm xử lý click `.tab-btn`, dòng 2743–2771)

- Chỉ **một panel hiện** tại một thời điểm; các panel khác `hidden` (riêng `#panelChart` dùng `style.display`).
- **Hero + statusbar chỉ hiện ở tab `chart`** (Trang chủ). Mọi tab khác: hero và statusbar ẩn, **`#islandWrap` (Dynamic Island) hiện** thay thế.
- `#pairStrip` chỉ hiện ở 3 tab: `chart`, `signals`, `analysis`.
- Chuyển tab thì `scrollTo(top:0, smooth)`; chuyển sang `chart` thì vẽ lại chart (`drawChart()`); sang `signals` thì render lại panel + danh sách + phân tích theo cặp; sang `analysis`/`volumebs`/`history`/`calendar`/`news` thì render lại đúng phase đó.
- **Thanh nav dưới (`.bnav`, 5 nút)** chỉ là shortcut bấm tab tương ứng: Trang chủ→`chart`, Tín hiệu→`signals`, Phân tích→`analysis`, VolumeB/S→`volumebs`, Auto-Trade→`auto`. Nút active đồng bộ 2 chiều với tabbar (`syncBnav`).
- **Không có tab Tài sản / Cộng đồng / Cá nhân** (mockup có nhưng app chưa có — không được bịa thêm).

### 1.3. State toàn cục quan trọng (script 1)

```js
state = { symbol: SYMBOLS[1],  // XAUUSD mặc định
          tf: "M5",            // khung chart đang xem; chọn cặp mới thì reset về M5
          tool: "cursor",      // cursor | trend | hline | fib | rect | text
          pending: null,       // điểm đầu đang chờ khi vẽ 2 điểm
          online: true, simOffline: false,
          followed: {},        // {SYM: true} — cặp đang theo dõi
          pan: 0 }             // số nến đang lùi về quá khứ (0 = live)
signals = {}        // SYM -> signal | null (tín hiệu tĩnh đã chốt)
live = {}           // SYM -> {price, chgPct, ts, srcTime}
candleCache = {}    // "SYM|TF" -> [{t,o,h,l,c,v}] tăng dần theo thời gian, tối đa 300 nến tải + nến đang chạy (cắt 340)
candleLoading = {}  // promise đang tải, chống tải trùng
drawings = {}       // "SYM|TF" -> [{type, i1,p1, i2,p2, text}] — hình vẽ tay, chỉ giữ trong bộ nhớ trang
STRAT = "swing"     // "swing" | "volumebs" | "ai" (xem §11)
IND = {...}         // thông số chỉ báo (xem §13)
histEntries = []    // lịch sử tín hiệu phiên đang mở (xem §15); openBySymbol, lastAction
lastInvalidated = {}// SYM -> thông tin lệnh trước bị hủy sớm (xem §3.4)
```

### 1.4. Các nhịp chạy nền (interval) — port đúng tần suất

| Nhịp | Việc | Dòng |
|---|---|---|
| 1.000 ms | Đồng hồ VN, đếm ngược đóng nến, refresh trạng thái cặp, `updateFeedStatus` | ~2675 |
| 2.000 ms | `pollPrices()` (giá live), `autoTradeTick()`, `renderGauge()` + `renderLadder()` | ~2719, ~3578, ~4918 |
| 3.000 ms | `histTrack()` (đóng TP/SL + ghi tín hiệu mới); render lại analysis/volumebs/history nếu đang mở | ~3570 |
| 5.000 ms | `checkTurnAlerts()` (Xung/TURN) | ~4920 |
| 6.000 ms | `renderPairAnalysis()` nếu đang ở tab signals | cuối script 6 |
| 30.000 ms | `maybeComputeSignal()` cho cả 8 cặp (chỉ chốt lại khi có nến H1 mới đóng); `pollBinance24h()`; `checkNewsAlert()` | ~1907, ~2719, ~3583 |
| 1.000 ms (ticker riêng) | `newsScanTick()` — quét tin (có giãn nhịp, §14) | ~3166 |
| 2.500 ms | `warmupSignals()` sau khi mở trang: nạp nền M15/H1/H4 cho cả 8 cặp, mỗi cặp cách nhau 350 ms | ~1900, ~2720 |
| 300.000 ms | `pollFxAnchor()` (neo er-api) | ~2719 |

---

## 2. NGUỒN GIÁ LIVE

### 2.1. Bảng cặp — `SYMBOLS` (dòng 1277–1286)

| Cặp | Tên | `dec` (số lẻ) | Nguồn giá (`feed`) | Mã nguồn giá | Nguồn nến (`csrc`) |
|---|---|---|---|---|---|
| BTCUSD | Bitcoin / USD | 2 | Binance | `BTCUSDT` | Binance |
| XAUUSD | Vàng / USD | 2 | Binance (nến PAXG) nhưng **giá chuẩn từ gold-api.com** | `PAXGUSDT` | Binance · PAXG/USDT |
| EURUSD | Euro / USD | 4 | Kraken + neo er-api | `EURUSD`, Kraken key `ZEURZUSD`, `fx:"EUR"`, `fxInv:true` | Kraken |
| GBPUSD | Bảng Anh / USD | 4 | Kraken + neo er-api | `GBPUSD`, `ZGBPZUSD`, `fx:"GBP"`, `fxInv:true` | Kraken |
| USDCAD | USD / Đô Canada | 4 | Kraken + neo er-api | `USDCAD`, `ZUSDZCAD`, `fx:"CAD"`, `fxInv:false` | Kraken |
| USDCHF | USD / Franc Thụy Sĩ | 4 | Kraken + neo er-api | `USDCHF`, `USDCHF`, `fx:"CHF"`, `fxInv:false` | Kraken |
| USDJPY | USD / Yên Nhật | 2 | Kraken + neo er-api | `USDJPY`, `ZUSDZJPY`, `fx:"JPY"`, `fxInv:false` | Kraken |
| USOIL | Dầu WTI / USD | 2 | **CNBC** (giá) + OKX (nến) | `CL-USDT-SWAP` | OKX · CL |

`dec` quyết định mọi định dạng giá của cặp đó (`fmt()` dùng `toLocaleString("en-US", {minimumFractionDigits: dec, maximumFractionDigits: dec})`).

### 2.2. API giá live — `pollPrices()` mỗi 2 giây (dòng 1419–1500)

Chạy song song bằng `Promise.allSettled`, nguồn nào lỗi thì nguồn đó giữ giá cũ (không bịa số mới):

| Nguồn | URL (đầy đủ) | Lấy gì | Ghi chú |
|---|---|---|---|
| Kraken ticker (forex) | `https://api.kraken.com/0/public/Ticker?pair=EURUSD,GBPUSD,USDCAD,USDCHF,USDJPY` | `b[0]` (bid), `a[0]` (ask), `c[0]` (last), `o[0]` (open) → `mid=(bid+ask)/2`, `chg=(last-open)/open*100` | Chỉ dùng làm **tick chạy** cho forex, xem §2.3 |
| Binance giá BTC | `https://data-api.binance.vision/api/v3/ticker/price?symbol=BTCUSDT` | `price` | |
| Binance 24h (mỗi 30 s) | `https://data-api.binance.vision/api/v3/ticker/24hr?symbols=["BTCUSDT","PAXGUSDT"]` | `priceChangePercent` → `chgCache.BTCUSD / .XAUUSD` | Chỉ lấy % thay đổi 24h, không lấy giá PAXG làm giá vàng |
| gold-api vàng | `https://api.gold-api.com/price/XAU` | `price`, `updatedAt` → `srcTime` | Giá chuẩn của XAUUSD |
| CNBC dầu | `https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol?symbols=@CL.1&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json` | `FormattedQuoteResult.FormattedQuote[0].last`, `.change`, `.last_time` | `chg = change/(price-change)*100`; giá WTI sàn NYMEX |
| er-api neo forex (mỗi 5 phút) | `https://open.er-api.com/v6/latest/USD` | `rates[EUR|GBP|CAD|CHF|JPY]`, `time_last_update_unix` | Xem §2.3; nguồn này chỉ cập nhật 1 lần/ngày |

**Không có WebSocket thật.** Web ghi "cập nhật mỗi 2 giây" — đó là polling HTTP 2 giây, Flutter port bằng polling tương đương (không được ghi là WebSocket 1 giây).

### 2.3. Công thức giá hiển thị của forex — `fxDisplay()` (dòng 1412–1418)

Forex **neo mức theo er-api + chạy tick theo Kraken**:

```
anchor = rates[fx];  anchorPrice = fxInv ? 1/rate : rate        // fxInv=true: EUR, GBP (vì er-api trả USD->EUR)
fxAnchor[sym] = { price: anchorPrice, kMid: krakenMid lúc neo, srcTime }
giá hiển thị = anchorPrice * krakenMid.mid / anchor.kMid        // tỉ lệ tick Kraken so với lúc neo
```

- Nếu chưa có neo: dùng thẳng `krakenMid.mid`. Nếu chưa có cả hai: không có giá → `CHƯA LẤY ĐƯỢC GIÁ LIVE`.
- `setLive(sym, price, chgPct, srcTime)` chỉ nhận giá hữu hạn > 0; giữ lại `chgPct`/`srcTime` cũ nếu lần này không có.

### 2.4. Nhãn trạng thái nguồn — `updateFeedStatus()` / `pairStatusHtml()` (dòng 1502–1533, 1933–1950)

- `feedFresh(f)`: nguồn còn tươi nếu lần thành công gần nhất < **30.000 ms** (riêng `erapi` < **420.000 ms** = 7 phút).
- Cả 5 nguồn tươi → chấm xanh, chip `GIÁ LIVE THẬT`, text "Đang trực tiếp — giá thật · cập nhật mỗi 2 giây · lần cuối HH:MM:SS".
- Một phần tươi → chấm vàng, chip `LIVE MỘT PHẦN`, liệt kê tên nguồn đang lỗi; cặp thuộc nguồn lỗi hiện `DỮ LIỆU CŨ` hoặc `CHƯA CÓ GIÁ`.
- Không nguồn nào tươi nhưng đã từng có → chấm đỏ, chip `DỮ LIỆU CŨ — MẤT KẾT NỐI`, kèm giờ giá cuối.
- Từng cặp (pair-strip): có giá + tuổi ≤ 20 s → `● LIVE · HH:MM:SS`; có giá nhưng cũ hơn 20 s hoặc đang offline → `◐ DỮ LIỆU CŨ · từ HH:MM:SS`; chưa có giá → `○ CHƯA LẤY ĐƯỢC GIÁ LIVE` (màu đỏ). Tooltip hiện "Giờ của nguồn" (`srcTime`) nếu có.
- **Giả lập offline** (`#offlineToggle`): dừng mọi polling giá (`pollPrices` kiểm tra `state.online`), hiện banner vàng "Dữ liệu có thể cũ. Đang hiển thị giá và nến thật gần nhất đã tải…". Sự kiện `offline`/`online` của trình duyệt cũng tự đổi trạng thái. Nút "Âm thanh: Bật/Tắt" nằm cạnh nút này trên statusbar (chỉ ở Trang chủ).

### 2.5. Nến — `fetchCandles()` / `ensureCandles()` / `patchFormingCandle()` (dòng 1336–1410)

- Khung: `TF_MIN = {M5:5, M15:15, H1:60, H4:240, D1:1440}` (phút). Nến đóng theo **giờ thật của khung** (biên `floor(now / stepMs) * stepMs`), không tăng tốc.
- URL nến:
  - Kraken (forex): `https://api.kraken.com/0/public/OHLC?pair=<pair>&interval=<5|15|60|240|1440>` — trả `[time, open, high, low, close, vwap, volume, count]`; lấy `t=r[0]*1000`, `v=r[6]`.
  - Binance (BTC, PAXG): `https://data-api.binance.vision/api/v3/klines?symbol=<sym>&interval=<5m|15m|1h|4h|1d>&limit=300` — `t=r[0]`, `v=r[5]`.
  - OKX (dầu): `https://www.okx.com/api/v5/market/candles?instId=CL-USDT-SWAP&bar=<5m|15m|1H|4H|1D>&limit=300` — dữ liệu trả về mới→cũ nên phải `.reverse()`.
- Tối đa **300 nến** tải về; cache cắt còn tối đa **340** phần tử khi thêm nến mới.
- **Căn mức series (`maybeShiftSeries`, dòng 1314–1332):** nến Kraken/PAXG/OKX có thể lệch mức so với giá chuẩn (riêng nến dầu OKX thấp hơn WTI NYMEX ~1,5%). Khi có giá live lần đầu cho một series: `f = giá live / close nến cuối`; nếu `|f-1| > 0,0004` thì nhân toàn bộ `o,h,l,c` của series với `f`, **chỉ làm 1 lần/series** (`shiftedKeys`). **BTCUSD không căn** (nến và giá cùng Binance).
- **Nến live đang chạy (`patchFormingCandle`):** mỗi lần có giá live mới, với từng khung: nếu nến cuối có `t < start` của biên hiện tại → push nến mới `{t: start, o: close nến trước, h/l/c: giá}`; ngược lại cập nhật `c = giá`, mở rộng `h`/`l` nếu vượt. Gọi từ `setLive()` nên nến cập nhật theo nhịp giá 2 giây.
- **Tính toán chỉ dùng nến đã đóng:** `closedCandles(sym, tf)` = cache bỏ phần tử cuối (nến đang chạy); trả `null` nếu < 3 nến.
- Lỗi tải nến: hiện "Không tải được nến thật (…) — đang tự thử lại…" và **tự thử lại sau 6 giây** (chỉ cho cặp/khung đang xem).
- Đếm ngược đóng nến (`updateCountdown`, mỗi giây): `Nến <TF> (thật) đóng sau M:SS`, tính từ biên khung hiện tại.

---

## 3. TÍN HIỆU TĨNH

### 3.1. Nguyên tắc chốt — `swingCore()` (dòng 1647–1693), `maybeComputeSignal()` (dòng 1856–1880)

- **Entry = giá đóng của nến H1 đã đóng gần nhất** — KHÔNG lấy giá live đang nhảy. SL/TP chốt cứng tại thời điểm nến H1 đóng và **không đổi theo từng giây**; giá live chỉ để đối chiếu.
- Tín hiệu được tính lại (kiểm tra mỗi 30 giây) nhưng **giữ nguyên nếu `closedAt` trùng** với tín hiệu cũ (cùng một nến H1 đã đóng). Chỉ tính lại khi:
  - có nến H1 mới đóng (`closedAt` khác), hoặc
  - `force = true` (đổi chiến lược / đổi thông số chỉ báo — `recomputeAllSignals()`).
- `closedAt = thời gian đóng của nến H1 đã đóng gần nhất` = `t` của nến cuối đã đóng + 60 phút.
- Yêu cầu dữ liệu: H1 đã đóng ≥ **55 nến** (nếu không đủ → `null` → UI hiện "ĐANG TẢI"). H4 ≥ 55 nến để tính bias; nếu không đủ thì bias lấy từ H1. M15 ≥ 20 nến để tính RSI, nếu không RSI = `null` (không chặn tín hiệu).

### 3.2. Công thức Swing gốc — `swingCore()`

Đầu vào (đều từ nến đã đóng): `e20 = EMA(closes H1, IND.emaFast)`, `e50 = EMA(closes H1, IND.emaSlow)`, `atr = ATR(H1, IND.atr)`, `rsi = RSI(closes M15, IND.rsiSig)` (mặc định EMA 20/50, RSI 14, ATR 14 — xem §13).

```
entry    = closesH1 cuối (đã đóng)
bias     = e20(H4) >= e50(H4) ? "bullish" : "bearish"   (fallback: e20(H1) >= e50(H1))
strength = |e20 - e50| / atr                            // độ tách EMA tính theo ATR
trendUp  = e20 > e50
```

| Điều kiện | Hướng | Độ tin cậy gốc (`baseConf`) |
|---|---|---|
| `strength < 0,08` | WAIT | `round(38 + strength*100)` |
| `trendUp && bias=="bullish" && (rsi==null \|\| rsi < 78)` | BUY | `round(min(95, 56 + strength*55 + (rsi trong [48,68] ? 9 : 0)))` |
| `!trendUp && bias=="bearish" && (rsi==null \|\| rsi > 22)` | SELL | `round(min(95, 56 + strength*55 + (rsi trong [32,52] ? 9 : 0)))` |
| Còn lại (H1/H4 không đồng thuận, hoặc RSI cực đoan) | WAIT | `round(42 + min(14, strength*30))`, kèm lý do "H1 và H4 chưa đồng thuận — chờ" hoặc "RSI ở vùng cực đoan — chờ hồi" |

Lý do hiển thị (tối đa 6 dòng, `reasons`): `EMA20 H1 <giá> >/< EMA50 <giá>`; `H4 cùng chiều tăng/giảm (EMA20 …)`; `RSI(14) M15 = …`; `ATR(14) H1 = …`.

### 3.3. Entry / SL / TP / RR — `sigLevels()` (dòng 1694–1703)

```
SL = entry ∓ IND.slMult × ATR(H1)     (mặc định 1,5×ATR; BUY: entry − 1,5×ATR; SELL: entry + 1,5×ATR)
TP = entry ± IND.tpMult × ATR(H1)     (mặc định 3×ATR;   BUY: entry + 3×ATR;   SELL: entry − 3×ATR)
RR = tpMult / slMult = 3 / 1,5 = 1 : 2,0  (đổi hệ số ở §13 thì RR đổi theo)
```

WAIT thì `sl = tp = null`. Khoảng SL hiển thị thêm bằng pip và %: `|entry − SL| / pipSize` pip và `|entry − SL| / entry × 100` % (xem bảng `pipSize` ở §3.4).

### 3.4. Hủy lệnh sớm khi đảo chiều — `recordInvalidation()` (dòng 1810–1827), `histTrack()` (§15)

Khi nến H1 mới đóng mà hướng tín hiệu **đổi** so với tín hiệu tĩnh trước (BUY/SELL → WAIT hoặc sang hướng ngược), tín hiệu cũ bị hủy sớm:

```
exit = giá live lúc đảo chiều (nếu chưa có giá live thì lấy entry)
d    = BUY ? (exit − entry) : (entry − exit)
pips = d / pipSize(sym);   pct = d / entry × 100
distPips = |entry − SL| / pipSize;   distPct = |entry − SL| / entry × 100
```

`pipSize(sym)`: BTCUSD = 1; XAUUSD = 0,1; USOIL = 0,01; USDJPY = 0,01; còn lại (EURUSD, GBPUSD, USDCAD, USDCHF) = 0,0001.

Ghi lại: hướng cũ, entry, SL, TP, **giá cắt, giờ cắt, pips (+/−), % (+/−)**, khoảng SL gốc (pip + %), lý do (`"Đảo chiều sang SELL — hủy lệnh sớm"` / `"Mất điều kiện (về WAIT) — hủy lệnh sớm"` / `"Đổi chiến lược/thông số — hủy lệnh sớm"`). Hiển thị trong: khung đỏ `#spInvalid` trong panel tín hiệu, dòng "Lệnh trước hủy sớm…" trong thẻ tín hiệu của cặp, và mục Lịch sử (xem §15). Lưu ý: `recordInvalidation` chỉ ghi khi tín hiệu cũ là BUY/SELL và có SL.

### 3.5. Giờ lên / giờ dừng tín hiệu — `sigStopInfo()` (dòng 1828–1855)

- **Giờ lên tín hiệu** = `sg.closedAt` (thời điểm nến H1 đóng và chốt tín hiệu), hiển thị dạng `DD/MM · HH:MM:SS` (`sigDateTxt`).
- **Giờ dừng:**
  - Nếu tín hiệu đã đóng trong Lịch sử (khớp đúng cặp + hướng + entry sai lệch ≤ 0,5 pip): **giờ dừng THẬT** = `exitAt` của bản ghi đó + lý do: `Chạm TP` / `Chạm SL` / `Hủy sớm` (kèm giá đóng). Hiển thị: `"Đã dừng lúc DD/MM · HH:MM:SS — Chạm TP tại giá …"`.
  - Nếu còn hiệu lực: **giờ dừng DỰ KIẾN** = `closedAt + 1 giờ` (thời điểm nến H1 tiếp theo đóng). Hiển thị: `"Chưa dừng — hiệu lực tới DD/MM · HH:MM:SS (nến H1 tiếp theo đóng); dừng sớm ngay khi giá chạm TP/SL hoặc tín hiệu đảo chiều."` (dạng ngắn: `"Dừng dự kiến HH:MM:SS (nến H1 đóng tiếp theo)"`).
  - WAIT: `"Tín hiệu WAIT — hết hiệu lực DD/MM · HH:MM:SS khi nến H1 tiếp theo đóng."`
- Màu chữ giờ dừng: đã dừng do TP → xanh lá; đã dừng do SL/hủy sớm → đỏ; còn hiệu lực → màu chữ thường.

---

## 4. TREND + % TIN CẬY

### 4.1. Trend từng khung — `trendForTf(sym, tf)` (dòng 2396–2409)

Tính từ **nến đã đóng của chính khung đó**, yêu cầu ≥ 55 nến (không đủ → `null` → pill hiện "Đang tải…"):

```
e20 = EMA(closes, IND.emaFast)   // mặc định 20
e50 = EMA(closes, IND.emaSlow)   // mặc định 50
e34 = EMA(closes, IND.ema34)     // mặc định 34
rsi9 = RSI(closes, IND.rsiChart) // mặc định 9
score = 0
  e20 > e50  → +1 ;  e20 < e50  → −1
  last > e34 → +1 ;  last < e34 → −1
dir = score >= 2 ? "up" : score <= -2 ? "dn" : "flat"
```

Hiển thị mỗi khung: `▲ Tăng` / `▼ Giảm` / `◆ Ngang` + `RSI9 <số>`. Pill viền xanh khi tăng, đỏ khi giảm.

### 4.2. Điểm Trend đa khung — `multiTrend(sym, wantUp)` (dòng 1584–1600)

Trọng số `TREND_W = {M5:10, M15:20, H1:30, H4:25, D1:15}` (tổng 100).

```
với mỗi khung có dữ liệu:
  cùng chiều với wantUp → wNet += trọng số, aligned++
  ngược chiều           → wNet -= trọng số, opposed++
  đi ngang              → wNet += 0
index = round(50 + 50 * (wNet / wTot))     // wTot = tổng trọng số các khung có dữ liệu; 0..100
```

`wantUp` = hướng cần đánh giá: BUY → true; SELL → false; WAIT → theo `bias` (bullish → true).

### 4.3. Công thức % tin cậy — `finishSignal()` (dòng 1704–1729)

```
conf = round(baseConf × 0,50 + trendIndex × 0,25 + paIndex × 0,25)
nếu action == "WAIT": conf = min(conf, 62)        // TRẦN WAIT 62%
conf = clamp(conf, 5, 97)
```

Trong đó `baseConf` = độ tin cậy gốc của chiến lược (§3.2 / §11), `trendIndex` = điểm Trend (§4.2), `paIndex` = điểm Price Action (§4.4). Màu thanh %: ≥ 75 xanh lá, 55–74 vàng cam, < 55 xám.

### 4.4. Điểm Price Action — `paScore(sym, wantUp)` (dòng 1601–1612)

Đếm **cả 2 mức** Cơ bản + Nâng cao (xem §5): `bull` = số mẫu ủng hộ tăng, `bear` = số mẫu ủng hộ giảm, `total` = tổng số mẫu (Cơ bản 5 + Nâng cao 7 = tối đa 12; mẫu trung tính tính vào `total` nhưng không tính vào bull/bear).

```
aligned = wantUp ? bull : bear ;  opposed = wantUp ? bear : bull
index = total ? round(50 + 50 × (aligned − opposed) / total) : 50   // clamp 0..100
```

### 4.5. Bảng phân tích điểm (`#spScoreTable`, render trong `renderSignalPanel`, dòng ~2050)

4 cột: Thành phần điểm | Điểm | Trọng số | Đóng góp. 3 dòng + 1 dòng tổng:

| Dòng | Điểm | Trọng số | Đóng góp |
|---|---|---|---|
| Tín hiệu gốc (`<tên chiến lược>`) — mô tả: `EMA20/50 H1 · RSI(14) M15 · ATR(14)` | `baseConf`% | 50% | `baseConf × 0,5` |
| Trend đa khung — mô tả: `<aligned>/<avail> khung cùng chiều (M5·M15·H1·H4·D1)` | `trendIndex`% | 25% | `trendIndex × 0,25` |
| Price Action — mô tả: `<aligned> mẫu cùng chiều · <opposed> ngược · <total> mẫu (Cơ bản + Nâng cao)` | `paIndex`% | 25% | `paIndex × 0,25` |
| **TỔNG ĐỘ TIN CẬY** (thêm `(WAIT — trần 62%)` khi WAIT) | | 100% | `conf`% |

Mỗi dòng có thanh tiến độ ngang (màu vàng cam) theo % điểm. Bảng này nằm trong khối thu gọn mặc định (xem §16.5).

---

## 5. PRICE ACTION 2 MỨC — `computePriceAction(sym)` (dòng 2443–2515)

- Nguồn: **nến M15 đã đóng** (`closedCandles(sym,"M15")`), yêu cầu ≥ 25 nến; M5 đã đóng (≥ 22 nến) cho xác nhận Execution; H1 đã đóng (≥ 55 nến) cho xu hướng H1 (EMA20 vs EMA50).
- Ký hiệu: `last` = nến M15 đóng gần nhất, `prev` = nến trước đó, `prev2` = nến trước nữa; `body = |c−o|`, `range = h−l` (tối thiểu 1e-9), `upW = h − max(o,c)`, `dnW = min(o,c) − l`.
- Mỗi mẫu trả về `dir`: `"bull"` / `"bear"` / `null` (trung tính / không có). `summarize()` đếm bull/bear/total cho từng mức.
- `levels` trả kèm để dùng cho điểm vào tối ưu (§5.3): `{hi20, lo20, brDir, sweepDir, sweepLevel, chochDir, fvgDir, fvgZone, obDir, obZone, retestDir}`.

### 5.1. Mức Cơ bản — 5 mẫu (đọc nến M15 đóng gần nhất)

| # | Mẫu | Điều kiện nhận diện (chính xác) | Hướng |
|---|---|---|---|
| 1 | **Pin Bar** | Bấc dưới `dnW > body×2` và bấc trên `upW < body×0,9` và `body > 0` → tăng (Hammer); ngược lại bấc trên `upW > body×2` và `dnW < body×0,9` → giảm (Shooting Star) | bull / bear / null |
| 2 | **Engulfing (nhấn chìm)** | Tăng: `last.c > last.o && prev.c < prev.o && last.c >= prev.o && last.o <= prev.c`; Giảm: `last.c < last.o && prev.c > prev.o && last.c <= prev.o && last.o >= prev.c` (thân nến sau bao phủ toàn bộ thân nến trước) | bull / bear / null |
| 3 | **Inside Bar** | `last.h <= prev.h && last.l >= prev.l` (nến nằm trọn trong biên nến trước) | luôn `null` (trung tính — chỉ báo nén giá, chờ phá biên) |
| 4 | **Doji / từ chối giá** | `body / range < 0,12` → Doji | luôn `null` (trung tính) |
| 5 | **Phá đỉnh / đáy 20 nến** | Cửa sổ `win20 = m15.slice(n−21, n−1)` (20 nến trước nến cuối), `hi20 = max(h)`, `lo20 = min(l)`; `last.c > hi20` → bull; `last.c < lo20` → bear | bull / bear / null |

### 5.2. Mức Nâng cao — 7 mẫu

| # | Mẫu | Điều kiện nhận diện (chính xác) | Hướng |
|---|---|---|---|
| 1 | **Liquidity Sweep** | Quét 5 nến M15 gần nhất (`i = n−5 … n−1`): với mỗi nến `c`, cửa sổ 20 nến trước nó (`hi/lo`); `c.h > hh && c.c < hh` → sweep đỉnh (bear, `sweepLevel = hh`); `c.l < ll && c.c > ll` → sweep đáy (bull, `sweepLevel = ll`). Nến quét sau ghi đè nến trước nếu cả hai loại xuất hiện | bull / bear / null |
| 2 | **BOS (phá cấu trúc)** | Cùng điều kiện phá đỉnh/đáy 20 nến như mẫu Cơ bản #5 (`brDir`) | bull / bear / null |
| 3 | **CHoCH (đổi tính chất)** | Có `brDir` và xu hướng H1 (`h1TrendUp = EMA20(H1) > EMA50(H1)`) ngược hướng phá: phá đỉnh trong khi H1 đang giảm → CHoCH tăng; phá đáy trong khi H1 đang tăng → CHoCH giảm | bull / bear / null |
| 4 | **FVG (Fair Value Gap)** | Quét 15 nến gần nhất, xét bộ 3 nến (`a = m15[j−2]`, `b = m15[j]`): `b.l > a.h` → FVG tăng, vùng `{low: a.h, high: b.l}`; `b.h < a.l` → FVG giảm, vùng `{low: b.h, high: a.l}`. FVG sau ghi đè FVG trước | bull / bear / null |
| 5 | **Order Block** | Chỉ khi có BOS: tăng → tìm ngược từ `n−2` về tối đa 12 nến, nến giảm cuối cùng trước nhịp phá lên → vùng `{low: l, high: h}`; giảm → nến tăng cuối cùng trước nhịp phá xuống. Không có BOS → `obZone = null` | = `brDir` (bull/bear/null) |
| 6 | **Retest vùng phá vỡ** | Có `brDir` và `atrH1 = ATR(H1, IND.atr)`; mức phá `lvl = brDir=="bull" ? hi20 : lo20`; giá hiện tại (live, fallback = close nến cuối) thỏa `|cur − lvl| <= 0,3 × atrH1` → đang retest đúng hướng phá | bull / bear / null |
| 7 | **Xác nhận M5 (Execution)** | Nến M5 đóng gần nhất so với đỉnh/đáy 20 nến M5 trước nó: `m5last.c > m5hi` → bull; `m5last.c < m5lo` → bear | bull / bear / null |

### 5.3. Hộp "Điểm vào chuẩn & đẹp — tối ưu" — `computeOptimal()` (dòng 1613–1646)

Áp dụng khi có `entry` và `atr` (ATR H1). Ứng viên được xét theo **thứ tự ưu tiên** (chọn ứng viên ưu tiên cao nhất; hòa thì chọn gần Entry nhất):

| Ưu tiên | Nguồn | Giá ứng viên | Điều kiện |
|---|---|---|---|
| 1 | **Retest sau BOS/CHoCH** | `hi20` (BUY) / `lo20` (SELL) | `brDir` cùng hướng vào; nhãn "Retest sau CHoCH tăng/giảm" nếu `chochDir` cùng hướng, không thì "Retest sau BOS tăng/giảm" |
| 2 | **Sau Liquidity Sweep** | `sweepLevel` | `sweepDir` cùng hướng vào và có `sweepLevel` |
| 3 | **Mép / giữa FVG** | giữa vùng FVG `(low+high)/2` | `fvgZone` tồn tại và `fvgDir` cùng hướng |
| 4 | **Order Block** | giữa vùng OB `(low+high)/2` | `obZone` tồn tại và `obDir` cùng hướng; ghi chú: nếu trùng POC/HVN của Volume Profile thì càng đẹp |
| 5 | **Hồi về EMA20 H1** | `e20h1` | Luôn có nếu tính được EMA20 H1 |
| 9 (fallback) | **Vùng hồi 0,5×ATR (tham chiếu)** | BUY: `entry − 0,5×ATR`; SELL: `entry + 0,5×ATR` | Khi không có ứng viên nào; ghi rõ "chưa nên vào tại đây" |

- **Cửa sổ lọc ứng viên:** BUY chỉ nhận giá trong `[entry − 1,8×ATR, entry + 0,3×ATR]`; SELL trong `[entry − 0,3×ATR, entry + 1,8×ATR]`. Ngoài cửa sổ thì loại.
- **Vùng vào:** `zoneLow/zoneHigh = price ± 0,15×ATR`.
- **Chất lượng + sao:** không fallback và `paIndex >= 60` → `"Chuẩn & đẹp" ★★★`; không fallback và `paIndex >= 45` → `"Chuẩn — chờ thêm 1 xác nhận PA" ★★☆`; còn lại (kể cả fallback) → `"Chưa đẹp — chờ xác nhận" ★☆☆`.
- **RR cải thiện:** `rrOptimal = |TP − optimalPrice| / |optimalPrice − SL|` (giữ nguyên SL/TP tĩnh), hiển thị dạng `RR tại điểm tối ưu ≈ 1 : X,X` so với `1 : 2,0` tại Entry chính.
- **Quan trọng:** điểm tối ưu **không thay** Entry/SL/TP tĩnh — chỉ là điểm chờ vào tốt hơn. Khi tín hiệu WAIT, hộp vẫn hiện (điểm chờ nếu bias hình thành tín hiệu).

---

## 6. THƯ VIỆN MẪU HÌNH NẾN — 15 MẪU — `PAT_DEFS` (dòng 4753–4804)

- Nguồn đếm: **nến đã đóng của khung đang chọn** (`closedCandles(sym, state.tf)`), cửa sổ tối đa **200 nến** gần nhất (`win = cs.slice(-200)`), yêu cầu tối thiểu **30 nến** (ít hơn → hiện "Chưa đủ nến", không hiện số thay thế).
- Dung sai đỉnh/đáy kẹp: `tol = avgRange × 0,15`, với `avgRange` = trung bình `(h−l)` của cả cửa sổ 200 nến.
- Mỗi mẫu: quét từng vị trí `i = 1 … n−1` trong cửa sổ; mẫu xuất hiện ở nến nào thì **đếm 1 lần tại nến đó**; ghi `lastI` (vị trí gần nhất) và `lastDir`.
- Thẻ "Vừa xuất hiện" (viền vàng) khi `lastI >= n−2` (tức xuất hiện ở 1 trong 2 nến đóng gần nhất).
- Hàm phụ: `patBody(c)=|c−o|`, `patRange(c)=max(1e-12, h−l)`, `patUpW(c)=h−max(o,c)`, `patDnW(c)=min(o,c)−l`.

| # | Mẫu (EN) | Điều kiện nhận diện chính xác (`a = cs[i−1]`, `b = cs[i]`) | Hướng hiển thị |
|---|---|---|---|
| 1 | **Đỉnh kẹp** (Tweezer Top) | `a` tăng, `b` giảm, `\|a.h − b.h\| <= tol` | Đảo chiều giảm (badge vàng "Đảo chiều") |
| 2 | **Đáy kẹp** (Tweezer Bottom) | `a` giảm, `b` tăng, `\|a.l − b.l\| <= tol` | Đảo chiều tăng |
| 3 | **Harami chữ thập** (Cross Harami) | Thân `a >= 0,55 × range(a)`; thân `b <= 0,12 × range(b)` (doji nhỏ); thân `b` nằm trọn trong thân `a`; hướng ngược với `a` (a tăng → bear, a giảm → bull) | Đảo chiều |
| 4 | **Nến trong** (Inside Bar) | `b.h <= a.h && b.l >= a.l` và (`b.h < a.h \|\| b.l > a.l`) | Trung tính |
| 5 | **Nhân chìm tăng** (Bullish Engulfing) | `b` tăng, `a` giảm, `b.c >= a.o && b.o <= a.c` | Đảo chiều tăng |
| 6 | **Nhân chìm giảm** (Bearish Engulfing) | `b` giảm, `a` tăng, `b.c <= a.o && b.o >= a.c` | Đảo chiều giảm |
| 7 | **Xuyên thủng** (Piercing Line) | `a` giảm, thân `a >= 0,5 × range(a)`; `b` tăng, `b.o <= a.l + tol`, `b.c > mid(a)` (mid = `(a.o+a.c)/2`) và `b.c < a.o` | Đảo chiều tăng |
| 8 | **Nến ngoài** (Outside Bar) | `b.h > a.h && b.l < a.l`; hướng theo thân `b` (tăng → bull, giảm → bear, doji → trung tính) | Thiên tăng / Thiên giảm / Trung tính |
| 9 | **Sao băng** (Shooting Star) | `body > 0`, `upW >= 2 × body`, `dnW <= 0,35 × range`, và đỉnh thân `max(o,c) <= l + 0,45 × range` | Đảo chiều giảm |
| 10 | **Con quay** (Spinning Top) | `body <= 0,32 × range`, `upW >= 0,2 × range`, `dnW >= 0,2 × range` | Trung tính |
| 11 | **Marubozu tăng** (Bullish Marubozu) | `b` tăng, `body >= 0,85 × range` | Thiên tăng |
| 12 | **Marubozu giảm** (Bearish Marubozu) | `b` giảm, `body >= 0,85 × range` | Thiên giảm |
| 13 | **Mây đen che phủ** (Dark Cloud Cover) | `a` tăng, thân `a >= 0,5 × range(a)`; `b` giảm, `b.o >= a.c − tol`, `b.c < mid(a)` và `b.c > a.o` | Đảo chiều giảm |
| 14 | **Pin Bar** (Hammer / Shooting) | `body > 0`; `dnW > body×2 && upW < body×0,9` → bull; `upW > body×2 && dnW < body×0,9` → bear | Đảo chiều |
| 15 | **Doji** | `body <= 0,10 × range` | Trung tính |

- Mỗi thẻ mẫu hiển thị: tên VN + tên EN, **số lần xuất hiện** (số lớn), badge hướng, "Lần gần nhất: `<khung> · DD/MM HH:MM`" (+ "— chính là nến đóng gần nhất" nếu fresh, hoặc "— cách đây N nến").
- Lưu ý khác biệt nhỏ cần giữ: Doji ở thư viện dùng ngưỡng `0,10`, còn Doji ở Price Action cơ bản dùng `0,12` (§5.1). Pin Bar ở cả hai nơi dùng cùng công thức.
- Thư viện hiển thị ở 2 chỗ: khối độc lập `#patLib` đã **gỡ** khỏi phase Tín hiệu (hàm `renderPatternLibrary` tự bỏ qua khi không còn khối); bản còn lại nằm trong **khối phân tích theo từng cặp** (§16.5) — chỉ hiện top 6 mẫu có số lần xuất hiện > 0, sắp xếp giảm dần theo số lần.

---

## 7. GAUGE CỘNG HƯỞNG ĐA KHUNG — `renderGauge()` (dòng 4640–4684)

- Gộp Trend 5 khung (M5/M15/H1/H4/D1) của cặp đang chọn, mỗi khung tính bằng `trendForTf` (§4.1). Chỉ đếm các khung **đã có đủ nến** (`avail`); chưa đủ khung nào thì hiện "Đang tải nến các khung…".
- Đếm: `upN` (Tăng), `flatN` (Trung tính), `dnN` (Giảm).
- **Kim đồng hồ:** `score = (upN − dnN) / avail` (−1…1); góc kim `theta = 90° − score × 78°` (score = 1 → kim chỉ 12° ≈ gần hết bên phải/Tăng; score = −1 → 168° ≈ bên trái/Giảm; score = 0 → 90° = chính giữa). Đầu kim: `(100 + 60·cos θ, 100 − 60·sin θ)` trong SVG `viewBox 0 0 200 112`, tâm kim `(100,100)`, bán kính kim 60.
- **Cung màu:** đỏ (Giảm) 180°→126°, xám (Ngang) 124°→56°, xanh lá (Tăng) 54°→0°, bán kính cung 80, dày 13. Nhãn: `GIẢM` (14,111), `NGANG` (88,14), `TĂNG` (160,111).
- **Kết luận văn bản:**
  - `upN > dnN && upN >= flatN` → "Phe **Tăng** đang chiếm đa số — **upN/avail khung** cùng nghiêng tăng" + (còn khung ngược chiều thì thêm "…còn dnN khung ngược chiều nên vẫn cần xác nhận ở khung lớn (H1/H4)", không thì "và không có khung nào ngược chiều").
  - Ngược lại cho phe Giảm.
  - `upN == dnN && upN > 0` → "Hai phe **cân bằng** — … chưa có cộng hưởng rõ, ưu tiên chờ thêm một khung đổi chiều."
  - Còn lại → "Đa số khung đang **đi ngang** (flatN/avail) — thị trường chưa chọn hướng, gauge ở vùng trung tính."
  - Nếu `avail < 5`: thêm "(Mới có avail/5 khung đủ nến đã đóng — gauge chỉ tổng hợp các khung đã tải.)"
- Gauge render lại mỗi 2 giây (`setInterval(renderGauge, 2000)`), nằm trong panel tín hiệu (khối thu gọn mặc định) và trong khối phân tích theo từng cặp (chỉ dạng đếm + % Trend, không vẽ SVG).

---

## 8. THANG TP NHIỀU TẦNG — `sigLevels()` + `renderLadder()` + `checkHistTiers()`

### 8.1. Các mức — `sigLevels(action, entry, sl, tp)` (dòng 1694–1703)

```
dist = |TP − Entry|   (> 0 mới có thang; WAIT hoặc thiếu SL/TP → null)
dir  = BUY ? +1 : −1
Inv  = SL
T1   = Entry + dir × dist × 0,25
T2   = Entry + dir × dist × 0,50
T3   = Entry + dir × dist × 0,75
T4   = TP                            (= 100%)
Entry = Entry
```

### 8.2. Theo dõi mô phỏng từng tầng — `checkHistTiers()` (dòng 3166–3195), chạy trong `histTrack()` mỗi 3 giây

- Áp dụng cho lệnh mô phỏng đang mở trong Lịch sử (`openBySymbol[sym]`, có `levels` + `tiers`).
- Quét nến **M5 và M15** kể từ `startAt − 15 phút` (`startAt` = `closedAt` của tín hiệu; fallback `openAt`): với mỗi nến theo thứ tự thời gian, BUY chạm tầng khi `h >= lvl`, SELL khi `l <= lvl`. Tầng nào chạm thì ghi `hit = true`, `at = t nến + step khung` (giờ đóng nến chạm), `price = lvl`.
- Nếu chưa chạm qua nến mà **giá live đã vượt tầng** thì ghi chạm ngay lúc đó (`at = now`).
- Trạng thái hiển thị mỗi tầng (`tierStatus`): đã chạm → `"✓ Đã chạm T<n> lúc HH:MM:SS"` + giá tầng + (nếu giá live đã hồi ngược qua tầng thì thêm "· giá live đã hồi X,X pip … (pullback)"); chưa chạm → `"Chưa chạm · còn ~X,X pip từ giá live"`.
- `Inv` (SL): đã chạm → đỏ `"Đã chạm Inv lúc HH:MM:SS — tín hiệu đã vô hiệu (dừng lỗ)"`; lệnh đóng do chạm SL thì ghi tương tự; chưa chạm → "Chưa chạm — giá chạm mức này là tín hiệu vô hiệu…".
- Trên biểu đồ (`drawChart`): các mức vẽ thành đường ngang từ nến tín hiệu (`sigIdx = visible.length − 22`, tối thiểu 2) kéo dài **20 nến về phải**; nhãn `Entry …`, `Inv (SL) …`, `T1 … ✓ đã chạm` (nếu đã chạm)… Màu: Entry xám `#68799c` (nét đứt `[2,4]`), Inv đỏ `#f6465d`, T1 `#3ecf8e`, T2 `#17c784`, T3 `#0da271`, T4 `#0b7a55` (đậm dần).
- Thứ tự hiển thị trong panel thang: sắp xếp **giá giảm dần** (T4 trên cùng → Inv dưới cùng với BUY; ngược lại với SELL do sort theo giá).

### 8.3. "Chênh mở phòng" (Sim Diff)

- Khi lệnh mô phỏng mở trong Lịch sử (`histTrack`, §15): `openPrice = giá live lúc mở` (fallback = Entry tĩnh); `simDiff = openPrice − Entry` (giá trị có dấu, chưa nhân hướng).
- Hiển thị: `simDiffPips = simDiff / pipSize` (pip, 1 số lẻ, dấu +/−, dấu phẩy thập phân) và `simDiffPct = simDiff / Entry × 100` (%). Đánh giá: `|simDiffPips| < 0,05` → "khớp Entry"; ngược lại "thuận lợi hơn Entry" nếu `(BUY ? −simDiffPips : simDiffPips) >= 0`, không thì "kém hơn Entry".
- Xuất hiện ở: đầu thang TP (`Chênh mở phòng: +X,X pip · mở mô phỏng tại <giá>`), từng dòng lịch sử, và trong `findHistFor` để gắn thang với đúng lệnh mô phỏng (khớp cặp + hướng + entry sai lệch ≤ 0,5 pip).
- Khoảng cách từng tầng tới Entry hiển thị dạng `+X,X pip · +X,XX% từ Entry` (`distTxt`).

---

## 9. CẢNH BÁO XUNG ĐA KHUNG VÀ TURN ĐỒNG BỘ — `checkTurnAlerts()` (dòng 4853–4925)

- Chạy mỗi **5 giây** cho cả 8 cặp; mỗi lần kiểm tra phải `ensureCandles` đủ 5 khung.
- **Điều kiện tiên quyết:** phải có đủ Trend của **cả 5 khung** (M5/M15/H1/H4/D1); thiếu khung nào → bỏ qua, không cảnh báo.
- **Mốc nền:** lần kiểm tra đầu tiên của mỗi cặp chỉ lưu `turnPrev[sym]` (map khung→dir), không cảnh báo.
- **TURN đồng bộ:** đếm số khung đảo chiều Tăng↔Giảm so với lần kiểm tra trước (`up→dn` hoặc `dn→up`; Ngang không tính). Kích hoạt khi **`flips >= 2 khung`** trong cùng một lần kiểm tra. Cooldown **10 phút/cặp** (`turnCooldown[sym+"|turn"]`). Nội dung: `"<N> khung cùng đảo chiều trong cùng một lần kiểm tra: <TF Tăng → Giảm · …>. Hướng Trend của <SYM> đang đổi đồng loạt (TURN đồng bộ) — cân nhắc chờ gauge cộng hưởng ổn định lại trước khi vào lệnh mới theo hướng cũ."`
- **Xung đa khung:** cả 5 khung cùng `up` hoặc cùng `dn` **và lần kiểm tra trước chưa phải toàn bộ cùng hướng đó** (tránh lặp cảnh báo khi xung kéo dài). Cooldown **10 phút/cặp/hướng** (`turnCooldown[sym+"|xung|up|dn"]`). Nội dung: `"Cả 5 khung M5/M15/H1/H4/D1 cùng TĂNG/GIẢM — xung đa khung nghiêng hẳn về phe mua/bán. Ngay trước đó Trend từng khung là: M5 … · M15 … · …"`
- Lưu tối đa **30 cảnh báo** (mới nhất lên đầu), danh sách hiển thị tối đa **12**; mỗi cảnh báo: tag `XUNG ĐA KHUNG` (xanh dương) / `TURN ĐỒNG BỘ` (vàng cam), cặp, giờ `DD/MM HH:MM:SS`, nội dung. Cảnh báo mới nhất đồng thời hiện **banner trên cùng** (`#turnAlert`, có nút Ẩn). Chip đếm: `"<N> cảnh báo"`. Không có cảnh báo nào trong phiên → empty-note "Chưa có cảnh báo nào trong phiên này…".

---

## 10. VOLUMEB/S — TONYD VOLUME PROFILE (script 3, dòng 3585–3962)

### 10.1. Volume Profile — `computeProfile(cs, rows)` (dòng 3607–3658)

- Nguồn: **nến M15 đã đóng**, lookback **200 nến** (`m15.slice(-200)`), chia thành **`rows = 24` hàng** (profile chi tiết; bản quét nhanh 20 nến dùng 8 hàng, xem §10.5).
- Phạm vi giá: `lo = min(l)`, `hi = max(h)` của cửa sổ; `step = (hi−lo)/24`; hàng `i`: `[lo+i·step, lo+(i+1)·step]`, giữa `mid`.
- **Phân bổ volume:** mỗi nến có volume `v` (volume thật của nến; nếu `v` thiếu/≤ 0 thì `v = 1`). Volume được chia cho các hàng theo **tỉ lệ chồng lấp** của biên nến với hàng: `share = v × overlap / (h−l)`. Nến có `h == l` thì dồn toàn bộ vào hàng chứa giá đóng.
- **Buy/Sell Volume ước tính (KHÔNG phải Delta tick thật):** `buyFrac = clamp((c−l)/(h−l), 0, 1)` — tỉ lệ vị trí đóng nến trong biên nến; `buy += share×buyFrac`, `sell += share×(1−buyFrac)`. Nến range = 0: `buyFrac = c>=o ? 1 : 0`.
- **POC:** hàng có `vol` lớn nhất.
- **Value Area 70%:** bắt đầu từ POC, mở rộng sang hàng kề trên/dưới có volume lớn hơn cho tới khi tích lũy ≥ `total × 0,70`; `VAH = prof[up].hi` (biên trên), `VAL = prof[dn].lo` (biên dưới).
- **HVN:** `vol > avg×1,25` và là cực đại địa phương (`vol >= vol hàng kề`) và không phải POC. **LVN:** `vol < avg×0,55` và là cực tiểu địa phương. (`avg = total/rows`.)
- **Delta:** `delta = buyTot − sellTot`; `deltaPct = delta/total×100` (%). Luôn ghi chú "ước tính".

### 10.2. Ichimoku — `computeIchimoku(cs)` (dòng 3596–3605)

Yêu cầu ≥ 52 nến. `hl(n) = (max(h,n) + min(l,n))/2`; Tenkan = `hl(9)`, Kijun = `hl(26)`, Senkou A = `(Tenkan+Kijun)/2`, Senkou B = `hl(52)`; mây `[min(A,B), max(A,B)]`; vị trí giá đóng cuối: `above` (trên mây) / `below` (dưới mây) / `inside` (trong mây).

### 10.3. Cấu trúc M5 — `vpM5Structure()` (dòng 3668–3687)

Dùng nến M5 đã đóng (≥ 25): cửa sổ 15 nến trước nến cuối (`pHigh/pLow`); `sweepLow = last.l < pLow && last.c > pLow`; `sweepHigh` tương tự; `bosUp = last.c > pHigh && !sweepHigh`; `bosDown` tương tự; `prevDir = sign(c[n−2] − c[n−12])`; `chochUp = bosUp && prevDir < 0`; `chochDown = bosDown && prevDir > 0`; `swingHigh15/Low15` = đỉnh/đáy 15 nến M5.

### 10.4. Bảng chấm điểm 10đ — `renderVolumeBS()` (dòng 3743–3945)

Xét cặp đang chọn (mặc định XAUUSD). Xu hướng H1 từ Ichimoku (fallback EMA20 H1). `atZone` = giá tại POC (`|price − POC| <= max(step×1,2, ATR(M15)×0,6)`) hoặc tại một HVN (cùng ngưỡng). `deltaRecent` = Delta của profile 20 nến M15 gần nhất (8 hàng).

| # | Tiêu chí | Điểm | Điều kiện ĐẠT |
|---|---|---|---|
| 1 | H1 cùng xu hướng (Ichimoku) | 2 | (BUY và trên mây) hoặc (SELL và dưới mây) |
| 2 | Giá tại POC / HVN quan trọng | 2 | `atZone` |
| 3 | Có Liquidity Sweep (M5) | 2 | BUY: `sweepLow`; SELL: `sweepHigh` |
| 4 | Có CHoCH / BOS (M5) | 2 | BUY: `chochUp \|\| bosUp`; SELL: `chochDown \|\| bosDown` |
| 5 | Buy/Sell Volume ủng hộ hướng vào | 1 | BUY: `deltaRecent > 0`; SELL: `deltaRecent < 0` |
| 6 | RR tối thiểu 1:2 | 1 | Có mô hình và `RR tới TP2 >= 2` |

**Ngưỡng:** 8–10: "Setup tốt, có thể xem xét vào lệnh"; 6–7: "Chờ xác nhận thêm"; < 6: "Không giao dịch". Kết luận chỉ ra hướng khi `model` tồn tại và `score >= 8`, ngược lại WAIT.

### 10.5. Quét cả 8 cặp — `vpScanFor(sym)` / `renderVpScan()` (dòng 3688–3742)

Mỗi cặp dựng profile M15 riêng (200 nến, 24 hàng) + lọc H1 + Delta gần nhất (profile 20 nến, 8 hàng):

```
trend = Ichimoku H1 (above→up, below→down, inside→neutral); fallback EMA20 H1 so với giá
nearPoc = |price − POC| <= step × 1,5
score (tối đa 5): trend != neutral → +2 ; nearPoc → +2 ; Delta gần nhất cùng dấu xu hướng → +1
action = trend up → BUY, down → SELL, neutral → WAIT;  nếu score < 3 → WAIT
```

Mỗi dòng quét hiện: cặp, BUY/SELL/WAIT, giá live, điểm quét `/5`, POC/VAH/VAL, xu hướng H1, "đang tại vùng POC" hay chưa, Delta%. Bấm dòng → xem chi tiết cặp đó (đổi `vpSelectedSym`, render lại).

### 10.6. Mô hình A / B / C và Entry / SL / TP

- **Mô hình C (phá vỡ LVN):** LVN gần nhất trên/dưới giá; nến M15 cuối đóng vượt qua LVN (`c > lvnBelow.hi` hoặc `c < lvnAbove.lo`) **và** volume nến đó `> avgVol×1,15` (avgVol = trung bình volume 20 nến trước) **và** M5 có BOS/CHoCH cùng hướng → `dir` theo hướng phá, `model = "C"`.
- **Mô hình A (Buy tại POC/HVN):** `trend == up && atZone && (sweepLow || chochUp || bosUp)` → BUY, model A.
- **Mô hình B (Sell tại POC/HVN):** `trend == down && atZone && (sweepHigh || chochDown || bosDown)` → SELL, model B.
- Nếu không có mô hình nhưng có xu hướng: `dir` = hướng xu hướng (chỉ để tham khảo, không có Entry/SL/TP).
- **Entry = giá live** (khác với tín hiệu Swing dùng giá đóng H1).
- **SL:** BUY: `(sweepLow ? lastM5.l : swingLow15) − ATR(M15)×0,15`; mô hình C thì `lvnBelow.lo − ATR(M15)×0,15`. SELL đối xứng (đỉnh quét / swingHigh15 / `lvnAbove.hi + ATR×0,15`).
- **TP1:** BUY: `swingHigh15` nếu > entry, không thì HVN trên gần nhất, không thì `entry + ATR×2`. SELL đối xứng.
- **TP2:** BUY: HVN trên gần nhất, không thì VAH; nếu TP2 ≤ entry thì `entry + ATR×3`. SELL đối xứng (HVN dưới / VAL / `entry − ATR×3`).
- **RR = |TP2 − Entry| / |Entry − SL|**. Ghi rõ: SL/TP này theo cấu trúc giá, **khác công thức ATR của tab tín hiệu Swing**.

### 10.7. Quản trị vốn + tính lot — `vpCalcLot()` (dòng 3945–3961)

Quy tắc hiển thị: rủi ro **0,25–0,5%/lệnh**, RR tối thiểu 1:2, tối đa **3 lệnh/ngày**, thua liên tiếp **2 lệnh thì dừng**, tránh tin mạnh. Công thức lot (mặc định: vốn 10.000.000 VND, rủi ro 0,5%, SL 5 USD, tỷ giá 26.000):

```
riskVnd = vốn × pct/100 ;  riskUsd = riskVnd / tỷ giá ;  lot = riskUsd / (SL_USD × 100)   // 1 lot XAUUSD = 100 oz
```

Hiển thị: "Rủi ro tối đa: X đồng (≈ Y USD) · Với SL S USD → khối lượng ≈ Z lot (làm tròn xuống theo bước lot của sàn; chưa trừ phí và trượt giá)".

### 10.8. Các phần phụ khác của phase VolumeB/S

- **Cấu trúc 4 khung:** H4 Market Map (Supply/Demand = đỉnh/đáy 100 nến H4), H1 Trend Filter (Ichimoku, EMA20, POC), M15 Setup (HVN, LVN, VAH, VAL, Delta), M5 Execution (Sweep, CHoCH, BOS, Retest). Lookback cấu hình: H4 100, H1 200, M15 200, M5 200.
- **Quy trình 5 bước:** (1) xu hướng H1 bằng Ichimoku; (2) vùng VP M15 (POC/HVN/VAH/VAL/LVN); (3) chờ giá quay lại vùng; (4) xác nhận M5 (Sweep/CHoCH/BOS); (5) vào lệnh sau xác nhận, chỉ khi điểm ≥ 8.
- **Kế hoạch ngày:** bias ngày (Ichimoku H1), vùng chờ Buy (POC · VAL · HVN dưới), vùng chờ Sell (POC · VAH · HVN trên), điểm lọc hiện tại, tin mạnh vàng hôm nay (sự kiện High ảnh hưởng vàng trong ngày, từ lịch), giới hạn ngày.
- **Lộ trình TonyD VP PRO (ghi trong trang):** 1) Hoàn thiện VP → 2) Bộ lọc → 3) Cảnh báo BUY/SELL/WAIT → 4) Backtest XAUUSD M5/M15 → 5) Đánh giá Win Rate, Profit Factor, Drawdown, RR trước vốn thật.
- Render chi tiết VP **giới hạn 1 lần/1,5 giây** (`vpLastRender`) để tránh render dồn khi giá về liên tục.

---

## 11. CHIẾN LƯỢC AI — 3 CHIẾN LƯỢC (script 5, dòng 4194–4310)

`STRAT` ∈ `"swing" | "volumebs" | "ai"`; nhãn `STRAT_LABEL`: Swing = `"Swing M15/H1 · xác nhận H4"`, VolumeB/S = `"VolumeB/S — TonyD Volume Profile"`, AI = `"AI hợp nhất (Swing + VolumeB/S + MACD)"`. Đổi chiến lược → `recomputeAllSignals()` (tính lại toàn bộ: tín hiệu tĩnh, Trend, PA, điểm vào tối ưu, dải tín hiệu, Backtest mặc định theo chiến lược mới). **"AI" ở đây là suy luận xác định trong trang, không gọi LLM thật** — ghi rõ trong UI: "bộ suy luận xác định chạy ngay trong trang… trang chưa nối LLM thật và không tự vào lệnh".

### 11.1. Swing — `swingCore()` (§3.2)

Hướng theo EMA nhanh/chậm H1, xác nhận EMA H4, lọc RSI M15. SL/TP theo hệ số × ATR. Đây là chiến lược gốc và là **gốc** của chiến lược AI.

### 11.2. VolumeB/S — `vpCore(sym)` (dòng 1730–1769)

- Yêu cầu: H1 đã đóng ≥ 55, M15 ≥ 40; `computeProfile` + `computeIchimoku` phải sẵn sàng.
- `entry` = giá đóng H1 đã đóng gần nhất (giống Swing); `atr = ATR(H1, IND.atr)`.
- `trend` từ Ichimoku H1: trên mây → up, dưới mây → down, trong mây → neutral (fallback EMA nhanh/chậm H1).
- `nearPoc = |entry − POC| <= max(step×1,5, atr×0,6)`; `beyond = "up"` nếu `entry > VAH`, `"down"` nếu `entry < VAL`.
- Quyết định: `trend up && (nearPoc || beyond=="up")` → BUY, `baseConf = nearPoc ? 72 : 63`; `trend down` tương tự → SELL; có xu hướng nhưng không có vùng → WAIT, `baseConf = 52`; không có xu hướng → WAIT, `baseConf = 46`.
- Điều chỉnh Delta (profile M15): cùng hướng và `deltaPct > 2` (BUY) / `< −2` (SELL) → `baseConf = min(92, +4)`; ngược hướng mạnh (`deltaPct < −6` khi BUY / `> 6` khi SELL) → `baseConf = max(40, −6)` + lý do "Delta ước tính đang ngược hướng — trừ điểm".
- SL/TP: cùng công thức hệ số × ATR như Swing. Sau đó vẫn qua `finishSignal()` nên % cuối vẫn = 50% gốc + 25% Trend + 25% PA.

### 11.3. AI hợp nhất — `aiAdjustCore(sym, core)` (dòng 1770–1793)

Lấy core Swing làm gốc, rồi:

1. Gắn lý do đầu tiên: `"AI hợp nhất: Swing + VolumeB/S + MACD + Trend + PA"`.
2. Đối chiếu `vpCore()`: nếu Swing BUY mà VolumeB/S bias bearish (hoặc ngược lại) → **hạ về WAIT**, `sl = tp = null`, `baseConf = min(baseConf, 48)`, lý do "AI: VolumeB/S (Ichimoku + POC) ngược chiều Swing — hạ về WAIT chờ đồng thuận". Nếu đồng thuận và action != WAIT → `baseConf = min(95, +6)`, lý do "AI: VolumeB/S đồng thuận hướng … — cộng 6 điểm gốc".
3. Đối chiếu MACD H1 (`macdSeriesCalc`, §13): MACD line > signal → tăng, ngược lại giảm; nếu MACD ngược hướng tín hiệu → `baseConf = max(35, −4)`, kèm lý do ghi rõ thông số MACD.

### 11.4. Lưu lựa chọn chiến lược — `STRAT_STORE_KEY = "dgnStratV1"` (dòng 4271–4300)

- **Chọn là lưu ngay** vào localStorage (`saveStratChoice()` → `localStorage.setItem("dgnStratV1", STRAT)`); thông báo: `"✓ Đã LƯU lựa chọn … vào trình duyệt lúc HH:MM:SS — tải lại trang vẫn giữ đúng chiến lược này…"`. Nếu trình duyệt chặn lưu trữ → thông báo cảnh báo "⚠ … KHÔNG lưu được — tải lại trang sẽ quay về lựa chọn đã lưu trước đó".
- **Khôi phục khi tải lại** (`restoreStratChoice()` chạy ngay khi script 5 load): đọc key, nếu hợp lệ thì đặt `STRAT`, đồng bộ radio + ô "Chiến lược test" của Backtest (`#btStrat`), tính lại toàn bộ tín hiệu, hiện `"✓ Đã khôi phục chiến lược ĐÃ LƯU…"`. Chưa có bản lưu → dùng mặc định Swing + ghi chú "Chưa có lựa chọn nào được lưu…".
- Port Flutter: dùng storage bền tương đương (SharedPreferences / file JSON local), cùng hành vi "chọn là lưu ngay, mở app khôi phục".

---

## 12. BACKTEST (script 5, dòng 4440–4631)

### 12.1. Engine — `runBacktest()` / `btSignalAt()` (dòng 4495–4574)

- Chạy trên **đúng series nến thật mà biểu đồ đang tải** (Kraken/Binance/OKX, tối đa ~300 nến; **không** dùng dữ liệu giả lập riêng).
- Chọn: cặp (`#btSym`, mặc định XAUUSD), khung tín hiệu (`#btTf`: M15 / H1 mặc định / H4), khoảng test (`#btRange`: 120 / 200 mặc định / 280 nến), chiến lược test (`#btStrat`: swing / volumebs / ai — đồng bộ với `STRAT` hiện tại).
- Yêu cầu: tổng nến đã tải ≥ **90 nến** (ít hơn → báo "Chưa đủ nến … (cần tối thiểu ~90 nến). Hãy thử khung khác hoặc chờ tải xong."). Chỉ test trên **nến đã đóng** (`closed = cs.slice(0, length−1)`); điểm bắt đầu `startI = max(80, closed.length − range)`.
- Logic vào/ra tại mỗi nến đã đóng `i` (`btSignalAt(cs, i, strat)`):
  - Tính EMA nhanh/chậm + ATR + RSI trên `cs.slice(0, i+1)` (dùng đúng `IND` hiện tại).
  - Swing: `eF > eS && (rsi==null || rsi < 78)` → BUY; `eF < eS && (rsi==null || rsi > 22)` → SELL. **Lưu ý: backtest Swing KHÔNG dùng bias H4** (khác tín hiệu live §3.2 — chỉ EMA khung test + RSI).
  - VolumeB/S: profile M15-style trên chính series khung test (`computeProfile(sub.slice(-200), 24)`), Ichimoku trên `sub.slice(-220)`; vào khi trend Ichimoku cùng hướng và (gần POC `|entry−POC| <= max(step×1,5, atr×0,6)` hoặc phá VAH/VAL).
  - AI: như Swing, rồi **loại tín hiệu** nếu MACD khung test ngược hướng (line vs signal) hoặc Ichimoku ngược hướng (BUY mà dưới mây / SELL mà trên mây).
  - Entry = giá đóng nến `i`; SL/TP = hệ số × ATR (giống §3.3).
- Lệnh đóng: duyệt các nến sau `i+1 … min(length−1, i+120)`; **nếu một nến chạm cả SL lẫn TP thì tính SL trước** (giả định thận trọng); BUY chạm SL khi `l <= SL`, chạm TP khi `h >= TP` (SELL ngược lại). **Tối đa giữ 120 nến** rồi đóng theo giá đóng nến hết hạn (`note = "Đóng hết hạn giữ (120 nến)"`).
- Sau khi đóng 1 lệnh: `i = exitIdx + 1` (không vào lệnh chồng lên nhau; lệnh tiếp theo chỉ xét từ nến sau nến đóng).
- `R` mỗi lệnh = `(exit − entry)/|entry − SL|` theo hướng (BUY: `(exit−entry)/dist`; SELL: `(entry−exit)/dist`); `result = "win"` nếu `r > 0` (kể cả lệnh đóng hết hạn có lãi), ngược lại `"loss"`. **Không tính phí và trượt giá.**

### 12.2. Chỉ số đầu ra — `renderBacktest()` (dòng 4575–4630)

- Thẻ "Kết quả": số lệnh test, Thắng/Thua, **Win rate %**, Tổng kết quả (±R, 2 số lẻ).
- Thẻ "Chất lượng hệ thống": **Profit factor** = ΣR thắng / Σ|R thua| (không có lệnh thua mà có R thắng → `"∞"`; không có R thắng → `"—"`); **RR thực tế TB** = R thắng TB / |R thua TB| (dạng `1 : X,XX`); **R trung bình/lệnh**; **Max drawdown (theo R)** = độ sụt equity (tích lũy R) lớn nhất từ đỉnh (peak-to-trough).
- Thẻ "Thông số đã dùng": tên phương pháp, chiến lược engine chạy, EMA nhanh/chậm, MACD · RSI · ATR, SL/TP (×ATR), dữ liệu (số nến đã đóng dùng + nguồn nến).
- Danh sách lệnh test: tối đa **80 lệnh gần nhất** (mới nhất lên đầu), mỗi lệnh: cặp, hướng, WIN/LOSS ±R, giờ mở (`vnDateTime`), Entry/SL/TP, giá đóng + giờ đóng + ghi chú (Chạm TP / Chạm SL / Đóng hết hạn giữ). Nếu 0 lệnh → thẻ "Chiến lược không sinh lệnh nào trong khoảng đã chọn — thử khoảng dài hơn…".
- Ghi chú bắt buộc hiển thị: **"Kết quả quá khứ không đảm bảo kết quả tương lai"** (cả trong `.bt-note` tĩnh và cuối `btListMeta`).

### 12.3. Khung nhập phương pháp giao dịch — `BT_METHOD_KEY = "dgnBtMethodV1"` (dòng 4440–4494)

- 2 ô: **Tên phương pháp** (`#btMethodName`, placeholder `"VD: Swing H1 theo EMA + retest POC"`) + **Mô tả/quy tắc** (`#btMethodDesc`, textarea 4 dòng, placeholder ví dụ quy tắc đầy đủ).
- Nút **"Lưu phương pháp"** → lưu `{name, desc, strat}` vào localStorage key `dgnBtMethodV1`; tải lại trang khôi phục cả 2 ô + thông báo đã khôi phục. Lưu thất bại (trình duyệt chặn) → báo rõ không lưu được.
- Chọn 1 trong 3 chiến lược ở ô "Chiến lược test" → **ô tên tự điền tên chiến lược đó**; nếu ô mô tả đang trống thì tự điền mô tả mặc định của chiến lược đó (`BT_STRAT_DESC`).
- **Tên phương pháp hiện rõ trên thẻ kết quả backtest** (thẻ "Thông số đã dùng" + dòng trạng thái + `btListMeta`). Nếu tên do người dùng tự đặt (khác cả 3 tên chiến lược có sẵn) → ghi thêm `"(tên do bạn tự đặt)"` và dòng: "Tên phương pháp do bạn tự đặt/ghi — engine vẫn chạy theo chiến lược … đã chọn".
- **Trung thực bắt buộc:** trang **chưa tự chuyển được văn bản tự do thành quy tắc chạy được** — engine vẫn chạy theo chiến lược đã chọn ở ô "Chiến lược test" cùng thông số chỉ báo hiện tại; phần tự viết chỉ là **tên + ghi chú quy tắc** để đối chiếu. Phải ghi rõ điều này trong UI (đã có sẵn trong web) và giữ nguyên khi port.

---

## 13. CHỈ BÁO + THÔNG SỐ TÙY CHỈNH

### 13.1. Giá trị mặc định — `IND_DEFAULT` / `IND` (dòng ~1566)

| Tham số | Mặc định | Giới hạn nhập (min–max) | Dùng ở đâu |
|---|---|---|---|
| EMA nhanh `emaFast` | 20 | 2–400 | Tín hiệu H1/H4, Trend, chart |
| EMA chậm `emaSlow` | 50 | 3–400 | Tín hiệu H1/H4, Trend, chart |
| EMA giữa `ema34` | 34 | 2–400 | Chart + Trend (giá so với EMA34) |
| EMA dài hạn `ema200` | 200 | 10–400 | **Chỉ lưu trữ — web không dùng trong bất kỳ công thức hay hình vẽ nào** (xem §13.4) |
| MACD nhanh `macdF` | 34 | 2–200 | MACD |
| MACD chậm `macdS` | 58 | 3–300 | MACD |
| MACD signal `macdSig` | 12 | 2–100 | MACD |
| RSI chart `rsiChart` | 9 | 2–50 | Chart RSI panel + Trend (RSI9) |
| RSI tín hiệu `rsiSig` | 14 | 2–50 | Lọc tín hiệu (M15) + Phân tích |
| ATR `atr` | 14 | 2–60 | ATR(H1) cho SL/TP, PA Retest, VolumeB/S |
| Hệ số SL `slMult` | 1,5 | 0,3–6 (bước 0,1) | SL = hệ số × ATR |
| Hệ số TP `tpMult` | 3 | 0,5–12 (bước 0,1) | TP = hệ số × ATR; **RR = tpMult/slMult** |
| Bollinger chu kỳ `bbP` | 20 | 5–100 | **Chỉ lưu trữ — web không vẽ/không tính Bollinger** (xem §13.4) |
| Bollinger độ lệch `bbM` | 2 | 0,5–5 (bước 0,1) | **Chỉ lưu trữ** (như trên) |

### 13.2. Công thức từng chỉ báo

- **EMA** — `emaLast(values, period)` (dòng 1535–1543) và `emaSeries(candles, period)` (dòng 2156–2165): hạt giống = SMA của `period` giá đầu tiên (tại index `period−1`); sau đó `e = price × k + e × (1−k)`, `k = 2/(period+1)`. Cần `values.length >= period`, ngược lại `null`.
- **RSI** — `rsiLast(values, period)` (dòng 1544–1555) và `rsiSeriesCalc(candles, period)` (dòng 2307–2319): **trung bình đơn giản** (không phải Wilder smoothing): `gain = Σ max(d,0)`, `loss = Σ max(−d,0)` trên `period` chênh lệch gần nhất; `loss == 0 → 100`; `rs = (gain/period)/(loss/period)`; `RSI = 100 − 100/(1+rs)`. Yêu cầu `length >= period+1` (rsiLast) / bắt đầu từ index `period` (rsiSeriesCalc).
- **ATR** — `atrLast(candles, period)` (dòng 1556–1565): trung bình đơn giản của True Range `max(h−l, |h−prevClose|, |l−prevClose|)` trên `period` nến gần nhất; yêu cầu `length >= period+1`.
- **MACD** — `macdSeriesCalc(candles)` (dòng 2297–2306): `line = EMA(macdF) − EMA(macdS)`; `signal = EMA(line, macdSig)` tính trên các giá trị line hợp lệ (bỏ null đầu); `hist = line − signal`. Yêu cầu hiển thị: "Chưa đủ nến cho MACD — cần trên `macdS + macdSig + 2` nến".
- **Chart vẽ:** EMA nhanh màu vàng `#f0b90b`, EMA chậm xanh dương `#4da3ff`, EMA34 cam `#ff7a1a` (vẽ trên toàn bộ series nến, cắt theo cửa sổ hiển thị). MACD panel: đường MACD xanh `#4da3ff`, Signal cam `#ff7a1a`, Histogram xanh lá/đỏ mờ theo dấu. RSI panel: đường xanh `#4da3ff`, đường 70/30 vàng đứt nét `[5,4]`, nhãn "Quá mua 70 · Quá bán 30", trạng thái "Quá mua / Quá bán / Trung tính".

### 13.3. Áp dụng / Khôi phục — `IND_STORE_KEY = "dgnIndSettingsV1"` (dòng 4302–4363)

- Form 14 ô nhập (`#indEmaFast` … `#indBbM`). Nút **"Áp dụng & tính lại"**: đọc form (số nguyên làm tròn + clamp vào min–max; số thập phân clamp không làm tròn), điền lại form bằng giá trị đã clamp, cập nhật nhãn chart (EMA/MACD/RSI), `recomputeAllSignals()` (chart + tín hiệu + Trend + Backtest tính lại), lưu **toàn bộ `IND` dạng JSON** vào localStorage key `dgnIndSettingsV1`. Thông báo thành công kèm giờ lưu + `RR kế hoạch = 1 : (tpMult/slMult)`; thất bại lưu trữ → cảnh báo "⚠ Đã áp dụng trong phiên… KHÔNG lưu được".
- Nút **"Khôi phục mặc định"**: reset `IND = IND_DEFAULT`, **xóa key localStorage**, điền lại form, tính lại toàn bộ.
- Khi tải trang: `loadIndSettings()` đọc key (chỉ nhận các key có trong `IND_DEFAULT` và là số hữu hạn), điền form + cập nhật nhãn; nếu có bản lưu → thông báo "Đang dùng thông số ĐÃ LƯU trong trình duyệt — tải lại trang vẫn giữ nguyên…".
- Nút "⚙ Thông số chỉ báo" trên toolbar chart → chuyển sang tab Chiến lược AI và cuộn tới thẻ cài đặt.

### 13.4. ⚠️ Hai thông số "chết" — phải ghi rõ khi port

- **`ema200` và `bbP`/`bbM` (Bollinger) chỉ tồn tại trong `IND` + form nhập + lưu trữ; không có bất kỳ hàm nào trong web dùng chúng để tính toán hay vẽ.** Không có dải Bollinger trên chart, không có EMA200 trên chart. Khi port, hoặc giữ nguyên hành vi (lưu trữ + hiển thị trong form, không dùng), hoặc — nếu muốn dùng thật — phải hỏi lại người dùng, **không tự ý bịa công thức Bollinger/EMA200 vào tín hiệu**.

### 13.5. Công cụ vẽ tay + xem quá khứ trên chart (để port đủ)

- Công cụ (toolbar): Chọn (cursor) / Trendline / Đường ngang / Fibonacci / Vùng hộp / Chữ + ô nhập ghi chú (tối đa 40 ký tự) + "Xoá hết hình vẽ" (chỉ xóa của cặp+khung hiện tại). Vẽ bằng 2 lần bấm (điểm đầu → điểm cuối), riêng đường ngang/chữ chỉ 1 lần bấm. Fibonacci vẽ 5 mức `0 / 0,382 / 0,5 / 0,618 / 1` giữa 2 điểm. Hình vẽ lưu theo key `"SYM|TF"`, chỉ trong bộ nhớ trang.
- Xem quá khứ: kéo ngang trên chart ở chế độ Chọn (tính theo `cw` = chiều rộng/nến), hoặc nút `◀◀ Lùi 16 nến`, `◀ 1 nến`, `1 nến ▶`, `16 nến ▶▶`, `Về hiện tại (Live)`. `state.pan` = số nến lùi, tối đa `candles.length − 20`; chart hiện **64 nến** (`endIdx = length − pan`, `visible = slice(endIdx−64, endIdx)`); trạng thái "Đang xem QUÁ KHỨ — lùi N nến so với hiện tại". Khi đang xem quá khứ, MACD/RSI panel hiện giá trị **tại nến đang xem** (kèm chú thích "(tại nến đang xem)").
- Mũi tên tín hiệu: BUY = tam giác xanh hướng lên dưới đáy nến tín hiệu, SELL = tam giác đỏ hướng xuống trên đỉnh nến; vị trí nến tín hiệu `sigIdx = visible.length − 22` (tối thiểu 2). Trục giá phải 64px, lưới 6 mức, nhãn thời gian mỗi 12 nến (D1: `DD/MM`, còn lại `HH:MM`). Canvas cao 430px (mobile ≤640px: 340px).

---

## 14. TIN TỨC LIVE + LỊCH KINH TẾ

### 14.1. Tin tức LIVE — `fetchLiveNews()` / `newsScanTick()` (dòng 3071–3166)

- **Nguồn:** FXStreet RSS: `https://www.fxstreet.com/rss/news`.
- **Đường lấy (thử lần lượt):**
  1. `https://api.rss2json.com/v1/api.json?rss_url=<encodeURIComponent(rss)>` — yêu cầu `status == "ok"` và `items` không rỗng; map `title/link/pubDate/description` (description strip HTML, cắt 300 ký tự; `pubDate` dạng `"2026-11-16 04:04:15"` được chuẩn hóa thành ISO `…T…Z`).
  2. Dự phòng: `https://api.allorigins.win/raw?url=<encodeURIComponent(rss)>` — parse XML gốc bằng DOMParser, lấy các `<item>` (`title/link/pubDate/description`).
- **Tần suất quét: 1 giây** — ticker `setInterval(newsScanTick, 1000)`. Mỗi tick: nếu đang fetch thì bỏ qua; nếu chưa tới lúc (`now − lastAttempt < delay`) thì bỏ qua; ngược lại ghi `lastAttempt = now`, `lastScanAt = now`, gọi `fetchLiveNews()`.
- **Cơ chế giãn nhịp khi lỗi** — `newsScanDelay() = failCount <= 0 ? 1000 : min(60000, 1000 × 2^failCount)` (ms): 1s → 2s → 4s → 8s → … → tối đa 60s. Thành công 1 lần → `failCount = 0` (quay về 1 giây). Trạng thái hiển thị: `"Quét gần nhất: HH:MM:SS (giờ VN) · Trạng thái: Đang quét mỗi 1 giây / Đang quét nguồn tin… / Nguồn lỗi — đã giãn nhịp quét, lần quét sau sau ~N giây"` + chấm xanh/đỏ nhấp nháy 1 giây (`scanPulse`).
- **So trùng tin:** key = `url + "|" + title` (`newsKeyOf`); chỉ thay danh sách + render lại khi key tổng của 30 tin mới **khác** key tổng cũ (quét 1 giây mà không có tin mới thì giữ nguyên DOM, không nhấp nháy). Tối đa **30 tin**.
- **Nhãn:** live thành công → `"● LIVE — tin lấy trực tiếp từ FXStreet RSS, dữ liệu mới nhất lấy lúc HH:MM:SS (giờ VN). Trang quét lại nguồn mỗi 1 giây và chỉ thay danh sách khi có tin mới… Nguồn RSS thực tế thường chỉ có tin mới theo phút — quét 1 giây chủ yếu là kiểm tra lại."` Lỗi (đã từng live) → `"CHƯA LẤY ĐƯỢC TIN LIVE ở lần quét gần nhất … Danh sách dưới đây là tin live đã lấy được lúc HH:MM:SS — có thể đã cũ…"`. Chưa từng live → `"CHƯA LẤY ĐƯỢC TIN LIVE — danh sách dưới đây là snapshot tin ngày 16/11/2026…"`.
- **Snapshot dự phòng `NEWS_SNAP`:** ~22 tin FXStreet ngày 13–16/11/2026 (mỗi tin `{t, u, d, s}`: tiêu đề, link gốc, ngày GMT, tóm tắt). Luôn ghi rõ là snapshot khi dùng.
- **Tag tác động với vàng — `goldImpact(n)` (từ khóa trong tiêu đề + tóm tắt, chữ thường):**
  - Tiêu cực (`neg`): `rate hike, hawkish, stronger dollar, dollar strengthens, dollar holds gains, yields rise, higher yields, supports usd, support usd, firm dollar, strong dollar`.
  - Tích cực (`pos`): `rate cut, safe-haven, safe haven, weaker dollar, dollar falls, dollar declines, dovish, easing bets, gold rises, gold gains, gold climbs, gold surges`.
  - Cả hai hoặc không có → trung tính (`neu`). Hiển thị: "Tích cực cho vàng" (xanh) / "Tiêu cực cho vàng" (đỏ) / "Trung tính" (xám).
- **Lọc tin:** chip `Tất cả, gold, XAU, Federal Reserve, inflation, dollar, DXY, treasury yield` — lọc theo chuỗi con (không phân biệt hoa thường) trong tiêu đề + tóm tắt. Mỗi tin hiển thị: tiêu đề (link mở bài gốc tab mới), `FXStreet · DD/MM HH:MM (giờ VN) · <tag>`, tóm tắt cắt **180 ký tự** + "…".

### 14.2. Lịch kinh tế — `renderCalendar()` / `checkNewsAlert()` (dòng 2925–3018)

- **Nguồn trực tiếp:** `https://nfs.faireconomy.media/ff_calendar_thisweek.json` (ForexFactory). Map: `title→t, country→c, date→d, impact→i, forecast→f, previous→p, actual→a`. Thành công → `calLive = true`.
- **Dự phòng `CAL_SNAP`:** snapshot lịch tuần lấy từ ForexFactory **trưa 16/11/2026 (giờ VN)**, ~130 sự kiện từ 15/11 đến 20/11/2026 (mỗi sự kiện `{t, c, d, i, f, p, a}`; `d` có offset `-05:00`). Nhãn: `"Snapshot lịch tuần lấy từ ForexFactory trưa ngày 16/11/2026 (giờ VN) — trang có thử tải bản trực tiếp khi mở, không được thì dùng snapshot này."` / khi live: `"Đang dùng lịch trực tiếp từ ForexFactory."`
- **Hiển thị:** giờ VN (`vnTime`, múi giờ Asia/Ho_Chi_Minh); nhóm theo ngày (tiêu đề ngày `Thứ…, DD/MM/YYYY`); mỗi dòng: giờ, mã nước, tên sự kiện, mức độ (High đỏ / Medium vàng / Low xám), Dự báo / Thực tế / Kỳ trước (thiếu → `"—"`).
- **Tin vàng — `isGoldEvent(e)`:** `c == "USD"` và tên khớp regex `/cpi|ppi|gdp|nonfarm|non-farm|payroll|fomc|federal funds|fed chair|powell|speaks/i` → viền đỏ (`gold-ev`) + tag `TIN VÀNG`. (Nói chung "CPI, NFP, FOMC, PPI, GDP Mỹ, phát biểu Fed".)
- **Bộ lọc:** ngày: Hôm nay (mặc định) / Cả tuần; mức độ: Mọi mức độ (mặc định) / High / Medium / Low / Chỉ tin vàng.
- **Cảnh báo tin mạnh — `checkNewsAlert()` (mỗi 30 giây):** tìm sự kiện vàng mức High có `0 < (t − now) <= 15 phút` → hiện banner đỏ `#newsAlert`: `"Sắp có tin mạnh ảnh hưởng vàng: <tên> (<nước>) lúc HH:MM — còn N phút. Cân nhắc đóng lệnh hoặc giảm rủi ro."` Không có → ẩn banner.

---

## 15. LỊCH SỬ + TỔNG TOÀN PHIÊN — `histEntries` (dòng 3210–3383)

### 15.1. Ghi tín hiệu — `histTrack()` (chạy mỗi 3 giây)

- Mỗi khi một cặp **đổi sang BUY/SELL** (so với `lastAction[sym]`): mở một bản ghi mới (unshift lên đầu danh sách). Nếu cặp đang có lệnh mở mà hướng đổi → **đóng lệnh cũ trước** bằng `closeHistEntry` với ghi chú hủy sớm (xem §15.2), rồi mới mở bản ghi mới.
- Các trường mỗi bản ghi: `id` (tăng dần), `symbol`, `action`, `entry` (tĩnh), `sl`, `tp`, `atr`, `openAt` (giờ mở bản ghi), `status` (`open`/`closed`), `result` (`win`/`loss`/null), `exit`, `exitAt`, `realizedR`, `note`, `startAt` (= `closedAt` của tín hiệu), `planStop` (= `closedAt + 1 giờ`), `strategy` (STRAT lúc mở), `conf` (% tin cậy lúc mở), `rr`, `levels` (thang Inv/T1–T4), `tiers` (T1–T4 `{hit, at, price}`), `invHit`, `openPrice` (giá live lúc mở), `simDiff/simDiffPips/simDiffPct` (§8.3).
- **Chỉ giữ trong phiên đang mở trang** — đóng trang là danh sách trống lại. Không đồng bộ, không lưu trữ bền.

### 15.2. Đóng lệnh — `closeHistEntry()` / `histCheckOutcomes()`

- **Chạm TP/SL:** kiểm tra giá live mỗi 3 giây: BUY chạm TP khi `price >= TP`, chạm SL khi `price <= SL` (SELL ngược lại). Đóng tại đúng giá TP/SL, `note = "Chạm TP"` / `"Chạm SL"`, `result = "win"` nếu TP, `"loss"` nếu SL.
- **Hủy sớm (đảo chiều):** đóng tại giá live lúc đảo chiều, `result = "win"` nếu `r >= 0` (cắt lãi) ngược lại `"loss"`; `note` dạng: `"Đảo chiều — HỦY LỆNH SỚM, cắt tại giá <giá> · +/−X,X pip (+/−X,XX% so với Entry <entry>; SL gốc <sl>)"`.
- **`realizedR`:** `dist = |entry − SL|`; `realizedR = (BUY ? exit−entry : entry−exit) / dist`. Thắng đủ TP = `+RR kế hoạch` R; thua đủ SL = `−1R`; hủy sớm = R thực tế lúc đóng (có thể là số lẻ, âm hoặc dương). Kèm `exitPips` (= chênh lệch giá / pipSize) và `exitPct` (= chênh lệch / entry × 100).
- Khi đóng do chạm TP: nếu T4 chưa ghi chạm thì ghi `tiers.T4 = {hit: true, at: exitAt, price: TP}`. Khi đóng do chạm SL: ghi `invHit = {at: exitAt, price: SL}`.

### 15.3. Thẻ TỔNG TOÀN PHIÊN + thống kê theo cặp — `renderHistory()`

Tính từ các tín hiệu **đã đóng trong phiên** (`status == "closed"`):

| Chỉ số | Công thức |
|---|---|
| Tín hiệu đã đóng | đếm `closed` |
| Win rate | `round(wins/closed × 100)%` + `(wins thắng / losses thua)` |
| Profit factor | `Σ max(0, R) / Σ \|min(0, R)\|`; không có lệnh thua mà có R thắng → `"∞"`; không có R thắng → `"—"` |
| RR thực tế TB | `R thắng TB / \|R thua TB\|`, dạng `1 : X,XX`; thiếu một phía → `"—"` |
| R trung bình / tín hiệu | `ΣR / số lệnh đóng` (dấu +/−, 2 số lẻ) |
| Tổng R | `ΣR` (dấu +/−, 2 số lẻ) |
| Đang mở | đếm `status == "open"` (hiện ở tiêu đề thẻ) |

- **Chưa có lệnh đóng → Win rate hiện `"—"`** và ghi chú: "Chưa có tín hiệu nào đóng trong phiên này — bảng winrate sẽ tự cập nhật ngay khi có lệnh chạm TP/SL hoặc hủy sớm". Thẻ tổng có viền vàng để phân biệt.
- Bảng theo cặp: 8 thẻ (mỗi cặp 1 thẻ) với cùng các chỉ số trên; cặp chưa có lệnh đóng → Win rate `"—"` + "Chưa có tín hiệu đóng để tính hiệu suất".
- Bộ lọc danh sách: cặp (Tất cả/8 cặp), ngày (Mọi ngày/Hôm nay), kết quả (Tất cả/Đang mở/Win/Loss). Mỗi dòng lịch sử hiện: cặp + hướng + badge ĐANG MỞ/WIN ±R/LOSS ±R + chiến lược lúc phát + % tin cậy lúc phát + giờ mở; chi tiết Entry/SL/TP; thang Inv/T1–T4 + trạng thái chạm từng tầng + Chênh mở phòng; khi đóng: giá đóng + giờ đóng + pip/% + ghi chú; khi mở: giờ lên tín hiệu + giờ dừng dự kiến (nến H1 đóng tiếp theo) hoặc "Đang chờ giá chạm TP/SL hoặc đảo chiều hủy sớm".

---

## 16. GIAO DIỆN

### 16.1. Tông màu — `:root` (dòng 13–20)

```
--bg:#edf1f8 · --bg2:#f3f5fa · --panel:#ffffff · --panel2:#edf2fa
--line:#d7e0ef · --line2:#a9bcdc
--txt (chữ chính, navy đậm): #0a1e42 · --mut:#46587a · --mut2:#68799c
--up (xanh lá): #0da271 · --dn (đỏ): #e0334e
--gold (vàng cam): #d97e06 · --blue:#2f7bff · --org (cam): #ff7d1f
Nền body: gradient trắng → #f3f6fb (340px) → #edf2f8; thẻ trắng, bo 18px, bóng rgba(10,30,66,.07)
Nút chính/tab active: gradient xanh #1f6bff → #2f8bff, chữ trắng
Nút Theo dõi: gradient cam #ff8a1e → #ff6a00
PANIC STOP: nền #d61f38, viền #ff8fa0
```

Font: `Be Vietnam Pro` cho chữ thường, `JetBrains Mono` cho số/giá (class `.mono`, tabular-nums).

### 16.2. Intro (dòng 493–495, 3969–4040)

- Toàn màn hình, nền gradient trắng → `#edf3fb`, **chỉ chạy logo DGN nguyên khối** (1 ảnh, không cắt mảnh — bản cắt 4 mảnh cũ đã bỏ vì lệch nhau, tạo khe trắng/mép gãy).
- Animation CSS `introLogoIn` 1,5s: `opacity 0 → 1`, `scale(.86) → 1,015 → 1`, `translateY(14px) → 0`, `drop-shadow(0 14px 30px rgba(10,58,168,.22))`; logo rộng `min(300px, 72vw)`.
- Tự ẩn sau **2.000 ms** (fade 0,45s), gỡ khỏi DOM sau 2.600 ms; **chạm vào là bỏ qua ngay**. `prefers-reduced-motion`: ẩn sau 400 ms, không animation.
- **Chime trong trẻo (Web Audio API, không file nhạc):** 8 nốt sine: 987,77 Hz @+0,10s (0,16s), 1174,66 @+0,27s, 1318,51 @+0,44s, 1567,98 @+0,61s (0,20s), rồi hợp âm 1567,98 @+1,12s (0,50s), 1975,53 @+1,24s, 2349,32 @+1,36s, 3135,96 @+1,50s (0,85s); volume 0,03–0,06, attack 0,02s, decay exponential. Trình duyệt chặn tự phát → chime phát ở **lần chạm đầu tiên** (listener `pointerdown` một lần). Nút "Âm thanh: Bật/Tắt" trên statusbar đồng bộ; bật lại thì phát thử chime ngắn (4 nốt cuối).
- Port Flutter: intro ~2s + âm chime tương đương (tổng hợp bằng code, không cần file nhạc ngoài); nếu không làm được tiếng thì **báo rõ là chưa có tiếng**, không giả vờ có.

### 16.3. Hero Trang chủ (dòng 516–575)

- Panel navy: gradient `150deg, #123a7d → #081f49 (55%) → #051633`, thêm 2 vệt sáng radial (xanh `#2f8cff` góc trên phải, cam `#ff7d1f` góc dưới trái), bo 22px, bóng `rgba(5,22,51,.28)`.
- Trái: logo DGN 66×66px + chữ **"DGN"** trắng 31px/800 + khẩu hiệu **`Trade Signals Smarter. Faster.`** (chữ "Smarter. Faster." màu `#b9cdf2`) + gạch cam gradient `#ff8a1e→#ffb347` (44×4px) + khối founder: viền trái cam 3px, dòng nhỏ "Our founder" + **`DGN`** trắng 19px + dòng phụ: "TradeSignal AI · Tín hiệu 8 cặp theo giá live thật, chốt tĩnh theo nến đóng · đổi chiến lược & backtest ở mục Chiến lược AI / Backtest".
- Phải: **ảnh CEO** (người áo vest navy có logo DGN) đứng trực tiếp trên nền hero, **không khung ảnh**, cao 100% hero, `max-width: 46vw` (mobile 48vw), `object-position: center top`, mép trái mờ dần bằng mask `linear-gradient(90deg, transparent 0, #000 26%)`.
- Dải thống kê 3 ô (nền trắng): **(1)** Tỷ lệ thắng (từ lịch sử phiên, chưa có lệnh đóng → `"—"`), **(2)** Tín hiệu đã ghi · đang mở N, **(3)** Cặp đang có giá live `N/8`. Chú thích: "Ba con số trên được tính trực tiếp từ lịch sử tín hiệu trang ghi được trong phiên đang mở và nguồn giá live hiện tại — đóng trang là tính lại từ đầu."

### 16.4. Thẻ tín hiệu nổi bật + dải tín hiệu ngang

- **Thẻ nổi bật (`#featCard`):** lấy từ `strongestSignal()` — tín hiệu BUY/SELL có **độ tin cậy cao nhất** trong 8 cặp (WAIT không tính; chưa có → "Đang quét 8 cặp…" + "Chưa có tín hiệu BUY/SELL đủ mạnh lúc này…"). Hiện: cặp (dạng `XAU/USD`), badge Long (cam) / Short (đỏ), Entry / TP (xanh) / SL (đỏ), % giá live so với Entry (xanh/đỏ, ô gradient xanh lá hoặc đỏ), trạng thái `"✓ Đã chốt tín hiệu tĩnh"`, meta: giờ lên tín hiệu (nến H1 đã đóng) + giờ dừng ngắn + độ tin cậy + RR + tên chiến lược. Nút "Xem chi tiết tín hiệu →" → chọn cặp + sang tab Tín hiệu.
- **⛔ TUYỆT ĐỐI KHÔNG dùng số minh họa của mockup:** không dùng `+72,5%`, `+2380`, `128K+`, `BTC 68.542 → 70.200` hay bất kỳ số minh họa nào khác. Mọi con số trên hero/thẻ nổi bật/thống kê đều phải tính từ dữ liệu thật đang chạy (tín hiệu mạnh nhất thật, lịch sử phiên, số cặp có giá live).
- **Dải tín hiệu ngang Trang chủ (`#homeRail`) và mục Chiến lược AI (`#stratRail`):** cùng một HTML, render lại mỗi 2,5 giây (giữ nguyên `scrollLeft`). Sắp xếp: tín hiệu BUY/SELL trước (theo độ tin cậy giảm dần), WAIT sau; thẻ mạnh nhất có viền vàng + tag `★ NỔI BẬT`. Mỗi thẻ (rộng 248px, cuộn ngang, snap): cặp + hướng + % tin cậy (gốc/Trend/PA) + Entry/SL/TP + RR + chiến lược + giờ lên + giờ dừng ngắn. Bấm thẻ → chọn cặp + sang tab Tín hiệu.

### 16.5. Phase Tín hiệu — bố cục

- **Thẻ tín hiệu 8 cặp nằm trên cùng** (`#sigList`): mỗi thẻ có cặp, hướng, Entry/SL/TP tĩnh + RR + thang Inv/T1–T4 + % tin cậy + dòng điểm (Gốc/Trend/PA) + điểm vào tối ưu + giờ lên/dừng + 2 lý do đầu + dòng "Lệnh trước hủy sớm…" (nếu có). Bấm thẻ → chọn cặp đó.
- **Panel tín hiệu cặp đang chọn (`#sigPanel`):** badge hướng, cặp + tên, chip chiến lược + nguồn giá, tag `TÍN HIỆU TĨNH — chốt khi nến đóng`, thanh % tin cậy; lưới KV: Entry (đã chốt tĩnh) / SL đỏ / TP xanh / RR / Bias (H4) / ATR (H1) thật / Lên tín hiệu lúc / Dừng tín hiệu; thang TP (§8); lý do (chip); **bảng phân tích điểm + điểm vào tối ưu**; **Trend đa khung + gauge**; meta dòng ghi công thức SL/TP + chiến lược; khung đỏ hủy sớm (nếu có); nút "＋ Theo dõi cặp này" (cam; đang theo dõi → vàng "✓ Đang theo dõi … — bấm để bỏ theo dõi", đồng thời chấm vàng trên pair-strip).
- **Thu gọn mặc định (nút Ẩn/Hiện, `initCollapses`, dòng 4365–4451):** bảng điểm + điểm vào tối ưu gom trong 1 khối ẩn sau nút "Hiện chi tiết điểm & điểm vào tối ưu"; Trend + gauge ẩn sau nút "Hiện Trend đa khung & gauge cộng hưởng"; danh sách lịch sử chi tiết ẩn sau nút "Hiện danh sách tín hiệu chi tiết". **Không còn khối phân tích nào hiển thị sẵn ngoài nút Ẩn/Hiện trong phase Tín hiệu** (2 khối độc lập cũ "Price Action — XAUUSD" và "Thư viện mẫu hình nến" đã gỡ).
- **Phân tích chi tiết theo từng cặp (`#pairAnalysisList`):** 8 khối, mỗi cặp 1 nút `Hiện phân tích ▼` / `Ẩn phân tích ▲` riêng; **mặc định thu gọn**; trạng thái mở/đóng từng cặp nhớ trong phiên (`pairOpenState`, biến bộ nhớ — tải lại trang reset hết về thu gọn); render lại mỗi 6 giây khi đang ở tab signals (chỉ khi đang mở). Nội dung mỗi khối (tính bằng đúng hàm theo cặp đã có): Trend đa khung + đếm cộng hưởng + điểm Trend; Price Action (tóm tắt Cơ bản/Nâng cao + điểm PA + tối đa 6 mẫu có hướng); Mẫu hình nến (top 6 mẫu có số lần > 0 trên khung đang chọn); VolumeB/S quét (kết luận + điểm /5 + POC/VAH/VAL + Delta + H1); Bảng điểm + điểm vào tối ưu (tóm tắt).
- **Thẻ "Tín hiệu mạnh nhất lúc này"** (`#strongestCard`, viền vàng): cặp + hướng + độ tin cậy + Entry/SL/TP + lý do + nút "Xem trên biểu đồ →".
- **Khối "Quy tắc Swing đang áp dụng":** liệt kê toàn bộ quy tắc (§3–§8) bằng chữ — port nguyên văn ý (không cần copy từng câu chữ, nhưng phải đủ các quy tắc).

### 16.6. Phase Phân tích — CHỈ 3 khối (nhận định, không phải dữ liệu thật)

1. **Nhận định vĩ mô:** sức mạnh USD suy từ % 24h của 5 cặp forex: `usdParts = [−chg(EURUSD), −chg(GBPUSD), +chg(USDJPY), +chg(USDCAD), +chg(USDCHF)]`, trung bình → `> +0,15%` = "USD mạnh", `< −0,15%` = "USD yếu", còn lại "đi ngang"; + nhận định vàng (giá live + bias H4), BTC/khẩu vị rủi ro, dầu WTI, sự kiện High 24h tới (tối đa 6, từ lịch), tổng hợp. **Ghi rõ: "NHẬN ĐỊNH được suy luận ngay trong trang từ giá live thật… không phải sự thật đã xảy ra và không phải dự báo chắc chắn".**
2. **Tin tức đang tác động lên từng cặp:** ghép tin theo từ khóa trong tiêu đề + tóm tắt — từ khóa riêng mỗi cặp (`PAIR_NEWS_KW`: BTCUSD bitcoin/btc/crypto; XAUUSD gold/xau/silver; EURUSD euro/ecb/eurozone; GBPUSD pound/gbp/boe/bank of england/british; USDCAD canadian/cad/bank of canada/usd/cad; USDCHF swiss/chf/franc/snb; USDJPY yen/jpy/boj/bank of japan/japan; USOIL oil/crude/wti/opec) tối đa 3 tin riêng + 2 tin chung USD/Fed (federal reserve/fed/dollar/inflation/treasury/yield/rate hike/rate cut/fomc/cpi/powell). Tin Fed/USD/lạm phát/lợi suất Mỹ là yếu tố chung cho cả 8 cặp.
3. **Nhận định biến động — dòng tiền lớn:** đọc từ Volume Profile M15 + Delta ước tính từng cặp (`vpScanFor`): ngay vùng POC → "tranh chấp"; ngoài VAH/VAL → phá vỡ thật hay quét thanh khoản; trong vùng giá trị + Delta dương/âm → chấp nhận giá cao/thấp hay hấp thụ/chốt lời; + khung giờ đề phòng biến động 12h tới (sự kiện High). **Ghi rõ: "NHẬN ĐỊNH suy luận từ chỉ báo… trang không có dữ liệu lệnh hay vị thế thật của bất kỳ tổ chức, cá mập hay nhà cái nào".**
- Cả 3 khối đều là **suy luận xác định trong trang** (deterministic, tính lại khi giá/lịch/tin đổi), không gọi API phân tích nào.

### 16.7. Dynamic Island (dòng 499–512, 4131–4192)

- Chỉ hiện ở các phase **ngoài Trang chủ**; `position: sticky; top: 8px`, căn giữa; nền navy `#0a1e42`, chữ trắng, bo tròn 999px, bóng `rgba(5,22,51,.35)`.
- Nội dung: logo DGN mini 24×24 (nền trắng, bo tròn, padding 2px) + nút `‹` + chấm live (xanh `#17c964`, lỗi → vàng) + cặp + giá live + % thay đổi (xanh `#17c964` / đỏ `#ff5c72`) + 8 chấm chỉ vị trí + đường phân cách + ngày giờ VN `DD/MM · HH:MM:SS` + nút `›`.
- Cập nhật mỗi giây. **Kéo/vuốt ngang** (ngưỡng 42px, ưu tiên ngang hơn dọc ×1,4) hoặc bấm `‹`/`›` để xem giá live từng cặp trong 8 cặp (xoay vòng); thao tác này **chỉ đổi cặp hiển thị trên island**, không đổi cặp đang chọn của app. Khi chọn cặp ở nơi khác, island tự bám theo (`__islandFollow`). Mặc định XAUUSD (khớp cặp đang chọn lúc mở trang).

---

## 17. AUTO-TRADE + PANIC STOP (script 2, dòng 3384–3583)

**Bản web là mô phỏng DEMO trong trang — chưa có backend, chưa có vault, chưa nối LLM thật, chưa vào lệnh Exness thật.** Mọi hành vi dưới đây đều là mock luồng, phải giữ đúng giới hạn đó khi port (không được ghi là "đã kết nối Exness thật").

### 17.1. Kết nối Exness (mô phỏng phiên)

- Form: API Key (text) + Secret Key (password). Bấm "Kết nối & tạo phiên": thiếu 1 trong 2 → báo lỗi đỏ (bản demo chấp nhận bất kỳ chuỗi nào).
- Thành công: tạo session token `sess_` + 24 byte ngẫu nhiên (hex, `crypto.getRandomValues`); **xóa key khỏi ô nhập ngay lập tức** — key không được gửi đi đâu, không được lưu ở bất kỳ đâu trong trang. Chỉ giữ `{connected: true, token, connectedAt}`.
- UI sau kết nối: `"● Đã kết nối (mô phỏng phiên) · Tài khoản: DEMO · Kết nối lúc HH:MM:SS"` + hiện token + ghi chú nguyên tắc "app chỉ giữ session token, key thuộc về vault của backend (bản này chưa có backend nên chưa có kết nối Exness thật)" + nút "Ngắt kết nối" (ngắt → nếu Auto-Trade đang bật thì PANIC STOP trước, rồi `location.reload()`).

### 17.2. Điều kiện bật Auto-Trade (2 lớp xác nhận)

1. Phải **kết nối Exness trước** (chưa kết nối → cuộn lên form + báo "Hãy kết nối Exness (mô phỏng phiên) ở mục trên trước khi bật Auto-Trade").
2. Mở modal xác nhận: **Lớp 1** — tick checkbox "Tôi đã đọc và hiểu các rủi ro trên" (cảnh báo: có thể mất tiền thật khi LIVE; lần đầu chỉ DEMO 24h; tự tắt khi vượt drawdown; PANIC STOP luôn sẵn sàng). **Lớp 2** — gõ **chính xác `TÔI ĐỒNG Ý`** (so sánh sau `trim()`, phân biệt hoa thường/dấu). Sai lớp nào → báo lỗi đỏ đúng lớp đó, không bật.
3. Bật thành công → `startAuto()`: lần đầu đặt `mode = "DEMO"`, `demoStart = now`, `demoEnd = now + 24 giờ`, `dayStartEquity = balance + realized`.

### 17.3. Cấu hình Auto-Trade (mặc định)

| Mục | Mặc định | Giới hạn |
|---|---|---|
| Cặp được phép | XAUUSD, BTCUSD, EURUSD được tick (8 cặp đều có checkbox) | — |
| Kiểu khối lượng | Lot cố định | Lot cố định / % rủi ro / lệnh |
| Lot cố định | 0,01 | ≥ 0,01 |
| % rủi ro / lệnh | 1% | 0,1–5% (khuyến nghị ≤ 1%) |
| Max lệnh mở cùng lúc | 3 | 1–8 |
| Max drawdown ngày (%) | 5 | 1–30 (vượt là tự tắt — PANIC STOP) |
| Confidence tối thiểu | 70 | 50–95 |
| Giờ giao dịch (giờ VN) | 00:00 → 23:59 | 0–23h (qua đêm được: from > to thì `h >= from \|\| h <= to`) |
| Số dư DEMO mô phỏng | 10.000 USD (chỉ đọc, hiển thị `balance + realized`, định dạng 2 số lẻ) | — |

### 17.4. Engine mô phỏng — `autoTradeTick()` (mỗi 2 giây)

- Đóng lệnh chạm SL/TP theo giá live (BUY: `price >= TP` → đóng tại TP; `price <= SL` → đóng tại SL; SELL ngược lại).
- **Drawdown ngày:** `equity = balance + realized + floating`; `dd = max(0, (dayStartEquity − equity)/dayStartEquity × 100)`; `dd >= maxDD` → `panicStop("Vượt max drawdown ngày (X,X% ≥ Y%)")`.
- Ngoài giờ giao dịch → không mở lệnh mới (lệnh đang mở vẫn được theo dõi đóng). Đủ max lệnh → không mở thêm.
- Mở lệnh mới cho từng cặp được tick: cần tín hiệu BUY/SELL tĩnh, `confidence >= confMin`, có SL; **mỗi cặp tối đa 1 lệnh mở**; chống mở trùng cùng tín hiệu bằng key `sym|action|closedAt` (`tradedKeys`).
- Lệnh mở tại **giá live** (`entry = live price`, SL/TP lấy từ tín hiệu tĩnh); `riskUSD` = chế độ lot: `lot/0,01 × 10 USD` (mô phỏng: 0,01 lot rủi ro 10 USD khi chạm SL); chế độ %: `(balance + realized) × riskPct/100`.
- P/L lệnh: `R = (BUY ? price−entry : entry−price) / |entry − SL|`; USD = `R × riskUSD`. Đóng lệnh cộng `realized += R × riskUSD`. Nhật ký tối đa 40 dòng (mới nhất lên đầu, giờ `HH:MM:SS`).

### 17.5. PANIC STOP

- Nút đỏ cố định: `position: fixed; right: 16px; bottom: 96px` (nằm trên thanh nav dưới), nền `#d61f38`, viền `#ff8fa0`, chữ `■ PANIC STOP` 16px/800, bóng đỏ; **chỉ hiện khi Auto-Trade đang bật** (`#panicBtn` ngoài + `#atPanicBtn` trong phase Auto-Trade — cả hai cùng gọi `panicStop()`).
- `panicStop(reason)`: đóng **tất cả** lệnh DEMO đang mở tại giá live (lý do "PANIC STOP"), tắt Auto-Trade, ghi log `"PANIC STOP — đã đóng N lệnh DEMO và tắt Auto-Trade ngay lập tức."`
- Chấm đỏ trên tab Auto-Trade (`#autoDot`) hiện khi đang bật. Chip trạng thái: chưa bật → "Chưa bật"; đang bật → `"DEMO · còn X giờ Y phút · LIVE khoá"`; đã tắt sau khi chạy → "Đã tắt · DEMO đã chạy, còn …".
- **LIVE khóa:** trong toàn bộ code web **không có đường nào chuyển sang LIVE** — hết 24 giờ demo cũng chỉ hiển thị "LIVE khóa"; LIVE "vẫn cần xác nhận riêng, không tự chuyển". Port Flutter phải giữ nguyên: không tự bịa luồng mở LIVE.

---

## 18. ASSETS INLINE

File HTML nhúng **4 assets riêng biệt** dạng base64 data-URI (không có file ngoài nào khác; font tải từ Google Fonts). Lưu ý: dòng 3970 là **comment CSS chứa lại đúng data-URI của logo intro** (không phải asset thứ 5). Dòng 501 và 519 dùng **cùng một payload** (cùng MD5) — chỉ tính là 1 asset dùng ở 2 chỗ.

| # | Asset | Dòng bắt đầu | Định dạng / kích thước ảnh | Kích thước data-URI | Dùng ở |
|---|---|---|---|---|---|
| 1 | **Logo DGN (favicon)** | 7 | PNG 680×560 | ~219 KB (224.272 ký tự base64) | `<link rel="icon">` |
| 2 | **Logo DGN intro (nguyên khối, nền trong suốt)** | 493 | PNG 880×587 | ~199 KB (203.460 ký tự base64) | `<img class="intro-logo">` trong `#introSplash` |
| 3 | **Logo DGN đầy đủ (nền trong suốt)** | 501 (island) + 519 (hero) | PNG 680×560 | ~261 KB (267.212 ký tự base64), cùng MD5 `f933df9bccb7…` ở cả 2 chỗ | Logo mini trong Dynamic Island + `.hero-mark` trong hero Trang chủ |
| 4 | **Ảnh CEO / founder** | 528 | JPEG (JFIF, bắt đầu `FFD8 FFE0`) | ~91 KB (92.848 ký tự base64) | `<figure class="founder">` bên phải hero; alt: "CEO — nhà sáng lập DGN, áo vest navy có logo DGN, đứng trực tiếp trên nền hero phía phải, không khung ảnh" |

- Web ghi chú logo intro "nền trong suốt đã kiểm tra: 0% pixel đen đục". Logo DGN: mark 3D xanh navy + góc cam trên nền trong suốt (không phải nền đen — bản nền đen cũ đã xử lý thành trong suốt).
- Khi port Flutter: cần trích xuất 4 file ảnh này ra `assets/` (favicon có thể bỏ hoặc dùng làm icon app nếu cần; logo đầy đủ dùng cho icon/launch/intro/island/hero; ảnh CEO chỉ dùng ở hero Trang chủ). **Ảnh CEO chỉ dùng trong app này, không dùng nơi khác.**

---

## 19. NHỮNG ĐIỂM MƠ HỒ / CẦN NGƯỜI PORT TỰ QUYẾT ĐỊNH

1. **Bollinger + EMA200 "chết" (§13.4):** web lưu 3 thông số này nhưng không tính/vẽ gì. Port nên giữ nguyên (form + lưu trữ, không dùng) hay triển khai thật (vẽ dải Bollinger, dùng EMA200 làm lọc xu hướng)? Cần quyết định trước khi code — không tự ý đưa vào tín hiệu.
2. **Backtest Swing bỏ bias H4 (§12.1):** tín hiệu live yêu cầu H1+H4 đồng thuận, nhưng `btSignalAt` chỉ dùng EMA khung test + RSI. Đây có thể là lỗi thiếu sót của web hoặc cố ý đơn giản hóa — cần quyết định có bổ sung xác nhận H4 vào backtest hay giữ y hệt web.
3. **Forex "neo er-api + tick Kraken" (§2.3):** đây là giá tổng hợp, không phải giá thật của một sàn. Trên Flutter có giữ nguyên cơ chế neo (er-api cập nhật 1 lần/ngày) hay đổi sang nguồn forex trực tiếp khác? Nếu đổi nguồn, toàn bộ mốc giá/SL/TP sẽ khác web.
4. **Nến dầu OKX lệch ~1,5% so với WTI NYMEX (§2.5):** web căn mức series 1 lần theo giá CNBC. Trên Flutter, nếu dùng nguồn nến dầu khác (hoặc không căn), nến và giá live sẽ lệch nhau — cần quyết định nguồn nến dầu và có giữ cơ chế căn mức hay không.
5. **Lưu trữ localStorage → Flutter:** web dùng 3 key (`dgnStratV1`, `dgnIndSettingsV1`, `dgnBtMethodV1`) + toàn bộ dữ liệu phiên (tín hiệu, lịch sử, hình vẽ, trạng thái mở/đóng) chỉ giữ trong bộ nhớ và mất khi đóng trang. Trên Flutter, có giữ đúng "đóng app là mất lịch sử" hay lưu bền lịch sử/tín hiệu? Quyết định này ảnh hưởng trực tiếp tới thẻ TỔNG TOÀN PHIÊN và thống kê hero.
6. **Chime intro (§16.2):** web tổng hợp 8 nốt sine bằng Web Audio API. Trên Flutter cần triển khai tương đương (tổng hợp tone hoặc file âm thanh). Nếu không làm được tiếng, phải báo rõ "chưa có tiếng" thay vì im lặng bỏ qua — và cần quyết định có dùng file nhạc ngoài hay không (web không dùng file ngoài).
7. **Tin tức quét 1 giây (§14.1):** rss2json/allorigins có thể giới hạn tần suất (rate limit) khi quét mỗi giây; web đã có giãn nhịp tới 60s. Trên Flutter, nếu dùng proxy khác hoặc gọi trực tiếp RSS, cần quyết định nguồn/proxy và nhịp quét thực tế (giữ 1 giây + giãn nhịp, hay giãn ngay từ đầu).
8. **Lịch kinh tế snapshot (§14.2):** `CAL_SNAP` là dữ liệu cứng từ 15–20/11/2026 — sau thời gian đó sẽ lỗi thời. Trên Flutter cần quyết định: chỉ dùng API ForexFactory trực tiếp (và hiện gì khi API lỗi), hay vẫn kèm snapshot (và snapshot lấy từ đâu, cập nhật khi nào).
9. **Auto-Trade LIVE (§17.5):** web hoàn toàn không có luồng LIVE (không backend/vault/Exness API thật). Đây là giới hạn lớn nhất: Flutter chỉ được port đúng bản DEMO mô phỏng; mọi cam kết về LIVE/auto-trade tiền thật đều cần backend riêng và xác nhận của người dùng — không được "hoàn thiện nốt" trong lúc port.
10. **Hiệu năng render:** web render lại nhiều khối mỗi 1,5–3 giây (rails, gauge, ladder, pair analysis, history). Trên Flutter cần quyết định chiến lược cập nhật UI tương đương (tránh rebuild toàn bộ cây widget mỗi 2 giây gây giật), nhưng vẫn giữ đúng tần suất cập nhật dữ liệu (giá 2s, tín hiệu 30s, tin 1s, gauge/ladder 2s).

---

*Hết spec. Nguồn duy nhất: file HTML gốc nêu ở đầu. Mọi công thức, ngưỡng, URL và key lưu trữ trong spec đều trích từ code web; chỗ nào web chỉ là suy luận trong trang hoặc số ước tính đều đã ghi rõ.*
