#!/bin/bash

# ==========================================
# Xray VLESS-Reality 手動部署腳本
# ==========================================

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

WORK_DIR="$HOME/Xray"
CONFIG_FILE="$WORK_DIR/config_server.json"
DATA_FILE="$WORK_DIR/reality_data.txt"
SERVICE_NAME="vless"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 預設偽裝網域
DEFAULT_DEST="aws.amazon.com"

echo -e "${GREEN}歡迎使用 Xray VLESS-Reality 部署腳本${PLAIN}"

# 核心下載與解壓共用邏輯
download_and_extract() {
    local TAG="$1"
    local CLEAN_VERSION=$(echo "$TAG" | tr -d 'v.')
    local BIN_NAME="xray_${CLEAN_VERSION}"
    local ZIP_NAME="Xray-linux-64_${TAG}.zip"

    echo -e "目標版本為: ${GREEN}${TAG}${PLAIN} (將命名為 ${BIN_NAME})"

    # 下載
    echo -e "正在下載..."
    curl -L -o "$ZIP_NAME" "https://github.com/XTLS/Xray-core/releases/download/${TAG}/Xray-linux-64.zip"

    if [ ! -f "$ZIP_NAME" ]; then
        echo -e "${RED}下載失敗，請檢查網路連線。${PLAIN}"
        return 1
    fi

    # 解壓縮
    echo -e "正在解壓縮..."
    unzip -q -o "$ZIP_NAME"

    if [ ! -f "xray" ]; then
        echo -e "${RED}解壓縮失敗，找不到 xray 執行檔。${PLAIN}"
        return 1
    fi

    # 重新命名二進位檔
    mv xray "$BIN_NAME"
    chmod +x "$BIN_NAME"

    # 建立軟連結 (方便後續呼叫 ./xray)
    ln -sf "$BIN_NAME" xray

    # 賦予綁定低位連接埠權限
    sudo setcap 'cap_net_bind_service=+ep' "$BIN_NAME" 2>/dev/null

    echo -e "${GREEN}Xray 核心 (${TAG}) 部署完成！${PLAIN}"
    return 0
}

# 1. 安裝 Xray 核心
install_xray() {
    echo -e "${YELLOW}開始安裝 Xray 核心...${PLAIN}"

    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR" || exit

    LATEST_TAG=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}無法取得 Xray 最新版本號，請檢查網路連線。${PLAIN}"
        return 1
    fi

    download_and_extract "$LATEST_TAG" && ls -l "$WORK_DIR"
}

# 2. 檢查並更新 Xray 核心
update_xray() {
    echo -e "${YELLOW}正在檢查 Xray 版本...${PLAIN}"

    if [ ! -x "$WORK_DIR/xray" ]; then
        echo -e "${RED}尚未安裝 Xray，請先執行安裝步驟 (選項 1)。${PLAIN}"
        return 1
    fi

    cd "$WORK_DIR" || exit

    LOCAL_VER=$(./xray version | head -n 1 | awk '{print $2}')
    LATEST_TAG=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}無法取得 GitHub 最新版本號，請檢查網路連線。${PLAIN}"
        return 1
    fi
    LATEST_VER="${LATEST_TAG#v}"

    echo -e "目前本機版本: ${YELLOW}v${LOCAL_VER}${PLAIN}"
    echo -e "GitHub 最新版: ${GREEN}${LATEST_TAG}${PLAIN}"

    if [ "$LOCAL_VER" == "$LATEST_VER" ]; then
        echo -e "${GREEN}目前已是最新版本，無需更新。${PLAIN}"
    else
        read -rp "發現新版本 ${LATEST_TAG}，是否立即下載更新並清理舊版？ [Y/n]: " confirm
        case $confirm in
            [nN][oO]|[nN])
                echo -e "已取消更新。"
                ;;
            *)
                OLD_CLEAN_VER=$(echo "$LOCAL_VER" | tr -d '.')
                OLD_BIN="xray_${OLD_CLEAN_VER}"
                OLD_ZIP="Xray-linux-64_v${LOCAL_VER}.zip"

                if download_and_extract "$LATEST_TAG"; then
                    echo -e "${YELLOW}正在清理舊版本檔案...${PLAIN}"
                    rm -f "$OLD_BIN" "$OLD_ZIP"
                    echo -e "${GREEN}已刪除舊版 ($OLD_BIN 與 $OLD_ZIP)。${PLAIN}"
                    ls -l "$WORK_DIR"
                    if systemctl is-active --quiet "$SERVICE_NAME"; then
                        echo -e "${YELLOW}偵測到 ${SERVICE_NAME} 服務運行中，正在自動重啟以套用新版本...${PLAIN}"
                        sudo systemctl restart "$SERVICE_NAME"
                    fi
                fi
                ;;
        esac
    fi
}

# 3. 生成配置與金鑰
generate_config() {
    echo -e "${YELLOW}開始生成 REALITY 配置...${PLAIN}"

    cd "$WORK_DIR" || exit

    if [ ! -x "./xray" ]; then
        echo -e "${RED}找不到 xray 執行檔，請先執行安裝步驟 (選項 1)。${PLAIN}"
        return 1
    fi

    SERVER_IP=$(curl -s ipv4.icanhazip.com)

    UUID=$(./xray uuid)
    X25519=$(./xray x25519)
    PRIVATE_KEY=$(echo "$X25519" | grep -i "PrivateKey:" | awk '{print $2}')
    PUBLIC_KEY=$(echo "$X25519" | grep -i "PublicKey" | awk -F': ' '{print $2}')
    SHORT_ID=$(openssl rand -hex 8)

    cat > "$DATA_FILE" <<EOF
[Server Info]
IP: $SERVER_IP
UUID: $UUID
PrivateKey: $PRIVATE_KEY
PublicKey: $PUBLIC_KEY
ShortId: $SHORT_ID
Dest: $DEFAULT_DEST
EOF

    cat > "$CONFIG_FILE" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 443, 
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "${DEFAULT_DEST}:443",
                    "serverNames": [
                        "${DEFAULT_DEST}"
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "${SHORT_ID}"
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ],
                "routeOnly": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
EOF

    echo -e "${GREEN}伺服器設定檔已生成：$CONFIG_FILE${PLAIN}"
    echo -e "${GREEN}金鑰與參數已備份至：$DATA_FILE${PLAIN}"

    show_surge_config
}

# 4. 顯示 Surge 配置
show_surge_config() {
    if [ ! -f "$DATA_FILE" ]; then
        echo -e "${RED}找不到參數檔案 ($DATA_FILE)，請先執行「產生 REALITY 金鑰與 JSON 設定檔」。${PLAIN}"
        return 1
    fi

    local IP=$(grep "^IP:" "$DATA_FILE" | awk -F': ' '{print $2}')
    local UUID=$(grep "^UUID:" "$DATA_FILE" | awk -F': ' '{print $2}')
    local PUBLIC_KEY=$(grep "^PublicKey:" "$DATA_FILE" | awk -F': ' '{print $2}')
    local SHORT_ID=$(grep "^ShortId:" "$DATA_FILE" | awk -F': ' '{print $2}')
    local DEST=$(grep "^Dest:" "$DATA_FILE" | awk -F': ' '{print $2}')
    
    local PORT=443
    if [ -f "$CONFIG_FILE" ]; then
        local PARSED_PORT=$(grep '"port":' "$CONFIG_FILE" | head -n 1 | tr -dc '0-9')
        [ -n "$PARSED_PORT" ] && PORT="$PARSED_PORT"
    fi

    echo -e "\n=========================================="
    echo -e "${YELLOW}Surge 客戶端 [Proxy] 節點配置：${PLAIN}"
    echo -e "=========================================="
    echo -e "My-Reality = vless, ${IP}, ${PORT}, username=${UUID}, flow=xtls-rprx-vision, sni=${DEST}, reality-public-key=${PUBLIC_KEY}, reality-short-id=${SHORT_ID}"
    echo -e "==========================================\n"
}

# 5. 新增到 systemctl (建立 vless 服務並設為開機自啟)
install_service() {
    echo -e "${YELLOW}正在配置 systemd 服務 (${SERVICE_NAME})...${PLAIN}"

    if [ ! -x "$WORK_DIR/xray" ] || [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}找不到 xray 執行檔或 config_server.json，請先完成選項 1 與選項 3。${PLAIN}"
        return 1
    fi

    if ! "$WORK_DIR/xray" -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}config_server.json 語法檢查未通過，請檢查設定檔！${PLAIN}"
        "$WORK_DIR/xray" -test -config "$CONFIG_FILE"
        return 1
    fi

    # 確保實際執行檔具備綁定低位連接埠權限
    sudo setcap 'cap_net_bind_service=+ep' "$(readlink -f "$WORK_DIR/xray")" 2>/dev/null

    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Xray VLESS-Reality Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=${WORK_DIR}
Environment="XRAY_LOCATION_ASSET=${WORK_DIR}"
ExecStart=${WORK_DIR}/xray run -config ${CONFIG_FILE}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SERVICE_NAME"
    echo -e "${GREEN}已將 ${SERVICE_NAME} 加入 systemctl 並啟動 (執行用戶: $(whoami))！${PLAIN}"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l | head -n 12
}

# 6. 啟動 vless 服務
start_service() {
    echo -e "${YELLOW}正在啟動 ${SERVICE_NAME} 服務...${PLAIN}"
    sudo systemctl start "$SERVICE_NAME"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l | head -n 12
}

# 7. 重啟 vless 服務
restart_service() {
    echo -e "${YELLOW}正在重啟 ${SERVICE_NAME} 服務...${PLAIN}"
    sudo systemctl restart "$SERVICE_NAME"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l | head -n 12
}

# 8. 停止 vless 服務
stop_service() {
    echo -e "${YELLOW}正在停止 ${SERVICE_NAME} 服務...${PLAIN}"
    sudo systemctl stop "$SERVICE_NAME"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l | head -n 12
}

# 9. 刪除 systemctl 服務
remove_service() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}找不到 ${SERVICE_FILE}，該服務可能尚未建立或已被刪除。${PLAIN}"
        return 1
    fi

    read -rp "確定要停止並徹底刪除 ${SERVICE_NAME} 系統服務嗎？ [y/N]: " confirm
    case $confirm in
        [yY][eE][sS]|[yY])
            echo -e "${YELLOW}正在停止並移除 ${SERVICE_NAME} 服務...${PLAIN}"
            sudo systemctl stop "$SERVICE_NAME" 2>/dev/null
            sudo systemctl disable "$SERVICE_NAME" 2>/dev/null
            sudo rm -f "$SERVICE_FILE"
            sudo systemctl daemon-reload
            sudo systemctl reset-failed 2>/dev/null
            echo -e "${GREEN}已成功從 systemctl 中刪除 ${SERVICE_NAME} 服務！（~/Xray 目錄內的檔案仍保留）${PLAIN}"
            ;;
        *)
            echo -e "已取消刪除操作。"
            ;;
    esac
}

# 10. 查看 vless 服務狀態
status_service() {
    echo -e "${YELLOW}正在查詢 ${SERVICE_NAME} 服務狀態...${PLAIN}"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l
}

# 選單
while true; do
    echo -e "\n請選擇操作："
    echo -e "  1. 下載並安裝 Xray 核心 (最新版)"
    echo -e "  2. 檢查並更新 Xray 核心"
    echo -e "  3. 產生 REALITY 金鑰與 JSON 設定檔"
    echo -e "  4. 顯示 Surge 客戶端配置"
    echo -e "  ------------------------------------------"
    echo -e "  5. 新增到 systemctl (建立並啟用 ${SERVICE_NAME} 服務)"
    echo -e "  6. 啟動 ${SERVICE_NAME} (systemctl start)"
    echo -e "  7. 重啟 ${SERVICE_NAME} (systemctl restart)"
    echo -e "  8. 停止 ${SERVICE_NAME} (systemctl stop)"
    echo -e "  9. 刪除 ${SERVICE_NAME} 服務 (移除 systemctl 服務)"
    echo -e " 10. 查看 ${SERVICE_NAME} 狀態 (systemctl status)"
    echo -e "  0. 退出"
    read -rp "請輸入數字 [0-10]: " choice

    case $choice in
        1) install_xray ;;
        2) update_xray ;;
        3) generate_config ;;
        4) show_surge_config ;;
        5) install_service ;;
        6) start_service ;;
        7) restart_service ;;
        8) stop_service ;;
        9) remove_service ;;
        10) status_service ;;
        0) exit 0 ;;
        *) echo -e "${RED}無效的輸入！${PLAIN}" ;;
    esac
done
