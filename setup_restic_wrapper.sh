#!/bin/bash

# Lấy đường dẫn thư mục chứa script hiện tại
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tạo file restic-wrap và truyền giá trị SCRIPT_DIR vào
sudo bash -c 'cat > /usr/local/bin/restic-wrap << '\''EOL'\''
#!/bin/bash
SCRIPT_DIR="'"$SCRIPT_DIR"'"
RESTIC_CONFIG="$SCRIPT_DIR/restic_backup_manager.sh"
load_restic_vars() {
    if [ -f "$RESTIC_CONFIG" ]; then
        while IFS= read -r line; do
            if [[ $line == export\ RESTIC* ]]; then
                eval "$line"
                export RESTIC_REPOSITORY
                export RESTIC_PASSWORD
            fi
        done < "$RESTIC_CONFIG"
    else
        echo "Error: Không tìm thấy file cấu hình $RESTIC_CONFIG"
        exit 1
    fi
}
load_restic_vars
/usr/local/bin/restic "$@"
EOL'

# Cấp quyền thực thi cho restic-wrap
sudo chmod +x /usr/local/bin/restic-wrap

# Thêm alias vào ~/.bashrc
if ! grep -q "alias restic=" ~/.bashrc; then
    echo "alias restic='/usr/local/bin/restic-wrap'" >> ~/.bashrc
    echo "Đã thêm alias 'restic' vào ~/.bashrc."
else
    echo "Alias 'restic' đã tồn tại trong ~/.bashrc."
fi

# Khởi động lại shell để áp dụng thay đổi
exec bash

# Thông báo hoàn thành
echo "Cài đặt restic wrapper và alias hoàn tất!"
