# Sửa lỗi Wi-Fi FU-Students trên Linux

[English](README.md)

Repo này giúp sinh viên FPT University Cần Thơ kết nối các mạng Wi-Fi sau trên Linux:

- `FU-Students`
- `FU-Students Alpha`
- `FU-Students_6G`

Lỗi thường gặp: bạn thấy Wi-Fi, bấm vào nhập tài khoản/mật khẩu, nhưng sau khi bấm **Connect** thì không có gì xảy ra. Bấm lại vào Wi-Fi thì máy lại hỏi tài khoản/mật khẩu lần nữa.

Script trong repo này sẽ cấu hình lại Wi-Fi backend sang `iwd` và tạo sẵn profile cho các mạng trên.

## Cách dùng nhanh

Clone repo, sau đó chạy:

```bash
chmod +x setup.sh rollback.sh
sudo ./setup.sh
```

Khi script hỏi có tạo profile Wi-Fi không, chọn yes. Sau đó nhập username/student ID và mật khẩu Wi-Fi của trường.

Sau khi chạy xong, không tạo lại các mạng `FU-Students` từ giao diện Wi-Fi của hệ điều hành. Nếu thông tin đăng nhập đúng, máy sẽ tự kết nối khi thấy mạng phù hợp.

## Nếu nhập sai tài khoản hoặc mật khẩu

Không cần rollback. Chạy:

```bash
sudo ./setup.sh --update-credentials
```

Script sẽ hỏi lại username/student ID và mật khẩu, sau đó ghi lại profile Wi-Fi.

Để kiểm tra profile có bị thiếu hoặc bị trống thông tin đăng nhập không:

```bash
sudo ./setup.sh --check
```

Lưu ý: lệnh kiểm tra không thể biết mật khẩu đúng hay sai. Nó chỉ kiểm tra profile có tồn tại và có field tài khoản/mật khẩu hay không.

## Nếu vẫn không kết nối được

Thử theo thứ tự:

1. Kiểm tra profile:

   ```bash
   sudo ./setup.sh --check
   ```

2. Nhập lại tài khoản/mật khẩu:

   ```bash
   sudo ./setup.sh --update-credentials
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

## Rollback

Nếu muốn hoàn tác thay đổi:

```bash
sudo ./rollback.sh
```

Sau khi rollback, script sẽ hỏi bạn có muốn reboot ngay không. Nên reboot trước khi thử Wi-Fi lại.

## Các lệnh trợ giúp

Xem hướng dẫn của script setup:

```bash
./setup.sh --help
```

Xem hướng dẫn của script rollback:

```bash
./rollback.sh --help
```

## Script sẽ thay đổi gì?

Script có thể ghi vào các file/thư mục sau:

- `/etc/NetworkManager/conf.d/wifi_backend.conf`
- `/var/lib/iwd/FU-Students.8021x`
- `/var/lib/iwd/FU-Students Alpha.8021x`
- `/var/lib/iwd/FU-Students_6G.8021x`
- `/var/backups/fu-students-wifi-fix/`
- `/var/lib/fu-students-wifi-fix/`

Nếu đã có profile iwd cũ cho các mạng này, script sẽ sao lưu trước khi ghi profile mới.

## Hệ thống được hỗ trợ

Script có thể tự cài `iwd` trên các hệ thống dùng:

- `dnf`, ví dụ Fedora
- `apt-get`, ví dụ Ubuntu hoặc Debian

Nếu distro của bạn không dùng `dnf` hoặc `apt-get`, hãy tự cài `iwd` trước rồi chạy lại script.

## Giấy phép

Dự án này dùng giấy phép GNU General Public License v3.0. Xem [LICENSE](LICENSE).
