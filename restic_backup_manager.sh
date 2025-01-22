#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Cấu hình Telegram
BOT_API_KEY="xxxxx:xxxxxxxxxxxxxxxxxxxx"
CHAT_ID="xxxxxxx"

# Cấu hình Restic Primary Backup
# Nên dùng cloud object storage dạng Amazon S3, Cloudflare R2
export RESTIC_REPOSITORY="rclone:cloudflare-free:bibica-net"
export RESTIC_PASSWORD="your-secure-password"	# đổi thành 1 password tùy thích

# Thư mục và file cần sao lưu
# Mỗi thư mục hoặc file cách nhau bởi khoảng trắng
BACKUP_DIR="/home /var/spool/cron/crontabs/root"

# Chính sách giữ backup
# Cấu hình mặc định tối đa giữ lại 67 bản
KEEP_HOURLY=24	# giữ lại 24 bản snapshot (1 bản mỗi giờ trong 24 giờ gần nhất)
KEEP_DAILY=31	# giữ lại 31 bản snapshot (1 bản mỗi ngày trong 31 ngày gần nhất)
KEEP_MONTHLY=12	# giữ lại 12 bản snapshot (1 bản mỗi tháng trong 12 tháng gần nhất)

# Chính sách kiểm tra toàn vẹn dữ liệu
# Muốn chạy kiểm tra lúc 3h chiều thì sửa VERIFY_HOUR=15
VERIFY_HOUR=4	# Mặc định lúc 4h sáng mỗi ngày

# Cấu hình Secondary Backup 
# Mặc định để trống: không dùng cloud dự phòng
# Các cloud thêm vào theo cú pháp của rclone, các cloud cách nhau bởi khoảng trắng
# Ví dụ: SECONDARY_REMOTE="cloudflare-free:bibica-net cloudflare-r2:bibica-net google-drive-api:bibica-net"
SECONDARY_REMOTE=""

# Cấu hình Rclone
export RCLONE_TRANSFERS=32
export RCLONE_CHECKERS=32

# Thiết lập đường dẫn
full_path=$(readlink -f "$0")
[ -z "$full_path" ] && { echo "[Lỗi] Không thể xác định đường dẫn script"; exit 1; }
SCRIPT_DIR=$(dirname "$full_path")
VERIFY_LAST_FILE="$SCRIPT_DIR/restic_last_verify"
LOCKFILE="$SCRIPT_DIR/restic_backup.lock"
LOG_FILE="$SCRIPT_DIR/backup.log"
touch "$LOG_FILE"

log() { 
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    if [ $(wc -c < "$LOG_FILE") -gt 1048576 ]; then
        grep "\[Lỗi\]" "$LOG_FILE" | tail -n 10 > "$LOG_FILE.tmp"
        mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

notify_error() {
    log "[Lỗi] $1 - Chi tiết: $2"
    curl -s -X POST "https://api.telegram.org/bot$BOT_API_KEY/sendMessage" -d "chat_id=$CHAT_ID" -d "parse_mode=HTML" \
         -d "text=$(printf "❌ [Lỗi] %s\n🔍 Chi tiết:\n<code>%s</code>\n🖥️ Thông tin hệ thống:\n- Máy chủ: %s\n- Hệ điều hành: %s" "$1" "$2" "$(hostname)" "$(uname -a)")" \
         || log "[Lỗi] Không thể gửi thông báo đến Telegram"
}

# Export các hàm và biến cho xargs
export -f log notify_error
export BOT_API_KEY CHAT_ID LOG_FILE

# Kiểm tra yêu cầu
for cmd in restic rclone xargs; do command -v $cmd >/dev/null || { notify_error "Không tìm thấy lệnh $cmd" "$cmd"; exit 1; }; done
for path in $BACKUP_DIR; do [ -e "$path" ] || { notify_error "Đường dẫn không tồn tại" "$path"; exit 1; }; done

# Thiết lập khóa và tối ưu tiến trình
exec 200>"$LOCKFILE" && flock -n 200 || { notify_error "Một tiến trình backup khác đang chạy" "$LOCKFILE"; exit 1; }
trap 'exec 200>&-; rm -f "$LOCKFILE"' EXIT
renice -n 19 -p $$ >/dev/null 2>&1 && ionice -c 2 -n 7 -p $$ >/dev/null 2>&1

# Backup chính
source_path=${RESTIC_REPOSITORY#rclone:}
log "Bắt đầu backup - $source_path"
if ! error_output=$(restic backup $BACKUP_DIR 2>&1); then
    if echo "$error_output" | grep -q "unable to open config file"; then
        log "Repository chưa tồn tại, đang khởi tạo..."
        if ! init_output=$(restic init 2>&1); then
            notify_error "Không thể khởi tạo repository" "$init_output"; exit 1
        fi
        log "Khởi tạo repository thành công, thực hiện lại backup..."
        if ! error_output=$(restic backup $BACKUP_DIR 2>&1); then
            notify_error "Backup thất bại sau khi khởi tạo" "$error_output"; exit 1
        fi
    else 
        notify_error "Backup thất bại" "$error_output"; exit 1
    fi
fi
log "Backup thành công"

# Dọn dẹp và kiểm tra
log "Bắt đầu dọn dẹp backup cũ"
if ! error_output=$(restic forget --prune --keep-hourly $KEEP_HOURLY --keep-daily $KEEP_DAILY --keep-monthly $KEEP_MONTHLY 2>&1); then
    notify_error "Không thể dọn dẹp backup cũ" "$error_output"
else
    log "Dọn dẹp backup cũ thành công"
fi

if [ ! -f "$VERIFY_LAST_FILE" ] || [ $(date +%Y-%m-%d) != $(cat "$VERIFY_LAST_FILE") ] && [ $(date +%H) -ge "$VERIFY_HOUR" ]; then
    log "Bắt đầu kiểm tra toàn vẹn dữ liệu"
    if ! error_output=$(restic check --read-data 2>&1); then
        notify_error "Kiểm tra toàn vẹn dữ liệu thất bại" "$error_output"
    else
        date +%Y-%m-%d > "$VERIFY_LAST_FILE"
        log "Kiểm tra toàn vẹn dữ liệu thành công"
    fi
fi

# Sao lưu dự phòng
[ -n "$SECONDARY_REMOTE" ] && {
    log "Bắt đầu sao lưu dự phòng"
    do_backup() {
        local target="$1"
        if ! error_output=$(rclone sync "$2" "$target" 2>&1); then
            log "[Lỗi] Sao lưu dự phòng thất bại - $target"
            notify_error "Sao lưu dự phòng thất bại - $target" "$error_output"
            return 1
        fi
        log "Sao lưu dự phòng thành công - $target"
        return 0
    }
    export -f do_backup
    
    if [ $(echo "$SECONDARY_REMOTE" | wc -w) -eq 1 ]; then
        log "Có 1 remote được cấu hình"
        do_backup "$SECONDARY_REMOTE" "$source_path"
    else
        log "Có nhiều remote được cấu hình, chạy song song"
        echo "$SECONDARY_REMOTE" | tr ' ' '\n' | xargs -P 4 -I {} bash -c "do_backup '{}' '$source_path'" && \
            log "Hoàn thành tất cả sao lưu dự phòng" || log "[Lỗi] Có lỗi xảy ra trong quá trình sao lưu dự phòng song song"
    fi
}

log "Hoàn tất quy trình backup"
