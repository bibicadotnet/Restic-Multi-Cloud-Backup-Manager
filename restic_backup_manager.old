#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Cấu hình Telegram
BOT_API_KEY="xxxxxxxx:xxxxxxxxxxxxx"
CHAT_ID="xxxxxxxxx"

# Cấu hình Restic Primary Backup
export RESTIC_REPOSITORY="rclone:cloudflare-free:restic-backup/bibica-net"
export RESTIC_PASSWORD="your-secure-password"

# Cấu hình Secondary Backup 
# Mặc định để trống là bỏ qua không dùng thêm cloud dự phòng
# Dùng thêm nhiều cloud thì cách nhau bởi khoảng trắng (dùng theo cú pháp của rclone)
# Ví dụ: google-drive-api:restic-backup/bibica-net cloudflare-r2:bibica-net
SECONDARY_REMOTE=""  

# Thư mục và file cần backup
# Mỗi thư mục hoặc file cách nhau bởi khoảng trắng
BACKUP_DIR="/home /var/spool/cron/crontabs/root"

# Chính sách giữ backup
KEEP_HOURLY=24
KEEP_DAILY=31
KEEP_MONTHLY=1

# Chính sách kiểm tra toàn vẹn dữ liệu
VERIFY_HOUR=4	# 4h sáng

# Cấu hình Rclone
export RCLONE_TRANSFERS=32
export RCLONE_CHECKERS=32

# Các thông số cấu hình khác
MAX_LOG_SIZE=10485760  # 10MB
LOCK_TIMEOUT=3600  # 1 giờ

# Lấy thư mục của script
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Đường dẫn cấu hình và theo dõi
VERIFY_LAST_FILE="$SCRIPT_DIR/restic_last_verify"
LOG_FILE="$SCRIPT_DIR/restic_backup.log"
LOCKFILE="$SCRIPT_DIR/restic_backup.lock"

# Đảm bảo file log tồn tại
touch "$LOG_FILE"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
    echo "Script cần chạy với quyền root"
    exit 1
fi

# Giảm độ ưu tiên của script
renice -n 19 -p $$ > /dev/null 2>&1
ionice -c 2 -n 7 -p $$ > /dev/null 2>&1

# Hàm ghi log và gửi thông báo
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Quản lý kích thước log
    if [ -f "$LOG_FILE" ] && [ $(stat -c %s "$LOG_FILE") -ge $MAX_LOG_SIZE ]; then
        grep -E '^\[.*\] \[(WARNING|ERROR)\]' "$LOG_FILE" > "$LOG_FILE.tmp"
        mv "$LOG_FILE.tmp" "$LOG_FILE"
        
        if [ $(stat -c %s "$LOG_FILE") -ge $MAX_LOG_SIZE ]; then
            tail -n 100 "$LOG_FILE" > "$LOG_FILE.tmp"
            mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    fi
    
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo -e "[$level] $message"
    
    # Chỉ gửi Telegram khi có WARNING hoặc ERROR
    if [ "$level" = "WARNING" ] || [ "$level" = "ERROR" ]; then
        send_telegram_message "[$level] $message"
    fi
}

# Hàm gửi thông báo Telegram
send_telegram_message() {
    local message="$1"
    local error_log="$2"
    
    local full_message="$message"
    if [ ! -z "$error_log" ]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        full_message="${full_message}\n\n🕒 Thời gian: ${timestamp}"
        full_message="${full_message}\n\n📝 Chi tiết:\n<code>${error_log}</code>"
    fi
    
    # Thêm thông tin hệ thống cho mọi thông báo
    local hostname=$(hostname)
    local system_info=$(uname -a)
    full_message="${full_message}\n\n🖥 Máy chủ: ${hostname}\n💻 Hệ thống: ${system_info}"
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_API_KEY/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d "text=${full_message}" \
        -d "parse_mode=HTML" \
        > /dev/null
}

# Hàm kiểm tra điều kiện cơ bản
check_prerequisites() {
    # Kiểm tra các lệnh cần thiết
    for cmd in restic rclone; do
        if ! command -v $cmd &> /dev/null; then
            log_message "ERROR" "Không tìm thấy lệnh: $cmd"
            return 1
        fi
    done
    
    # Kiểm tra thư mục backup
    local has_error=0
    for path in $BACKUP_DIR; do
        if [ ! -e "$path" ]; then
            log_message "ERROR" "Không tồn tại đường dẫn: $path"
            has_error=1
        fi
    done
    
    return $has_error
}

# Thực hiện backup với cơ chế thử lại tối đa 3 lần nếu gặp lỗi mạng
perform_backup_with_retry() {
    local command="$1"
    local operation="$2"
    local retry_count=0
    
    while [ $retry_count -lt 3 ]; do
        # Tùy chỉnh thông báo dựa trên loại operation
        case "$operation" in
            "Restic Backup")
                log_message "INFO" "Đang thực hiện backup dữ liệu (lần $((retry_count + 1))/3)..."
                ;;
            "Restic Verify")
                log_message "INFO" "Đang kiểm tra toàn vẹn dữ liệu (lần $((retry_count + 1))/3)..."
                ;;
            "Restic Forget & Prune")
                log_message "INFO" "Đang xóa các bản backup cũ (lần $((retry_count + 1))/3)..."
                ;;
        esac
        
        if error_log=$(eval "$command" 2>&1); then
            # Tùy chỉnh thông báo thành công
            case "$operation" in
                "Restic Backup")
                    log_message "INFO" "Backup dữ liệu thành công"
                    ;;
                "Restic Verify")
                    log_message "INFO" "Kiểm tra toàn vẹn dữ liệu thành công"
                    ;;
                "Restic Forget & Prune")
                    log_message "INFO" "Xóa các bản backup cũ thành công"
                    ;;
            esac
            return 0
        fi
        
        # Nếu repository chưa tồn tại, tạo mới và thử lại
        if [[ "$error_log" == *"unable to open config file"* ]] || [[ "$error_log" == *"Is there a repository at the following location?"* ]]; then
            log_message "INFO" "Chưa có repository Restic, đang khởi tạo..."
            if restic init; then
                log_message "INFO" "Đã khởi tạo repository Restic, tiếp tục backup..."
                continue
            else
                log_message "ERROR" "Không thể tạo repository"
                return 1
            fi
        fi
        
        # Chỉ retry với lỗi mạng/tạm thời
        if echo "$error_log" | grep -qiE "network|timeout|temporary|connection refused"; then
            retry_count=$((retry_count + 1))
            # Tùy chỉnh thông báo thất bại
            case "$operation" in
                "Restic Backup")
                    log_message "WARNING" "Backup dữ liệu thất bại, thử lại sau 5 giây..."
                    ;;
                "Restic Verify")
                    log_message "WARNING" "Kiểm tra toàn vẹn thất bại, thử lại sau 5 giây..."
                    ;;
                "Restic Forget & Prune")
                    log_message "WARNING" "Dọn dẹp backup thất bại, thử lại sau 5 giây..."
                    ;;
            esac
            sleep 5
            continue
        fi
        
        # Lỗi nghiêm trọng
        log_message "ERROR" "$operation thất bại: $error_log"
        return 1
    done
    
    # Tùy chỉnh thông báo thất bại sau 3 lần thử
    case "$operation" in
        "Restic Backup")
            log_message "ERROR" "Backup dữ liệu thất bại sau 3 lần thử"
            ;;
        "Restic Verify")
            log_message "ERROR" "Kiểm tra toàn vẹn thất bại sau 3 lần thử"
            ;;
        "Restic Forget & Prune")
            log_message "ERROR" "Dọn dẹp backup thất bại sau 3 lần thử"
            ;;
    esac
    return 1
}

# Kiểm tra xem có cần verify backup không (mỗi ngày vào giờ đã cấu hình)
should_run_verify() {
    local current_hour=$(date +%H)
    local current_date=$(date +%Y-%m-%d)
    
    if [ ! -f "$VERIFY_LAST_FILE" ]; then
        date -d "yesterday" +%Y-%m-%d > "$VERIFY_LAST_FILE"
    fi
    
    local last_verify_date=$(cat "$VERIFY_LAST_FILE")
    
    if [ "$current_date" != "$last_verify_date" ] && [ "$current_hour" -ge "$VERIFY_HOUR" ]; then
        return 0
    fi
    
    return 1
}

# Hàm cập nhật thời gian verify
update_verify_time() {
    date +%Y-%m-%d > "$VERIFY_LAST_FILE"
    log_message "INFO" "Đã cập nhật lại thời gian kiểm tra toàn vẹn dữ liệu lần tiếp theo"
}

# Hàm sao chép repository Restic sang các cloud dự phòng
perform_secondary_backup() {
    if [ -z "$SECONDARY_REMOTE" ]; then
    #    log_message "INFO" "Không có cấu hình cloud dự phòng, bỏ qua bước sao chép"
        return 0
    fi

    local source_path=${RESTIC_REPOSITORY#rclone:}
	log_message "INFO" "Bắt đầu sao chép repository sang cloud dự phòng"
    # Tách danh sách cloud dự phòng
    IFS=' ' read -r -a remotes <<< "$SECONDARY_REMOTE"

    for remote in "${remotes[@]}"; do
        log_message "INFO" "Đang sao chép repository sang cloud dự phòng: $remote"

        error_log=$(rclone sync "$source_path" "$remote" \
            --transfers $RCLONE_TRANSFERS \
            --checkers $RCLONE_CHECKERS \
            2>&1)

        if [ $? -ne 0 ]; then
            log_message "ERROR" "Lỗi sao chép repository sang cloud dự phòng: $remote: $error_log"
            return 1
        fi

        log_message "INFO" "Đã sao chép xong repository sang cloud dự phòng: $remote"
    done

    return 0
}

# Hàm chính
main() {
    # Kiểm tra điều kiện cơ bản
    check_prerequisites || exit 1

    # Kiểm tra và tạo lock
    exec 200>"$LOCKFILE"
    if ! flock -n 200; then
        log_message "INFO" "Một tiến trình backup khác đang chạy, thoát..."
        exit 1
    fi
	
	# Ghi PID và đảm bảo xóa lock khi kết thúc
    echo $$ > "$LOCKFILE"
    trap 'rm -f "$LOCKFILE"; log_message "INFO" "✨ Hoàn tất quy trình backup."; exit' EXIT SIGINT SIGTERM
	
	log_message "INFO" "🚀 Bắt đầu quy trình backup..."
	
    # Backup chính
    perform_backup_with_retry "restic backup $BACKUP_DIR" "Restic Backup" || exit 1

    # Thực hiện forget và prune
	log_message "INFO" "Bắt đầu xóa các bản backup cũ theo chính sách..."
    perform_backup_with_retry "restic forget --prune --keep-hourly $KEEP_HOURLY --keep-daily $KEEP_DAILY --keep-monthly $KEEP_MONTHLY" "Restic Forget & Prune" || exit 1

    # Kiểm tra toàn vẹn backup (nếu cần)
    if should_run_verify; then
		log_message "INFO" "Bắt đầu kiểm tra toàn vẹn dữ liệu backup..."
        perform_backup_with_retry "restic check --read-data" "Restic Verify" || exit 1
        update_verify_time
    fi
	
	# Sao chép sang cloud dự phòng
    perform_secondary_backup || exit 1
}

# Chạy script
main
