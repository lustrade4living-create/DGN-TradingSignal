# DGN — TradeSignal AI

TradeSignal AI — ứng dụng Flutter Android cho tín hiệu Swing 8 cặp:
BTCUSD, XAUUSD, EURUSD, GBPUSD, USDCAD, USDCHF, USDJPY, USOIL.

Phiên bản hiện tại: **1.2.3+6** (package `com.tradesignal.ai`, minSdk 21, targetSdk 34).

> Lưu ý quan trọng: đây là công cụ hỗ trợ phân tích, tín hiệu chỉ mang tính
> tham khảo. Auto-Trade trong app hiện chỉ là bản demo, chưa vào lệnh thật.
> Không lưu key/secret Exness trên máy — key chỉ giữ trong bộ nhớ phiên.

## Tính năng chính (v1.2.3)

- Tín hiệu tĩnh chốt theo nến H1 đã đóng; Entry/SL/TP không đổi theo giá live.
- Trạng thái tín hiệu cập nhật từng giây: VÀO NGAY (NOW) / CHỜ LIMIT /
  KHÔNG NÊN VÀO NỮA, kèm khoảng cách tới Entry, giờ ra tín hiệu và giờ hết hiệu lực.
- Lịch sử tín hiệu lưu bền: SL / TP / Thoát tại Entry / Cắt lỗ sớm / Cắt lãi sớm.
- VolumeB/S quét cả 8 cặp (Volume Profile M15: POC/VAH/VAL, HVN/LVN, Delta ước tính).
- Trend dạng dải pill M5/M15/H1/H4/D1; Price Action cơ bản + nâng cao
  (Pin Bar, Engulfing, Sweep, BOS, CHoCH, FVG, Order Block, Retest).
- Độ tin cậy = 50% tín hiệu gốc + 25% Trend + 25% Price Action, WAIT trần 62%.
- Hộp "Điểm vào chuẩn & đẹp — tối ưu" ngoài Entry chính.
- Backtest tối đa 2000 nến đã đóng, chạy qua Isolate, có khung nhập phương pháp.
- Chiến lược AI lưu trong trình duyệt / trên máy; chỉ báo tùy chỉnh 14 thông số.
- Tin tức Live FXStreet quét 1 giây; lịch kinh tế giờ VN; Dynamic Island vuốt ngang 8 cặp.
- Menu 3 gạch góc dưới bên trái; nút PANIC STOP đỏ luôn hiện khi Auto-Trade bật.
- Giá live polling 2 giây (HttpClient thuần Dart: gold-api / Binance / er-api +
  Kraken / Yahoo CL=F cho USOIL); giá cũ > 5 phút hiện DỮ LIỆU CŨ.
- Giá USOIL là giá hợp đồng tương lai NYMEX tháng gần nhất (Yahoo CL=F) —
  có thể lệch 1–2 USD với giá spot/CFD trên Exness, nhất là quanh ngày roll.

## Giới hạn đã biết

- Chưa chạy thử trên máy thật / mạng thật ở bản này — người dùng kiểm tra cuối.
- Delta VolumeB/S chỉ ước tính từ vị trí đóng nến, chưa phải Delta tick thật.
- Giá polling 2 giây, chưa phải WebSocket 1 giây. Tin live 1 giây có thể bị giới hạn.
- Lịch sử tín hiệu trên web chỉ giữ trong lúc mở trang ở các bản web cũ;
  bản APK v1.2.3 đã lưu bền qua lần mở app.

## Web (GitHub Pages)

Repo này có sẵn workflow `.github/workflows/deploy-web.yml`: mỗi lần đẩy
code lên nhánh `main`, GitHub tự build bản web (`flutter build web`) và đăng
lên Pages. Bật một lần trong repo: Settings → Pages → Build and deployment →
Source: **GitHub Actions**. Trang chạy ở:

https://lustrade4living-create.github.io/DGN-TradingSignal/

Lưu ý: bản web cần đủ file ảnh trong `assets/` thì build mới chạy được.
Trên web, phần lưu cài đặt/lịch sử không giữ được sau khi đóng trang (kênh
lưu file của Android không có trên web) — lịch sử tín hiệu chỉ giữ trong lúc
mở trang.

## Build APK

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

File APK ở `build/app/outputs/flutter-apk/app-release.apk`.

Build tay không Gradle (khi mạng nội bộ chặn Java) xem `manual/build_apk.sh`
— script này cần sẵn các file `.jar` trong `manual/libs/` và `manual/r8.jar`,
các file này không đẩy lên GitHub (file nhị phân lớn), cần tải lại khi dùng.

## Cấu trúc

- `lib/` — toàn bộ mã Dart: `main.dart`, `engine.dart`, `signal_core.dart`,
  `signal_status.dart`, `market_data.dart`, `volume_profile.dart`,
  `backtest.dart`, `history.dart`, `news_live.dart`, `patterns.dart`,
  `indicators.dart`, `chart.dart`, `alerts.dart`, `storage.dart`, `safe_json.dart`
- `lib/widgets/` — Dynamic Island, gauge, menu 3 gạch, hero, thẻ tín hiệu
- `assets/` — logo DGN và ảnh CEO/founder (file ảnh, xem ghi chú bên dưới)
- `test/` — 87 test (v1.2.3)
- `port/` — tài liệu đối chiếu bản web và bản Flutter

## Ghi chú về file ảnh

Thư mục `assets/` và các icon `mipmap` / `AppIcon` / `web/icons` là file ảnh
nhị phân. Khi đẩy code lên GitHub bằng công cụ kết nối, chỉ đẩy được file
chữ; các file ảnh cần tải lên repo sau bằng trang web GitHub (kéo-thả thư
mục `assets/` và các icon) thì app mới đủ logo, ảnh CEO và icon như bản APK.
