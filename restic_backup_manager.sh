#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Cấu hình Telegram
BOT_API_KEY="xxxxxxxx:xxxxxxxxxxxxxxxxxxxx"
CHAT_ID="xxxxxxxxxxx"

# Cấu hình Restic Primary Backup
# Nên dùng cloud object storage dạng Amazon S3, Cloudflare R2
export RESTIC_REPOSITORY="rclone:google-drive-api:bibica-net"
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
   echo "$message"
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
exec 200>"$LOCKFILE" && flock -n 200 || { log "[Lỗi] Một tiến trình Restic Multi-Cloud Backup Manager khác đang chạy"; exit 1; }
trap 'exec 200>&-; rm -f "$LOCKFILE"' EXIT

renice -n 19 -p $$ >/dev/null 2>&1 && ionice -c 2 -n 7 -p $$ >/dev/null 2>&1

# Hàm tạo alias tự động
setup_alias() {
    local shell_rc_file
    local alias_restore="alias restore='$full_path restore'"
    local alias_backup="alias backup='$full_path'"

    # Xác định file cấu hình shell dựa trên shell hiện tại
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc_file="$HOME/.zshrc"
    else
        shell_rc_file="$HOME/.bashrc"
    fi

    # Kiểm tra và cập nhật alias 'restore'
    if grep -q "alias restore=" "$shell_rc_file"; then
        current_alias_restore=$(grep "alias restore=" "$shell_rc_file" | cut -d "'" -f 2 | cut -d " " -f 1)
        if [[ "$current_alias_restore" != "$full_path" ]]; then
            sed -i.bak "s|alias restore=.*|alias restore='$full_path restore'|" "$shell_rc_file"
            echo "Đã cập nhật alias 'restore' để trỏ đến file script mới: $full_path."
        else
            echo "Alias 'restore' đã tồn tại và trỏ đến file script hiện tại: $full_path."
        fi
    else
        echo "$alias_restore" >> "$shell_rc_file"
        echo "Đã thêm alias 'restore' vào $shell_rc_file."
    fi

    # Kiểm tra và cập nhật alias 'backup'
    if grep -q "alias backup=" "$shell_rc_file"; then
        current_alias_backup=$(grep "alias backup=" "$shell_rc_file" | cut -d "'" -f 2)
        if [[ "$current_alias_backup" != "$full_path" ]]; then
            sed -i.bak "s|alias backup=.*|alias backup='$full_path'|" "$shell_rc_file"
            echo "Đã cập nhật alias 'backup' để trỏ đến file script mới: $full_path."
        else
            echo "Alias 'backup' đã tồn tại và trỏ đến file script hiện tại: $full_path."
        fi
    else
        echo "$alias_backup" >> "$shell_rc_file"
        echo "Đã thêm alias 'backup' vào $shell_rc_file."
    fi

    echo "Để áp dụng thay đổi, chạy lệnh: source $shell_rc_file"
}

# Kiểm tra tham số đầu vào
if [[ "$1" == "install" ]]; then
    setup_alias
    exit 0
fi

# Hàm phục hồi
restore_menu() {
    # Lấy giá trị từ biến môi trường
    PRIMARY_REPO="$RESTIC_REPOSITORY"
    SECONDARY_REPOS=($SECONDARY_REMOTE)

    # Loại bỏ tiền tố "rclone:" nếu có
    if [[ "$PRIMARY_REPO" =~ ^rclone: ]]; then
        PRIMARY_REPO_DISPLAY="${PRIMARY_REPO#rclone:}"
    else
        PRIMARY_REPO_DISPLAY="$PRIMARY_REPO"
    fi
	echo
    echo "=== CHỌN KHO LƯU TRỮ ĐỂ PHỤC HỒI ==="
    echo "1) Sao lưu chính - $PRIMARY_REPO_DISPLAY"
    
    # Hiển thị các kho lưu trữ dự phòng
    for ((i=0; i<${#SECONDARY_REPOS[@]}; i++)); do
        echo "$((i+2))) Sao lưu dự phòng - ${SECONDARY_REPOS[$i]}"
    done

    echo "0) Thoát"
	echo	
    read -p "Nhập lựa chọn của bạn: " choice

	case $choice in
		1)
			# Kiểm tra xem PRIMARY_REPO đã có "rclone:" chưa
			if [[ ! "$PRIMARY_REPO" =~ ^rclone: ]]; then
				export RESTIC_REPOSITORY="rclone:$PRIMARY_REPO"
			else
				export RESTIC_REPOSITORY="$PRIMARY_REPO"
			fi
			;;
		0)
			echo "Thoát Restic Multi-Cloud Backup Manager."
			echo
			exit 0
			;;
		*)
			if [[ $choice -ge 2 ]]; then  # Xử lý các lựa chọn từ 2 trở lên
				# Tính toán chỉ số của kho lưu trữ dự phòng dựa trên lựa chọn
				index=$((choice - 2))  # Lựa chọn 2 tương ứng với SECONDARY_REPOS[0], 3 tương ứng với SECONDARY_REPOS[1], ...
				
				# Kiểm tra xem chỉ số có hợp lệ không
				if [ $index -ge 0 ] && [ $index -lt ${#SECONDARY_REPOS[@]} ]; then
					# Kiểm tra xem kho lưu trữ đã có "rclone:" chưa
					if [[ ! "${SECONDARY_REPOS[$index]}" =~ ^rclone: ]]; then
						export RESTIC_REPOSITORY="rclone:${SECONDARY_REPOS[$index]}"
					else
						export RESTIC_REPOSITORY="${SECONDARY_REPOS[$index]}"
					fi
				else
					echo "Không có kho lưu trữ dự phòng tương ứng với lựa chọn này."
					restore_menu
					return
				fi
			else
				echo "Lựa chọn không hợp lệ"
				restore_menu
				return
			fi
			;;
	esac

	# Kiểm tra xem kho lưu trữ có hợp lệ không
	if ! restic snapshots -r "$RESTIC_REPOSITORY" > /dev/null 2>&1; then
		echo "❌ Lỗi: Không thể kết nối đến kho lưu trữ $RESTIC_REPOSITORY."
		echo "Vui lòng kiểm tra lại cấu hình hoặc chọn kho lưu trữ khác."
		echo
		restore_menu
		return
	fi

	# Nếu kho lưu trữ hợp lệ, tiếp tục hiển thị danh sách snapshots
	echo	
	echo "Đã chọn kho lưu trữ: $RESTIC_REPOSITORY"
	echo "=== DANH SÁCH CÁC BẢN SAO LƯU ==="
	restic snapshots -r "$RESTIC_REPOSITORY"
	echo
	
    while true; do
        read -p "📋 Nhập ID bản sao lưu để phục hồi (hoặc 'back' để quay lại): " snapshot_id

        if [ "$snapshot_id" == "back" ]; then
            restore_menu
            return
        fi

        # Kiểm tra ID snapshot
        if [[ ! "$snapshot_id" =~ ^[a-f0-9]{8}$ ]]; then
			echo
            echo "❌ ID không hợp lệ. ID phải là chuỗi hex dài 8 ký tự (ví dụ: 96701d8b)."
			echo
            continue
        fi

        # Kiểm tra xem ID có tồn tại trong kho lưu trữ không
		if ! restic snapshots -r "$RESTIC_REPOSITORY" | grep -q -w "$snapshot_id"; then
			echo
			echo "❌ ID không tồn tại trong kho lưu trữ."
			echo
			continue
		fi

        break
    done

	echo
    echo "=== TÙY CHỌN PHỤC HỒI ==="
    echo "1) Phục hồi toàn bộ bản sao lưu"
    echo "2) Phục hồi một phần (thư mục/tập tin cụ thể)"
    echo "0) Quay lại"
    read -p "Nhập lựa chọn của bạn: " restore_choice

    case $restore_choice in
        1)
            while true; do
				echo "📂 Nhập đường dẫn để phục hồi (nơi dữ liệu giải nén vào)."
				echo "   Ví dụ: /home/user (dữ liệu trên cloud storage sẽ giải nén vào /home/user): "
				echo "   Ví dụ: / (dữ liệu trên cloud storage sẽ tự động giải nén vào đường dẫn như ban đầu): "
				read -p "> " restore_path
                if [ -z "$restore_path" ]; then
                    restore_path="/"
                fi

                # Kiểm tra đường dẫn phục hồi
                if [[ ! "$restore_path" =~ ^/ ]]; then
					echo
                    echo "❌ Đường dẫn phải bắt đầu bằng / Ví dụ: /home/user"
					echo
                    continue
                fi

                break
            done

			echo
			echo "=== XÁC NHẬN PHỤC HỒI ==="
			echo -e "📦 Kho lưu trữ: \e[32m$RESTIC_REPOSITORY\e[0m"
			echo -e "📋 ID bản sao lưu: \e[34m$snapshot_id\e[0m"
			echo -e "📂 Đường dẫn phục hồi (nơi dữ liệu giải nén vào): \e[33m$restore_path\e[0m"
            read -p "⚠️ Xác nhận phục hồi? (yes/no): " confirm

            if [ "$confirm" == "yes" ]; then
                restic restore -r "$RESTIC_REPOSITORY" "$snapshot_id" --target "$restore_path"
            else
                restore_menu
            fi
            ;;
        2)
            while true; do
				echo "📂 Nhập đường dẫn để phục hồi (nơi dữ liệu giải nén vào)."
				echo "   Ví dụ: /home/user (dữ liệu trên cloud storage sẽ giải nén vào /home/user): "
				echo "   Ví dụ: / (dữ liệu trên cloud storage sẽ tự động giải nén vào đường dẫn như ban đầu): "
				read -p "> " restore_path
                if [ -z "$restore_path" ]; then
                    restore_path="/"
                fi

                # Kiểm tra đường dẫn phục hồi
                if [[ ! "$restore_path" =~ ^/ ]]; then
					echo
                    echo "❌ Đường dẫn phải bắt đầu bằng / Ví dụ: /home/user"
					echo
                    continue
                fi

                break
            done

            while true; do
				echo "📂 Nhập đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi."
				echo "   Ví dụ: /home/backup (phục hồi thư mục /home/backup từ bản sao lưu): "
				read -p "> " restore_item

                # Kiểm tra đường dẫn thư mục/tập tin
                if [[ ! "$restore_item" =~ ^/ ]]; then
					echo
                    echo "❌ Đường dẫn phải bắt đầu bằng / Ví dụ: /home/backup"
					echo
                    continue
                fi

                break
            done
			
			echo
			echo "=== XÁC NHẬN PHỤC HỒI ==="
			echo -e "📦 Kho lưu trữ: \e[32m$RESTIC_REPOSITORY\e[0m"
			echo -e "📋 ID bản sao lưu: \e[34m$snapshot_id\e[0m"
			echo -e "📂 Đường dẫn phục hồi (nơi dữ liệu giải nén vào): \e[33m$restore_path\e[0m"
			echo -e "📂 Đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi: \e[31m$restore_item\e[0m"
			read -p "⚠️ Xác nhận phục hồi? (yes/no): " confirm

            if [ "$confirm" == "yes" ]; then
                restic restore -r "$RESTIC_REPOSITORY" "$snapshot_id:$restore_item" --target "$restore_path"
            else
                restore_menu
            fi
            ;;
        0)
            restore_menu
            ;;
        *)
            echo "Lựa chọn không hợp lệ"
            restore_menu
            ;;
    esac
}

# Kiểm tra tham số đầu vào
if [ "$1" == "restore" ]; then
    restore_menu
    exit 0
fi

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
