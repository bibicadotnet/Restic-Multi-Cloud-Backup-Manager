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
Xem hướng dẫn và giải thích chi tiết hơn ở [bài viết gốc](https://bibica.net/restic-multi-cloud-backup-manager-bash-script-sao-luu-qua-restic-va-rclone/)
# Cài đặt
- Cài đặt [Restic](https://restic.readthedocs.io/en/latest/020_installation.html) chỉ cần cài đặt Restic là đủ, không cần thực hiện thêm bước nào khác.
- Với [Rclone](https://rclone.org/install/) cấu hình ít nhất một dịch vụ cloud storage cho Restic. Nếu muốn sử dụng nhiều dịch vụ cloud storage dự phòng, bạn có thể tạo thêm các cấu hình tương ứng.
   -   Khuyến nghị: Sử dụng các dịch vụ cloud object storage như Amazon S3 hoặc Cloudflare R2 để đạt hiệu quả cao về tốc độ và độ ổn định.
   -   Nếu không có: Có thể sử dụng Google Drive, tuy tốc độ không nhanh bằng các dịch vụ cloud object storage, nhưng tiện lợi vì hầu hết người dùng đều có sẵn tài khoản Google.
- Thông báo Telegram, lấy `BOT_API_KEY` và `CHAT_ID` để nhận tin nhắn
# Tải và Cấu hình Script
Tải Script:

```
apt-get -y install wget git # hoặc yum -y install wget git nếu dùng OS khác
git clone https://github.com/bibicadotnet/Restic-Multi-Cloud-Backup-Manager.git restic
rm -rf restic/.git restic/README.md
chmod 755 restic/*.sh
```
# Chỉnh sửa Cấu hình:

Mở file cấu hình:

```
nano /restic/restic_backup_manager.sh
```
Cấu hình Telegram Bot:

```
BOT_API_KEY="xxxxxxxx:xxxxxxxxxxxxx"
CHAT_ID="xxxxxxxxx"
```
Cấu hình Restic:

```
export RESTIC_REPOSITORY="rclone:cloudflare-free:bibica-net"
export RESTIC_PASSWORD="your-secure-password"
```
Cấu hình thư mục và file cần sao lưu:
```
BACKUP_DIR="/home /var/spool/cron/crontabs/root"
```
Cấu hình chính sách giữ backup:

```
KEEP_HOURLY=24
KEEP_DAILY=31
KEEP_MONTHLY=12
```
Cấu hình kiểm tra toàn vẹn dữ liệu:

```
VERIFY_HOUR=4
```
Cấu hình Secondary Backup (nếu cần):

```
SECONDARY_REMOTE="google-drive-api:restic-backup/bibica-net cloudflare-r2:bibica-net"
```
# Chạy Script
Chạy thử Script:

```
/restic/restic_backup_manager.sh
````
# Cấu hình Cron để chạy tự động:

Mở trình chỉnh sửa cron:

```
crontab -e
```
Thêm dòng sau để chạy script mỗi giờ:

```
0 * * * * /restic/restic_backup_manager.sh
```
Hoặc thêm nhanh bằng lệnh:

```
(crontab -l 2>/dev/null; echo "0 * * * * /restic/restic_backup_manager.sh") | crontab -
```
# Khôi phục Dữ liệu
Tắt Cron trước khi khôi phục:

```
crontab -l | grep -v "[[:space:]]/restic/restic_backup_manager.sh$" | crontab -
```
Liệt kê các snapshot:
```
restic snapshots
```
Khôi phục một snapshot cụ thể:
```
restic restore <snapshot_id> --target /restore/test
```
Khôi phục thư mục hoặc file cụ thể:
```
restic restore <snapshot_id>:/path/to/restore --target /restore/test
```
khôi phục mọi thư mục và tệp từ bản sao lưu gần nhất (latest) vào chính xác vị trí ban đầu
```
restic restore latest --target /
```
Bật lại Cron sau khi khôi phục:
```
(crontab -l 2>/dev/null; echo "0 * * * * /restic/restic_backup_manager.sh") | crontab -
```
