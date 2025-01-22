#!/bin/bash

# Hàm kiểm tra và cài đặt các công cụ cần thiết
install_required_tools() {
    local tools=("$@")  # Danh sách các công cụ cần kiểm tra và cài đặt

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Công cụ '$tool' chưa được cài đặt. Tự động cài đặt $tool..."
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y "$tool"
            elif command -v yum &> /dev/null; then
                sudo yum install -y "$tool"
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y "$tool"
            else
                echo "Lỗi: Không thể xác định trình quản lý gói để cài đặt $tool."
                exit 1
            fi
        fi
    done
}

# Kiểm tra và cài đặt các công cụ cần thiết
install_required_tools "bzip2" "jq"

# Lấy phiên bản mới nhất của Restic từ GitHub
LATEST_RELEASE=$(curl -s https://api.github.com/repos/restic/restic/releases/latest | jq -r .tag_name)
echo "Phiên bản mới nhất của Restic: $LATEST_RELEASE"

# Xác định kiến trúc hệ thống
ARCH=$(uname -m)

# Xác định URL tải về dựa trên kiến trúc
case "$ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    armv7l|armv8l)
        ARCH="arm"
        ;;
    i386|i686)
        ARCH="386"
        ;;
    ppc64le)
        ARCH="ppc64le"
        ;;
    s390x)
        ARCH="s390x"
        ;;
    *)
        echo "Lỗi: Kiến trúc không được hỗ trợ: $ARCH"
        exit 1
        ;;
esac

# Xác định hệ điều hành
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

# Tên file tải về
RESTIC_FILE="restic_${LATEST_RELEASE:1}_${OS}_${ARCH}.bz2"

# URL tải về Restic
URL="https://github.com/restic/restic/releases/download/$LATEST_RELEASE/$RESTIC_FILE"

# Thư mục tạm để tải về
TMP_DIR=$(mktemp -d)

# Tên file tải về
RESTIC_FILE_PATH="${TMP_DIR}/restic.bz2"

# Tải về Restic
echo "Đang tải Restic cho kiến trúc ${ARCH}..."
wget -L "$URL" -O "$RESTIC_FILE_PATH"

# Kiểm tra xem tải về có thành công không
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể tải về Restic."
    rm -rf "${TMP_DIR}"
    exit 1
fi

# Giải nén file
echo "Đang giải nén Restic..."
bunzip2 "$RESTIC_FILE_PATH"

# Kiểm tra xem giải nén có thành công không
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể giải nén file Restic."
    rm -rf "${TMP_DIR}"
    exit 1
fi

# Cấp quyền thực thi
chmod +x "${TMP_DIR}/restic"

# Di chuyển Restic vào thư mục /usr/local/bin
echo "Đang cài đặt Restic vào /usr/local/bin..."
sudo mv "${TMP_DIR}/restic" /usr/local/bin/restic

# Kiểm tra xem cài đặt có thành công không
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể cài đặt Restic."
    rm -rf "${TMP_DIR}"
    exit 1
fi

# Dọn dẹp thư mục tạm
rm -rf "${TMP_DIR}"

# Kiểm tra phiên bản Restic
echo "Cài đặt thành công Restic."
restic version
