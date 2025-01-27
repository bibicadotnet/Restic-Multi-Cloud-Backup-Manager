# Restic-Multi-Cloud-Backup-Manager - backup và restore cho [LCMP](https://github.com/bibicadotnet/Docker-LCMP-Multisite-WordPress-Minimal)
Bash script sao lưu và phục hồi dữ liệu qua Restic và Rclone


```backup
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
```restore
=== CHỌN KHO LƯU TRỮ ĐỂ PHỤC HỒI ===
1) Sao lưu chính - google-drive-api:bibica-net
2) Sao lưu dự phòng - cloudflare-free:bibica-net
3) Sao lưu dự phòng - cloudflare-r2:bibica-net
0) Thoát
```
```
=== XÁC NHẬN PHỤC HỒI ===
📦 Kho lưu trữ: rclone:cloudflare-free:bibica-net
📋 ID bản sao lưu: 2df1aa71
📂 Đường dẫn phục hồi (nơi dữ liệu giải nén vào): /test004
📂 Đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi: /home/backup

1) Thực hiện phục hồi
2) Sửa lại đường dẫn phục hồi (nơi dữ liệu giải nén vào)
3) Sửa lại đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi
0) Trở về menu chính

Nhập lựa chọn của bạn: 1
repository 5db6f8b8 opened (version 2, compression level auto)
[0:00] 100.00%  1 / 1 index files loaded
restoring snapshot 2df1aa71 of [/home] at 2025-01-27 23:30:15.404757034 +0700 +07 by root@bibica-net to /test004
Summary: Restored 23 / 22 files/dirs (95.125 KiB / 95.125 KiB) in 0:00
```
Xem hướng dẫn và giải thích chi tiết hơn ở [bài viết gốc](https://bibica.net/restic-multi-cloud-backup-manager-bash-script-sao-luu-qua-restic-va-rclone/)
# Cài đặt
- Cài đặt [Restic](https://restic.readthedocs.io/en/latest/020_installation.html) chỉ cần cài đặt Restic là đủ, không cần thực hiện thêm bước nào khác.
- Với [Rclone](https://rclone.org/install/) cấu hình ít nhất một dịch vụ cloud storage cho Restic. Nếu muốn sử dụng nhiều dịch vụ cloud storage dự phòng, bạn có thể tạo thêm các cấu hình tương ứng.
   -   Khuyến nghị: sử dụng các dịch vụ cloud object storage như Amazon S3 hoặc Cloudflare R2 để đạt hiệu quả cao về tốc độ và độ ổn định.
   -   Nếu không có S3: có thể sử dụng Google Drive, tuy tốc độ không nhanh bằng các dịch vụ cloud object storage, nhưng tiện lợi vì hầu hết người dùng đều có sẵn tài khoản Google.
- Thông báo Telegram, lấy `BOT_API_KEY` và `CHAT_ID` để nhận tin nhắn
# Tải và Cấu hình Script
Tải Script:
```
sudo mkdir -p /restic && sudo wget https://go.bibica.net/restic -O /restic/restic_backup_manager.sh && sudo chmod +x /restic/restic_backup_manager.sh
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

Bạn sẽ thấy 1 thông báo tương tự như thế nếu chưa cấu hình cron, copy sẵn lệnh bên dưới chạy là được
```
* Restic Multi-Cloud Backup Manager chưa được cấu hình để chạy qua cron.
* Bạn có thể chạy lệnh bên dưới để thêm nó vào cron:
(crontab -l 2>/dev/null; echo "0 * * * * /root/restic/restic_backup_manager.sh") | crontab -
```
# Cài đặt alias
Tạo phím tắt
```
/restic/restic_backup_manager.sh install
```
- Khi gõ `backup` là chạy trực tiếp `/restic/restic_backup_manager.sh` để tạo backup
- Khi gõ `restore` là gọi chạy trực tiếp `/restic/restic_backup_manager.sh restore`
# Khôi phục Dữ liệu
```
restore
```
Làm theo hướng dẫn trên màn hình
# Tự cập nhập biến cấu hình Restic
Sử dụng biến cấu hình `RESTIC_REPOSITORY` trên shell
```
/restic/setup_restic_wrapper.sh
```
