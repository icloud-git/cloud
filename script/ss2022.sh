#!/bin/bash

# Shadowsocks-rust 管理腳本 for Debian

# 定義默認端口和加密方式
DEFAULT_PORT=443
ENCRYPTION_METHOD="2022-blake3-aes-256-gcm"
CONFIG_FILE="/etc/shadowsocks-rust/config.json"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"

# 函數：生成 32 字節 Base64 隨機密碼
generate_password() {
    echo $(openssl rand -base64 32)
}

# 設置端口
set_port() {
    read -p "請輸入服務器端口 (默認: $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}
}

# 獲取公網 IP
get_public_ip() {
    PUBLIC_IP=$(curl -s https://speed.cloudflare.com/meta -4 | grep -Po '"clientIp":"\K[^"]*')
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP="<服務器IP>"
    fi
}

# 安裝 shadowsocks-rust
install_shadowsocks() {
    echo "安裝 Shadowsocks-rust..."

    # 設置端口
    set_port

    # 安裝依賴
    sudo apt update
    sudo apt install -y curl wget unzip

    # 獲取最新的 shadowsocks-rust 版本號
    VERSION=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    wget "https://github.com/shadowsocks/shadowsocks-rust/releases/download/$VERSION/shadowsocks-$VERSION.x86_64-unknown-linux-gnu.tar.xz" -O shadowsocks-rust.tar.xz
    tar -xvf shadowsocks-rust.tar.xz
    sudo mv ssserver /usr/local/bin/

    # 配置 Shadowsocks
    SS_PASSWORD=$(generate_password)
    echo "Shadowsocks 密碼生成完成：$SS_PASSWORD"

    # 創建配置文件
    sudo mkdir -p /etc/shadowsocks-rust
    sudo bash -c "cat > $CONFIG_FILE" <<EOF
{
    "server": "::",
    "server_port": $PORT,
    "password": "$SS_PASSWORD",
    "method": "$ENCRYPTION_METHOD",
    "mode": "tcp_and_udp"
}
EOF

    # 設置 systemd 服務
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Shadowsocks Rust Service
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 啟動並設置開機自啟
    sudo systemctl daemon-reload
    sudo systemctl enable shadowsocks
    sudo systemctl start shadowsocks
    echo "Shadowsocks 安裝完成，服務已啟動！"

    # 獲取公網 IP
    get_public_ip

    # 顯示配置信息示範
    echo "配置信息示範:"
    echo "ss2022 = ss, $PUBLIC_IP, $PORT, encrypt-method=$ENCRYPTION_METHOD, password=$SS_PASSWORD"
}

# 更改端口
change_port() {
    set_port
    sudo sed -i "s/\"server_port\": [0-9]*/\"server_port\": $PORT/" $CONFIG_FILE
    sudo systemctl daemon-reload
    sudo systemctl restart shadowsocks
    echo "端口已更改為 $PORT"
}

# 查看配置
view_config() {
    echo "當前 Shadowsocks 配置:"
    sudo cat $CONFIG_FILE
}

# 查看 Shadowsocks 狀態
view_status() {
    sudo systemctl status shadowsocks
}

# 重啟 shadowsocks
restart_shadowsocks() {
    sudo systemctl restart shadowsocks
    echo "Shadowsocks 已重啟！"
}

# 停止 shadowsocks
stop_shadowsocks() {
    sudo systemctl stop shadowsocks
    echo "Shadowsocks 已停止！"
}

# 完整移除 shadowsocks
remove_shadowsocks() {
    sudo systemctl stop shadowsocks
    sudo systemctl disable shadowsocks
    sudo rm -f /usr/local/bin/ssserver
    sudo rm -f $SERVICE_FILE
    sudo rm -rf /etc/shadowsocks-rust
    sudo systemctl daemon-reload
    echo "Shadowsocks 已完全移除！"
}

# 主選單
main_menu() {
    echo "選擇操作:"
    echo "1) 安裝 Shadowsocks"
    echo "2) 更改端口"
    echo "3) 查看 Shadowsocks 配置"
    echo "4) 查看 Shadowsocks 狀態"
    echo "5) 重啟 Shadowsocks"
    echo "6) 停止 Shadowsocks"
    echo "7) 完整移除 Shadowsocks"
    read -p "請選擇 (1-7): " choice

    case $choice in
    1) install_shadowsocks ;;
    2) change_port ;;
    3) view_config ;;
    4) view_status ;;
    5) restart_shadowsocks ;;
    6) stop_shadowsocks ;;
    7) remove_shadowsocks ;;
    *) echo "無效選擇" ;;
    esac
}

# 開始腳本
main_menu
