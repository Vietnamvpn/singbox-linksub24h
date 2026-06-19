# 📖 HƯỚNG DẪN SỬ DỤNG SCRIPT SING-BOX PROXY TOOL V3

Đây là bộ mã nguồn (script) tự động cài đặt và quản lý proxy dựa trên lõi **Sing-box**. Hệ thống hỗ trợ các giao thức mạnh mẽ nhất hiện nay bao gồm: **Hysteria2, TUIC v5, và VLESS (gRPC-Reality)**, kết hợp với cơ sở dữ liệu SQLite để quản lý người dùng thông minh.

## 🛠 I. YÊU CẦU CHUẨN BỊ TRƯỚC KHI CÀI ĐẶT
* **Hệ điều hành:** Linux (Khuyên dùng Ubuntu hoặc Debian vì script sử dụng trình quản lý gói `apt`).
* **Quyền hạn:** Đăng nhập VPS với quyền `root`.
* **Tường lửa:** Đảm bảo đã mở các cổng (port) bạn dự định sử dụng trên trang quản lý Firewall của nhà cung cấp VPS.

---

## 🚀 II. HƯỚNG DẪN CÀI ĐẶT LẦN ĐẦU (INITIAL SETUP)

**Bước 1: Chạy lệnh cài đặt**
Copy dòng lệnh dưới đây và dán vào Terminal (SSH) của VPS:
```bash
curl -sSL https://raw.githubusercontent.com/Vietnamvpn/singbox-ls/refs/heads/main/install.sh | bash
```

**Bước 2: Xác nhận thông tin hệ thống**
Hệ thống sẽ tự động tải các gói cần thiết (curl, jq, sqlite3,...), tải lõi Sing-box mới nhất và hiển thị cấu hình VPS của bạn. Nhấn `1` để đồng ý tiếp tục.

**Bước 3: Thuật sĩ cài đặt Node (Vòng lặp)**
Hệ thống sẽ hỏi bạn muốn cài giao thức nào trước (Hysteria2, TUIC, VLESS).
* **Nhập Port:** Chọn một cổng bất kỳ (VD: 443, 8443, 20000).
* **Nhập Domain:** Nếu có tên miền thì nhập, nếu không có cứ **bỏ trống** (nhấn Enter), hệ thống sẽ tự dùng IP của VPS.
* **Nhập SNI:**
    * *Với Hy2/TUIC:* Bỏ trống để hệ thống tự random (google.com, yahoo.com...).
    * *Với VLESS:* Nếu bỏ trống, mặc định dùng `www.microsoft.com` để ngụy trang (Reality).
* Sau khi thiết lập xong 1 Node, script sẽ hỏi bạn có muốn tạo thêm Node khác không (`y/n`). Bạn có thể tạo nhiều Node cùng lúc ở bước này.

**Bước 4: Tạo User chung**
Nhập tên Người dùng (Username). Mật khẩu và UUID sẽ được **tự động tạo ngẫu nhiên** và áp dụng cho tất cả các Node bạn vừa tạo. 

---

## 💻 III. HƯỚNG DẪN SỬ DỤNG MENU QUẢN LÝ (MAIN MENU)

Sau khi cài đặt xong, bạn sẽ được đưa vào Menu quản lý. 
> 💡 **Mẹo:** Để gọi lại Menu này ở các lần đăng nhập SSH sau, bạn chỉ cần gõ lệnh: **`sbls`** (hoặc chạy lại file cài đặt).

Menu được chia thành các nhóm tính năng sau:

### 1. Nhóm Trạng thái & Theo dõi (Phím 1 - 3)
* **[1] Xem danh sách & Xuất Link kết nối:** Hiển thị toàn bộ User hiện có. Với mỗi User, script sẽ in ra các đường link cấu hình chuẩn (URL scheme) của Hysteria2, TUIC, và VLESS. Bạn chỉ cần copy link này dán vào app trên điện thoại/máy tính (v2rayN, Nekobox, Sing-box...).
* **[2] Xem LOG theo dõi kết nối:** Xem trực tiếp (real-time) các thiết bị đang kết nối vào VPS của bạn. Bấm `Ctrl + C` để thoát màn hình Log.
* **[3] Xem trạng thái hệ thống VPS:** Kiểm tra Uptime, % tải CPU, RAM trống, Ổ cứng trống và các Port mạng đang mở.

### 2. Nhóm Quản lý Node Proxy (Phím 4 - 6)
* **[4] Thêm một Node độc lập mới:** Giúp bạn mở thêm 1 cổng mạng với giao thức mới mà không làm ảnh hưởng đến các Node đang chạy. Hệ thống sẽ tạo một User ngẫu nhiên riêng cho Node này.
* **[5] Xóa bỏ một Node (Đóng cổng):** Nhập Port của Node muốn xóa. Dữ liệu cấu hình, Iptables và database liên quan đến Port này sẽ bị dọn sạch.
* **[6] Cập nhật Đổi cổng hoặc Domain cho Node:** Nhập Port cũ đang chạy, sau đó chọn:
    * Đổi sang Port mới (Tự động cập nhật firewall).
    * Đổi sang Domain/IP mới.
    * Đổi tên Tag hiển thị của Node.

### 3. Nhóm Quản lý Người Dùng - User (Phím 7 - 8, 16)
* **[7] Thêm người dùng:** Bạn nhập Tên User.
    * Nếu muốn thêm vào *1 Node cụ thể*: Nhập Port của Node đó.
    * Nếu muốn thêm vào *Tất cả các Node*: Bỏ trống Port. Mật khẩu và UUID sẽ được tự động đồng bộ.
* **[8] Xóa bỏ người dùng khỏi Node:** Nhập tên User cần xóa. Tương tự, nếu bỏ trống Port, User đó sẽ bị xóa khỏi TOÀN BỘ hệ thống.
* **[16] Tạm khóa / Mở khóa mạng User:** (Tính năng rất hay) Nhập tên User. Hệ thống sẽ "cắt mạng" người này bằng cách xóa khỏi file cấu hình đang chạy, nhưng **vẫn lưu thông tin trong Database**. Khi cần mở lại mạng, chọn lại tính năng này, nhập tên User đó, hệ thống sẽ tự động khôi phục cấu hình như cũ.

### 4. Nhóm Tiện ích Mở rộng (Phím 9 - 10, 17)
* **[9] Tạo bộ nhớ ảo (SWAP):** Giúp VPS không bị treo khi hết RAM. Nhập `1` hoặc `2` tương ứng với 1GB hoặc 2GB RAM ảo.
* **[10] Xin chứng chỉ SSL Cloudflare:** (Dành cho người có tên miền riêng). Yêu cầu nhập Tên miền, Email Cloudflare và Global API Key. Script sẽ dùng `acme.sh` để xin chứng chỉ chuẩn xác thực DNS và tự động gắn vào Sing-box.
* **[17] Cấu hình Webhook:** Cài đặt 1 đường link URL (Trang PHP của bạn) để VPS tự động đẩy dữ liệu Log kết nối lên web mỗi 60 giây. Giúp bạn thống kê dung lượng/IP qua giao diện Web của riêng bạn.

### 5. Nhóm Quản lý Dịch vụ Hệ thống (Phím 11 - 15)
* **[11] Bắt đầu / [12] Dừng / [13] Khởi động lại:** Các lệnh cơ bản để quản lý tiến trình chạy ngầm (Systemd Service) của Sing-box. Thường dùng số **13** sau khi bạn sửa thủ công thứ gì đó.
* **[14] Gỡ cài đặt, Xóa sạch tàn dư:** Dọn sạch 100% mọi thứ script này đã cài ra (Core, DB, Config, Systemd, Tool) đưa VPS về trạng thái ban đầu. **Lưu ý: Không thể khôi phục lại.**
* **[15] Cập nhật Tool (Từ Github):** Tải bản cập nhật mới nhất của đoạn script Menu này từ Github của bạn mà không làm mất dữ liệu hiện tại.

---

## 💡 VÀI LƯU Ý QUAN TRỌNG

1. **Chống trùng lặp:** Hệ thống DB (SQLite) được thiết kế để không cho phép thêm trùng tên User trên cùng 1 Port để tránh xung đột cấu hình json.
2. **Khôi phục mật khẩu:** Do mật khẩu được tạo ngẫu nhiên, nếu bạn quên, hãy dùng tùy chọn **[1]** để in lại toàn bộ Link kết nối. Link sẽ chứa sẵn mật khẩu / UUID của người dùng.
3. **Port Range (Hysteria2):** Nếu ở bước cài đặt bạn sử dụng Port Range (vd: `2000:3000`), hệ thống sẽ tự động tạo luật `iptables` để chuyển tiếp tất cả dải port đó về Port chính của bạn.
