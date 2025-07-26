#!/bin/bash

#===============================================================================================
# Komari Agent 非官方管理腳本 (優化版 v6 - 繁體中文)
#
# 優化重點:
#   - 新增重啟 Agent 功能
#   - 改進狀態檢查邏輯
#   - 優化用戶界面
#   - 增強錯誤處理
#   - 加入快速狀態檢查
#   - 支持鏡像站下載 (github.moeyy.xyz)
#   - 新增命令行參數支持
#
# 使用: ./k.sh [選項]
# 選項:
#   -cn, --mirror    強制使用鏡像站 (github.moeyy.xyz)
#   -h, --help       顯示幫助信息
#===============================================================================================

# --- 全局變量 ---
USE_MIRROR=false

# --- 參數處理 ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -cn|--mirror)
                USE_MIRROR=true
                echo -e "${CYAN}✓ 已啟用鏡像站模式 (github.moeyy.xyz)${NC}"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}錯誤：未知參數 '$1'${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo "Komari Agent 管理腳本 v6"
    echo
    echo "用法: $0 [選項]"
    echo
    echo "選項:"
    echo "  -cn, --mirror    強制使用鏡像站 (github.moeyy.xyz)"
    echo "  -h, --help       顯示此幫助信息"
    echo
    echo "示例:"
    echo "  $0              # 正常啟動 (自動選擇最佳源)"
    echo "  $0 -cn          # 強制使用鏡像站"
    echo "  $0 --mirror     # 強制使用鏡像站"
    echo
    echo "快速使用:"
    echo "  # 正常模式"
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/icloud-git/cloud/refs/heads/main/script/k.sh)"
    echo
    echo "  # 鏡像模式"
    echo "  bash <(curl -fsSL https://github.moeyy.xyz/https://raw.githubusercontent.com/icloud-git/cloud/refs/heads/main/script/k.sh) -cn"
}

# --- 設定 (請根據您的情況修改此處) ---
AGENT_ENDPOINT="https://ping.080886.xyz"

# --- 常量 (通常無需修改) ---
AGENT_DIR="$HOME/.komari-agent"
AGENT_EXEC_NAME="komari-agent"
CONFIG_FILE="${AGENT_DIR}/config.conf"
LOG_FILE="${AGENT_DIR}/agent.log"
PID_FILE="${AGENT_DIR}/agent.pid"
GITHUB_REPO="komari-monitor/komari-agent"
DEFAULT_INTERVAL=20

# --- 顏色定義 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# --- 輔助函數 ---
check_root() { 
    if [[ $EUID -eq 0 ]]; then 
        echo -e "${RED}錯誤：請不要使用 root 使用者執行此腳本！${NC}"; 
        exit 1; 
    fi; 
}

get_latest_version() { 
    echo -e "${YELLOW}正在從 GitHub 獲取最新版本資訊...${NC}" >&2; 
    local latest_tag=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); 
    if [[ -z "$latest_tag" ]]; then 
        echo -e "${RED}錯誤：無法獲取最新版本號。${NC}" >&2; 
        return 1; 
    fi; 
    echo "${latest_tag//v/}"; 
}

detect_arch() { 
    case $(uname -m) in 
        x86_64|amd64) echo "linux-amd64" ;; 
        i386|i686) echo "linux-386" ;; 
        aarch64|arm64) echo "linux-arm64" ;; 
        armv7l) echo "linux-arm" ;; 
        *) echo -e "${RED}錯誤：不支援的系統架構: $(uname -m)${NC}" >&2; exit 1; ;; 
    esac; 
}

load_config() { 
    if [[ -f "$CONFIG_FILE" ]]; then 
        source "$CONFIG_FILE"; 
    else 
        AGENT_TOKEN=""; 
        AGENT_INTERVAL="$DEFAULT_INTERVAL"; 
    fi; 
}

save_config() { 
    mkdir -p "$AGENT_DIR"; 
    echo "AGENT_TOKEN='${AGENT_TOKEN}'" > "$CONFIG_FILE"; 
    echo "AGENT_INTERVAL='${AGENT_INTERVAL}'" >> "$CONFIG_FILE"; 
}

# 獲取 Agent PID
get_agent_pid() {
    local pid=""
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
            echo "$pid"
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # 如果 PID 文件無效，嘗試查找運行中的進程
    local running_pid=$(pgrep -f "$AGENT_EXEC_NAME" | head -1)
    if [ -n "$running_pid" ]; then
        echo "$running_pid" > "$PID_FILE"
        echo "$running_pid"
        return 0
    fi
    
    return 1
}

# 檢查 Agent 是否運行
is_agent_running() {
    local pid=$(get_agent_pid)
    [ -n "$pid" ]
}

stop_agent() {
    echo -e "${YELLOW}正在停止 Agent...${NC}"
    
    local was_running=false
    local pid=$(get_agent_pid)
    
    if [ -n "$pid" ]; then
        echo -e "${YELLOW}正在停止 Agent 行程 (PID: $pid)...${NC}"
        kill "$pid" 2>/dev/null
        was_running=true
        
        # 等待進程結束
        local count=0
        while [ $count -lt 10 ] && ps -p "$pid" > /dev/null 2>&1; do
            sleep 1
            ((count++))
        done
        
        # 如果還沒結束，強制結束
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}正在強制停止...${NC}"
            kill -9 "$pid" 2>/dev/null
        fi
    fi
    
    # 清理任何殘留進程
    if pgrep -f "$AGENT_EXEC_NAME" > /dev/null; then
        echo -e "${YELLOW}正在清理殘留的 Agent 行程...${NC}"
        pkill -f "$AGENT_EXEC_NAME"
        was_running=true
    fi
    
    rm -f "$PID_FILE"
    
    if $was_running; then
        echo -e "${GREEN}Agent 已成功停止。${NC}"
    else
        echo -e "${BLUE}Agent 並未在執行中。${NC}"
    fi
}

start_agent() {
    echo -e "${YELLOW}正在啟動 Agent...${NC}"
    
    # 如果已經在運行，先詢問是否重啟
    if is_agent_running; then
        local current_pid=$(get_agent_pid)
        echo -e "${YELLOW}Agent 已在執行中 (PID: $current_pid)。${NC}"
        read -p "是否要重新啟動？(y/N): " restart_confirm
        if [[ "${restart_confirm,,}" != "y" ]]; then
            echo -e "${BLUE}取消啟動。${NC}"
            return
        fi
        stop_agent
        sleep 2
    fi
    
    load_config
    if [[ -z "$AGENT_TOKEN" ]]; then 
        echo -e "${RED}錯誤：Token 尚未設定，無法啟動。${NC}"; 
        return; 
    fi
    
    local agent_executable=$(find "$AGENT_DIR" -type f -name "${AGENT_EXEC_NAME}-*" 2>/dev/null | head -1)
    if ! [[ -x "$agent_executable" ]]; then 
        echo -e "${RED}錯誤：找不到 Agent 執行檔。${NC}"; 
        return; 
    fi
    
    local cmd="nohup ${agent_executable} -e ${AGENT_ENDPOINT} -t ${AGENT_TOKEN} --disable-web-ssh --interval ${AGENT_INTERVAL}"
    echo -e "${CYAN}執行命令: ${cmd}${NC}"
    
    # 清理舊日誌
    echo "--- Agent 啟動於 $(date) ---" > "$LOG_FILE"
    
    # 啟動 Agent
    ( $cmd >> "$LOG_FILE" 2>&1 & )
    local new_pid=$!
    echo $new_pid > "$PID_FILE"
    
    echo -e "${GREEN}Agent 啟動命令已執行 (PID: $new_pid)。${NC}"
    echo -e "${CYAN}正在顯示啟動日誌...${NC}"
    echo
    
    # 等待一下讓日誌產生
    sleep 2
    
    # 顯示最近的日誌內容
    if [ -f "$LOG_FILE" ]; then
        echo -e "${CYAN}--- 最近日誌 ---${NC}"
        tail -20 "$LOG_FILE" 2>/dev/null || echo "無法讀取日誌"
        echo
        echo -e "${CYAN}提示：使用選項 'l' 查看完整即時日誌。${NC}"
    fi
}

# *** 新增：重啟 Agent 功能 ***
restart_agent() {
    echo -e "${PURPLE}--- 重啟 Agent ---${NC}"
    
    if is_agent_running; then
        echo -e "${YELLOW}Agent 正在執行中，即將重啟...${NC}"
        stop_agent
        sleep 2
    else
        echo -e "${BLUE}Agent 未在執行中，將直接啟動...${NC}"
    fi
    
    start_agent
    
    if is_agent_running; then
        echo -e "${GREEN}Agent 重啟完成！${NC}"
    else
        echo -e "${RED}Agent 重啟失敗，請檢查配置和日誌。${NC}"
    fi
}

# 快速狀態檢查
status_agent() {
    echo -e "${CYAN}--- Agent 狀態檢查 ---${NC}"
    
    if is_agent_running; then
        local pid=$(get_agent_pid)
        echo -e "狀態: ${GREEN}執行中${NC}"
        echo -e "PID: ${pid}"
        
        # 顯示進程資訊
        if command -v ps >/dev/null 2>&1; then
            echo -e "進程資訊:"
            ps -p "$pid" -o pid,ppid,etime,pcpu,pmem,cmd --no-headers 2>/dev/null || echo "無法獲取詳細資訊"
        fi
        
        # 檢查日誌文件大小
        if [ -f "$LOG_FILE" ]; then
            local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)
            echo -e "日誌大小: ${log_size} bytes"
        fi
    else
        echo -e "狀態: ${RED}已停止${NC}"
        
        # 檢查是否有配置
        if [ -f "$CONFIG_FILE" ]; then
            load_config
            echo -e "Token: ${AGENT_TOKEN:0:8}...****"
            echo -e "上報間隔: ${AGENT_INTERVAL} 秒"
        else
            echo -e "${YELLOW}尚未配置${NC}"
        fi
    fi
}

install_or_update() {
    local is_update=${1:-"install"}
    
    if [[ "$is_update" == "update" ]]; then 
        local installed_version_file=$(find "$AGENT_DIR" -type f -name "${AGENT_EXEC_NAME}-*" 2>/dev/null | head -1)
        local latest_version_check=$(get_latest_version)
        if [[ $? -ne 0 ]]; then return; fi
        
        local latest_short_version_check=${latest_version_check//./}
        if [[ "$installed_version_file" == *"$latest_short_version_check"* ]]; then 
            echo -e "${GREEN}您已在使用最新版本 (${latest_version_check})。${NC}"; 
            return; 
        fi
        echo -e "${YELLOW}發現新版本 ${latest_version_check}！準備更新...${NC}"
    fi
    
    local version=$(get_latest_version)
    if [[ $? -ne 0 ]]; then return; fi
    
    local arch=$(detect_arch)
    local short_version=${version//./}
    local filename="${AGENT_EXEC_NAME}-${short_version}"
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/komari-agent-${arch}"
    local mirror_url="https://github.moeyy.xyz/https://github.com/${GITHUB_REPO}/releases/download/${version}/komari-agent-${arch}"
    
    echo "系統架構: ${arch}"
    echo "目標檔案: ${AGENT_DIR}/${filename}"
    
    mkdir -p "$AGENT_DIR"
    echo -e "${YELLOW}正在下載 Agent...${NC}"
    
    if [ "$USE_MIRROR" = true ]; then
        # 強制使用鏡像站
        echo -e "${CYAN}使用鏡像站下載...${NC}"
        if curl -L --connect-timeout 15 --max-time 120 --progress-bar -o "${AGENT_DIR}/agent.tmp" "$mirror_url"; then
            echo -e "${GREEN}從鏡像站下載成功！${NC}"
        else
            echo -e "${RED}鏡像站下載失敗！${NC}"
            rm -f "${AGENT_DIR}/agent.tmp"
            return
        fi
    else
        # 自動選擇模式：先嘗試 GitHub，失敗後切換鏡像站
        echo "嘗試從 GitHub 下載..."
        if curl -L --connect-timeout 15 --max-time 120 --progress-bar -o "${AGENT_DIR}/agent.tmp" "$download_url"; then
            echo -e "${GREEN}從 GitHub 下載成功！${NC}"
        else
            echo -e "${YELLOW}GitHub 下載失敗，自動切換到鏡像站...${NC}"
            # 清理失敗的下載
            rm -f "${AGENT_DIR}/agent.tmp"
            
            # 嘗試從鏡像站下載
            if curl -L --connect-timeout 15 --max-time 120 --progress-bar -o "${AGENT_DIR}/agent.tmp" "$mirror_url"; then
                echo -e "${GREEN}從鏡像站下載成功！${NC}"
            else
                echo -e "${RED}所有下載源均失敗！${NC}"
                rm -f "${AGENT_DIR}/agent.tmp"
                return
            fi
        fi
    fi
    
    local file_size=$(stat -c%s "${AGENT_DIR}/agent.tmp" 2>/dev/null || stat -f%z "${AGENT_DIR}/agent.tmp")
    if [[ "$file_size" -lt 1000000 ]]; then 
        echo -e "${RED}下載失敗：檔案大小異常 (${file_size} bytes)。${NC}"
        rm -f "${AGENT_DIR}/agent.tmp"
        return
    fi
    
    echo -e "${GREEN}下載成功 (檔案大小: ${file_size} bytes)。${NC}"
    
    # 停止舊版本
    stop_agent
    
    # 移除舊執行檔
    find "$AGENT_DIR" -type f -name "${AGENT_EXEC_NAME}-*" -exec rm {} \;
    
    # 安裝新版本
    mv "${AGENT_DIR}/agent.tmp" "${AGENT_DIR}/${filename}"
    chmod +x "${AGENT_DIR}/${filename}"
    
    echo -e "${GREEN}Agent 已成功安裝/更新到版本 ${version}！${NC}"
    
    # 如果是安裝，則啟動；如果是更新，詢問是否啟動
    if [[ "$is_update" == "install" ]]; then
        start_agent
    else
        read -p "是否立即啟動更新後的 Agent？(Y/n): " start_confirm
        if [[ "${start_confirm,,}" != "n" ]]; then
            start_agent
        fi
    fi
}

install_agent() {
    echo -e "${CYAN}--- 安裝 Komari Agent ---${NC}"
    
    if [[ -d "$AGENT_DIR" ]]; then 
        echo -e "${YELLOW}偵測到已存在的安裝目錄，將覆蓋設定。${NC}"
    fi
    
    read -p "請輸入您的 Agent Token: " user_token
    if [[ -z "$user_token" ]]; then 
        echo -e "${RED}Token 不可為空！${NC}"
        return
    fi
    
    read -p "請輸入上報間隔 (秒，預設 ${DEFAULT_INTERVAL}): " user_interval
    if [[ -z "$user_interval" ]]; then
        user_interval="$DEFAULT_INTERVAL"
    elif ! [[ "$user_interval" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}間隔必須是數字，使用預設值 ${DEFAULT_INTERVAL}。${NC}"
        user_interval="$DEFAULT_INTERVAL"
    fi
    
    AGENT_TOKEN="$user_token"
    AGENT_INTERVAL="$user_interval"
    save_config
    
    install_or_update "install"
}

change_token() {
    echo -e "${CYAN}--- 更改 Agent Token ---${NC}"
    
    if ! [[ -f "$CONFIG_FILE" ]]; then 
        echo -e "${RED}錯誤：Agent 尚未安裝。${NC}"
        return
    fi
    
    load_config
    echo "目前 Token: ${AGENT_TOKEN:0:8}...****"
    read -p "請輸入新的 Agent Token: " new_token
    
    if [[ -z "$new_token" ]]; then 
        echo -e "${RED}Token 不可為空！${NC}"
        return
    fi
    
    AGENT_TOKEN="$new_token"
    save_config
    echo -e "${GREEN}Token 更新成功！${NC}"
    
    read -p "是否立即重啟 Agent 以應用新設定？(Y/n): " restart_confirm
    if [[ "${restart_confirm,,}" != "n" ]]; then
        restart_agent
    fi
}

change_interval() {
    echo -e "${CYAN}--- 更改上報頻率 ---${NC}"
    
    if ! [[ -f "$CONFIG_FILE" ]]; then 
        echo -e "${RED}錯誤：Agent 尚未安裝。${NC}"
        return
    fi
    
    load_config
    echo "目前上報頻率: ${AGENT_INTERVAL} 秒"
    read -p "請輸入新的上報頻率 (秒): " new_interval
    
    if ! [[ "$new_interval" =~ ^[0-9]+$ ]]; then 
        echo -e "${RED}輸入無效，請輸入純數字。${NC}"
        return
    fi
    
    AGENT_INTERVAL="$new_interval"
    save_config
    echo -e "${GREEN}上報頻率更新為 ${new_interval} 秒！${NC}"
    
    read -p "是否立即重啟 Agent 以應用新設定？(Y/n): " restart_confirm
    if [[ "${restart_confirm,,}" != "n" ]]; then
        restart_agent
    fi
}

update_agent() {
    echo -e "${CYAN}--- 更新 Agent ---${NC}"
    
    if ! [[ -d "$AGENT_DIR" ]]; then 
        echo -e "${RED}錯誤：Agent 尚未安裝。${NC}"
        return
    fi
    
    install_or_update "update"
}

uninstall_agent() {
    echo -e "${CYAN}--- 完整刪除 (解除安裝) ---${NC}"
    
    if ! [[ -d "$AGENT_DIR" ]]; then 
        echo -e "${YELLOW}未找到 Agent 安裝目錄。${NC}"
        return
    fi
    
    echo -e "${RED}警告：此操作將停止 Agent 並刪除所有相關檔案 (${AGENT_DIR})。${NC}"
    echo -e "${RED}此操作不可還原！${NC}"
    
    read -p "您確定要繼續嗎？(y/N): " confirm
    if [[ "${confirm,,}" == "y" ]]; then 
        stop_agent
        rm -rf "$AGENT_DIR"
        echo -e "${GREEN}Komari Agent 已被徹底刪除。${NC}"
    else 
        echo "解除安裝已取消。"
    fi
}

show_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${CYAN}--- Agent 日誌 (按 Ctrl+C 退出) ---${NC}"
        tail -f "$LOG_FILE"
    else 
        echo -e "${RED}日誌檔案不存在。${NC}"
    fi
}

main_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "      Komari Agent 管理腳本 v6"
        if [ "$USE_MIRROR" = true ]; then
            echo -e "        ${CYAN}(鏡像站模式)${NC}"
        else
            echo -e "        ${GREEN}(自動選擇模式)${NC}"
        fi
        echo "=========================================="
        
        # 顯示狀態
        if is_agent_running; then
            local pid=$(get_agent_pid)
            echo -e "      狀態: ${GREEN}執行中 (PID: $pid)${NC}"
        else
            echo -e "      狀態: ${RED}已停止${NC}"
        fi
        
        # 顯示配置資訊
        if [ -f "$CONFIG_FILE" ]; then
            load_config
            echo -e "      間隔: ${AGENT_INTERVAL} 秒"
        fi
        
        echo "------------------------------------------"
        echo " 1. 安裝 Agent (首次使用)"
        echo " 2. 更改 Token"
        echo " 3. 更改上報頻率"
        echo " 4. 重啟 Agent"
        echo " 5. 更新 Agent 到最新版本"
        echo " 6. 完整刪除 (解除安裝)"
        echo "------------------------------------------"
        echo " s. 檢查/啟動 Agent"
        echo " t. 停止 Agent"
        echo " x. 詳細狀態檢查"
        echo " l. 查看日誌"
        echo "------------------------------------------"
        echo " q. 退出腳本"
        echo "=========================================="
        
        read -p "請輸入您的選擇: " choice
        
        case $choice in
            1) install_agent ;;
            2) change_token ;;
            3) change_interval ;;
            4) restart_agent ;;
            5) update_agent ;;
            6) uninstall_agent ;;
            s|S) 
                if is_agent_running; then
                    local pid=$(get_agent_pid)
                    echo -e "${GREEN}Agent 正在執行中 (PID: $pid)。${NC}"
                else
                    echo -e "${YELLOW}Agent 已停止，正在嘗試啟動...${NC}"
                    start_agent
                fi
                ;;
            t|T) stop_agent ;;
            x|X) status_agent ;;
            l|L) show_logs ;;
            q|Q) 
                echo -e "${GREEN}感謝使用 Komari Agent 管理腳本！${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}無效的輸入，請重試。${NC}"
                ;;
        esac
        
        echo
        read -p "按任意鍵返回主選單..."
    done
}

# --- 腳本入口 ---
check_root

# 解析命令行參數
parse_args "$@"

main_menu
