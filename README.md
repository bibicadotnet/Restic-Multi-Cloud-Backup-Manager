# Restic-Multi-Cloud-Backup-Manager
Bash script tự động sao lưu qua Restic và Rclone
```
[2025-01-22 11:37:00] Bắt đầu backup - cloudflare-free:bibica-net
[2025-01-22 11:37:00] Repository chưa tồn tại, đang khởi tạo...
[2025-01-22 11:37:04] Khởi tạo repository thành công, thực hiện lại backup...
[2025-01-22 11:37:18] Backup thành công
[2025-01-22 11:37:18] Bắt đầu dọn dẹp backup cũ
[2025-01-22 11:37:20] Dọn dẹp backup cũ thành công
[2025-01-22 11:37:20] Bắt đầu kiểm tra toàn vẹn dữ liệu
[2025-01-22 11:37:32] Kiểm tra toàn vẹn dữ liệu thành công
[2025-01-22 11:37:32] Bắt đầu sao lưu dự phòng
[2025-01-22 11:37:32] Có nhiều remote được cấu hình, chạy song song
[2025-01-22 11:37:39] Sao lưu dự phòng thành công - cloudflare-r2:bibica-net
[2025-01-22 11:38:50] Sao lưu dự phòng thành công - google-drive-api:bibica-net
[2025-01-22 11:38:50] Hoàn thành tất cả sao lưu dự phòng
[2025-01-22 11:38:50] Hoàn tất quy trình backup
```

# Cài đặt
- Cài đặt [Restic](https://restic.readthedocs.io/en/latest/020_installation.html) là được, không cần làm gì thêm
- Với [Rclone](https://rclone.org/install/) cấu hình sẵn tối thiểu 1 dịch vụ cloud storage cho Restic, dùng thêm nhiều cloud storage dự phòng thì cứ tạo thêm
- Thông báo Telegram, lấy `BOT_API_KEY` và `CHAT_ID` để nhận tin nhắn
```
sudo mkdir -p /restic && sudo wget https://go.bibica.net/restic -O /restic/restic_backup_manager.sh && sudo chmod +x /restic/restic_backup_manager.sh
```
# Cấu hình

#### Cấu hình Telegram
```
BOT_API_KEY="xxxxx:xxxxxxxxxxxxxxxxxxxx"
CHAT_ID="xxxxxxx"
```
#### Cấu hình Restic Primary Backup
```
export RESTIC_REPOSITORY="rclone:cloudflare-free:bibica-net"
export RESTIC_PASSWORD="your-secure-password"	# đổi thành 1 password tùy thích
```
- `RESTIC_REPOSITORY`: nơi lưu trữ các bản sao lưu chính

Ví dụ: `cloudflare-free` tên của remote đã cấu hình trong Rclone

- `/restic-backup/bibica-net` đường dẫn thư mục trên cloudflare-free
- `RESTIC_PASSWORD`: mật khẩu sử dụng để mã hóa các bản sao lưu
- `your-secure-password` mật khẩu đặt tùy ý
#### Thư mục và file cần sao lưu
```
BACKUP_DIR="/home /var/spool/cron/crontabs/root"
```
Mỗi thư mục hoặc file cách nhau bởi khoảng trắng
#### Chính sách giữ backup
```
KEEP_HOURLY=24	# giữ lại 24 bản snapshot (1 bản mỗi giờ trong 24 giờ gần nhất)
KEEP_DAILY=31	# giữ lại 31 bản snapshot (1 bản mỗi ngày trong 31 ngày gần nhất)
KEEP_MONTHLY=12	# giữ lại 12 bản snapshot (1 bản mỗi tháng trong 12 tháng gần nhất)
```
#### Chính sách kiểm tra toàn vẹn dữ liệu
```
VERIFY_HOUR=4	# Mặc định lúc 4h sáng mỗi ngày
```
Muốn chạy kiểm tra lúc 3h chiều thì sửa `VERIFY_HOUR=15`
#### Cấu hình Secondary Backup 
```
SECONDARY_REMOTE=""
```
- Mặc định để trống: không dùng cloud dự phòng
- Các cloud thêm vào theo cú pháp của rclone, các cloud cách nhau bởi khoảng trắng
Ví dụ: `SECONDARY_REMOTE="cloudflare-free:bibica-net cloudflare-r2:bibica-net google-drive-api:bibica-net"`
