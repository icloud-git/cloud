#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
# System Required: Debian/Ubuntu
# Description: Snell Server 管理腳本 (v5/v6 雙版本)
# Version: 3.0.0
#=================================================

sh_ver="3.0.0"
SNELL_V5_VER="v5.0.1"
SNELL_V6_VER="v6.0.0b4"

# ── 顏色定義 ──────────────────────────────────────
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Yellow_font_prefix="\033[0;33m" && Blue_font_prefix="\033[34m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[錯誤]${Font_color_suffix}"
Warning="${Yellow_font_prefix}[警告]${Font_color_suffix}"
Question="${Blue_font_prefix}[詢問]${Font_color_suffix}"

# ── 路徑函數（依版本號動態生成）───────────────────
get_paths(){
    local ver="$1"   # v5 或 v6
    local major
    if [[ "$ver" == "v5" ]]; then
        major="v5"; snell_target_ver="${SNELL_V5_VER}"
    else
        major="v6"; snell_target_ver="${SNELL_V6_VER}"
    fi
    FOLDER="/etc/snell/${major}/"
    FILE="/usr/local/bin/snell-server-${major}"
    CONF="/etc/snell/${major}/config.conf"
    LOG_FILE="/var/log/snell-server-${major}.log"
    Now_ver_File="/etc/snell/${major}/ver.txt"
    SERVICE_NAME="snell-server-${major}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
}

# ── 基礎工具函數 ──────────────────────────────────
check_root(){
    if [[ $EUID != 0 ]]; then
        echo -e "${Error} 當前非ROOT賬號，無法繼續操作！"
        echo -e "${Info} 請使用: ${Green_font_prefix}sudo su${Font_color_suffix} 獲取ROOT權限"
        exit 1
    fi
}

check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"; pm="yum"
    elif grep -qi "debian" /etc/issue 2>/dev/null; then
        release="debian"; pm="apt-get"
    elif grep -qi "ubuntu" /etc/issue 2>/dev/null; then
        release="ubuntu"; pm="apt-get"
    elif grep -qi "debian" /etc/os-release 2>/dev/null; then
        release="debian"; pm="apt-get"
    elif grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        release="ubuntu"; pm="apt-get"
    else
        echo -e "${Error} 當前系統不受支持！僅支持 Debian/Ubuntu/CentOS"
        exit 1
    fi
}

install_dependencies(){
    echo -e "${Info} 正在安裝依賴包..."
    if [[ ${pm} == "apt-get" ]]; then
        apt-get update -y
        apt-get install -y gzip wget curl unzip systemd
    elif [[ ${pm} == "yum" ]]; then
        yum update -y
        yum install -y gzip wget curl unzip systemd
    fi
    if [[ $? != 0 ]]; then
        echo -e "${Error} 依賴安裝失敗！"
        exit 1
    fi
}

get_system_arch(){
    local uname_m
    uname_m=$(uname -m)
    case "$uname_m" in
        "i686"|"i386")          arch="i386"   ;;
        *"armv7"*|"armv6l")     arch="armv7l" ;;
        *"armv8"*|"aarch64")    arch="aarch64";;
        "x86_64"|"amd64")       arch="amd64"  ;;
        *)
            echo -e "${Error} 不支持的系統架構: $uname_m"
            exit 1
            ;;
    esac
    echo -e "${Info} 檢測到系統架構: ${Green_font_prefix}${arch}${Font_color_suffix}"
}

# ── 版本檢測 ──────────────────────────────────────
check_installed_status(){
    if [[ ! -e "${FILE}" ]]; then
        echo -e "${Error} Snell Server ${current_ver_label} 未安裝！"
        return 1
    fi
    return 0
}

get_current_version(){
    if [[ -f "${Now_ver_File}" ]]; then
        local cv
        cv=$(cat "${Now_ver_File}")
        echo -e "${Info} 當前 ${current_ver_label} 版本: ${Green_font_prefix}${cv}${Font_color_suffix}"
    else
        echo -e "${Warning} 無法獲取 ${current_ver_label} 版本信息"
    fi
}

# ── 舊版遷移 ──────────────────────────────────────
# 舊版安裝特徵：binary 在 /usr/local/bin/snell-server（無版本後綴）
#               service 為 snell-server.service
#               config  在 /etc/snell/config.conf
LEGACY_FILE="/usr/local/bin/snell-server"
LEGACY_SERVICE="/etc/systemd/system/snell-server.service"
LEGACY_CONF="/etc/snell/config.conf"
LEGACY_VER_FILE="/etc/snell/ver.txt"

detect_legacy(){
    if [[ -e "${LEGACY_FILE}" ]]; then
        echo -e "${Warning} 偵測到舊版安裝（無版本號）："
        echo -e "  Binary : ${LEGACY_FILE}"
        echo -e "  Service: ${LEGACY_SERVICE}"
        echo -e "  Config : ${LEGACY_CONF}"
        local lv=""
        [[ -f "${LEGACY_VER_FILE}" ]] && lv=$(cat "${LEGACY_VER_FILE}")
        [[ -n "${lv}" ]] && echo -e "  版本   : ${lv}"
        return 0   # 有舊版
    else
        echo -e "${Info} 未偵測到舊版安裝"
        return 1   # 無舊版
    fi
}

migrate_legacy(){
    if ! detect_legacy; then
        return 0
    fi

    echo -e "${Question} 請選擇遷移目標版本："
    echo -e " ${Green_font_prefix}1.${Font_color_suffix} 遷移為 Snell v5（推薦，保持現有配置）"
    echo -e " ${Green_font_prefix}2.${Font_color_suffix} 遷移為 Snell v6（Beta）"
    echo -e " ${Green_font_prefix}0.${Font_color_suffix} 取消"
    read -e -p " 請輸入數字 [0-2]: " mig_choice

    case "${mig_choice}" in
        1) _do_migrate "v5" ;;
        2) _do_migrate "v6" ;;
        0) echo -e "${Info} 取消遷移"; return 0 ;;
        *) echo -e "${Error} 無效選擇"; return 1 ;;
    esac
}

_do_migrate(){
    local target="$1"
    get_paths "${target}"

    echo -e "${Info} 開始將舊版遷移至 Snell ${target}..."

    # 停止舊服務
    if systemctl is-active --quiet snell-server 2>/dev/null; then
        echo -e "${Info} 停止舊版服務..."
        systemctl stop snell-server
    fi
    systemctl disable snell-server 2>/dev/null

    # 建立新目錄
    mkdir -p "${FOLDER}"

    # 搬移 binary
    echo -e "${Info} 搬移 binary: ${LEGACY_FILE} → ${FILE}"
    cp -f "${LEGACY_FILE}" "${FILE}"
    chmod +x "${FILE}"

    # 搬移 config（若新路徑不存在）
    if [[ ! -f "${CONF}" ]] && [[ -f "${LEGACY_CONF}" ]]; then
        echo -e "${Info} 複製配置: ${LEGACY_CONF} → ${CONF}"
        cp -f "${LEGACY_CONF}" "${CONF}"
    fi

    # 修正 config version 欄位（v6 用 6，v5 用 5）
    if [[ "${target}" == "v6" ]]; then
        sed -i 's/^version = .*/version = 6/' "${CONF}" 2>/dev/null
    else
        sed -i 's/^version = .*/version = 5/' "${CONF}" 2>/dev/null
    fi

    # 寫入版本文件
    if [[ -f "${LEGACY_VER_FILE}" ]]; then
        cp -f "${LEGACY_VER_FILE}" "${Now_ver_File}"
    fi

    # 建立新 systemd 服務
    create_service

    # 啟動新服務
    systemctl start "${SERVICE_NAME}"
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${Info} ${Green_font_prefix}遷移成功！服務 ${SERVICE_NAME} 已啟動${Font_color_suffix}"
    else
        echo -e "${Error} 服務啟動失敗，請檢查日誌: journalctl -u ${SERVICE_NAME}"
        return 1
    fi

    # 提示是否移除舊版殘留
    echo -e "${Question} 是否移除舊版殘留文件（${LEGACY_FILE}、${LEGACY_SERVICE}）？(y/N)"
    read -e -p ": " rm_legacy
    if [[ ${rm_legacy} =~ ^[Yy]$ ]]; then
        rm -f "${LEGACY_FILE}"
        rm -f "${LEGACY_SERVICE}"
        # 保留舊 config 作備份
        [[ -f "${LEGACY_CONF}" ]] && mv -f "${LEGACY_CONF}" "${LEGACY_CONF}.bak"
        [[ -f "${LEGACY_VER_FILE}" ]] && rm -f "${LEGACY_VER_FILE}"
        systemctl daemon-reload
        echo -e "${Info} 舊版殘留文件已清除（config 備份至 ${LEGACY_CONF}.bak）"
    fi

    show_config
}

# ── 下載 / 配置 / 服務 ────────────────────────────
download_snell(){
    local download_url="https://dl.nssurge.com/snell/snell-server-${snell_target_ver}-linux-${arch}.zip"
    local temp_dir="/tmp/snell_install_${current_ver_label}"

    echo -e "${Info} 正在下載 Snell Server ${snell_target_ver} (${arch})..."
    echo -e "${Info} 下載地址: ${download_url}"

    [[ -d "${temp_dir}" ]] && rm -rf "${temp_dir}"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"

    if ! wget --no-check-certificate -O "snell-server.zip" "${download_url}"; then
        echo -e "${Error} 下載失敗！"
        rm -rf "${temp_dir}"
        exit 1
    fi

    if ! unzip -o "snell-server.zip"; then
        echo -e "${Error} 解壓失敗！"
        rm -rf "${temp_dir}"
        exit 1
    fi

    if [[ ! -e "snell-server" ]]; then
        echo -e "${Error} 未找到 snell-server 二進制文件！"
        rm -rf "${temp_dir}"
        exit 1
    fi

    [[ ! -d "${FOLDER}" ]] && mkdir -p "${FOLDER}"

    chmod +x snell-server
    mv -f snell-server "${FILE}"
    echo "${snell_target_ver}" > "${Now_ver_File}"

    cd /
    rm -rf "${temp_dir}"

    echo -e "${Info} Snell Server ${current_ver_label} 下載安裝完成！"
}

create_service(){
    echo -e "${Info} 正在創建系統服務 ${SERVICE_NAME}..."

    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Snell Proxy Service (${current_ver_label})
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Group=root
LimitNOFILE=32768
ExecStartPre=/bin/sh -c "ulimit -n 51200"
ExecStart=${FILE} -c ${CONF}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    echo -e "${Info} 系統服務 ${SERVICE_NAME} 創建完成！"
}

set_port(){
    while true; do
        echo -e "${Question} 請輸入 Snell Server ${current_ver_label} 端口 [1-65535]"
        read -e -p "(默認: 6160): " port
        [[ -z "${port}" ]] && port="6160"
        if [[ ${port} =~ ^[0-9]+$ ]] && [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
            echo -e "${Info} 端口設置: ${Green_font_prefix}${port}${Font_color_suffix}"
            break
        else
            echo -e "${Error} 輸入錯誤，請輸入 1-65535 之間的數字！"
        fi
    done
}

generate_psk(){
    psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
    echo -e "${Info} 生成密鑰: ${Green_font_prefix}${psk}${Font_color_suffix}"
}

write_config(){
    echo -e "${Info} 正在生成配置文件 ${CONF}..."

    if [[ "${current_ver_label}" == "v6" ]]; then
        # v6 移除 obfs，改用 mode 參數
        cat > "${CONF}" << EOF
[snell-server]
listen = 0.0.0.0:${port}
psk = ${psk}
mode = default
tfo = true
mptcp = true
version = 6
EOF
    else
        cat > "${CONF}" << EOF
[snell-server]
listen = 0.0.0.0:${port}
psk = ${psk}
obfs = http
obfs-host = www.bing.com
tfo = true
mptcp = true
version = 5
EOF
    fi

    echo -e "${Info} 配置文件寫入完成！"
}

get_ip(){
    local_ip=$(curl -s -4 http://checkip.amazonaws.com 2>/dev/null)
    [[ -z "${local_ip}" ]] && local_ip=$(curl -s -4 http://ipinfo.io/ip 2>/dev/null)
    [[ -z "${local_ip}" ]] && local_ip="你的服務器IP"
}

show_config(){
    if [[ ! -f "${CONF}" ]]; then
        echo -e "${Error} 配置文件 ${CONF} 不存在！"
        return 1
    fi

    local config_port config_psk proto_ver
    config_port=$(grep "^listen" "${CONF}" | sed -n 's/.*:\([0-9]\+\).*/\1/p')
    [[ -z "${config_port}" ]] && config_port=$(awk -F':' '/^listen/{print $NF}' "${CONF}")

    config_psk=$(grep "^psk" "${CONF}" | sed 's/^psk = //')
    [[ -z "${config_psk}" ]] && config_psk=$(awk -F' = ' '/^psk/{print $2}' "${CONF}")

    proto_ver=$(grep "^version" "${CONF}" | awk -F' = ' '{print $2}')
    [[ -z "${proto_ver}" ]] && proto_ver="${current_ver_label//v/}"

    get_ip

    if [[ "${current_ver_label}" == "v6" ]]; then
        # v6：顯示 mode，無 obfs
        local config_mode
        config_mode=$(grep "^mode" "${CONF}" | awk -F' = ' '{print $2}')
        [[ -z "${config_mode}" ]] && config_mode="default"

        echo -e "\n${Info} 當前 Snell Server v6 配置信息："
        echo -e "————————————————————————————————"
        echo -e " 服務器地址: ${Green_font_prefix}${local_ip}${Font_color_suffix}"
        echo -e " 端口      : ${Green_font_prefix}${config_port}${Font_color_suffix}"
        echo -e " 密鑰      : ${Green_font_prefix}${config_psk}${Font_color_suffix}"
        echo -e " 模式      : ${Green_font_prefix}${config_mode}${Font_color_suffix}"
        echo -e " 協議版本  : ${Green_font_prefix}${proto_ver}${Font_color_suffix}"
        echo -e "————————————————————————————————"

        echo -e "\n${Info} Surge 配置示例："
        echo -e "${Green_font_prefix}snell-v6 = snell, ${local_ip}, ${config_port}, psk=${config_psk}, version=${proto_ver}${Font_color_suffix}"

        echo -e "\n${Info} Clash Meta 配置示例："
        echo -e "${Green_font_prefix}- name: \"Snell-v6\""
        echo -e "  type: snell"
        echo -e "  server: ${local_ip}"
        echo -e "  port: ${config_port}"
        echo -e "  psk: ${config_psk}"
        echo -e "  version: ${proto_ver}${Font_color_suffix}"
    else
        # v5：顯示 obfs/obfs-host
        local config_obfs config_obfs_host
        config_obfs=$(grep "^obfs[^-]" "${CONF}" | sed 's/^obfs = //')
        [[ -z "${config_obfs}" ]] && config_obfs=$(awk -F' = ' '/^obfs[^-]/{print $2}' "${CONF}")
        config_obfs_host=$(grep "^obfs-host" "${CONF}" | sed 's/^obfs-host = //')
        [[ -z "${config_obfs_host}" ]] && config_obfs_host=$(awk -F' = ' '/^obfs-host/{print $2}' "${CONF}")

        echo -e "\n${Info} 當前 Snell Server v5 配置信息："
        echo -e "————————————————————————————————"
        echo -e " 服務器地址: ${Green_font_prefix}${local_ip}${Font_color_suffix}"
        echo -e " 端口      : ${Green_font_prefix}${config_port}${Font_color_suffix}"
        echo -e " 密鑰      : ${Green_font_prefix}${config_psk}${Font_color_suffix}"
        echo -e " 混淆      : ${Green_font_prefix}${config_obfs}${Font_color_suffix}"
        echo -e " 混淆主機  : ${Green_font_prefix}${config_obfs_host}${Font_color_suffix}"
        echo -e " 協議版本  : ${Green_font_prefix}${proto_ver}${Font_color_suffix}"
        echo -e "————————————————————————————————"

        echo -e "\n${Info} Surge 配置示例："
        echo -e "${Green_font_prefix}snell-v5 = snell, ${local_ip}, ${config_port}, psk=${config_psk}, obfs=${config_obfs}, obfs-host=${config_obfs_host}, version=${proto_ver}${Font_color_suffix}"

        echo -e "\n${Info} Clash 配置示例："
        echo -e "${Green_font_prefix}- name: \"Snell-v5\""
        echo -e "  type: snell"
        echo -e "  server: ${local_ip}"
        echo -e "  port: ${config_port}"
        echo -e "  psk: ${config_psk}"
        echo -e "  obfs-opts:"
        echo -e "    mode: ${config_obfs}"
        echo -e "    host: ${config_obfs_host}"
        echo -e "  version: ${proto_ver}${Font_color_suffix}"
    fi
}

# ── 生命週期 ──────────────────────────────────────
install_snell(){
    check_root
    check_sys

    if check_installed_status 2>/dev/null; then
        echo -e "${Error} 檢測到 Snell Server ${current_ver_label} 已安裝！"
        echo -e "${Info} 如需重新安裝，請先卸載現有版本"
        exit 1
    fi

    echo -e "${Info} 開始安裝 Snell Server ${current_ver_label} (${snell_target_ver})..."

    get_system_arch
    set_port
    generate_psk
    install_dependencies
    download_snell
    create_service
    write_config

    echo -e "${Info} 正在啟動 Snell Server ${current_ver_label}..."
    if systemctl start "${SERVICE_NAME}"; then
        echo -e "${Info} ${Green_font_prefix}Snell Server ${current_ver_label} 啟動成功！${Font_color_suffix}"
        show_config
        echo -e "\n${Info} Snell Server ${current_ver_label} 安裝完成！"
    else
        echo -e "${Error} Snell Server ${current_ver_label} 啟動失敗！"
        exit 1
    fi
}

start_snell(){
    check_installed_status || exit 1
    echo -e "${Info} 正在啟動 Snell Server ${current_ver_label}..."
    if systemctl start "${SERVICE_NAME}"; then
        echo -e "${Info} Snell Server ${current_ver_label} 啟動成功！"
        return 0
    else
        echo -e "${Error} Snell Server ${current_ver_label} 啟動失敗！"
        return 1
    fi
}

stop_snell(){
    check_installed_status || exit 1
    echo -e "${Info} 正在停止 Snell Server ${current_ver_label}..."
    if systemctl stop "${SERVICE_NAME}"; then
        echo -e "${Info} Snell Server ${current_ver_label} 停止成功！"
    else
        echo -e "${Error} Snell Server ${current_ver_label} 停止失敗！"
    fi
}

restart_snell(){
    check_installed_status || exit 1
    echo -e "${Info} 正在重啟 Snell Server ${current_ver_label}..."
    if systemctl restart "${SERVICE_NAME}"; then
        echo -e "${Info} Snell Server ${current_ver_label} 重啟成功！"
        show_config
    else
        echo -e "${Error} Snell Server ${current_ver_label} 重啟失敗！"
    fi
}

status_snell(){
    check_installed_status || exit 1
    echo -e "${Info} Snell Server ${current_ver_label} 運行狀態："
    systemctl status "${SERVICE_NAME}" --no-pager
    echo -e "\n${Info} 最近日誌："
    journalctl -u "${SERVICE_NAME}" -n 10 --no-pager
}

update_snell(){
    check_installed_status || exit 1
    echo -e "${Info} 正在更新 Snell Server ${current_ver_label} 到 ${snell_target_ver}..."
    get_current_version
    get_system_arch
    stop_snell
    download_snell
    echo -e "${Info} 正在重啟服務..."
    if systemctl start "${SERVICE_NAME}"; then
        echo -e "${Info} Snell Server ${current_ver_label} 更新完成！"
        show_config
    else
        echo -e "${Error} 服務重啟失敗！"
    fi
}

uninstall_snell(){
    check_installed_status || exit 1
    echo -e "${Warning} 確定要卸載 Snell Server ${current_ver_label} 嗎？這將刪除所有相關文件！"
    read -e -p "(y/N): " confirm
    if [[ ${confirm} =~ ^[Yy]$ ]]; then
        echo -e "${Info} 正在卸載 Snell Server ${current_ver_label}..."
        systemctl stop "${SERVICE_NAME}" 2>/dev/null
        systemctl disable "${SERVICE_NAME}" 2>/dev/null
        rm -f "${FILE}"
        rm -f "${SERVICE_FILE}"
        rm -rf "${FOLDER}"
        systemctl daemon-reload
        echo -e "${Info} Snell Server ${current_ver_label} 卸載完成！"
    else
        echo -e "${Info} 取消卸載操作"
    fi
}

edit_config(){
    check_installed_status || exit 1
    local editor
    if command -v nano >/dev/null 2>&1; then
        editor="nano"
    elif command -v vim >/dev/null 2>&1; then
        editor="vim"
    elif command -v vi >/dev/null 2>&1; then
        editor="vi"
    else
        echo -e "${Error} 未找到可用的文本編輯器！"
        return 1
    fi
    echo -e "${Info} 使用 ${editor} 編輯配置文件 ${CONF}..."
    echo -e "${Warning} 編輯完成後需要重啟服務才能生效！"
    ${editor} "${CONF}"
    echo -e "${Question} 是否重啟服務使配置生效？(y/N)"
    read -e -p ": " restart_confirm
    [[ ${restart_confirm} =~ ^[Yy]$ ]] && restart_snell
}

# ── 選版本 ────────────────────────────────────────
# 設定 current_ver_label 並呼叫 get_paths
# 可透過參數傳入 v5/v6，或互動詢問
select_version(){
    local ver="$1"
    if [[ "${ver}" == "v5" || "${ver}" == "v6" ]]; then
        current_ver_label="${ver}"
    else
        echo -e "${Question} 請選擇 Snell 版本："
        echo -e " ${Green_font_prefix}1.${Font_color_suffix} Snell v5 (穩定版 ${SNELL_V5_VER})"
        echo -e " ${Green_font_prefix}2.${Font_color_suffix} Snell v6 (Beta ${SNELL_V6_VER})"
        read -e -p " 請輸入數字 [1-2]: " ver_choice
        case "${ver_choice}" in
            1) current_ver_label="v5" ;;
            2) current_ver_label="v6" ;;
            *) echo -e "${Error} 無效選擇，預設使用 v5"; current_ver_label="v5" ;;
        esac
    fi
    get_paths "${current_ver_label}"
}

# ── 主選單 ────────────────────────────────────────
show_menu(){
    clear
    echo -e "
  Snell Server 管理腳本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
  ————————————————————————————————
  ${Yellow_font_prefix}⚡ 支持版本: v5 (${SNELL_V5_VER})  |  v6 Beta (${SNELL_V6_VER})${Font_color_suffix}
  ————————————————————————————————
 ${Green_font_prefix} A.${Font_color_suffix} 修復舊版 → 遷移至 v5/v6（無版本號舊裝置）
  ————————————————————————————————
 ${Green_font_prefix} 1.${Font_color_suffix} 安裝 Snell Server (v5/v6)
 ${Green_font_prefix} 2.${Font_color_suffix} 卸載 Snell Server (v5/v6)
  ————————————————————————————————
 ${Green_font_prefix} 3.${Font_color_suffix} 啟動 Snell Server (v5/v6)
 ${Green_font_prefix} 4.${Font_color_suffix} 停止 Snell Server (v5/v6)
 ${Green_font_prefix} 5.${Font_color_suffix} 重啟 Snell Server (v5/v6)
 ${Green_font_prefix} 6.${Font_color_suffix} 查看運行狀態     (v5/v6)
  ————————————————————————————————
 ${Green_font_prefix} 7.${Font_color_suffix} 查看配置信息     (v5/v6)
 ${Green_font_prefix} 8.${Font_color_suffix} 編輯配置文件     (v5/v6)
 ${Green_font_prefix} 9.${Font_color_suffix} 更新 Snell Server(v5/v6)
  ————————————————————————————————
 ${Green_font_prefix} 0.${Font_color_suffix} 退出腳本
  ————————————————————————————————"

    read -e -p " 請輸入選項 [0-9/A]: " choice

    case "${choice}" in
        A|a) migrate_legacy ;;
        1) select_version; install_snell ;;
        2) select_version; uninstall_snell ;;
        3) select_version; start_snell ;;
        4) select_version; stop_snell ;;
        5) select_version; restart_snell ;;
        6) select_version; status_snell ;;
        7) select_version; show_config ;;
        8) select_version; edit_config ;;
        9) select_version; update_snell ;;
        0) exit 0 ;;
        *) echo -e "${Error} 請輸入正確的選項" ;;
    esac

    echo
    read -e -p "按回車鍵繼續..."
    show_menu
}

# ── 入口 ──────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    # 支援: ./snell.sh install v5  或  ./snell.sh install
    action="$1"
    ver_arg="$2"   # 可選: v5 或 v6

    case "${action}" in
        "install")   select_version "${ver_arg}"; install_snell ;;
        "uninstall") select_version "${ver_arg}"; uninstall_snell ;;
        "start")     select_version "${ver_arg}"; start_snell ;;
        "stop")      select_version "${ver_arg}"; stop_snell ;;
        "restart")   select_version "${ver_arg}"; restart_snell ;;
        "status")    select_version "${ver_arg}"; status_snell ;;
        "update")    select_version "${ver_arg}"; update_snell ;;
        "config")    select_version "${ver_arg}"; show_config ;;
        "migrate")   migrate_legacy ;;
        *)
            echo "用法: $0 {install|uninstall|start|stop|restart|status|update|config|migrate} [v5|v6]"
            echo "範例:"
            echo "  $0 install v5      # 安裝 Snell v5"
            echo "  $0 install v6      # 安裝 Snell v6"
            echo "  $0 migrate         # 修復舊版安裝（無版本號）"
            exit 1
            ;;
    esac
else
    show_menu
fi
