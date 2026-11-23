# Thiết kế hệ thống Demo POS, In hóa đơn Mobile & Tải 3 luồng (100.000 sản phẩm)

**Ngày:** 2026-11-23  
**Phạm vi:** Dự án full-stack gồm Backend (`Node.js` + `SQLite`) và ứng dụng Mobile (`Flutter` trên Android thật & Emulator).

---

## 1. Mục tiêu & Bối cảnh (Intent & Why)

Xây dựng ứng dụng demo bán hàng (POS) trên mobile giải quyết hai bài toán cốt lõi từ [docs/spec.md](../../spec.md):

1. **Bán hàng, tính tiền & in hóa đơn trực tiếp trên mobile:** Nhân viên tạo giỏ hàng với đầy đủ chiết khấu dòng, thuế VAT, giảm giá đơn, ghi chú, hình thức thanh toán, lưu đơn hàng về backend để cấp mã đơn/trừ tồn kho, và xuất lệnh in ra máy in thật (máy in bill nhiệt ESC/POS hoặc máy in qua Android Print Service / PDF).
2. **Trải nghiệm duyệt 100.000 sản phẩm mượt như Shopee với 3 luồng dữ liệu độc lập:** Tách biệt luồng thông tin cơ bản (nhanh), luồng tồn kho chậm có `sleep 1s` mỗi sản phẩm (chạy song song ~1 giây/trang 10 sản phẩm), và luồng ảnh/video (`< 5MB` qua link) đi kèm cơ chế hủy tác vụ (`Cancellation`), tải đón đầu (prefetch), hiển thị lũy tiến (progressive rendering + shimmer) và kiểm soát RAM để không giật lag khi cuộn nhanh.

### Mục tiêu (Goals)
- **Backend Node.js + SQLite:** Khởi tạo nhanh 100.000 sản phẩm (tồn kho mặc định `10`), đánh index phục vụ phân trang mượt (`10 sản phẩm/trang`), mô phỏng API tồn kho `sleep 1s` cho từng `productId`, host sẵn media mẫu `< 5MB`, và lưu hóa đơn + trừ tồn kho khi thanh toán.
- **Mobile Flutter UX chuẩn thương mại (Shopee-like):**
  - Danh sách hiển thị ngay khung card cố định chiều cao từ Luồng 1; các vùng chưa có dữ liệu từ Luồng 2 & 3 dùng hiệu ứng Shimmer nhẹ và Fade-in khi tải xong, không làm nhảy layout.
  - Prefetch trang kế tiếp trước khi cuộn chạm đáy, kết hợp `CancelToken` theo vòng đời hiển thị để hủy ngay request thừa khi người dùng cuộn/lướt nhanh.
  - Giao diện bán hàng thuần túy, không chèn bảng thông số debug lên màn hình (chỉ log thời gian 3 luồng và số request đã hủy ra console/DevTools).
- **In ấn kép:** Hỗ trợ cả in bill nhiệt ESC/POS (LAN/Wi-Fi TCP 9100 và Bluetooth, render dạng ảnh/bitmap để hiển thị tiếng Việt có dấu chuẩn) và in qua PDF / Android Print Service (dùng được cho mọi máy in văn phòng có driver Android và kiểm chứng được trên Emulator).

### Ngoài phạm vi (Non-Goals)
- Không xây dựng hệ thống đăng nhập, phân quyền tài khoản phức tạp (chọn nhanh nhân viên từ danh sách mẫu và chỉnh thông tin cửa hàng/logo trong Cài đặt).
- Không tích hợp cổng thanh toán trực tuyến thực tế (chỉ chọn hình thức thanh toán để ghi nhận và in lên hóa đơn).
- Không đồng bộ đa chi nhánh hay báo cáo kế toán cuối kỳ.

### Điều tuyệt đối tránh (Anti-Goals)
- Không để Luồng 2 (`sleep 1s`) chặn việc hiển thị danh sách từ Luồng 1 hoặc chặn thao tác thêm sản phẩm vào giỏ.
- Không để cuộn nhanh qua 100.000 dòng gây nghẽn connection pool, tụt FPS, hoặc tràn RAM (OOM) do giải mã đồng thời nhiều ảnh độ phân giải cao hay mở nhiều video decoder cùng lúc.
- Không sinh 100.000 file media vật lý gây phình ổ cứng; sử dụng bộ file ảnh/video mẫu `< 5MB` được phân phối theo nhóm/hash ID qua URL hợp lệ.

---

## 2. Các phương án đã cân nhắc (Approaches)

Trước khi chốt thiết kế, 3 phương án triển khai đã được đánh giá:

1. **Phương án 1 — Tải song song theo Trang + Kiến trúc Gọn nhẹ *(Đã chọn, nâng cấp Mobile lên Clean Architecture + BLoC/Cubit)***:
   - *Backend:* Node.js + Fastify + `node:sqlite` (tích hợp sẵn trên Node 24, không cần build tool native trên Windows).
   - *Mobile:* Clean Architecture (`data / domain / presentation` theo từng feature `catalog`, `cart`, `invoice`, `settings`) + `flutter_bloc` (`Cubit`), `Dio` (HTTP/1.1 keep-alive pool `maxConnectionsPerHost = 16`) + `CancelToken` gắn với vòng đời trang/item hiển thị, `Custom ScrollController` + LRU Page Cache (15–20 trang), prefetching + shimmer + `CachedNetworkImage` (`memCacheWidth`) + video phát theo yêu cầu (on-demand dialog) + `SharedPreferences` lưu cấu hình & giỏ hàng nháp.
   - *Đánh đổi:* Cấu trúc Mobile phân tách rõ tầng nghiệp vụ và UI cho quy mô mở rộng tốt, đồng thời giữ phía Backend đơn giản nhất có thể và vẫn kiểm soát trực tiếp vòng đời `CancelToken` + LRU cache trên trang 10 sản phẩm.
2. **Phương án 2 — Hủy tác vụ tự động theo từng Widget (`Riverpod autoDispose`) + Express/ORM**:
   - *Đánh đổi:* Rất tự nhiên cho hủy request ở cấp từng card qua `ref.onDispose`, nhưng tăng đáng kể boilerplate (Riverpod + ORM), tốc độ seed/query 100k dòng qua ORM chậm hơn SQLite thuần, và dễ bắn request thừa khi người dùng cuộn qua lại nhẹ nếu thiếu debounce chặt.
3. **Phương án 3 — Fastify HTTP/2 (TLS self-signed) + `Isolate` riêng**:
   - *Đánh đổi:* Loại bỏ hoàn toàn giới hạn socket HTTP/1.1 nhưng việc cấu hình chứng chỉ tự ký trên Android thật & Emulator qua LAN dễ phát sinh lỗi kết nối khi demo trực tiếp, không cần thiết khi HTTP/1.1 keep-alive với pool `>= 12` kết nối đã xử lý tốt trang 10 sản phẩm trong ~1 giây.

**Lý do chọn Phương án 1:** Đáp ứng trọn vẹn cả 3 mục tiêu kỹ thuật (tách 3 luồng, song song ~1s/trang, cancellation khi cuộn nhanh) lẫn trải nghiệm mượt kiểu Shopee với chi phí mã nguồn tối giản và độ ổn định cao nhất khi demo.

---

## 3. Ràng buộc & Hạ tầng (Constraints)

- **Runtime hiện có trên máy phát triển:** Node.js `v24.21.0` (có sẵn `node:sqlite`), Flutter `3.44.8` / Dart `3.12.2`.
- **Thiết bị chạy thử:** Android thật (qua USB/LAN cùng mạng máy chủ) và Android Emulator (dùng `10.0.2.2` trỏ về localhost máy host; cho phép cấu hình lại Base URL backend ngay trong màn hình Cài đặt của app).
- **Truyền thông mạng:** HTTP/1.1 cleartext trong mạng nội bộ demo (cần bật `usesCleartextTraffic="true"` trên Android manifest cho dev/demo).

---

## 4. Thiết kế chi tiết Backend (`backend/`)

### 4.1. Cơ sở dữ liệu SQLite (`backend/data/pos.db`)
- Bật chế độ `WAL` (`PRAGMA journal_mode = WAL;`) để đọc 100k sản phẩm đồng thời với thao tác ghi đơn hàng không bị khóa.
- **Bảng `products` (100.000 bản ghi seed sẵn khi khởi động lần đầu nếu bảng trống):**
  - `id` INTEGER PRIMARY KEY
  - `sku` TEXT UNIQUE NOT NULL (VD: `SP000001` .. `SP100000`)
  - `name` TEXT NOT NULL
  - `unit` TEXT NOT NULL (Cái, Hộp, Chai, Thùng, Gói...)
  - `price` REAL NOT NULL (VNĐ)
  - `vat_rate` REAL NOT NULL DEFAULT 8 (0, 8, hoặc 10%)
  - `stock` INTEGER NOT NULL DEFAULT 10
  - `media_type` TEXT NOT NULL (`image` hoặc `video`)
  - `media_url` TEXT NOT NULL (đường dẫn tới static media `< 5MB` trên server)
  - `thumbnail_url` TEXT NOT NULL (ảnh đại diện nhẹ cho card danh sách, đặc biệt với item video)
  - Index trên `(id)` (keyset/offset nhanh) và `(sku, name)` cho tìm kiếm cơ bản khi thêm vào giỏ.
- **Bảng `orders`:**
  - `id` INTEGER PRIMARY KEY AUTOINCREMENT
  - `order_code` TEXT UNIQUE NOT NULL (VD: `HD-20261123-0001`)
  - `staff_name` TEXT NOT NULL
  - `payment_method` TEXT NOT NULL (`Tiền mặt`, `Chuyển khoản`, `Thẻ`, `Ví điện tử`)
  - `subtotal` REAL NOT NULL (tổng trước giảm giá đơn, đã gồm VAT)
  - `discount_percent` REAL NOT NULL DEFAULT 0
  - `discount_amount` REAL NOT NULL DEFAULT 0
  - `total_payable` REAL NOT NULL
  - `store_name`, `store_phone`, `store_address`, `store_logo_url` (snapshot thông tin cửa hàng tại thời điểm xuất đơn)
  - `created_at` TEXT NOT NULL (ISO-8601)
- **Bảng `order_items`:**
  - `id` INTEGER PRIMARY KEY AUTOINCREMENT
  - `order_id` INTEGER NOT NULL REFERENCES `orders(id)`
  - `product_id` INTEGER NOT NULL REFERENCES `products(id)`
  - `sku`, `name`, `unit` (snapshot)
  - `quantity` REAL NOT NULL
  - `unit_price` REAL NOT NULL
  - `discount_percent` REAL NOT NULL DEFAULT 0
  - `discount_amount` REAL NOT NULL DEFAULT 0
  - `vat_rate` REAL NOT NULL DEFAULT 0
  - `vat_amount` REAL NOT NULL DEFAULT 0
  - `line_total` REAL NOT NULL
  - `note` TEXT

### 4.2. Các API Endpoint (3 luồng + Đơn hàng + Media)
1. **Luồng 1 — Danh sách sản phẩm phân trang (`10 sản phẩm/trang`):**
   - `GET /api/products?page=1&limit=10&q=` (giới hạn `limit` mặc định `10`, tối đa `50`).
   - Trả về: `{ items: [{ id, sku, name, unit, price, vatRate }], page, limit, total, hasMore }`.
   - Không chứa `stock` hay `mediaUrl` ở endpoint này để đảm bảo Luồng 1 phản hồi dưới vài chục mili-giây.
2. **Luồng 2 — Tồn kho từng sản phẩm (mô phỏng trễ 1 giây):**
   - `GET /api/products/:id/stock`
   - Thực thi `await sleep(1000)` (hủy timer nếu client đóng socket sớm `req.raw.on('close', ...)` để giải phóng tài nguyên server khi mobile cancel).
   - Trả về `{ productId, stock }` (mặc định ban đầu là `10`, giảm dần sau khi xuất đơn).
3. **Luồng 3 — Media ảnh/video (`< 5MB` qua link):**
   - `GET /api/products/media?ids=1,2,...,10` hoặc `GET /api/products/:id/media` — đề xuất cung cấp endpoint theo từng `productId` (`GET /api/products/:id/media`) để giữ tính đối xứng độc lập hoàn toàn với vòng đời từng widget, hoặc nhận batch `ids` (builder giữ cấu trúc đơn giản nhất có thể tách luồng). Trả về `{ productId, mediaType, mediaUrl, thumbnailUrl, sizeBytes }`.
   - Static files tại `GET /media/...`: gồm một bộ ảnh PNG/JPEG sắc nét (~100–300KB) và video MP4 mẫu dung lượng `< 5MB` (VD: ~1–3MB) phục vụ hỗ trợ `Range` requests cho player video.
4. **Tạo đơn & Trừ tồn kho:**
   - `POST /api/orders`: nhận giỏ hàng, tính lại/xác thực tổng tiền phía server trong transaction SQLite, kiểm tra và trừ `products.stock = MAX(0, stock - qty)` (hoặc báo lỗi nếu không đủ tồn kho — chọn chính sách rõ ràng: báo lỗi `409` nếu `qty > stock`), sinh `order_code`, lưu `orders` + `order_items`, trả về hóa đơn hoàn chỉnh để mobile in.
   - `GET /api/orders`: lấy danh sách đơn gần đây để xem lại & in lại (reprint) khi cần.

---

## 5. Thiết kế chi tiết Mobile (`lib/`)

### 5.1. Trải nghiệm tải dữ liệu mượt kiểu Shopee (3 Luồng & Vòng đời)
- **Giao diện danh sách (2-cột Grid hoặc List card chiều cao cố định):**
  - Chiều cao item cố định trước (`itemExtent` hoặc tỷ lệ thẻ cố định) giúp Flutter tính toán layout O(1) khi cuộn qua hàng nghìn sản phẩm.
  - **Luồng 1 (Ngay lập tức):** Khi trang 10 SP trả về, hiển thị ngay Tên, Mã SKU, Đơn vị tính, Đơn giá, nút `+ Thêm giỏ`.
  - **Luồng 2 (Tồn kho song song ~1s/trang):** Ngay khi trang 10 SP sẵn sàng (hoặc các item đi vào vùng hiển thị + buffer), mobile kích hoạt 10 request `GET /api/products/:id/stock` song song trên `Dio` (cấu hình `HttpClient.maxConnectionsPerHost = 16` để không bị nghẽn hàng đợi mặc định). Trong 1s chờ, badge tồn kho hiển thị khung Shimmer xám; khi có kết quả, chuyển sang badge tồn kho (`Còn: 10`) bằng `AnimatedSwitcher`/fade-in.
  - **Luồng 3 (Media `< 5MB`):** Ảnh sản phẩm dùng `cached_network_image` với `memCacheWidth` giới hạn theo kích thước hiển thị thực tế (~300px) và `fadeInDuration: 200ms`. Với sản phẩm có `mediaType == 'video'`, card chỉ hiển thị `thumbnailUrl` + icon Play để đảm bảo FPS cao và không tràn RAM; khi nhân viên chạm vào preview media mới mở dialog phát video trực tiếp từ `mediaUrl` (`video_player` được `dispose()` ngay khi đóng dialog).
- **Prefetching & Debounce khi cuộn nhanh:**
  - Khi vị trí cuộn đạt ~70% của trang đang hiển thị cuối (cách cuối danh sách ~2–3 sản phẩm), tự động gọi trước trang `page + 1` (Luồng 1).
  - Nếu người dùng kéo thanh cuộn / lướt nhanh qua nhiều trang liên tiếp: áp dụng debounce ngắn (~120–150ms) trước khi bắn Luồng 2 & Luồng 3 cho trang mới, đồng thời gọi `cancelToken.cancel()` đối với các trang đã trượt khỏi vùng nhìn thấy + vùng đệm (±1 trang).
  - Các page đã tải xong được giữ trong bộ nhớ đệm LRU giới hạn (ví dụ tối đa 15–20 trang gần nhất, tương đương 150–200 sản phẩm) để cuộn ngược lại tức thì mà không tích lũy RAM vô hạn khi duyệt sâu vào 100.000 sản phẩm.

### 5.2. Giỏ hàng & Công thức tính hóa đơn chuẩn POS
Mỗi dòng trong giỏ hàng cho phép chỉnh: `số lượng`, `% chiết khấu` (0–100%), `% thuế VAT` (mặc định từ sản phẩm, cho sửa 0/5/8/10%), `ghi chú hàng`.

Công thức tính thống nhất giữa Mobile (preview realtime) và Backend (lưu đơn):
- `tiền hàng gốc = giá bán × số lượng`
- `tiền chiết khấu dòng = làm tròn(tiền hàng gốc × (% chiết khấu / 100))`
- `tiền sau chiết khấu dòng = tiền hàng gốc - tiền chiết khấu dòng`
- `tiền VAT dòng = làm tròn(tiền sau chiết khấu dòng × (% VAT / 100))`
- `thành tiền dòng = tiền sau chiết khấu dòng + tiền VAT dòng`
- `tổng giá trị đơn = Σ(thành tiền dòng)`
- `tiền giảm đơn = làm tròn(tổng giá trị đơn × (% giảm giá đơn / 100))`
- `tổng cần thanh toán = tổng giá trị đơn - tiền giảm đơn`

*(Làm tròn theo đơn vị đồng VNĐ `round()` ở từng bước).*

### 5.3. Mẫu hóa đơn & Giải pháp In ấn kép
**Nội dung hóa đơn đầy đủ theo `docs/spec.md`:**
- **Header cửa hàng:** Logo (asset mặc định hoặc URL cấu hình trong Cài đặt), Tên cửa hàng, SĐT, Địa chỉ.
- **Thông tin đơn:** Mã đơn (`order_code`), Ngày hóa đơn, Thời gian tạo, Nhân viên bán hàng.
- **Bảng chi tiết hàng hóa:** Mã, Tên, ĐVT, SL, Giá bán, % CK, Tiền CK, Thuế VAT, Thành tiền, Ghi chú hàng.
- **Tổng kết & Thanh toán:** Tổng giá trị đơn, % giảm giá, Tiền giảm, Tổng cần thanh toán, Hình thức thanh toán.

**2 chế độ In ấn (cấu hình trong Cài đặt máy in, hỗ trợ chuyển nhanh tại màn hình Xem trước hóa đơn):**
1. **In Bill Nhiệt ESC/POS (LAN/Wi-Fi TCP 9100 & Bluetooth Classic):**
   - Hỗ trợ chọn khổ giấy `80mm` (576px) hoặc `58mm` (384px).
   - **Kỹ thuật in tiếng Việt không lỗi font:** Dựng layout hóa đơn trên widget/canvas Flutter hoặc ảnh raster monochrome (`ui.PictureRecorder` -> PNG/bitmap bytes) rồi chuyển thành lệnh ảnh raster ESC/POS (`GS v 0`), giúp in tiếng Việt có dấu, logo và bảng căn lề sắc nét trên mọi máy in nhiệt Trung Quốc/Xprinter/Epson mà không phụ thuộc codepage.
2. **In qua Android Print Service / PDF (`pdf` + `printing`):**
   - Tạo file PDF đúng mẫu hóa đơn (hỗ trợ font Unicode tiếng Việt nhúng sẵn) và gọi `Printing.layoutPdf(...)`.
   - Hoạt động mượt trên **Android Emulator** (lưu PDF hoặc in máy in ảo) lẫn **Android thật** (in qua máy in Wi-Fi/USB/Mopria có sẵn driver trên Android).

---

## 6. Những phần để Builder tự quyết định (Left to the Builder)

- Cấu trúc thư mục chi tiết trong `backend/src/` và `lib/` theo chuẩn sạch, gọn.
- Bộ dữ liệu seed mẫu (tên sản phẩm, danh mục giả lập, ảnh PNG mẫu và 1–2 file video MP4 `< 5MB` tối ưu dung lượng).
- Chọn package Flutter cụ thể tương thích Dart 3.12 / Flutter 3.44 (`flutter_bloc`, `equatable`, `dio`, `cached_network_image`, `shimmer`, `video_player`, `shared_preferences`, `pdf`, `printing`, `print_bluetooth_thermal`, `image`, `intl`).
- Thiết kế UI chi tiết (màu sắc, icon, bố cục responsive cho màn hình dọc điện thoại) miễn đảm bảo sạch sẽ, dễ thao tác bán hàng nhanh.
