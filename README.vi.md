# Sửa lỗi Wi-Fi FU-Students trên Linux

[English](README.md)

Script này giúp kết nối các mạng Wi-Fi sau tại FPT University Cần Thơ:

- `FU-Students`
- `FU-Students Alpha`
- `FU-Students_6G`

Script có thể tự cài thành phần cần thiết trên Fedora, Ubuntu, Linux Mint và Debian. Với bản Linux khác, bạn có thể phải tự cài `iwd` trước (tìm `iwd install <tên distro>` trên mạng để được hướng dẫn).

## Cài đặt

Mở Terminal và chạy các lệnh sau:

```bash
git clone https://github.com/just-one-script/fu-students-wifi-fix.git
cd fu-students-wifi-fix
chmod +x fu-students-wifi-fix.sh
sudo ./fu-students-wifi-fix.sh --setup
```

Nhập tên đăng nhập và mật khẩu Wi-Fi khi được hỏi.

Nếu máy vẫn chưa kết nối được vào mạng ngay sau khi chạy script, hãy khởi động lại máy.

## Nếu vẫn không kết nối được sau khi khởi động lại

Kiểm tra cấu hình đã được tạo đầy đủ:

```bash
sudo ./fu-students-wifi-fix.sh --check
```

Nếu có thể đã nhập sai tài khoản hoặc mật khẩu:

```bash
sudo ./fu-students-wifi-fix.sh --update-credentials
```

## Hoàn tác thay đổi

Để đưa cấu hình Wi-Fi về trạng thái trước khi chạy setup:

```bash
sudo ./fu-students-wifi-fix.sh --rollback
```

**Nên khởi động lại máy sau khi hoàn tác.** Script không gỡ thành phần `iwd` đã cài đặt.

## Giấy phép

GNU General Public License v3.0. Xem [LICENSE](LICENSE).
