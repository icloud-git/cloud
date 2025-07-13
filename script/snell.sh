#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
# System Required: Debian/Ubuntu
# Description: Snell Server 管理腳本 (優化版)
# Version: 2.0.0
#=================================================

sh_ver="2.0.0"
snell_ver="v5.0.0"
FOLDER="/etc/snell/"
FILE="/usr/local/bin/snell-server"
CONF="/etc/snell/config.conf"
LOG_FILE="/var/log/snell-server.log"
Now_ver_File="/etc/snell/ver.txt"
SERVICE_FILE="/etc/systemd/system/snell-server.service"

# 顏色定義
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Yellow_font_prefix="\033[0;33m" && Blue_font_prefix="\033[34m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[錯誤]${Font_color_suffix}"
Warning="${Yellow_font_prefix}[警告]${Font_color_suffix}"
Question="${Blue_font_prefix}[詢問]${Font_color_suffix}"

# 檢查Root權限
check_root(){
    if [[ $EUID != 0 ]]; then
        echo -e "${Error} 當前非ROOT賬號，無法繼續操作！"
        echo -e "${Info} 請使用: ${Green_font_prefix}sudo su${Font_color_suffix} 獲取ROOT權限"
        exit 1
    fi
}

# 檢查系統類型
check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        pm="yum"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
        pm="apt-get"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
        pm="apt-get"
    else
        echo -e "${Error} 當前系統不受支持！僅支持 Debian/Ubuntu/CentOS"
        exit 1
    fi
}

# 安裝依賴
install_dependencies(){
    echo -e "${Info} 正在安裝依賴包..."
    if [[ ${pm} == "apt-get" ]]; then
        apt-get update -y
        apt-get install gzip wget curl unzip systemd -y
    elif [[ ${pm} == "yum" ]]; then
        yum update -y
        yum install gzip wget curl unzip systemd -y
    fi
    
    if [[ $? != 0 ]]; then
        echo -e "${Error} 依賴安裝失敗！"
        exit 1
    fi
}

# 系統架構檢測
get_system_arch() {
    local uname=$(uname -m)
    case "$uname" in
        "i686"|"i386")
            arch="i386"
            ;;
        *"armv7"*|"armv6l")
            arch="armv7l"
            ;;
        *"armv8"*|"aarch64")
            arch="aarch64"
            ;;
        "x86_64"|"amd64")
            arch="amd64"
            ;;
        *)
            echo -e "${Error} 不支持的系統架構: $uname"
            exit 1
            ;;
    esac
    echo -e "${Info} 檢測到系統架構: ${Green_font_prefix}${arch}${Font_color_suffix}"
}

# 檢查是否已安裝
check_installed_status(){
    if [[ ! -e ${FILE} ]]; then
        echo -e "${Error} Snell Server 未安裝！"
        return 1
    fi
    return 0
}

# 獲取當前版本
get_current_version(){
    if [[ -f ${Now_ver_File} ]]; then
        current_ver=$(cat ${Now_ver_File})
        echo -e "${Info} 當前版本: ${Green_font_prefix}${current_ver}${Font_color_suffix}"
    else
        echo -e "${Warning} 無法獲取當前版本信息"
    fi
}

# 下載Snell Server
download_snell(){
    local download_url="https://dl.nssurge.com/snell/snell-server-${snell_ver}-linux-${arch}.zip"
    local temp_dir="/tmp/snell_install"
    
    echo -e "${Info} 正在下載 Snell Server ${snell_ver} (${arch})..."
    echo -e "${Info} 下載地址: ${download_url}"
    
    # 創建臨時目錄
    [[ -d ${temp_dir} ]] && rm -rf ${temp_dir}
    mkdir -p ${temp_dir}
    cd ${temp_dir}
    
    # 下載文件
    if ! wget --no-check-certificate -O "snell-server.zip" "${download_url}"; then
        echo -e "${Error} Snell Server 下載失敗！"
        rm -rf ${temp_dir}
        exit 1
    fi
    
    # 解壓文件
    if ! unzip -o "snell-server.zip"; then
        echo -e "${Error} Snell Server 解壓失敗！"
        rm -rf ${temp_dir}
        exit 1
    fi
    
    # 檢查二進制文件
    if [[ ! -e "snell-server" ]]; then
        echo -e "${Error} 未找到 snell-server 二進制文件！"
        rm -rf ${temp_dir}
        exit 1
    fi
    
    # 創建目錄
    [[ ! -d ${FOLDER} ]] && mkdir -p ${FOLDER}
    
    # 移動文件
    chmod +x snell-server
    mv -f snell-server "${FILE}"
    echo "${snell_ver}" > ${Now_ver_File}
    
    # 清理臨時文件
    cd /
    rm -rf ${temp_dir}
    
    echo -e "${Info} Snell Server 下載安裝完成！"
}

# 創建系統服務
create_service(){
    echo -e "${Info} 正在創建系統服務..."
    
    cat > ${SERVICE_FILE} << EOF
[Unit]
Description=Snell Proxy Service
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
    systemctl enable snell-server
    echo -e "${Info} 系統服務創建完成！"
}

# 設置端口
set_port(){
    while true; do
        echo -e "${Question} 請輸入 Snell Server 端口 [1-65535]"
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

# 生成密鑰
generate_psk(){
    psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
    echo -e "${Info} 生成密鑰: ${Green_font_prefix}${psk}${Font_color_suffix}"
}

# 寫入配置文件
write_config(){
    echo -e "${Info} 正在生成配置文件..."
    
    cat > ${CONF} << EOF
[snell-server]
listen = 0.0.0.0:${port}
psk = ${psk}
obfs = http
obfs-host = www.bing.com
tfo = true
mptcp = true
version = 5
EOF
    
    echo -e "${Info} 配置文件寫入完成！"
}

# 獲取外網IP
get_ip(){
    local_ip=$(curl -s -4 http://checkip.amazonaws.com 2>/dev/null)
    if [[ -z ${local_ip} ]]; then
        local_ip=$(curl -s -4 http://ipinfo.io/ip 2>/dev/null)
    fi
    if [[ -z ${local_ip} ]]; then
        local_ip="你的服務器IP"
    fi
}

# 顯示配置信息
show_config(){
    if [[ ! -f ${CONF} ]]; then
        echo -e "${Error} 配置文件不存在！"
        return 1
    fi
    
    # 更可靠的配置解析方法
    local config_port=$(grep "^listen" ${CONF} | sed -n 's/.*:\([0-9]\+\).*/\1/p')
    local config_psk=$(grep "^psk" ${CONF} | sed 's/^psk = //')
    local config_obfs=$(grep "^obfs[^-]" ${CONF} | sed 's/^obfs = //')
    local config_obfs_host=$(grep "^obfs-host" ${CONF} | sed 's/^obfs-host = //')
    
    # 如果上面的方法失敗，嘗試備用方法
    [[ -z "${config_port}" ]] && config_port=$(awk -F':' '/^listen/{print $NF}' ${CONF})
    [[ -z "${config_psk}" ]] && config_psk=$(awk -F' = ' '/^psk/{print $2}' ${CONF})
    [[ -z "${config_obfs}" ]] && config_obfs=$(awk -F' = ' '/^obfs[^-]/{print $2}' ${CONF})
    [[ -z "${config_obfs_host}" ]] && config_obfs_host=$(awk -F' = ' '/^obfs-host/{print $2}' ${CONF})
    
    get_ip
    
    echo -e "\n${Info} 當前 Snell Server 配置信息："
    echo -e "————————————————————————————————"
    echo -e " 服務器地址: ${Green_font_prefix}${local_ip}${Font_color_suffix}"
    echo -e " 端口: ${Green_font_prefix}${config_port}${Font_color_suffix}"
    echo -e " 密鑰: ${Green_font_prefix}${config_psk}${Font_color_suffix}"
    echo -e " 混淆: ${Green_font_prefix}${config_obfs}${Font_color_suffix}"
    echo -e " 混淆主機: ${Green_font_prefix}${config_obfs_host}${Font_color_suffix}"
    echo -e "————————————————————————————————"
    
    echo -e "\n${Info} Surge 配置示例："
    echo -e "${Green_font_prefix}snell = snell, ${local_ip}, ${config_port}, psk=${config_psk}, obfs=${config_obfs}, obfs-host=${config_obfs_host}, version=5${Font_color_suffix}"
    
    echo -e "\n${Info} Clash 配置示例："
    echo -e "${Green_font_prefix}- name: \"Snell\""
    echo -e "  type: snell"
    echo -e "  server: ${local_ip}"
    echo -e "  port: ${config_port}"
    echo -e "  psk: ${config_psk}"
    echo -e "  obfs-opts:"
    echo -e "    mode: http"
    echo -e "    host: ${config_obfs_host}"
    echo -e "  version: 5${Font_color_suffix}"
}

# 安裝Snell Server
install_snell(){
    check_root
    check_sys
    
    if check_installed_status; then
        echo -e "${Error} 檢測到 Snell Server 已安裝！"
        echo -e "${Info} 如需重新安裝，請先卸載現有版本"
        exit 1
    fi
    
    echo -e "${Info} 開始安裝 Snell Server ${snell_ver}..."
    
    get_system_arch
    set_port
    generate_psk
    install_dependencies
    download_snell
    create_service
    write_config
    
    echo -e "${Info} 正在啟動 Snell Server..."
    if start_snell; then
        show_config
        echo -e "\n${Info} Snell Server 安裝完成！"
    else
        echo -e "${Error} Snell Server 啟動失敗！"
        exit 1
    fi
}

# 啟動服務
start_snell(){
    check_installed_status || exit 1
    
    echo -e "${Info} 正在啟動 Snell Server..."
    if systemctl start snell-server; then
        echo -e "${Info} Snell Server 啟動成功！"
        return 0
    else
        echo -e "${Error} Snell Server 啟動失敗！"
        return 1
    fi
}

# 停止服務
stop_snell(){
    check_installed_status || exit 1
    
    echo -e "${Info} 正在停止 Snell Server..."
    if systemctl stop snell-server; then
        echo -e "${Info} Snell Server 停止成功！"
    else
        echo -e "${Error} Snell Server 停止失敗！"
    fi
}

# 重啟服務
restart_snell(){
    check_installed_status || exit 1
    
    echo -e "${Info} 正在重啟 Snell Server..."
    if systemctl restart snell-server; then
        echo -e "${Info} Snell Server 重啟成功！"
        show_config
    else
        echo -e "${Error} Snell Server 重啟失敗！"
    fi
}

# 查看狀態
status_snell(){
    check_installed_status || exit 1
    
    echo -e "${Info} Snell Server 運行狀態："
    systemctl status snell-server --no-pager
    
    echo -e "\n${Info} 最近日志："
    journalctl -u snell-server -n 10 --no-pager
}

# 更新Snell Server
update_snell(){
    check_installed_status || exit 1
    
    echo -e "${Info} 正在更新 Snell Server 到 ${snell_ver}..."
    get_current_version
    
    get_system_arch
    stop_snell
    download_snell
    
    echo -e "${Info} 正在重啟服務..."
    if restart_snell; then
        echo -e "${Info} Snell Server 更新完成！"
    else
        echo -e "${Error} 服務重啟失敗！"
    fi
}

# 卸載Snell Server
uninstall_snell(){
    check_installed_status || exit 1
    
    echo -e "${Warning} 確定要卸載 Snell Server 嗎？這將刪除所有相關文件！"
    read -e -p "(y/N): " confirm
    
    if [[ ${confirm} =~ ^[Yy]$ ]]; then
        echo -e "${Info} 正在卸載 Snell Server..."
        
        systemctl stop snell-server 2>/dev/null
        systemctl disable snell-server 2>/dev/null
        
        rm -f "${FILE}"
        rm -f "${SERVICE_FILE}"
        rm -rf "${FOLDER}"
        
        systemctl daemon-reload
        
        echo -e "${Info} Snell Server 卸載完成！"
    else
        echo -e "${Info} 取消卸載操作"
    fi
}

# 編輯配置
edit_config(){
    check_installed_status || exit 1
    
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
    
    echo -e "${Info} 使用 ${editor} 編輯配置文件..."
    echo -e "${Warning} 編輯完成後需要重啟服務才能生效！"
    
    ${editor} ${CONF}
    
    echo -e "${Question} 是否重啟服務使配置生效？(y/N)"
    read -e -p ": " restart_confirm
    
    if [[ ${restart_confirm} =~ ^[Yy]$ ]]; then
        restart_snell
    fi
}

# 主菜單
show_menu(){
    clear
    echo -e "
  Snell Server 管理腳本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
  適用版本: ${Green_font_prefix}Snell ${snell_ver}${Font_color_suffix}
  ————————————————————————————————
 ${Green_font_prefix}1.${Font_color_suffix} 安裝 Snell Server
 ${Green_font_prefix}2.${Font_color_suffix} 卸載 Snell Server
  ————————————————————————————————
 ${Green_font_prefix}3.${Font_color_suffix} 啟動 Snell Server
 ${Green_font_prefix}4.${Font_color_suffix} 停止 Snell Server
 ${Green_font_prefix}5.${Font_color_suffix} 重啟 Snell Server
 ${Green_font_prefix}6.${Font_color_suffix} 查看運行狀態
  ————————————————————————————————
 ${Green_font_prefix}7.${Font_color_suffix} 查看配置信息
 ${Green_font_prefix}8.${Font_color_suffix} 編輯配置文件
 ${Green_font_prefix}9.${Font_color_suffix} 更新 Snell Server
  ————————————————————————————————
 ${Green_font_prefix}0.${Font_color_suffix} 退出腳本
  ————————————————————————————————"
    
    read -e -p " 請輸入數字 [0-9]: " choice
    
    case "$choice" in
        1) install_snell ;;
        2) uninstall_snell ;;
        3) start_snell ;;
        4) stop_snell ;;
        5) restart_snell ;;
        6) status_snell ;;
        7) show_config ;;
        8) edit_config ;;
        9) update_snell ;;
        0) exit 0 ;;
        *) echo -e "${Error} 請輸入正確的數字 [0-9]" ;;
    esac
    
    echo
    read -e -p "按回車鍵繼續..." 
    show_menu
}

# 主程序入口
main(){
    show_menu
}

# 如果有參數則直接執行對應功能
if [[ $# -gt 0 ]]; then
    case "$1" in
        "install") install_snell ;;
        "uninstall") uninstall_snell ;;
        "start") start_snell ;;
        "stop") stop_snell ;;
        "restart") restart_snell ;;
        "status") status_snell ;;
        "update") update_snell ;;
        "config") show_config ;;
        *) echo "用法: $0 {install|uninstall|start|stop|restart|status|update|config}" ;;
    esac
else
    main
fi
