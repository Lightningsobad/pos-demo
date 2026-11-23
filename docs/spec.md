
```
1. In ấn hóa đơn trên mobile (tạo giỏ hàng sản phẩm, có đầy đủ thông tin: mã,
tên, đvt, giá bán, % chiết khấu, tiền chiết khấu, thuế VAT, thành tiền, ghi chú
hàng; đơn: logo, tên cửa hàng,sđt, địa chỉ, mã đơn, ngày hoá đơn, thời gian tạo,
nhân viên, tổng giá trị đơn, % giảm giá, tiền giảm, tổng cần thanh toán, hình
thức thanh toán
```

```
2. Tạo 100k dữ liệu -> Xử lý load 3 luồng bằng cách phân trang (10 sản
phẩm/trang)
```

```
- Luồng 1: Load danh sách sản phẩm (ID, tên, đơn vị tính, đơn giá)
- Luồng 2: Load tồn kho sản phẩm (cho vào sleep 1' cho 1 sản phẩm, và trả về giá
trị là 10)
- Luồng 3: Load video, hình ảnh (mỗi video hoặc hình ảnh <5mb và dùng link)
```


