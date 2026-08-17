# Sửa lỗi Wi-Fi FU-Students trên Linux

[English](README.md)

Script này giúp kết nối các mạng Wi-Fi sau tại FPT University Cần Thơ:

- `FU-Students`
- `FU-Students Alpha`
- `FU-Students_6G`

Sau khi dùng script, bạn vẫn có thể kết nối Wi-Fi gia đình, Wi-Fi từ điện thoại và các mạng công cộng như bình thường.

## Cài đặt

Mở ứng dụng Terminal tại thư mục chứa script rồi chạy:

```bash
chmod +x fu-students-wifi-fix.sh
sudo ./fu-students-wifi-fix.sh --setup
```

Nhập tài khoản sinh viên và mật khẩu Wi-Fi khi được hỏi. Mật khẩu sẽ không hiện trên màn hình trong lúc nhập.

Sau khi script chạy xong, thử kết nối lại Wi-Fi. Nếu máy vẫn giữ trạng thái lỗi cũ, hãy khởi động lại máy.

> Nếu đã dùng phiên bản cũ của script, chỉ cần chạy lại `--setup`. Không cần chạy lệnh hoàn tác trước.

## Nếu vẫn không kết nối được

Kiểm tra cấu hình đã được tạo đầy đủ:

```bash
sudo ./fu-students-wifi-fix.sh --check
```

Nếu có thể đã nhập sai tài khoản hoặc mật khẩu:

```bash
sudo ./fu-students-wifi-fix.sh --update-credentials
```

### Khi cần chứng chỉ của FPT

Script mặc định dùng các chứng chỉ bảo mật có sẵn trong máy. Nếu Wi-Fi trường vẫn từ chối kết nối, máy có thể cần chứng chỉ riêng của FPT:

1. Tải file `fun-DC-CA.p12` theo [hướng dẫn của Helpdesk FPT Cần Thơ](https://it.fpt.edu.vn/cantho/cach-vao-wifi-truong-bang-dien-thoai/). Bạn có thể cần dùng Wi-Fi khách, mạng điện thoại hoặc một kết nối Internet khác để tải file.
2. Chạy lệnh sau và thay đường dẫn bằng vị trí file vừa tải:

   ```bash
   sudo ./fu-students-wifi-fix.sh --ca-cert ~/Downloads/fun-DC-CA.p12
   ```

3. Ngắt rồi kết nối lại Wi-Fi trường.

Chỉ sử dụng chứng chỉ tải từ nguồn chính thức của FPT. Nếu muốn quay lại dùng chứng chỉ có sẵn trong hệ điều hành:

```bash
sudo ./fu-students-wifi-fix.sh --ca-cert system
```

Nếu vẫn gặp lỗi, gửi kết quả của các lệnh sau cho bộ phận hỗ trợ kỹ thuật:

```bash
sudo ./fu-students-wifi-fix.sh --check
journalctl -u NetworkManager -u iwd -b
```

## Hoàn tác thay đổi

Để đưa cấu hình Wi-Fi về trạng thái trước khi chạy setup:

```bash
sudo ./fu-students-wifi-fix.sh --rollback
```

Nên khởi động lại máy sau khi hoàn tác. Script không gỡ thành phần `iwd` đã cài đặt.

## Hệ thống hỗ trợ

Script có thể tự cài thành phần cần thiết trên Fedora, Ubuntu, Linux Mint và Debian. Với bản Linux khác, bạn có thể phải tự cài `iwd` trước.

## Giấy phép

GNU General Public License v3.0. Xem [LICENSE](LICENSE).
