# POS, In hóa đơn Mobile & Tải 3 luồng (100k sản phẩm) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Xây dựng hoàn chỉnh hệ thống demo POS từ Backend (`Node.js` + `Fastify` + `node:sqlite` với 100.000 sản phẩm) đến Mobile (`Flutter` Clean Architecture + `BLoC/Cubit` chạy Android thật & Emulator), hỗ trợ trải nghiệm cuộn mượt kiểu Shopee với 3 luồng bất đồng bộ + `CancelToken`, giỏ hàng đầy đủ chiết khấu/VAT và in hóa đơn kép (ESC/POS + Android Print PDF).

**Architecture:** Backend dùng Fastify phục vụ 3 API tách biệt (danh sách phân trang 10 SP/trang, tồn kho `sleep 1000ms` theo từng `productId` có hủy timer khi socket đóng, media link `< 5MB` tĩnh) và transaction SQLite tạo đơn/trừ tồn kho. Mobile tổ chức theo Clean Architecture (`data/domain/presentation`) cho 4 feature (`catalog`, `cart`, `invoice`, `settings`) dùng `Cubit`, `Dio` (`maxConnectionsPerHost = 16`, `CancelToken`), LRU cache 15–20 trang, prefetching ở 70% danh sách, shimmer/fade-in, `SharedPreferences` lưu giỏ nháp & cấu hình, cùng 2 adapter in ấn (`pdf`/`printing` và ESC/POS raster bitmap qua TCP 9100 / Bluetooth).

**Tech Stack:** Node.js `v24.21.0` (`node:sqlite`, `node --test`), Fastify, `@fastify/cors`, `@fastify/static`; Flutter `3.44.8` / Dart `3.12.2`, `flutter_bloc`, `equatable`, `dio`, `cached_network_image`, `shimmer`, `video_player`, `shared_preferences`, `pdf`, `printing`, `print_bluetooth_thermal`, `image`, `intl`, `bloc_test`, `mocktail`.

**Spec:** [docs/superpowers/specs/2026-11-23-pos-invoice-3stream-design.md](../specs/2026-11-23-pos-invoice-3stream-design.md)

## Global Constraints

- Phân trang cố định `10` sản phẩm/trang trên tập `100.000` sản phẩm seed sẵn (tồn kho khởi tạo `10`).
- Luồng 1 (`GET /api/products`), Luồng 2 (`GET /api/products/:id/stock` với `sleep 1000ms`), Luồng 3 (`GET /api/products/:id/media` với media `< 5MB` qua link) tách biệt hoàn toàn, không để Luồng 2 chặn hiển thị Luồng 1.
- Giao diện Mobile giữ sạch chuẩn thương mại (không hiển thị bảng debug metric 3 luồng lên UI; chỉ log thời gian & cancellation ra console/DevTools).
- Công thức POS nhất quán Backend & Mobile: `tiền sau CK dòng = (giá bán * SL) - round(giá bán * SL * %CK/100)`; `VAT = round(tiền sau CK dòng * %VAT/100)`; `tổng đơn = Σ(tiền sau CK dòng + VAT)`; `tiền giảm đơn = round(tổng đơn * %giảm/100)`; `tổng cần thanh toán = tổng đơn - tiền giảm đơn`.
- Hỗ trợ chạy HTTP cleartext nội bộ trên Android (`usesCleartextTraffic="true"`), tương thích cả Android Emulator (`10.0.2.2`) và Android thật (cấu hình Server URL trong Cài đặt).
- Repo hiện chưa khởi tạo Git, bỏ qua bước `git commit` ở từng task; xác minh hoàn tất từng task bằng test suite & analyzer tương ứng.

## Review Focus

1. **Race condition & StateError khi cuộn nhanh / hủy `CancelToken`:** Request Luồng 2/3 bị hủy khi trang rời viewport không được hiển thị lỗi đỏ trên UI, và response trả về muộn sau khi Cubit đã `close()` hoặc page bị đẩy khỏi LRU cache không được crash hay ghi đè sai dữ liệu.
2. **Đặt hàng đồng thời vượt tồn kho & tin cậy giá từ client (`POST /api/orders`):** Hai đơn gửi cùng lúc khi tồn kho chỉ đủ cho một đơn phải chặn đơn thứ hai với HTTP `409`, và tổng tiền phải được tính lại từ `products.price` trong SQLite thay vì dùng giá client gửi.
3. **Làm tròn số lẻ & biên nhập liệu POS:** Giá lẻ (VD `33.333`, SL `3`, CK `15%`, VAT `8%`, giảm đơn `5%`) phải khớp 100% giữa `pos_calculator.dart` và `pricing.js`; % CK/giảm giá ngoài `[0, 100]` hoặc `SL <= 0` phải bị từ chối.
4. **Media Luồng 3 lỗi / Video khi cuộn nhanh:** Link ảnh lỗi hoặc timeout chỉ hiện placeholder an toàn, không vỡ chiều cao cố định của card; item video trên danh sách chỉ render thumbnail tĩnh và chỉ tạo `VideoPlayerController` khi mở dialog chi tiết.
5. **Lỗi kết nối máy in ESC/POS trên Emulator hoặc khi mất mạng/tắt Bluetooth:** Khi in ESC/POS timeout/thất bại, app giữ nguyên hóa đơn vừa tạo (không gọi `POST /api/orders` lại) và cho phép in lại hoặc chuyển ngay sang xuất PDF / Android Print Service.

---

## Cấu trúc thư mục triển khai (File Structure)

### Phase 1: Backend (`backend/`)
- `backend/package.json` — Cấu hình ESM (`"type": "module"`), script `start`, `seed`, `test`, dependencies (`fastify`, `@fastify/cors`, `@fastify/static`).
- `backend/src/db/database.js` — Mở `DatabaseSync` (`node:sqlite`), bật `PRAGMA journal_mode = WAL`, tạo bảng `products`, `orders`, `order_items` và index.
- `backend/src/db/seed.js` — Tạo bộ media mẫu `< 5MB` (`backend/public/media/prod_1..4.png`, `sample_promo.mp4` dung lượng nhỏ hợp lệ) và seed `100.000` dòng `products` idempotent trong transaction.
- `backend/src/services/pricing.js` — Hàm tính toán POS (`calculateOrderPricing`) dùng chung cho route đơn hàng.
- `backend/src/routes/products.js` — Route Luồng 1 (`/api/products`), Luồng 2 (`/api/products/:id/stock` với `sleep` hủy theo socket close), Luồng 3 (`/api/products/:id/media`).
- `backend/src/routes/orders.js` — Route `POST /api/orders` (transaction trừ tồn kho + lưu đơn), `GET /api/orders`.
- `backend/src/app.js` — `buildApp(options)` đăng ký CORS, static `/media`, routes.
- `backend/src/server.js` — Khởi tạo DB, seed nếu rỗng, lắng nghe `0.0.0.0:3000`.
- `backend/test/*.test.js` — Bộ unit + integration tests với `node --test`.

### Phase 2: Mobile (`lib/`, `android/`, `pubspec.yaml`, `test/`)
- `pubspec.yaml` — Khai báo dependencies Flutter & dev_dependencies (`bloc_test`, `mocktail`).
- `android/app/src/main/AndroidManifest.xml` — Quyền Internet, Bluetooth (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`), cleartext traffic.
- `lib/core/config/app_config.dart` — Giá trị mặc định Server URL, page size `10`, LRU max pages `20`, debounce `150ms`.
- `lib/core/network/dio_client.dart` — Khởi tạo `Dio` với `maxConnectionsPerHost = 16`, timeout chuẩn.
- `lib/core/utils/pos_calculator.dart` & `currency_formatter.dart` — Logic tính tiền POS và format VNĐ.
- `lib/features/settings/` — `StoreConfig`, `PrinterConfig`, `AppSettings`, `SettingsLocalDatasource`, `SettingsCubit/State`, `SettingsPage`.
- `lib/features/catalog/` — `Product`, `ProductStockState`, `ProductMedia` (domain), `CatalogRemoteDatasource`, `CatalogRepositoryImpl` (data), `CatalogCubit/State` (LRU cache + prefetch + parallel Luồng 2/3 + `CancelToken`), `CatalogPage`, `ProductCard`, `VideoDetailDialog` (presentation).
- `lib/features/cart/` — `CartItem`, `CartSummary` (domain), `CartLocalDatasource` (`SharedPreferences` JSON), `CartRepositoryImpl` (data), `CartCubit/State`, `CartPage`, `CartItemEditSheet` (presentation).
- `lib/features/invoice/` — `Invoice`, `InvoiceItem`, `PrinterService` (domain), `InvoiceRemoteDatasource`, `PdfInvoiceService`, `EscPosRasterPrinterService` (data), `InvoiceCubit/State`, `InvoicePreviewPage`, `InvoiceHistoryPage` (presentation).
- `lib/app.dart` & `lib/main.dart` — Wiring DI + `MultiBlocProvider` + `MainShellPage` (BottomNavigationBar).
- `test/` — Unit/BLoC/Widget tests cho `pos_calculator`, `CatalogCubit`, `CartCubit`, `InvoiceCubit`, `ProductCard`.

---

## Phase 1: Backend (`Node.js` + `Fastify` + `node:sqlite`)

### Task 1: Khởi tạo Backend, SQLite Schema & POS Pricing Service

**Files:**
- Create: `backend/package.json`
- Create: `backend/src/db/database.js`
- Create: `backend/src/services/pricing.js`
- Test: `backend/test/pricing.test.js`

**Interfaces:**
- Produces (`backend/src/db/database.js`):
  - `openDatabase(dbPath: string): DatabaseSync` (tạo thư mục cha nếu cần, bật `WAL`, tạo schema `products`, `orders`, `order_items` & index `idx_products_sku_name`)
- Produces (`backend/src/services/pricing.js`):
  - `calculateOrderPricing(items: Array<{ productId, sku, name, unit, unitPrice, quantity, discountPercent, vatRate, note }>, orderDiscountPercent: number): { items: ComputedLine[], subtotal: number, discountPercent: number, discountAmount: number, totalPayable: number }`

- [ ] **Step 1: Tạo `backend/package.json` và viết failing test cho `pricing.js`**

Tạo `backend/package.json` với `"type": "module"`, scripts `"start": "node src/server.js"`, `"seed": "node src/db/seed.js"`, `"test": "node --test test/*.test.js"`, và dependencies `fastify`, `@fastify/cors`, `@fastify/static`.

Viết `backend/test/pricing.test.js` kiểm tra:
- `test('tinh chinh xac so le VNĐ cho chiet khau dong, VAT va giam gia don')`: đầu vào `unitPrice: 33333, quantity: 3, discountPercent: 15, vatRate: 8` và `orderDiscountPercent: 5` -> kiểm tra từng trường `discountAmount`, `vatAmount`, `lineTotal`, `subtotal`, `totalPayable` khớp quy tắc `Math.round` từng bước.
- `test('tu choi so luong <= 0 hoac % chiet khau ngoai [0, 100]')`: kiểm tra ném `RangeError` với `quantity: 0`, `discountPercent: 105`, `orderDiscountPercent: -1`.

- [ ] **Step 2: Cài dependencies và chạy test để xác nhận fail**

Run: `cd backend && npm install && node --test test/pricing.test.js`
Expected: FAIL với lỗi không tìm thấy `../src/services/pricing.js`.

- [ ] **Step 3: Implement `database.js` và `pricing.js`**

- Trong `backend/src/db/database.js`: implement `openDatabase(dbPath)` dùng `DatabaseSync` từ `node:sqlite`, chạy `PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;`, tạo 3 bảng `products`, `orders`, `order_items` theo đúng cột trong spec, cùng index `CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)`.
- Trong `backend/src/services/pricing.js`: implement `calculateOrderPricing(items, orderDiscountPercent)` validate `items.length > 0`, `quantity > 0`, `0 <= discountPercent <= 100`, `0 <= vatRate <= 100`, `0 <= orderDiscountPercent <= 100`, tính và làm tròn `Math.round()` từng bước.

- [ ] **Step 4: Chạy lại test để xác nhận pass**

Run: `cd backend && node --test test/pricing.test.js`
Expected: PASS (tất cả test cases xanh).

---

### Task 2: Seeder 100.000 sản phẩm & Bộ Media mẫu `< 5MB`

**Files:**
- Create: `backend/src/db/seed.js`
- Test: `backend/test/seed.test.js`

**Interfaces:**
- Consumes: `openDatabase(dbPath)` từ `backend/src/db/database.js`
- Produces:
  - `ensureSampleMedia(mediaDir: string): { images: string[], video: string }`
  - `seedProducts(db: DatabaseSync, count?: number): number` (mặc định `count = 100000`, idempotent: nếu bảng `products` đã có dữ liệu thì bỏ qua và trả về tổng số dòng hiện có)

- [ ] **Step 1: Viết failing test `backend/test/seed.test.js`**

Kiểm tra trên DB tạm (`:memory:` hoặc file temp) + thư mục media temp:
- `ensureSampleMedia` tạo các file ảnh PNG hợp lệ và 1 file MP4 mẫu đều có `statSync(file).size < 5 * 1024 * 1024` (dưới 5MB).
- `seedProducts(db, 1000)` (chạy nhanh trong test) và gọi lại lần 2 xác nhận tổng dòng vẫn là `1000` (idempotent), mọi dòng có `stock === 10`, `media_type` là `'image'` hoặc `'video'`, và `thumbnail_url` khác rỗng.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `cd backend && node --test test/seed.test.js`
Expected: FAIL với lỗi module `seed.js` chưa tồn tại.

- [ ] **Step 3: Implement `backend/src/db/seed.js`**

- `ensureSampleMedia(mediaDir)`: tạo thư mục nếu chưa có; tạo 4 file PNG màu khác nhau (dùng `zlib.deflateSync` + CRC32 thuần Node không cần dependency ảnh ngoài) và 1 file MP4 tối giản hợp lệ (ftyp + moov + mdat hợp lệ kích thước vài KB–vài trăm KB, `< 5MB`) nếu chưa tồn tại.
- `seedProducts(db, count = 100000)`: kiểm tra `SELECT COUNT(*) AS cnt FROM products`; nếu `cnt > 0` return `cnt`. Ngược lại chạy `BEGIN` -> prepared statement `INSERT INTO products (...) VALUES (...)` trong vòng lặp `1..count` -> `COMMIT` (90% `image`, 10% `video`, giá từ `15.000` đến `2.500.000`, VAT `0`/`8`/`10`, `stock = 10`). Cho phép chạy trực tiếp bằng `node src/db/seed.js` để tạo sẵn `backend/data/pos.db`.

- [ ] **Step 4: Chạy test & chạy seed thật 100.000 dòng kiểm tra tốc độ**

Run: `cd backend && node --test test/seed.test.js && node src/db/seed.js`
Expected: Test PASS; seed 100.000 dòng hoàn tất trong vài giây và in tổng số bản ghi `100000`.

---

### Task 3: Fastify App & 3 API Luồng Sản phẩm / Tồn kho / Media

**Files:**
- Create: `backend/src/routes/products.js`
- Create: `backend/src/app.js`
- Test: `backend/test/products_routes.test.js`

**Interfaces:**
- Consumes: `openDatabase`, `seedProducts`, `ensureSampleMedia`
- Produces:
  - `registerProductRoutes(fastify, { db, stockDelayMs })`
  - `buildApp({ dbPath, mediaDir, stockDelayMs, autoSeedCount }): FastifyInstance`
  - Endpoints:
    - `GET /api/products?page=1&limit=10&q=` -> `{ items: [{ id, sku, name, unit, price, vatRate }], page, limit, total, hasMore }`
    - `GET /api/products/:id/stock` -> `{ productId, stock }` (sau `stockDelayMs`, mặc định `1000`ms; hủy `setTimeout` khi `request.raw` đóng sớm)
    - `GET /api/products/:id/media` -> `{ productId, mediaType, mediaUrl, thumbnailUrl, sizeBytes }` (URL đầy đủ dựa trên `request.protocol + '://' + request.headers.host` hoặc path `/media/...` chuẩn hóa)

- [ ] **Step 1: Viết failing integration test `backend/test/products_routes.test.js`**

Dùng `fastify.inject()` trên DB seed `25` sản phẩm:
- `GET /api/products?page=1&limit=10` trả `200`, `items.length === 10`, không chứa `stock` hay `mediaUrl`, `hasMore === true`; `page=3` trả `5` items và `hasMore === false`.
- `GET /api/products/1/stock` với `stockDelayMs: 50` trả `200` với `{ productId: 1, stock: 10 }`; ID không tồn tại trả `404`.
- `GET /api/products/1/media` trả `200` với `sizeBytes < 5 * 1024 * 1024` và file tải qua `GET /media/...` trả `200`.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `cd backend && node --test test/products_routes.test.js`
Expected: FAIL vì chưa có `app.js` / `products.js`.

- [ ] **Step 3: Implement `backend/src/routes/products.js` và `backend/src/app.js`**

- Trong `products.js`: phân trang `LIMIT ? OFFSET ?` kèm tìm kiếm `WHERE sku LIKE ? OR name LIKE ?` khi có `q`. Route `/stock` tạo `Promise` bọc `setTimeout` và lắng nghe `request.raw.on('close', ...)` để `clearTimeout` nếu client hủy request giữa chừng (giải phóng tài nguyên khi mobile cancel). Route `/media` đọc `media_type`, `media_url`, `thumbnail_url`, đo kích thước file thực bằng `fs.statSync` (hoặc cache stat map) để trả `sizeBytes`.
- Trong `app.js`: đăng ký `@fastify/cors` (`origin: true`), `@fastify/static` mount `/media/` trỏ tới `mediaDir`, và register routes.

- [ ] **Step 4: Chạy test để xác nhận pass**

Run: `cd backend && node --test test/products_routes.test.js`
Expected: PASS.

---

### Task 4: Order API (Transaction Trừ Tồn Kho & Cấp Mã Đơn) + Server Entrypoint

**Files:**
- Create: `backend/src/routes/orders.js`
- Create: `backend/src/server.js`
- Modify: `backend/src/app.js` (register `orders` routes)
- Test: `backend/test/orders_routes.test.js`

**Interfaces:**
- Consumes: `calculateOrderPricing` từ `backend/src/services/pricing.js`, `db`
- Produces:
  - `POST /api/orders`: body `{ staffName, paymentMethod, discountPercent, store: { name, phone, address, logoUrl }, items: [{ productId, quantity, discountPercent, vatRate, note }] }` -> trả `201` với object hóa đơn đầy đủ (`orderCode`, `createdAt`, `items`, `subtotal`, `discountPercent`, `discountAmount`, `totalPayable`, ...). Trả `409` nếu `quantity > stock` hoặc `400` nếu input không hợp lệ.
  - `GET /api/orders?limit=20` -> trả `{ items: [...] }` danh sách hóa đơn gần nhất kèm `items` chi tiết để xem lại và in lại.

- [ ] **Step 1: Viết failing integration test `backend/test/orders_routes.test.js`**

Kiểm tra các kịch bản (bao gồm **Review Focus #2 & #3**):
- Tạo đơn thành công (`201`): gửi `unitPrice` giả mạo từ client -> xác nhận backend bỏ qua giá giả mạo, tính theo `products.price` trong DB, sinh `orderCode` dạng `HD-YYYYMMDD-XXXX`, và `GET /api/products/:id/stock` sau đó giảm đúng bằng `quantity`.
- Đặt vượt tồn kho / hai đơn cạnh tranh (`stock = 10`, đơn 1 đặt `7`, đơn 2 đặt `5`): đơn 1 trả `201` (`stock` còn `3`), đơn 2 trả `409` và `stock` vẫn giữ nguyên `3` (không âm).
- `GET /api/orders` trả về hóa đơn mới tạo kèm đầy đủ chi tiết dòng hàng.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `cd backend && node --test test/orders_routes.test.js`
Expected: FAIL.

- [ ] **Step 3: Implement `backend/src/routes/orders.js`, gắn vào `app.js`, và tạo `backend/src/server.js`**

- Trong `POST /api/orders`: dùng `BEGIN IMMEDIATE` transaction trong SQLite để đọc `products` theo IDs, kiểm tra `stock >= quantity`, gọi `calculateOrderPricing` với `price` lấy từ DB, trừ `stock = stock - quantity`, insert `orders` + `order_items`, `COMMIT` (hoặc `ROLLBACK` khi lỗi).
- Trong `server.js`: mở `backend/data/pos.db`, đảm bảo media & seed `100000` sản phẩm khi khởi động nếu trống, listen `host: '0.0.0.0', port: 3000`.

- [ ] **Step 4: Chạy toàn bộ backend test suite**

Run: `cd backend && node --test test/*.test.js`
Expected: PASS toàn bộ `pricing`, `seed`, `products_routes`, `orders_routes`.

---

## Phase 2: Mobile (`Flutter` Clean Architecture + `BLoC/Cubit`)

### Task 5: Cấu hình Dependencies, Android Permissions & Core POS Utilities

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `lib/core/config/app_config.dart`
- Create: `lib/core/network/dio_client.dart`
- Create: `lib/core/utils/pos_calculator.dart`
- Create: `lib/core/utils/currency_formatter.dart`
- Test: `test/core/pos_calculator_test.dart`

**Interfaces:**
- Produces (`lib/core/utils/pos_calculator.dart`):
  - `class PosLineCalculation { final double grossAmount, discountAmount, taxableAmount, vatAmount, lineTotal; }`
  - `class PosOrderCalculation { final double subtotal, discountAmount, totalPayable; }`
  - `PosLineCalculation calculateLine({ required double unitPrice, required double quantity, required double discountPercent, required double vatRate })`
  - `PosOrderCalculation calculateOrder({ required List<double> lineTotals, required double orderDiscountPercent })`
- Produces (`lib/core/network/dio_client.dart`):
  - `class DioClient { Dio get dio; void updateBaseUrl(String baseUrl); }` (cấu hình `IOHttpClientAdapter` với `maxConnectionsPerHost = 16`, `connectTimeout: 5s`, `receiveTimeout: 10s`)

- [ ] **Step 1: Cập nhật `pubspec.yaml`, `AndroidManifest.xml`, và viết failing test `test/core/pos_calculator_test.dart`**

- Thêm dependencies vào `pubspec.yaml`: `flutter_bloc`, `equatable`, `dio`, `cached_network_image`, `shimmer`, `video_player`, `shared_preferences`, `pdf`, `printing`, `print_bluetooth_thermal`, `image`, `intl`; dev_dependencies: `bloc_test`, `mocktail`.
- Trong `AndroidManifest.xml`: thêm `android:usesCleartextTraffic="true"` trên `<application>`, cùng các `<uses-permission>`: `INTERNET`, `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, `ACCESS_FINE_LOCATION`.
- Viết `test/core/pos_calculator_test.dart` test các ca số lẻ khớp với `backend/test/pricing.test.js` (`33333`, SL `3`, CK `15%`, VAT `8%`, giảm đơn `5%`) và biên lỗi `ArgumentError` khi `quantity <= 0` hoặc `%` ngoài `[0, 100]` (**Review Focus #3**).

- [ ] **Step 2: Chạy `flutter pub get` và chạy test để xác nhận fail**

Run: `flutter pub get && flutter test test/core/pos_calculator_test.dart`
Expected: FAIL vì chưa tạo `pos_calculator.dart`.

- [ ] **Step 3: Implement `app_config.dart`, `dio_client.dart`, `pos_calculator.dart`, `currency_formatter.dart`**

Implement công thức làm tròn `.roundToDouble()` từng bước giống hệt `pricing.js`, format tiền tệ `###,### đ` qua `intl`, và cấu hình `DioClient` với `IOHttpClientAdapter` (`httpClient.maxConnectionsPerHost = 16`).

- [ ] **Step 4: Chạy test & analyze**

Run: `flutter test test/core/pos_calculator_test.dart && flutter analyze lib/core`
Expected: PASS, zero analyzer issues.

---

### Task 6: Feature `settings` (Cửa hàng, Logo, Nhân viên, Server URL, Cấu hình Máy in)

**Files:**
- Create: `lib/features/settings/domain/entities/app_settings.dart` (`StoreConfig`, `PrinterConfig`, `PrinterMode { escPosLan, escPosBluetooth, pdfSystem }`, `AppSettings`)
- Create: `lib/features/settings/domain/repositories/settings_repository.dart`
- Create: `lib/features/settings/data/datasources/settings_local_datasource.dart`
- Create: `lib/features/settings/data/repositories/settings_repository_impl.dart`
- Create: `lib/features/settings/presentation/cubit/settings_cubit.dart`
- Create: `lib/features/settings/presentation/cubit/settings_state.dart`
- Create: `lib/features/settings/presentation/pages/settings_page.dart`
- Test: `test/features/settings/settings_cubit_test.dart`

**Interfaces:**
- Consumes: `DioClient` (cập nhật `baseUrl` khi `serverUrl` đổi), `SharedPreferences`
- Produces:
  - `SettingsCubit`: `loadSettings()`, `saveSettings(AppSettings)`, `scanBluetoothDevices()`, `SettingsState` giữ `AppSettings` hiện tại.

- [ ] **Step 1: Viết failing test `test/features/settings/settings_cubit_test.dart`**

Test `loadSettings()` trả về cấu hình mặc định hợp lệ (`serverUrl: http://10.0.2.2:3000`, danh sách nhân viên mẫu, `StoreConfig` mặc định) khi `SharedPreferences` trống, và `saveSettings()` lưu bền vững + gọi `dioClient.updateBaseUrl(...)`.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `flutter test test/features/settings/settings_cubit_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement Clean Architecture layers (`domain` -> `data` -> `presentation`) cho `settings`**

`SettingsPage` cho phép sửa nhanh: Server URL (kèm nút điền nhanh `10.0.2.2:3000`), Tên/SĐT/Địa chỉ/Logo URL cửa hàng, Nhân viên mặc định, Chế độ in (`ESC/POS LAN`, `ESC/POS Bluetooth`, `PDF / Android Print`), IP/Port máy in LAN (`9100`), khổ giấy (`80mm` / `58mm`), và chọn thiết bị Bluetooth đã ghép nối.

- [ ] **Step 4: Chạy test & analyze**

Run: `flutter test test/features/settings/settings_cubit_test.dart && flutter analyze lib/features/settings`
Expected: PASS.

---

### Task 7: Feature `catalog` — Domain, 3-Stream Remote Datasource & CancelToken

**Files:**
- Create: `lib/features/catalog/domain/entities/product.dart` (`Product`, `ProductStockResult`, `ProductMedia`, `CatalogPageResult`)
- Create: `lib/features/catalog/domain/repositories/catalog_repository.dart`
- Create: `lib/features/catalog/data/datasources/catalog_remote_datasource.dart`
- Create: `lib/features/catalog/data/repositories/catalog_repository_impl.dart`
- Test: `test/features/catalog/catalog_remote_datasource_test.dart`

**Interfaces:**
- Consumes: `DioClient`
- Produces (`CatalogRepository`):
  - `Future<CatalogPageResult> fetchProducts({ required int page, int limit = 10, String query = '', CancelToken? cancelToken })`
  - `Future<int> fetchProductStock(int productId, { CancelToken? cancelToken })`
  - `Future<ProductMedia> fetchProductMedia(int productId, { CancelToken? cancelToken })`

- [ ] **Step 1: Viết failing test `test/features/catalog/catalog_remote_datasource_test.dart`**

Mock `Dio` (adapter/mocktail):
- Kiểm tra `fetchProducts` parse đúng `{ items, page, limit, total, hasMore }`.
- Kiểm tra `fetchProductStock` và `fetchProductMedia` truyền đúng `cancelToken` và ném/xử lý `DioExceptionType.cancel` sạch sẽ để tầng Cubit phân biệt được cancel với lỗi mạng thật.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `flutter test test/features/catalog/catalog_remote_datasource_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `domain` và `data` cho `catalog`**

Log debug thời gian phản hồi Luồng 1, Luồng 2, Luồng 3 và thông báo `CANCELLED` bằng `debugPrint` (chỉ ra console/DevTools, không đưa lên UI).

- [ ] **Step 4: Chạy test & analyze**

Run: `flutter test test/features/catalog/catalog_remote_datasource_test.dart && flutter analyze lib/features/catalog`
Expected: PASS.

---

### Task 8: Feature `catalog` — Shopee-like `CatalogCubit` (LRU Cache, Prefetch, Parallel Concurrency & Cancellation)

**Files:**
- Create: `lib/features/catalog/presentation/cubit/catalog_state.dart`
- Create: `lib/features/catalog/presentation/cubit/catalog_cubit.dart`
- Test: `test/features/catalog/catalog_cubit_test.dart`

**Interfaces:**
- Consumes: `CatalogRepository`
- Produces (`CatalogCubit`):
  - `loadInitial({ String query = '' })`
  - `onScrollPositionChanged({ required int firstVisibleIndex, required int lastVisibleIndex })` (kích hoạt prefetch khi gần cuối danh sách, quản lý cửa sổ trang active + ±1 trang, hủy `CancelToken` cho trang cũ và debounce ~150ms khi cuộn nhanh)
  - `loadNextPage()`
  - `decrementLocalStock(Map<int, double> soldQuantities)` (cập nhật tồn kho ngay trên UI sau khi xuất đơn thành công)
  - `CatalogState`: `products` (theo thứ tự trang còn giữ trong LRU max 20 trang), `stockByProductId` (`Map<int, StockLoadStatus>` gồm `loading`, `loaded(int)`, `error`), `mediaByProductId` (`Map<int, MediaLoadStatus>`), `isLoadingInitial`, `isLoadingMore`, `hasMore`, `searchQuery`.

- [ ] **Step 1: Viết failing test `test/features/catalog/catalog_cubit_test.dart`**

Sử dụng `bloc_test` + `mocktail` kiểm tra (**Review Focus #1**):
- `loadInitial()` emit danh sách 10 sản phẩm từ Luồng 1 ngay lập tức trong khi Luồng 2 (`fetchProductStock`) và Luồng 3 (`fetchProductMedia`) vẫn đang chờ, sau đó 10 request Luồng 2 & 10 request Luồng 3 chạy song song (tổng thời gian bằng 1 lần trễ, không phải 10 lần).
- Khi gọi `onScrollPositionChanged` nhảy nhanh từ trang 1 sang trang 5 (sau khi vượt debounce), `CancelToken` của trang 1 bị `.cancel()` và lỗi `DioExceptionType.cancel` KHÔNG chuyển trạng thái sang lỗi đỏ (`error`).
- Khi `cubit.close()` xảy ra trong lúc request Luồng 2/3 vẫn đang chạy và sau đó mới hoàn tất, không xảy ra `StateError: Cannot emit new states after calling close`.
- Khi số trang vượt quá giới hạn LRU (`20` trang), trang cũ nhất được giải phóng khỏi state map để giữ RAM ổn định.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `flutter test test/features/catalog/catalog_cubit_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `catalog_state.dart` và `catalog_cubit.dart`**

- Mỗi `page` giữ 1 `CancelToken` riêng cho Luồng 2 và Luồng 3 của trang đó.
- Khi `onScrollPositionChanged` phát hiện trang đang nhìn + vùng đệm `[activePage - 1 .. activePage + 1]` thay đổi: hủy các `CancelToken` nằm ngoài vùng đệm, dùng `Timer(150ms)` debounce trước khi bắn Luồng 2 & 3 cho trang mới vào vùng nhìn thấy, và tự `loadNextPage()` nếu `lastVisibleIndex >= products.length - 3`.
- Trước mọi `emit(...)`, kiểm tra `if (isClosed) return;`.

- [ ] **Step 4: Chạy test & analyze**

Run: `flutter test test/features/catalog/catalog_cubit_test.dart && flutter analyze lib/features/catalog`
Expected: PASS.

---

### Task 9: Feature `catalog` — UI Shopee-like (`CatalogPage`, `ProductCard`, Shimmer, Video Dialog)

**Files:**
- Create: `lib/features/catalog/presentation/widgets/product_card.dart`
- Create: `lib/features/catalog/presentation/widgets/video_detail_dialog.dart`
- Create: `lib/features/catalog/presentation/pages/catalog_page.dart`
- Test: `test/features/catalog/product_card_test.dart`

**Interfaces:**
- Consumes: `CatalogCubit`, `CartCubit` (thêm sản phẩm vào giỏ)
- Produces: `CatalogPage`, `ProductCard` (chiều cao cố định, khung ảnh `memCacheWidth: 300` + Shimmer + FadeIn, badge tồn kho Shimmer -> `Còn: X`, badge `Video` mở `VideoDetailDialog`, nút `+ Thêm`).

- [ ] **Step 1: Viết failing widget test `test/features/catalog/product_card_test.dart`**

Kiểm tra (**Review Focus #4**):
- Card hiển thị đầy đủ Tên, Mã SKU, ĐVT, Giá bán ngay khi Luồng 1 có dữ liệu dù Luồng 2 & 3 vẫn ở trạng thái `loading` (hiển thị Shimmer thay vì khóa card hay hiện text lỗi).
- Item `mediaType == 'video'` trên card hiển thị badge Play/Video và KHÔNG khởi tạo `VideoPlayerController` trên danh sách; chỉ mở dialog video khi user chạm vào vùng media.
- Bấm nút `+ Thêm` gọi callback `onAddToCart` ngay cả khi tồn kho đang tải hoặc còn hàng; nếu tồn kho đã load về `0` thì disable nút thêm và hiện `Hết hàng`.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `flutter test test/features/catalog/product_card_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `product_card.dart`, `video_detail_dialog.dart`, `catalog_page.dart`**

- `CatalogPage` dùng `CustomScrollView` + `SliverGrid` (hoặc `GridView.builder` 2 cột với `childAspectRatio` cố định) + ô tìm kiếm debounce 300ms theo tên/mã SKU + `NotificationListener<ScrollNotification>` / `ScrollController` tính chính xác `firstVisibleIndex` / `lastVisibleIndex` để báo cho `CatalogCubit.onScrollPositionChanged`.
- `ProductCard` dùng `CachedNetworkImage(memCacheWidth: 300, fadeInDuration: Duration(milliseconds: 200), errorWidget: ...)` bảo đảm không nhảy layout hay crash khi link hỏng.
- `VideoDetailDialog` khởi tạo `VideoPlayerController.networkUrl(...)` trong `initState` và bắt buộc `controller.dispose()` trong `dispose()`.

- [ ] **Step 4: Chạy test & analyze**

Run: `flutter test test/features/catalog/product_card_test.dart && flutter analyze lib/features/catalog`
Expected: PASS.

---

### Task 10: Feature `cart` — Giỏ hàng POS, Chiết khấu/VAT/Ghi chú & Lưu nháp cục bộ

**Files:**
- Create: `lib/features/cart/domain/entities/cart_item.dart`
- Create: `lib/features/cart/domain/entities/cart_summary.dart`
- Create: `lib/features/cart/domain/repositories/cart_repository.dart`
- Create: `lib/features/cart/data/datasources/cart_local_datasource.dart`
- Create: `lib/features/cart/data/repositories/cart_repository_impl.dart`
- Create: `lib/features/cart/presentation/cubit/cart_state.dart`
- Create: `lib/features/cart/presentation/cubit/cart_cubit.dart`
- Create: `lib/features/cart/presentation/widgets/cart_item_edit_sheet.dart`
- Create: `lib/features/cart/presentation/pages/cart_page.dart`
- Test: `test/features/cart/cart_cubit_test.dart`

**Interfaces:**
- Consumes: `PosCalculator`, `SharedPreferences`
- Produces:
  - `CartCubit`: `loadDraftCart()`, `addProduct(Product)`, `updateItem(int productId, { double? quantity, double? discountPercent, double? vatRate, String? note })`, `removeItem(int productId)`, `setOrderDiscountPercent(double)`, `setStaffName(String)`, `setPaymentMethod(String)`, `clearCart()`.

- [ ] **Step 1: Viết failing test `test/features/cart/cart_cubit_test.dart`**

Kiểm tra:
- Thêm cùng 1 sản phẩm 2 lần -> tăng `quantity` từ `1` lên `2` và tính lại `CartSummary` tự động.
- Cập nhật `% chiết khấu` (`15%`), `% VAT` (`8%`), `ghi chú hàng`, `% giảm giá đơn` (`5%`) -> khớp `PosCalculator` và tự lưu JSON xuống `CartRepository` (khôi phục lại khi gọi `loadDraftCart()`).
- Nhập `% chiết khấu > 100` hoặc `quantity <= 0` bị chặn (giữ trạng thái hợp lệ + báo validation message).

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `flutter test test/features/cart/cart_cubit_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `cart` (domain -> data -> presentation)**

`CartPage` hiển thị danh sách dòng hàng (chạm để mở `CartItemEditSheet` chỉnh SL, % chiết khấu, % VAT, ghi chú hàng), chọn nhân viên, nhập `% giảm giá` toàn đơn, chọn `hình thức thanh toán`, hiển thị rõ `Tổng giá trị đơn`, `Tiền giảm`, `Tổng cần thanh toán`, và nút **Thanh toán & Xuất hóa đơn**.

- [ ] **Step 4: Chạy test & analyze**

Run: `flutter test test/features/cart/cart_cubit_test.dart && flutter analyze lib/features/cart`
Expected: PASS.

---

### Task 11: Feature `invoice` — Tạo đơn Backend & Dịch vụ In kép (ESC/POS Raster + PDF Android Print)

**Files:**
- Create: `lib/features/invoice/domain/entities/invoice.dart`
- Create: `lib/features/invoice/domain/repositories/invoice_repository.dart`
- Create: `lib/features/invoice/domain/services/printer_service.dart`
- Create: `lib/features/invoice/data/datasources/invoice_remote_datasource.dart`
- Create: `lib/features/invoice/data/repositories/invoice_repository_impl.dart`
- Create: `lib/features/invoice/data/services/pdf_invoice_service.dart`
- Create: `lib/features/invoice/data/services/escpos_raster_printer_service.dart`
- Create: `lib/features/invoice/presentation/cubit/invoice_state.dart`
- Create: `lib/features/invoice/presentation/cubit/invoice_cubit.dart`
- Create: `lib/features/invoice/presentation/pages/invoice_preview_page.dart`
- Create: `lib/features/invoice/presentation/pages/invoice_history_page.dart`
- Test: `test/features/invoice/invoice_cubit_test.dart`
- Test: `test/features/invoice/escpos_raster_test.dart`

**Interfaces:**
- Consumes: `DioClient`, `CartState`, `AppSettings`
- Produces:
  - `InvoiceCubit`: `submitOrderAndOpenPreview(...)`, `printCurrentInvoice(PrinterConfig)`, `loadHistory()`, `selectInvoice(Invoice)`
  - `EscPosRasterPrinterService.encodeBitmapToEscPos(img.Image image): List<int>` (sinh header `GS v 0` chuẩn + dữ liệu 1-bit MSB-first + lệnh cắt giấy `GS V 66 0`)

- [ ] **Step 1: Viết failing tests `invoice_cubit_test.dart` và `escpos_raster_test.dart`**

Kiểm tra (**Review Focus #5**):
- `submitOrderAndOpenPreview` gọi `POST /api/orders` 1 lần, emit trạng thái `InvoiceReady(invoice)`. Sau đó nếu gọi `printCurrentInvoice` bị lỗi kết nối (máy in tắt / timeout), state chuyển báo lỗi in nhưng **giữ nguyên `currentInvoice`** để user bấm **In lại** hoặc **Chuyển sang In PDF / Android Print** mà không gọi lại `POST /api/orders`.
- `encodeBitmapToEscPos` với ảnh trắng đen `384x16` (khổ 58mm) sinh đúng byte prefix `0x1D, 0x76, 0x30, 0x00`, `xL = 48, xH = 0, yL = 16, yH = 0` và tổng độ dài payload raster `48 * 16 = 768` bytes.

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `flutter test test/features/invoice/`
Expected: FAIL.

- [ ] **Step 3: Implement `invoice` (domain -> data -> services -> presentation)**

- `PdfInvoiceService`: dùng `pdf` + `printing` (`PdfGoogleFonts.notoSansRegular()` / asset font Unicode hoặc font hệ thống bundle) dựng hóa đơn đầy đủ 100% trường trong `docs/spec.md` (logo, tên cửa hàng, sđt, địa chỉ, mã đơn, ngày hóa đơn, thời gian tạo, nhân viên, bảng chi tiết dòng hàng có mã, tên, ĐVT, giá bán, % CK, tiền CK, thuế VAT, thành tiền, ghi chú hàng; tổng giá trị đơn, % giảm, tiền giảm, tổng cần thanh toán, hình thức thanh toán) và gọi `Printing.layoutPdf(...)`.
- `EscPosRasterPrinterService`: render `Widget` xem trước hóa đơn (bọc `RepaintBoundary` với bề rộng `576px` cho `80mm` hoặc `384px` cho `58mm`) thành PNG `toByteData` -> decode bằng package `image` -> convert grayscale threshold -> `GS v 0` -> gửi qua TCP `Socket.connect(ip, port, timeout: 3s)` (LAN) hoặc `PrintBluetoothThermal` (Bluetooth).
- `InvoicePreviewPage`: hiển thị bản xem trước hóa đơn (chính widget `RepaintBoundary` dùng để chụp bitmap in ESC/POS!), nút **In máy in nhiệt (ESC/POS)**, nút **In PDF / Hệ thống (Android Print)**, và nút chuyển nhanh sang cấu hình máy in nếu cần.

- [ ] **Step 4: Chạy test & analyze**

Run: `flutter test test/features/invoice/ && flutter analyze lib/features/invoice`
Expected: PASS.

---

### Task 12: Tích hợp `app.dart`, `main.dart` & Smoke Test Toàn luồng

**Files:**
- Create: `lib/app.dart`
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart` (thay thế widget counter mặc định bằng smoke test app POS)

**Interfaces:**
- Consumes: tất cả repositories & cubits từ Tasks 6–11
- Produces: `PosDemoApp` (`MultiRepositoryProvider` + `MultiBlocProvider` + `MainShellPage` gồm 4 tab: `Sản phẩm`, `Giỏ hàng` có badge đếm SL, `Hóa đơn`, `Cài đặt`)

- [ ] **Step 1: Viết failing smoke test trong `test/widget_test.dart`**

Render `PosDemoApp` với fake/mock dependencies hoặc `SharedPreferences.setMockInitialValues({})`, xác nhận hiện đủ 4 tab navigation (`Sản phẩm`, `Giỏ hàng`, `Hóa đơn`, `Cài đặt`), chuyển tab hoạt động không crash.

- [ ] **Step 2: Chạy `flutter test test/widget_test.dart` để xác nhận fail**

Run: `flutter test test/widget_test.dart`
Expected: FAIL vì `PosDemoApp` chưa tồn tại.

- [ ] **Step 3: Implement `lib/app.dart` và cập nhật `lib/main.dart`**

- Khởi tạo `SharedPreferences.getInstance()`, `DioClient`, repositories, và `MultiBlocProvider` (`SettingsCubit`, `CatalogCubit`, `CartCubit`, `InvoiceCubit`).
- Lắng nghe khi `InvoiceCubit` tạo đơn thành công -> gọi `CartCubit.clearCart()` và `CatalogCubit.decrementLocalStock(...)`, đồng thời điều hướng mở `InvoicePreviewPage`.

- [ ] **Step 4: Chạy toàn bộ test suite & build verification**

Run:
- `cd backend && node --test test/*.test.js`
- `flutter analyze && flutter test`
Expected: Toàn bộ backend tests, `flutter analyze`, và `flutter test` đều PASS 100%.

---

## Checklist tự rà soát (Self-Review)
1. **Spec coverage:** Đủ toàn bộ trường dòng hàng & thông tin đơn/cửa hàng trong `docs/spec.md`; đủ 100k sản phẩm, 10 SP/trang, 3 luồng độc lập (`sleep 1s` song song, hủy socket/CancelToken, media `< 5MB`); đủ Clean Architecture + BLoC/Cubit, Shopee-like shimmer/prefetch/LRU/on-demand video, `SharedPreferences` draft cart, in kép ESC/POS raster + PDF Android Print.
2. **Step scan:** Mỗi bước nêu rõ file, interface, test assertions và lệnh verify cụ thể, không có bước mơ hồ.
3. **Type consistency:** Tên class/hàm (`openDatabase`, `calculateOrderPricing`, `PosCalculator`, `DioClient`, `CatalogCubit`, `CartCubit`, `InvoiceCubit`, `SettingsCubit`, `EscPosRasterPrinterService`, `PdfInvoiceService`) thống nhất xuyên suốt từ `Interfaces` tới các task sau.
4. **Review Focus:** Cả 5 kịch bản rủi ro ở mục `Review Focus` đều được gắn test trực tiếp vào đúng task sở hữu (`Task 4`, `Task 5`, `Task 8`, `Task 9`, `Task 11`).
