#!/bin/bash

# Cài đặt công cụ nếu chưa có
for tool in bzip2 jq; do
    command -v "$tool" &>/dev/null || {
        echo "Cài đặt $tool..."
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y "$tool"
        elif command -v yum &>/dev/null; then
            sudo yum install -y "$tool"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "$tool"
        else
            echo "Không tìm thấy trình quản lý gói."; exit 1
        fi
    }
done

# Lấy thông tin cần thiết
LATEST_RELEASE=$(curl -s https://api.github.com/repos/restic/restic/releases/latest | jq -r .tag_name)
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' -e 's/armv[78]l/arm/' -e 's/i[3-6]86/386/' -e 's/ppc64le/ppc64le/' -e 's/s390x/s390x/')
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
[ "$ARCH" = "unsupported" ] && { echo "Kiến trúc không được hỗ trợ: $ARCH"; exit 1; }

# Tải và cài đặt Restic
TMP_DIR=$(mktemp -d)
RESTIC_PATH="$TMP_DIR/restic"
URL="https://github.com/restic/restic/releases/download/$LATEST_RELEASE/restic_${LATEST_RELEASE:1}_${OS}_${ARCH}.bz2"

echo "Đang tải Restic $LATEST_RELEASE..."
wget -qO- "$URL" | bunzip2 > "$RESTIC_PATH" || { echo "Lỗi khi tải hoặc giải nén."; rm -rf "$TMP_DIR"; exit 1; }
chmod +x "$RESTIC_PATH" && sudo mv "$RESTIC_PATH" /usr/local/bin/restic || { echo "Lỗi khi cài đặt."; rm -rf "$TMP_DIR"; exit 1; }

# Dọn dẹp và kiểm tra
rm -rf "$TMP_DIR"
echo "Cài đặt thành công Restic:"
restic version
