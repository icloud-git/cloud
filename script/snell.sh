#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
# System Required: Debian
# Description: Snell Server 管理腳本
#=================================================

sh_ver="1.0.0"
FOLDER="/etc/snell/"
FILE="/usr/local/bin/snell-server"
CONF="/etc/snell/config.conf"
Now_ver_File="/etc/snell/ver.txt"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Yellow_font_prefix="\033[0;33m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[錯誤]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"

check_root(){
    [[ $EUID != 0 ]] && echo -e "${Error} 當前非ROOT賬號(或沒有ROOT權限)，無法繼續操作，請更換ROOT賬號或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令獲取臨時ROOT權限。" && exit 1
}

check_sys(){
    if cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    else
        echo -e "${Error} 當前系統不是 Debian，不支持！" && exit 1
    fi
}

Installation_dependency(){
    apt-get update && apt-get install gzip wget curl unzip -y
}

sysArch() {
    uname=$(uname -m)
    if [[ "$uname" == "i686" ]] || [[ "$uname" == "i386" ]]; then
        arch="i386"
    elif [[ "$uname" == *"armv7"* ]] || [[ "$uname" == "armv6l" ]]; then
        arch="armv7l"
    elif [[ "$uname" == *"armv8"* ]] || [[ "$uname" == "aarch64" ]]; then
        arch="aarch64"
    else
        arch="amd64"
    fi    
}

check_installed_status(){
    [[ ! -e ${FILE} ]] && echo -e "${Error} Snell Server 沒有安裝，請檢查 !" && exit 1
}

Download() {
    if [[ ! -e "${FOLDER}" ]]; then
        mkdir "${FOLDER}"
    fi
    echo -e "${Info} 正在請求下載 Snell Server ……"
    wget --no-check-certificate -O "snell-server.zip" "https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip"

    if [[ ! -e "snell-server.zip" ]]; then
        echo -e "${Error} Snell Server 下載失敗！"
        exit 1
    else
        unzip -o "snell-server.zip"
    fi
    if [[ ! -e "snell-server" ]]; then
        echo -e "${Error} Snell Server 解壓失敗！"
        exit 1
    else
        rm -rf "snell-server.zip"
        chmod +x snell-server
        mv -f snell-server "${FILE}"
        echo "v4.1.0" > ${Now_ver_File}
        echo -e "${Info} Snell Server 主程序下載安裝完畢！"
    fi
}

Service(){
    echo '[Unit]
Description=Snell Service
After=network-online.target
Wants=network-online.target
[Service]
LimitNOFILE=32767 
Type=simple
User=root
Restart=on-failure
RestartSec=10s
ExecStartPre=/bin/sh -c "ulimit -n 51200"
ExecStart=/usr/local/bin/snell-server -c /etc/snell/config.conf
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/snell-server.service
    systemctl enable --now snell-server
    echo -e "${Info} Snell Server 服務配置完成 !"
}

Write_config(){
    cat > ${CONF}<<-EOF
[snell-server]
listen = ::0:${port}
ipv6 = true
psk = ${psk}
obfs = http
obfs-host = www.bing.com
tfo = true
version = 4
# dns = 1.1.1.1, 8.8.8.8, 2001:4860:4860::8888
EOF
}

Set_port(){
    while true
    do
        echo -e "${Tip} 本步驟不涉及系統防火墻端口操作，請手動放行相應端口！"
        echo -e "請輸入 Snell Server 端口 [1-65535]"
        read -e -p "(默認: 2345):" port
        [[ -z "${port}" ]] && port="2345"
        echo $((${port}+0)) &>/dev/null
        if [[ $? -eq 0 ]]; then
            if [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
                echo && echo "=============================="
                echo -e "端口 : ${Red_font_prefix} ${port} ${Font_color_suffix}"
                echo "==============================" && echo
                break
            else
                echo "輸入錯誤, 請輸入正確的端口。"
            fi
        else
            echo "輸入錯誤, 請輸入正確的端口。"
        fi
    done
}

Set_psk(){
    psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo && echo "=============================="
    echo -e "密鑰 : ${Red_font_prefix} ${psk} ${Font_color_suffix}"
    echo "==============================" && echo
}

Install(){
    check_root
    check_sys
    sysArch
    [[ -e ${FILE} ]] && echo -e "${Error} 檢測到 Snell Server 已安裝 !" && exit 1
    echo -e "${Info} 開始設置 配置..."
    Set_port
    Set_psk
    echo -e "${Info} 開始安裝/配置 依賴..."
    Installation_dependency
    echo -e "${Info} 開始下載/安裝 Snell Server..."
    Download
    echo -e "${Info} 開始安裝 服務腳本..."
    Service
    echo -e "${Info} 開始寫入 配置文件..."
    Write_config
    echo -e "${Info} Snell Server 安裝完畢，開始啟動..."
    Start
    # Output Surge configuration
    local_ip=$(curl -s http://checkip.amazonaws.com)
    echo -e "\n${Info} 你可以在 Surge 中使用以下配置："
    echo "server = snell, ${local_ip}, ${port}, psk=${psk}, obfs=http, obfs-host=www.bing.com, version=4, reuse=true, tfo=true"
}

Start(){
    check_installed_status
    systemctl start snell-server
    echo -e "${Info} Snell Server 啟動成功 !"
}

Uninstall(){
    check_installed_status
    echo "確定要卸載 Snell Server ? (y/N)"
    echo
    read -e -p "(默認: n):" unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        systemctl stop snell-server
        systemctl disable snell-server
        rm -rf "${FILE}" "${CONF}" "${Now_ver_File}"
        echo && echo "Snell Server 卸載完成 !" && echo
    else
        echo && echo "卸載已取消..." && echo
    fi
}

start_menu(){
    clear
    echo && echo -e "
  Snell Server 管理腳本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
  ————————————————
 ${Green_font_prefix}1.${Font_color_suffix} 安裝 Snell Server
 ${Green_font_prefix}2.${Font_color_suffix} 卸載 Snell Server
  ————————————————
 ${Green_font_prefix}3.${Font_color_suffix} 啟動 Snell Server
 ${Green_font_prefix}4.${Font_color_suffix} 停止 Snell Server
 ${Green_font_prefix}5.${Font_color_suffix} 重啟 Snell Server
  ————————————————
 ${Green_font_prefix}6.${Font_color_suffix} 更新 Snell Server
  ————————————————
 ${Green_font_prefix}0.${Font_color_suffix} 退出腳本
  ————————————————" && echo
    read -e -p " 請輸入數字 [0-6]:" num
    case "$num" in
        1)
        Install
        ;;
        2)
        Uninstall
        ;;
        3)
        Start
        ;;
        4)
        systemctl stop snell-server
        echo -e "${Info} Snell Server 停止成功 !"
        ;;
        5)
        systemctl restart snell-server
        echo -e "${Info} Snell Server 重啟成功 !"
        echo -e "現在配置(/etc/snell/config.conf)："
        cat /etc/snell/config.conf
        ;;
        6)
        systemctl stop snell-server
        Download
        systemctl restart snell-server
        systemctl status snell-server
        ;;
        0)
        exit 1
        ;;
        *)
        echo "請輸入正確數字 [0-6]"
        ;;
    esac
}

start_menu
