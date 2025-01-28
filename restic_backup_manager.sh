#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# ==================== CẤU HÌNH ====================
# Cấu hình Telegram
BOT_API_KEY="xxxxxxxxxxx:xxxxxxxxxxxxxxxxxxxx"
CHAT_ID="xxxxxxxxxxxxxx"

# Cấu hình Restic Primary Backup
export RESTIC_REPOSITORY="rclone:cloudflare-free:bibica-net"
export RESTIC_PASSWORD="your-secure-password"

# Thư mục và file cần sao lưu
BACKUP_DIR="/home /var/spool/cron/crontabs/root /root/.config/rclone"

# Chính sách giữ backup
KEEP_HOURLY=24
KEEP_DAILY=31
KEEP_MONTHLY=12

# Chính sách kiểm tra toàn vẹn dữ liệu
VERIFY_HOUR=4

# Cấu hình Secondary Backup
SECONDARY_REMOTE=""

# Cấu hình Rclone
export RCLONE_TRANSFERS=32
export RCLONE_CHECKERS=32

# Thiết lập đường dẫn
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
LOG_DIR="$SCRIPT_DIR/logs"
VERIFY_LAST_FILE="$LOG_DIR/restic_last_verify"
LOCKFILE="$LOG_DIR/restic_backup.lock"
LOG_FILE="$LOG_DIR/backup.log"

# Tạo thư mục log nếu chưa tồn tại
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# ==================== HÀM PHỤ TRỢ ====================
# Hàm ghi log
log() {
   local message="$1"
   local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
   echo "$timestamp $message" >> "$LOG_FILE"
   if [ -t 1 ]; then
      echo "$timestamp $message"
   fi
   if [ $(wc -c < "$LOG_FILE") -gt 1048576 ]; then
       grep "\[Lỗi\]" "$LOG_FILE" | tail -n 10 > "$LOG_FILE.tmp"
       mv "$LOG_FILE.tmp" "$LOG_FILE"
   fi
}

# Hàm thông báo lỗi qua Telegram
notify_error() {
    local error_message="$1"
    local error_detail="$2"
    log "[Lỗi] $error_message - Chi tiết: $error_detail"
    curl -s -X POST "https://api.telegram.org/bot$BOT_API_KEY/sendMessage" -d "chat_id=$CHAT_ID" -d "parse_mode=HTML" \
         -d "text=$(printf "❌ [Lỗi] %s\n🔍 Chi tiết:\n<code>%s</code>\n🖥️ Thông tin hệ thống:\n- Máy chủ: %s\n- Hệ điều hành: %s" "$error_message" "$error_detail" "$(hostname)" "$(uname -a)")" \
         >/dev/null 2>&1 || log "[Lỗi] Không thể gửi thông báo đến Telegram"
}

# Export các hàm và biến cho xargs
export -f log notify_error
export BOT_API_KEY CHAT_ID LOG_FILE

# ==================== KIỂM TRA YÊU CẦU ====================
check_requirements() {
    for cmd in restic rclone xargs curl; do
        command -v $cmd >/dev/null || { notify_error "Không tìm thấy lệnh $cmd" "$cmd"; exit 1; }
    done
    for path in $BACKUP_DIR; do
        [ -e "$path" ] || { notify_error "Đường dẫn không tồn tại" "$path"; exit 1; }
    done
}

# ==================== THIẾT LẬP KHÓA VÀ TỐI ƯU TIẾN TRÌNH ====================
setup_lock() {
    exec 200>"$LOCKFILE" && flock -n 200 || { log "[Lỗi] Một tiến trình Restic Multi-Cloud Backup Manager khác đang chạy"; exit 1; }
    trap 'exec 200>&-; rm -f "$LOCKFILE"' EXIT
    renice -n 19 -p $$ >/dev/null 2>&1 && ionice -c 2 -n 7 -p $$ >/dev/null 2>&1
}

# ==================== KIỂM TRA CRON JOB ====================
check_cron_job() {
    local script_name=$(basename "$0")
    local script_path=$(realpath "$0")
    if ! crontab -l | grep -v '^#' | grep -q "$script_name"; then
        echo -e "\n* Restic Multi-Cloud Backup Manager chưa được cấu hình để chạy qua cron."
        echo -e "* Bạn có thể chạy lệnh bên dưới để thêm nó vào cron:\n"
        echo -e "\033[1;32m(crontab -l 2>/dev/null; echo \"0 * * * * $script_path\") | crontab -\033[0m\n"
    fi
}

# ==================== THIẾT LẬP ALIAS ====================
setup_alias() {
    local shell_rc_file
    local alias_restore="alias restore='$0 restore'"
    local alias_backup="alias backup='$0'"

    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc_file="$HOME/.zshrc"
    else
        shell_rc_file="$HOME/.bashrc"
    fi

    if grep -q "alias restore=" "$shell_rc_file"; then
        current_alias_restore=$(grep "alias restore=" "$shell_rc_file" | cut -d "'" -f 2 | cut -d " " -f 1)
        if [[ "$current_alias_restore" != "$0" ]]; then
            sed -i.bak "s|alias restore=.*|alias restore='$0 restore'|" "$shell_rc_file"
            echo "Đã cập nhật alias 'restore' để trỏ đến file script mới: $0."
        else
            echo "Alias 'restore' đã tồn tại và trỏ đến file script hiện tại: $0."
        fi
    else
        echo "$alias_restore" >> "$shell_rc_file"
        echo "Đã thêm alias 'restore' vào $shell_rc_file."
    fi

    if grep -q "alias backup=" "$shell_rc_file"; then
        current_alias_backup=$(grep "alias backup=" "$shell_rc_file" | cut -d "'" -f 2)
        if [[ "$current_alias_backup" != "$0" ]]; then
            sed -i.bak "s|alias backup=.*|alias backup='$0'|" "$shell_rc_file"
            echo "Đã cập nhật alias 'backup' để trỏ đến file script mới: $0."
        else
            echo "Alias 'backup' đã tồn tại và trỏ đến file script hiện tại: $0."
        fi
    else
        echo "$alias_backup" >> "$shell_rc_file"
        echo "Đã thêm alias 'backup' vào $shell_rc_file."
    fi

    echo "Để áp dụng thay đổi, chạy lệnh: source $shell_rc_file"
}

# ==================== PHỤC HỒI DỮ LIỆU ====================
restore_menu() {
    local PRIMARY_REPO="$RESTIC_REPOSITORY"
    local SECONDARY_REPOS=($SECONDARY_REMOTE)
    local PRIMARY_REPO_DISPLAY="${PRIMARY_REPO#rclone:}"

    echo
    echo "=== CHỌN KHO LƯU TRỮ ĐỂ PHỤC HỒI ==="
    echo "1) Sao lưu chính - $PRIMARY_REPO_DISPLAY"
    
    for ((i=0; i<${#SECONDARY_REPOS[@]}; i++)); do
        echo "$((i+2))) Sao lưu dự phòng - ${SECONDARY_REPOS[$i]#rclone:}"
    done

    echo "0) Thoát"
    echo

    while true; do
        read -p "Nhập lựa chọn của bạn: " choice

        case $choice in
            1)
                if [[ ! "$PRIMARY_REPO" =~ ^rclone: ]]; then
                    local selected_repo="rclone:$PRIMARY_REPO"
                else
                    local selected_repo="$PRIMARY_REPO"
                fi
                break
                ;;
            0)
                echo "Thoát Restic Multi-Cloud Backup Manager."
                echo
                exit 0
                ;;
            *)
                if [[ $choice -ge 2 ]]; then
                    local index=$((choice - 2))
                    if [ $index -ge 0 ] && [ $index -lt ${#SECONDARY_REPOS[@]} ]; then
                        if [[ ! "${SECONDARY_REPOS[$index]}" =~ ^rclone: ]]; then
                            local selected_repo="rclone:${SECONDARY_REPOS[$index]}"
                        else
                            local selected_repo="${SECONDARY_REPOS[$index]}"
                        fi
                        break
                    fi
                fi
                echo -e "\e[31m❌ Lựa chọn không hợp lệ. Vui lòng chọn lại.\e[0m"
                ;;
        esac
    done

    # Kiểm tra kết nối đến kho lưu trữ và lấy danh sách snapshots
    local snapshots_result
    if ! snapshots_result=$(restic snapshots -r "$selected_repo" 2>&1); then
        echo -e "\e[31m❌ Lỗi: Không thể kết nối đến kho lưu trữ $selected_repo.\e[0m"
        echo "$snapshots_result"
        echo "Vui lòng kiểm tra lại cấu hình hoặc chọn kho lưu trữ khác."
        echo
        restore_menu
        return
    fi

    echo
    echo "Đã chọn kho lưu trữ: $selected_repo"
    echo "=== DANH SÁCH CÁC BẢN SAO LƯU ==="
    echo "$snapshots_result"
    echo

    while true; do
        read -p "📋 Nhập ID bản sao lưu để phục hồi (hoặc 'back' để quay lại): " snapshot_id

        if [ "$snapshot_id" == "back" ]; then
            restore_menu
            return
        fi

        # Kiểm tra xem snapshot_id có tồn tại trong kết quả snapshots hay không
        if ! echo "$snapshots_result" | grep -q -w "$snapshot_id"; then
            echo -e "\e[31m❌ ID không tồn tại trong kho lưu trữ.\e[0m"
            echo
            continue
        fi

        break
    done

    while true; do
        echo
        echo "=== TÙY CHỌN PHỤC HỒI ==="
        echo "1) Phục hồi toàn bộ bản sao lưu"
        echo "2) Phục hồi một phần (thư mục/tập tin cụ thể)"
        echo "0) Quay lại"
        read -p "Nhập lựa chọn của bạn: " restore_choice

        case $restore_choice in
            1|2)
                local restore_path=""
                local restore_item=""

                # Nhập đường dẫn phục hồi
                while true; do
                    echo "📂 Nhập đường dẫn để phục hồi (nơi dữ liệu giải nén vào)."
                    echo "   Ví dụ: /home/user (dữ liệu trên cloud storage sẽ giải nén vào /home/user): "
                    echo "   Ví dụ: / (dữ liệu trên cloud storage sẽ tự động giải nén vào đường dẫn như ban đầu): "
                    read -p "> " restore_path
                    if [ -z "$restore_path" ]; then
                        restore_path="/"
                    fi

                    if [[ ! "$restore_path" =~ ^/ ]]; then
                        echo -e "\e[31m❌ Đường dẫn phải bắt đầu bằng / Ví dụ: /home/user\e[0m"
                        echo
                        continue
                    fi
                    break
                done

                # Nhập đường dẫn thư mục/tập tin nếu phục hồi một phần
                if [ "$restore_choice" == "2" ]; then
                    while true; do
                        echo "📂 Nhập đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi."
                        echo "   Ví dụ: /home/backup (phục hồi thư mục /home/backup từ bản sao lưu): "
                        read -p "> " restore_item

                        if [[ ! "$restore_item" =~ ^/ ]]; then
                            echo -e "\e[31m❌ Đường dẫn phải bắt đầu bằng / Ví dụ: /home/backup\e[0m"
                            echo
                            continue
                        fi
                        break
                    done
                fi

                # Xác nhận phục hồi
                while true; do
                    echo
                    echo "=== XÁC NHẬN PHỤC HỒI ==="
                    echo -e "📦 Kho lưu trữ: \e[32m$selected_repo\e[0m"
                    echo -e "📋 ID bản sao lưu: \e[34m$snapshot_id\e[0m"
                    echo -e "📂 Đường dẫn phục hồi (nơi dữ liệu giải nén vào): \e[33m$restore_path\e[0m"
                    [ "$restore_choice" == "2" ] && echo -e "📂 Đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi: \e[31m$restore_item\e[0m"
                    echo
                    echo "1) Thực hiện phục hồi"
                    echo "2) Sửa lại đường dẫn phục hồi (nơi dữ liệu giải nén vào)"
                    [ "$restore_choice" == "2" ] && echo "3) Sửa lại đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi"
                    echo "0) Trở về menu chính"
                    echo
                    read -p "Nhập lựa chọn của bạn: " confirm_choice

                    case $confirm_choice in
                        1)
                            if [ "$restore_choice" == "1" ]; then
                                restic restore -r "$selected_repo" "$snapshot_id" --target "$restore_path"
                            else
                                restic restore -r "$selected_repo" "$snapshot_id" --target "$restore_path" --include "$restore_item"
                            fi
                            return
                            ;;
                        2)
                            while true; do
                                echo "📂 Nhập đường dẫn để phục hồi (nơi dữ liệu giải nén vào) mới:"
                                read -p "> " restore_path
                                if [ -z "$restore_path" ]; then
                                    restore_path="/"
                                fi
                                if [[ ! "$restore_path" =~ ^/ ]]; then
                                    echo -e "\e[31m❌ Đường dẫn phải bắt đầu bằng / Ví dụ: /home/user\e[0m"
                                else
                                    break
                                fi
                            done
                            continue
                            ;;
                        3)
                            if [ "$restore_choice" == "2" ]; then
                                while true; do
                                    echo "📂 Nhập đường dẫn thư mục/tập tin trong bản sao lưu muốn phục hồi mới (ví dụ: /home/backup):"
                                    read -p "> " restore_item
                                    if [[ ! "$restore_item" =~ ^/ ]]; then
                                        echo -e "\e[31m❌ Đường dẫn phải bắt đầu bằng / Ví dụ: /home/backup\e[0m"
                                    else
                                        break
                                    fi
                                done
                                continue
                            else
                                echo -e "\e[31m❌ Lựa chọn không hợp lệ. Vui lòng chọn lại.\e[0m"
                            fi
                            ;;
                        0)
                            restore_menu
                            return
                            ;;
                        *)
                            echo -e "\e[31m❌ Lựa chọn không hợp lệ. Vui lòng chọn lại.\e[0m"
                            echo
                            ;;
                    esac
                done
                ;;
            0)
                restore_menu
                return
                ;;
            *)
                echo -e "\e[31m❌ Lựa chọn không hợp lệ. Vui lòng chọn lại.\e[0m"
                ;;
        esac
    done
}

# ==================== THỰC HIỆN BACKUP ====================
perform_backup() {
    local source_path=${RESTIC_REPOSITORY#rclone:}
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

	log "Bắt đầu dọn dẹp backup cũ"
	if ! error_output=$(restic forget --prune --keep-hourly $KEEP_HOURLY --keep-daily $KEEP_DAILY --keep-monthly $KEEP_MONTHLY 2>&1); then
		notify_error "Không thể dọn dẹp backup cũ" "$error_output"
		exit 1
	else
		log "Dọn dẹp backup cũ thành công"
	fi

	if [ ! -f "$VERIFY_LAST_FILE" ] || [ $(date +%Y-%m-%d) != $(cat "$VERIFY_LAST_FILE") ] && [ $(date +%H) -ge "$VERIFY_HOUR" ]; then
		log "Bắt đầu kiểm tra toàn vẹn dữ liệu"
		if ! error_output=$(restic check --read-data 2>&1); then
			notify_error "Kiểm tra toàn vẹn dữ liệu thất bại" "$error_output"
			exit 1
		else
			date +%Y-%m-%d > "$VERIFY_LAST_FILE"
			log "Kiểm tra toàn vẹn dữ liệu thành công"
		fi
	fi

	[ -n "$SECONDARY_REMOTE" ] && {
		log "Bắt đầu sao lưu dự phòng"
		do_backup() {
			local target="$1"
			if ! error_output=$(rclone sync "$2" "$target" 2>&1); then
				notify_error "Sao lưu dự phòng thất bại - $target" "$error_output"
				exit 1
			fi
			log "Sao lưu dự phòng thành công - $target"
		}
		export -f do_backup

		if [ $(echo "$SECONDARY_REMOTE" | wc -w) -eq 1 ]; then
			log "Có 1 remote được cấu hình"
			do_backup "$SECONDARY_REMOTE" "$source_path"
		else
			log "Có nhiều remote được cấu hình, chạy song song"
			echo "$SECONDARY_REMOTE" | tr ' ' '\n' | xargs -P 4 -I {} bash -c "do_backup '{}' '$source_path'" && \
				log "Hoàn thành tất cả sao lưu dự phòng" || { 
					notify_error "Có lỗi xảy ra trong quá trình sao lưu dự phòng song song" "$error_output"
					exit 1
				}
		fi
	}
    log "Hoàn tất quy trình backup"
}

# ==================== XỬ LÝ THAM SỐ ĐẦU VÀO ====================
if [ "$1" == "install" ]; then
	setup_lock
    setup_alias
    exit 0
elif [ "$1" == "restore" ]; then
	setup_lock
	check_cron_job
    restore_menu
    exit 0
fi

# ==================== THỰC THI CHÍNH ====================
check_requirements
setup_lock
check_cron_job
perform_backup
