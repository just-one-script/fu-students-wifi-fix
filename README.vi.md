# Sửa lỗi Wi-Fi FU-Students trên Linux

[English](README.md)

Repo này giúp sinh viên FPT University Cần Thơ kết nối các mạng Wi-Fi sau trên Linux:

- `FU-Students`
- `FU-Students Alpha`
- `FU-Students_6G`

Script `fu-students-wifi-fix.sh` trong repo này sẽ cấu hình lại Wi-Fi backend sang `iwd` và tạo sẵn profile cho các mạng trên.

## 1. Hệ thống được hỗ trợ

Script có thể tự cài `iwd` trên các hệ thống dùng:

- `dnf`, ví dụ Fedora
- `apt-get`, ví dụ Ubuntu hoặc Debian

> [!important]
>
> Nếu distro của bạn không dùng `dnf` hoặc `apt-get`, hãy tự cài `iwd` trước rồi chạy lại script.

## 2. Cách dùng nhanh

```bash
git clone https://github.com/just-one-script/fu-students-wifi-fix.git
cd fu-students-wifi-fix
chmod +x fu-students-wifi-fix.sh
sudo ./fu-students-wifi-fix.sh --setup
```

Khi script hỏi có tạo profile Wi-Fi không, chọn yes. Sau đó nhập username/student ID và mật khẩu Wi-Fi của trường.

> [!important]
>
> Sau khi chạy xong, không tạo lại các mạng `FU-Students` từ giao diện Wi-Fi của hệ điều hành. Nếu thông tin đăng nhập đúng, máy sẽ tự kết nối khi thấy mạng phù hợp.

Nếu chạy script mà không thêm flag nào, script chỉ hiện hướng dẫn:

```bash
./fu-students-wifi-fix.sh
```

## 3. Nếu nhập sai tài khoản hoặc mật khẩu khi setup

Không cần rollback. Chạy:

```bash
sudo ./fu-students-wifi-fix.sh --update-credentials
```

Script sẽ hỏi lại username/student ID và mật khẩu, sau đó ghi lại profile Wi-Fi.

Để kiểm tra profile có bị thiếu hoặc bị trống thông tin đăng nhập không:

```bash
sudo ./fu-students-wifi-fix.sh --check
```

> [!note]
>
> Lệnh kiểm tra trên không thể biết mật khẩu đúng hay sai. Nó chỉ kiểm tra profile có tồn tại và có field tài khoản/mật khẩu hay không.

## 4. Nếu vẫn không kết nối được

Thử theo thứ tự:

1. Kiểm tra profile:

   ```bash
   sudo ./fu-students-wifi-fix.sh --check
   ```

2. Nhập lại tài khoản/mật khẩu:

   ```bash
   sudo ./fu-students-wifi-fix.sh --update-credentials
   ```

3. Nếu trước đó bạn đã từng bấm kết nối bằng giao diện Wi-Fi của hệ điều hành, xóa các profile cũ:

   ```bash
   nmcli connection delete FU-Students
   nmcli connection delete 'FU-Students Alpha'
   nmcli connection delete FU-Students_6G
   ```

4. Restart NetworkManager:

   ```bash
   sudo systemctl restart NetworkManager
   ```

5. Nếu vẫn lỗi, reboot máy.

6. Xem log để tìm lỗi:

   ```bash
   journalctl -u iwd -b
   journalctl -u NetworkManager -b
   ```

## 5. Rollback

Nếu muốn hoàn tác thay đổi:

```bash
sudo ./fu-students-wifi-fix.sh --rollback
```

> [!note]
>
> Sau khi rollback, script sẽ hỏi bạn có muốn reboot ngay không. Nên reboot trước khi thử Wi-Fi lại.

## 6. Giấy phép

Dự án này dùng giấy phép GNU General Public License v3.0. Xem [LICENSE](LICENSE).
