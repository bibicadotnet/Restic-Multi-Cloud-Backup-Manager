# Restic-Multi-Cloud-Backup-Manager
Bash script tự động sao lưu qua Restic và Rclone

# Cài đặt
```
sudo mkdir -p /restic && sudo wget https://go.bibica.net/restic -O /restic/restic_backup_manager.sh && sudo chmod +x /restic/restic_backup_manager.sh
```
# Cấu hình
```
nano /restic/restic_backup_manager.sh
```
#### Cấu hình Telegram
```
BOT_API_KEY="xxxxx:xxxxxxxxxxxxxxxxxxxx"
CHAT_ID="xxxxxxx"
```
#### Cấu hình Restic Primary Backup
- `RESTIC_REPOSITORY`: nơi lưu trữ các bản sao lưu chính

Ví dụ: `cloudflare-free` tên của remote đã cấu hình trong Rclone

- `/restic-backup/bibica-net` đường dẫn thư mục trên cloudflare-free
- `RESTIC_PASSWORD`: mật khẩu sử dụng để mã hóa các bản sao lưu
- `your-secure-password` mật khẩu đặt tùy ý
```
export RESTIC_REPOSITORY="rclone:cloudflare-free:bibica-net"
export RESTIC_PASSWORD="your-secure-password"	# đổi thành 1 password tùy thích
```
#### Thư mục và file cần sao lưu
Mỗi thư mục hoặc file cách nhau bởi khoảng trắng
```
BACKUP_DIR="/home /var/spool/cron/crontabs/root"
```
#### Chính sách giữ backup
```
KEEP_HOURLY=24	# giữ lại 24 bản snapshot (1 bản mỗi giờ trong 24 giờ gần nhất)
KEEP_DAILY=31	# giữ lại 31 bản snapshot (1 bản mỗi ngày trong 31 ngày gần nhất)
KEEP_MONTHLY=12	# giữ lại 12 bản snapshot (1 bản mỗi tháng trong 12 tháng gần nhất)
```
#### Chính sách kiểm tra toàn vẹn dữ liệu
Muốn chạy kiểm tra lúc 3h chiều thì sửa VERIFY_HOUR=15
```
VERIFY_HOUR=4	# Mặc định lúc 4h sáng mỗi ngày
```
#### Cấu hình Secondary Backup 
- Mặc định để trống: không dùng cloud dự phòng
- Các cloud thêm vào theo cú pháp của rclone, các cloud cách nhau bởi khoảng trắng

Ví dụ: SECONDARY_REMOTE="cloudflare-free:bibica-net cloudflare-r2:bibica-net google-drive-api:bibica-net"
```
SECONDARY_REMOTE=""
```
