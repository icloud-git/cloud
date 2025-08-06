#!/bin/bash

#===============================================================================================
# Komari Agent 非官方管理腳本 (優化版 v8 - systemd 支持版)
#
# 作者: Your Name/Community (可以替換)
# 日期: 2025-08-06
#
# v8 更新日誌:
#   - 【新增】完整 systemd 服務支持，開機自啟動
#   - 【新增】智能服務管理，自動選擇最佳管理方式
#   - 【新增】綜合狀態監控，同時支持傳統和 systemd 方式
#   - 【優化】增強故障恢復能力，自動重啟崩潰服務
#
# v7 更新日誌:
#   - 【修復】修正因上游 Release 檔案命名變更導致的下載失敗問題 (komari-agent- -> komari-)。
#   - 【優化】增強進程查找與停止的準確性，鎖定安裝目錄，徹底解決多 PID 問題。
#   - 【優化】改善版本號處理邏輯，以兼容 "1.0.3-fix1" 這類格式。
#
# 優化重點 (v6):
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
    echo "Komari Agent 管理腳本 v8"
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

# --- systemd 服務相關變量 ---
SERVICE_NAME="komari-agent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

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

# 獲取 Agent PID (v7 優化版)
get_agent_pid() {
    local pid=""
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        # 再次確認 PID 文件中的進程是否還在運行且屬於 Agent
        if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1 && grep -q -a "$AGENT_DIR" "/proc/$pid/cmdline" 2>/dev/null; then
            echo "$pid"
            return 0
        else
            # PID 無效，刪除舊文件
            rm -f "$PID_FILE"
        fi
    fi
    
    # 如果 PID 文件無效，嘗試更精確地查找運行中的進程
    # 【v7 修復】查找命令列中包含 Agent 安裝路徑的進程，更精準
    local running_pid=$(pgrep -f "${AGENT_DIR}/${AGENT_EXEC_NAME}")
    if [ -n "$running_pid" ]; then
        # 如果找到多個，通常取第一個即可，stop_agent 會處理全部
        running_pid=$(echo "$running_pid" | head -n 1)
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

# 檢查是否支援 systemd
check_systemd_support() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return 1
    fi
    
    if ! systemctl --version >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# 創建 systemd 服務文件
create_systemd_service() {
    echo -e "${YELLOW}正在創建 systemd 服務...${NC}"
    
    if ! check_systemd_support; then
        echo -e "${RED}錯誤：此系統不支援 systemd${NC}"
        return 1
    fi
    
    load_config
    if [[ -z "$AGENT_TOKEN" ]]; then 
        echo -e "${RED}錯誤：Token 尚未設定，無法創建服務。請先安裝 Agent。${NC}"; 
        return 1; 
    fi
    
    local agent_executable=$(find "$AGENT_DIR" -type f -name "${AGENT_EXEC_NAME}-*" 2>/dev/null | head -1)
    if ! [[ -x "$agent_executable" ]]; then 
        echo -e "${RED}錯誤：找不到 Agent 執行檔。請先安裝 Agent。${NC}"; 
        return 1; 
    fi
    
    # 創建服務文件內容
    local service_content="[Unit]
Description=Komari Agent
Documentation=https://github.com/komari-monitor/komari-agent
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=30
StartLimitBurst=3

[Service]
Type=simple
User=${USER}
Group=$(id -gn)
WorkingDirectory=${AGENT_DIR}
ExecStart=${agent_executable} -e ${AGENT_ENDPOINT} -t ${AGENT_TOKEN} --disable-web-ssh --interval ${AGENT_INTERVAL}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
TimeoutStopSec=30
KillMode=mixed
StandardOutput=journal
StandardError=journal
SyslogIdentifier=komari-agent

# 環境變量
Environment=HOME=${HOME}
Environment=USER=${USER}

# 安全設定
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${AGENT_DIR}
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
SecureBits=keep-caps

[Install]
WantedBy=multi-user.target"

    # 寫入服務文件（需要 sudo）
    echo "$service_content" | sudo tee "$SERVICE_FILE" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}systemd 服務文件已創建：${SERVICE_FILE}${NC}"
        
        # 重載 systemd 並啟用服務
        echo -e "${YELLOW}正在重載 systemd 配置...${NC}"
        sudo systemctl daemon-reload
        
        echo -e "${YELLOW}正在啟用服務（開機自啟）...${NC}"
        sudo systemctl enable "$SERVICE_NAME"
        
        echo -e "${GREEN}✓ 服務已啟用，將在開機時自動啟動${NC}"
        echo -e "${CYAN}服務文件位置：${SERVICE_FILE}${NC}"
        return 0
    else
        echo -e "${RED}創建服務文件失敗！請檢查 sudo 權限。${NC}"
        return 1
    fi
}

# 更新 systemd 服務配置
update_systemd_service() {
    echo -e "${YELLOW}正在更新 systemd 服務配置...${NC}"
    
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "${YELLOW}服務文件不存在，正在創建...${NC}"
        create_systemd_service
        return $?
    fi
    
    # 停止服務
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null
    
    # 重新創建服務文件
    create_systemd_service
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}服務配置已更新${NC}"
        read -p "是否立即啟動服務？(Y/n): " start_confirm
        if [[ "${start_confirm,,}" != "n" ]]; then
            start_systemd_service
        fi
    fi
}

# 移除 systemd 服務
remove_systemd_service() {
    echo -e "${YELLOW}正在移除 systemd 服務...${NC}"
    
    if ! check_systemd_support; then
        echo -e "${RED}錯誤：此系統不支援 systemd${NC}"
        return 1
    fi
    
    # 停止並禁用服務
    echo -e "${YELLOW}正在停止服務...${NC}"
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null
    
    echo -e "${YELLOW}正在禁用服務...${NC}"
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    # 移除服務文件
    if [[ -f "$SERVICE_FILE" ]]; then
        sudo rm -f "$SERVICE_FILE"
        sudo systemctl daemon-reload
        sudo systemctl reset-failed "$SERVICE_NAME" 2>/dev/null
        echo -e "${GREEN}✓ systemd 服務已完全移除${NC}"
    else
        echo -e "${YELLOW}服務文件不存在${NC}"
    fi
}

# 傳統方式停止 Agent
stop_agent() {
    echo -e "${YELLOW}正在停止 Agent (傳統方式)...${NC}"
    
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
    
    # 【v7 修復】使用更精確的 pkill 模式，清理任何殘留的、從安裝目錄啟動的進程
    if pgrep -f "${AGENT_DIR}/${AGENT_EXEC_NAME}" > /dev/null; then
        echo -e "${YELLOW}正在清理殘留的 Agent 行程...${NC}"
        pkill -9 -f "${AGENT_DIR}/${AGENT_EXEC_NAME}"
        was_running=true
    fi
    
    rm -f "$PID_FILE"
    
    if $was_running; then
        echo -e "${GREEN}Agent 已成功停止。${NC}"
    else
        echo -e "${BLUE}Agent 並未在執行中。${NC}"
    fi
}

# 傳統方式啟動 Agent
start_agent() {
    echo -e "${YELLOW}正在啟動 Agent (傳統方式)...${NC}"
    
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
        echo -e "${RED}錯誤：找不到 Agent 執行檔或沒有執行權限。${NC}"; 
        return; 
    fi
    
    local cmd="${agent_executable} -e ${AGENT_ENDPOINT} -t ${AGENT_TOKEN} --disable-web-ssh --interval ${AGENT_INTERVAL}"
    echo -e "${CYAN}執行命令: nohup ${cmd}${NC}"
    
    # 添加更詳細的啟動日誌
    echo "=========================================" >> "$LOG_FILE"
    echo "Agent 啟動於 $(date)" >> "$LOG_FILE"
    echo "執行命令: $cmd" >> "$LOG_FILE"
    echo "PID: 即將獲取" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    # 使用更可靠的後台啟動方式
    nohup $cmd >> "$LOG_FILE" 2>&1 &
    local new_pid=$!
    
    # 記錄 PID 到日誌
    echo "獲取到 PID: $new_pid" >> "$LOG_FILE"
    
    # 確保 PID 有效
    if [[ -n "$new_pid" && "$new_pid" =~ ^[0-9]+$ ]]; then
        echo $new_pid > "$PID_FILE"
        
        sleep 3 # 等待進程穩定
        
        # 檢查 PID 是否有效
        if ps -p "$new_pid" > /dev/null 2>&1; then
            echo -e "${GREEN}Agent 啟動成功 (PID: $new_pid)。${NC}"
            echo -e "${CYAN}正在顯示啟動日誌...${NC}"
            echo
            sleep 1
            echo -e "${CYAN}--- 最近日誌 ---${NC}"
            tail -20 "$LOG_FILE" 2>/dev/null || echo "無法讀取日誌"
            echo
            echo -e "${CYAN}提示：使用選項 'l' 查看完整即時日誌${NC}"
        else
            echo -e "${RED}Agent 啟動失敗！進程未能正常啟動。${NC}"
            echo -e "${CYAN}日誌內容：${NC}"
            tail -30 "$LOG_FILE"
            rm -f "$PID_FILE"
        fi
    else
        echo -e "${RED}Agent 啟動失敗！無法獲取有效的進程 ID。${NC}"
        echo -e "${CYAN}日誌內容：${NC}"
        tail -30 "$LOG_FILE"
    fi
}

# systemd 方式啟動服務
start_systemd_service() {
    echo -e "${YELLOW}正在通過 systemd 啟動 Agent...${NC}"
    
    if ! check_systemd_support; then
        echo -e "${YELLOW}系統不支援 systemd，fallback 到傳統啟動方式...${NC}"
        start_agent
        return
    fi
    
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "${YELLOW}服務文件不存在，正在創建...${NC}"
        if ! create_systemd_service; then
            echo -e "${YELLOW}創建失敗，fallback 到傳統啟動方式...${NC}"
            start_agent
            return
        fi
    fi
    
    # 先停止傳統方式啟動的進程
    if is_agent_running; then
        echo -e "${YELLOW}檢測到傳統方式啟動的進程，正在停止...${NC}"
        stop_agent
        sleep 2
    fi
    
    echo -e "${YELLOW}正在啟動 systemd 服務...${NC}"
    sudo systemctl start "$SERVICE_NAME"
    sleep 3
    
    # 檢查服務狀態
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ Agent 服務啟動成功${NC}"
        echo
        echo -e "${CYAN}服務狀態：${NC}"
        sudo systemctl status "$SERVICE_NAME" --no-pager -l --lines=5
    else
        echo -e "${RED}✗ Agent 服務啟動失敗${NC}"
        echo
        echo -e "${CYAN}錯誤日誌：${NC}"
        sudo journalctl -u "$SERVICE_NAME" --no-pager -l -n 10
        echo
        echo -e "${YELLOW}嘗試 fallback 到傳統啟動方式...${NC}"
        start_agent
    fi
}

# systemd 方式停止服務
stop_systemd_service() {
    echo -e "${YELLOW}正在通過 systemd 停止 Agent...${NC}"
    
    if ! check_systemd_support; then
        echo -e "${YELLOW}系統不支援 systemd，fallback 到傳統停止方式...${NC}"
        stop_agent
        return
    fi
    
    local was_running=false
    
    # 停止 systemd 服務
    if [[ -f "$SERVICE_FILE" ]] && sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        sudo systemctl stop "$SERVICE_NAME"
        was_running=true
    fi
    
    # 同時停止傳統方式啟動的進程
    if is_agent_running; then
        echo -e "${YELLOW}同時停止傳統方式啟動的進程...${NC}"
        stop_agent
        was_running=true
    fi
    
    if $was_running; then
        echo -e "${GREEN}✓ Agent 服務已停止${NC}"
    else
        echo -e "${BLUE}Agent 服務並未在執行中${NC}"
    fi
}

# systemd 方式重啟服務
restart_systemd_service() {
    echo -e "${PURPLE}--- 重啟 Agent (systemd) ---${NC}"
    
    if ! check_systemd_support; then
        restart_agent
        return
    fi
    
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "${YELLOW}服務文件不存在，使用傳統方式重啟...${NC}"
        restart_agent
        return
    fi
    
    # 先停止所有相關進程
    stop_systemd_service
    sleep 2
    
    # 重啟 systemd 服務
    echo -e "${YELLOW}正在重啟 systemd 服務...${NC}"
    sudo systemctl restart "$SERVICE_NAME"
    sleep 3
    
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ Agent 服務重啟成功${NC}"
        echo
        sudo systemctl status "$SERVICE_NAME" --no-pager -l --lines=3
    else
        echo -e "${RED}✗ Agent 服務重啟失敗${NC}"
        sudo journalctl -u "$SERVICE_NAME" --no-pager -l -n 10
    fi
}

# 傳統方式重啟
restart_agent() {
    echo -e "${PURPLE}--- 重啟 Agent (傳統) ---${NC}"
    stop_agent
    sleep 2
    start_agent
}

# 傳統狀態檢查
status_agent() {
    echo -e "${CYAN}--- Agent 狀態檢查 (傳統) ---${NC}"
    
    if is_agent_running; then
        local pid=$(get_agent_pid)
        echo -e "狀態: ${GREEN}執行中${NC}"
        echo -e "PID: ${pid}"
        
        if command -v ps >/dev/null 2>&1; then
            echo -e "進程資訊:"
            ps -p "$pid" -o pid,ppid,etime,pcpu,pmem,cmd --no-headers 2>/dev/null || echo "無法獲取詳細資訊"
        fi
        
        if [ -f "$LOG_FILE" ]; then
            local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)
            echo -e "日誌大小: ${log_size} bytes"
        fi
    else
        echo -e "狀態: ${RED}已停止${NC}"
        if [ -f "$CONFIG_FILE" ]; then
            load_config
            echo -e "Token: ${AGENT_TOKEN:0:8}...****"
            echo -e "上報間隔: ${AGENT_INTERVAL} 秒"
        else
            echo -e "${YELLOW}尚未配置${NC}"
        fi
    fi
}

# 綜合狀態檢查（同時檢查 systemd 和傳統方式）
status_comprehensive() {
    echo -e "${CYAN}--- Agent 綜合狀態檢查 ---${NC}"
    
    local systemd_available=false
    local systemd_running=false
    local traditional_running=false
    
    # 檢查 systemd 狀態
    if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
        systemd_available=true
        echo -e "${CYAN}systemd 服務狀態：${NC}"
        
        if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
            systemd_running=true
            echo -e "  狀態: ${GREEN}執行中${NC}"
        else
            echo -e "  狀態: ${RED}已停止${NC}"
        fi
        
        echo -e "  開機自啟: $(sudo systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo "disabled")"
        echo -e "  服務文件: ${SERVICE_FILE}"
        echo
        
        sudo systemctl status "$SERVICE_NAME" --no-pager -l --lines=5 2>/dev/null
        echo
    else
        echo -e "${YELLOW}systemd 服務未配置${NC}"
        echo
    fi
    
    # 檢查傳統進程狀態
    echo -e "${CYAN}傳統進程狀態：${NC}"
    if is_agent_running; then
        traditional_running=true
        local pid=$(get_agent_pid)
        echo -e "  狀態: ${GREEN}執行中${NC}"
        echo -e "  PID: ${pid}"
        
        if command -v ps >/dev/null 2>&1; then
            echo -e "  進程資訊:"
            ps -p "$pid" -o pid,ppid,etime,pcpu,pmem,cmd --no-headers 2>/dev/null || echo "    無法獲取詳細資訊"
        fi
    else
        echo -e "  狀態: ${RED}已停止${NC}"
    fi
    
    # 配置資訊
    echo
    echo -e "${CYAN}配置資訊：${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        load_config
        echo -e "  Token: ${AGENT_TOKEN:0:8}...****"
        echo -e "  上報間隔: ${AGENT_INTERVAL} 秒"
        echo -e "  配置文件: ${CONFIG_FILE}"
    else
        echo -e "  ${YELLOW}尚未配置${NC}"
    fi
    
    # 日誌資訊
    echo
    echo -e "${CYAN}日誌資訊：${NC}"
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)
        echo -e "  傳統日誌: ${LOG_FILE} (${log_size} bytes)"
    fi
    
    if $systemd_available; then
        echo -e "  systemd 日誌: journalctl -u $SERVICE_NAME"
    fi
    
    # 總結和建議
    echo
    echo -e "${CYAN}狀態總結：${NC}"
    if $systemd_running && $traditional_running; then
        echo -e "  ${YELLOW}⚠️  同時檢測到 systemd 和傳統進程在運行，建議停止傳統進程${NC}"
    elif $systemd_running; then
        echo -e "  ${GREEN}✓ systemd 服務正常運行${NC}"
    elif $traditional_running; then
        echo -e "  ${GREEN}✓ 傳統進程正常運行${NC}"
        if $systemd_available; then
            echo -e "  ${CYAN}💡 建議遷移到 systemd 服務管理${NC}"
        fi
    else
        echo -e "  ${RED}✗ 沒有檢測到運行中的 Agent${NC}"
    fi
}

# 智能服務管理（自動選擇 systemd 或傳統方式）
smart_start() {
    if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
        start_systemd_service
    else
        start_agent
    fi
}

smart_stop() {
    if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
        stop_systemd_service
    else
        stop_agent
    fi
}

smart_restart() {
    if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
        restart_systemd_service
    else
        restart_agent
    fi
}

install_or_update() {
    local is_update=${1:-"install"}
    
    if [[ "$is_update" == "update" ]]; then 
        local installed_version_file=$(find "$AGENT_DIR" -type f -name "${AGENT_EXEC_NAME}-*" 2>/dev/null | head -1)
        local latest_version_check=$(get_latest_version)
        if [[ $? -ne 0 ]]; then return; fi
        
        local latest_short_version_check=$(echo "${latest_version_check}" | sed -e 's/\.//g' -e 's/-//g')
        if [[ "$installed_version_file" == *"$latest_short_version_check"* ]]; then 
            echo -e "${GREEN}您已在使用最新版本 (${latest_version_check})。${NC}"; 
            return; 
        fi
        echo -e "${YELLOW}發現新版本 ${latest_version_check}！準備更新...${NC}"
    fi
    
    local version=$(get_latest_version)
    if [[ $? -ne 0 ]]; then return; fi
    
    local arch=$(detect_arch)
    # 【v7 修復】優化版本號處理，移除點和連字符，例如 "1.0.3-fix1" -> "103fix1"
    local short_version=$(echo "${version}" | sed -e 's/\.//g' -e 's/-//g')
    local filename="${AGENT_EXEC_NAME}-${short_version}"

    # 【v7 修復】修正下載 URL，移除版本號前的 "v" 前綴
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/komari-agent-${arch}"
    local mirror_url="https://github.moeyy.xyz/https://github.com/${GITHUB_REPO}/releases/download/${version}/komari-agent-${arch}"

    echo "系統架構: ${arch}"
    echo "目標檔案: ${AGENT_DIR}/${filename}"
    echo "下載 URL: ${download_url}"
    
    mkdir -p "$AGENT_DIR"
    echo -e "${YELLOW}正在下載 Agent...${NC}"
    
    if [ "$USE_MIRROR" = true ]; then
        echo -e "${CYAN}使用鏡像站下載...${NC}"
        if ! curl -L --connect-timeout 15 --max-time 120 --progress-bar -o "${AGENT_DIR}/agent.tmp" "$mirror_url"; then
            echo -e "${RED}鏡像站下載失敗！${NC}"; rm -f "${AGENT_DIR}/agent.tmp"; return 1;
        fi
    else
        echo "嘗試從 GitHub 下載..."
        if ! curl -L --connect-timeout 15 --max-time 120 --progress-bar -o "${AGENT_DIR}/agent.tmp" "$download_url"; then
            echo -e "${YELLOW}GitHub 下載失敗，自動切換到鏡像站...${NC}"
            if ! curl -L --connect-timeout 15 --max-time 120 --progress-bar -o "${AGENT_DIR}/agent.tmp" "$mirror_url"; then
                echo -e "${RED}所有下載源均失敗！${NC}"; rm -f "${AGENT_DIR}/agent.tmp"; return 1;
            fi
        fi
    fi
    
    local file_size=$(stat -c%s "${AGENT_DIR}/agent.tmp" 2>/dev/null || stat -f%z "${AGENT_DIR}/agent.tmp")
    if [[ "$file_size" -lt 1000000 ]]; then 
        echo -e "${RED}下載失敗：檔案大小異常 (${file_size} bytes)。可能下載到了錯誤頁面。${NC}"
        rm -f "${AGENT_DIR}/agent.tmp"
        return 1
    fi
    
    echo -e "${GREEN}下載成功 (檔案大小: ${file_size} bytes)。${NC}"
    
    # 停止所有相關服務
    smart_stop
    
    find "$AGENT_DIR" -type f -name "${AGENT_EXEC_NAME}-*" -exec rm {} \;
    
    mv "${AGENT_DIR}/agent.tmp" "${AGENT_DIR}/${filename}"
    chmod +x "${AGENT_DIR}/${filename}"
    
    echo -e "${GREEN}Agent 已成功安裝/更新到版本 ${version}！${NC}"
    
    if [[ "$is_update" == "install" ]]; then
        smart_start
    else
        read -p "是否立即啟動更新後的 Agent？(Y/n): " start_confirm
        if [[ "${start_confirm,,}" != "n" ]]; then
            # 更新後需要更新 systemd 服務
            if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
                echo -e "${YELLOW}檢測到 systemd 服務，正在更新配置...${NC}"
                update_systemd_service
            else
                smart_start
            fi
        fi
    fi
}

install_agent() {
    echo -e "${CYAN}--- 安裝 Komari Agent ---${NC}"
    
    if [[ -d "$AGENT_DIR" ]]; then 
        echo -e "${YELLOW}偵測到已存在的安裝目錄，將覆蓋設定。${NC}"
    fi
    
    read -p "請輸入您的 Agent Token: " user_token
    if [[ -z "$user_token" ]]; then echo -e "${RED}Token 不可為空！${NC}"; return; fi
    
    read -p "請輸入上報間隔 (秒，預設 ${DEFAULT_INTERVAL}): " user_interval
    if [[ -z "$user_interval" ]]; then user_interval="$DEFAULT_INTERVAL";
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
    if ! [[ -f "$CONFIG_FILE" ]]; then echo -e "${RED}錯誤：Agent 尚未安裝。${NC}"; return; fi
    load_config
    echo "目前 Token: ${AGENT_TOKEN:0:8}...****"
    read -p "請輸入新的 Agent Token: " new_token
    if [[ -z "$new_token" ]]; then echo -e "${RED}Token 不可為空！${NC}"; return; fi
    AGENT_TOKEN="$new_token"
    save_config
    echo -e "${GREEN}Token 更新成功！${NC}"
    
    # Token 更改後需要更新 systemd 服務
    if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
        echo -e "${YELLOW}檢測到 systemd 服務，正在更新配置...${NC}"
        update_systemd_service
    else
        read -p "是否立即重啟 Agent 以應用新設定？(Y/n): " restart_confirm
        if [[ "${restart_confirm,,}" != "n" ]]; then smart_restart; fi
    fi
}

change_interval() {
    echo -e "${CYAN}--- 更改上報頻率 ---${NC}"
    if ! [[ -f "$CONFIG_FILE" ]]; then echo -e "${RED}錯誤：Agent 尚未安裝。${NC}"; return; fi
    load_config
    echo "目前上報頻率: ${AGENT_INTERVAL} 秒"
    read -p "請輸入新的上報頻率 (秒): " new_interval
    if ! [[ "$new_interval" =~ ^[0-9]+$ ]]; then echo -e "${RED}輸入無效，請輸入純數字。${NC}"; return; fi
    AGENT_INTERVAL="$new_interval"
    save_config
    echo -e "${GREEN}上報頻率更新為 ${new_interval} 秒！${NC}"
    
    # 間隔更改後需要更新 systemd 服務
    if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
        echo -e "${YELLOW}檢測到 systemd 服務，正在更新配置...${NC}"
        update_systemd_service
    else
        read -p "是否立即重啟 Agent 以應用新設定？(Y/n): " restart_confirm
        if [[ "${restart_confirm,,}" != "n" ]]; then smart_restart; fi
    fi
}

update_agent() {
    echo -e "${CYAN}--- 更新 Agent ---${NC}"
    if ! [[ -d "$AGENT_DIR" ]]; then echo -e "${RED}錯誤：Agent 尚未安裝。${NC}"; return; fi
    install_or_update "update"
}

uninstall_agent() {
    echo -e "${CYAN}--- 完整刪除 (解除安裝) ---${NC}"
    if ! [[ -d "$AGENT_DIR" ]]; then echo -e "${YELLOW}未找到 Agent 安裝目錄。${NC}"; return; fi
    echo -e "${RED}警告：此操作將停止 Agent 並刪除所有相關檔案 (${AGENT_DIR})。${NC}"
    echo -e "${RED}此操作不可還原！${NC}"
    read -p "您確定要繼續嗎？(y/N): " confirm
    if [[ "${confirm,,}" == "y" ]]; then 
        # 完整刪除時也移除 systemd 服務
        if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
            remove_systemd_service
        fi
        smart_stop
        rm -rf "$AGENT_DIR"
        echo -e "${GREEN}Komari Agent 已被徹底刪除。${NC}"
    else 
        echo "解除安裝已取消。"
    fi
}

# 查看傳統日誌
show_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${CYAN}--- Agent 日誌 (按 Ctrl+C 退出) ---${NC}"
        tail -f "$LOG_FILE"
    else 
        echo -e "${RED}日誌檔案不存在。${NC}"
    fi
}

# 查看 systemd 日誌
show_systemd_logs() {
    if ! check_systemd_support; then
        echo -e "${YELLOW}系統不支援 systemd，顯示傳統日誌...${NC}"
        show_logs
        return
    fi
    
    if [[ -f "$SERVICE_FILE" ]]; then
        echo -e "${CYAN}--- Agent systemd 日誌 (按 Ctrl+C 退出) ---${NC}"
        echo -e "${YELLOW}提示：使用 'journalctl -u $SERVICE_NAME' 查看完整日誌${NC}"
        echo
        sudo journalctl -u "$SERVICE_NAME" -f --no-pager
    else
        echo -e "${YELLOW}systemd 服務未配置，顯示傳統日誌...${NC}"
        show_logs
    fi
}

main_menu() {
    while true; do
        clear
        echo "=========================================="
        echo -e "      Komari Agent 管理腳本 ${GREEN}v8${NC}"
        if [ "$USE_MIRROR" = true ]; then echo -e "        ${CYAN}(鏡像站模式)${NC}";
        else echo -e "        ${GREEN}(自動選擇模式)${NC}"; fi
        echo "=========================================="
        
        # 智能狀態顯示
        local systemd_status=""
        local traditional_status=""
        
        if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
            if sudo systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                systemd_status="${GREEN}systemd: 執行中${NC}"
            else
                systemd_status="${RED}systemd: 已停止${NC}"
            fi
        fi
        
        if is_agent_running; then 
            local pid=$(get_agent_pid)
            traditional_status="${GREEN}傳統: 執行中 (PID: $pid)${NC}"
        else 
            traditional_status="${RED}傳統: 已停止${NC}"
        fi
        
        if [[ -n "$systemd_status" && -n "$traditional_status" ]]; then
            echo -e "      狀態: $systemd_status | $traditional_status"
        elif [[ -n "$systemd_status" ]]; then
            echo -e "      狀態: $systemd_status"
        else
            echo -e "      狀態: $traditional_status"
        fi
        
        if [ -f "$CONFIG_FILE" ]; then load_config; echo -e "      間隔: ${AGENT_INTERVAL} 秒"; fi
        
        echo "------------------------------------------"
        echo " 1. 安裝 Agent (首次使用)"
        echo " 2. 更改 Token"
        echo " 3. 更改上報頻率"
        echo " 4. 重啟 Agent (智能選擇)"
        echo " 5. 更新 Agent 到最新版本"
        echo " 6. 完整刪除 (解除安裝)"
        echo "------------------------------------------"
        echo " s. 檢查/啟動 Agent (智能選擇)"
        echo " t. 停止 Agent (智能選擇)"
        echo " x. 綜合狀態檢查"
        echo " l. 查看日誌 (傳統)"
        echo "------------------------------------------"
        if check_systemd_support; then
            echo " [systemd 服務管理]"
            echo " 7. 創建/更新 systemd 服務"
            echo " 8. 移除 systemd 服務"
            echo " 9. 啟動服務 (systemd)"
            echo " 0. 停止服務 (systemd)"
            echo " r. 重啟服務 (systemd)"
            echo " j. 查看日誌 (systemd)"
            echo "------------------------------------------"
        fi
        echo " q. 退出腳本"
        echo "=========================================="
        
        read -p "請輸入您的選擇: " choice
        
        case $choice in
            1) install_agent ;;
            2) change_token ;;
            3) change_interval ;;
            4) smart_restart ;;
            5) update_agent ;;
            6) uninstall_agent ;;
            7) create_systemd_service ;;
            8) remove_systemd_service ;;
            9) start_systemd_service ;;
            0) stop_systemd_service ;;
            s|S) 
                if check_systemd_support && [[ -f "$SERVICE_FILE" ]]; then
                    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
                        echo -e "${GREEN}Agent 服務正在執行中 (systemd)。${NC}"
                    else
                        echo -e "${YELLOW}Agent 服務已停止，正在嘗試啟動...${NC}"
                        start_systemd_service
                    fi
                else
                    if is_agent_running; then 
                        echo -e "${GREEN}Agent 正在執行中 (傳統)。${NC}"
                    else 
                        echo -e "${YELLOW}Agent 已停止，正在嘗試啟動...${NC}"
                        start_agent
                    fi
                fi ;;
            t|T) smart_stop ;;
            x|X) status_comprehensive ;;
            l|L) show_logs ;;
            j|J) show_systemd_logs ;;
            r|R) restart_systemd_service ;;
            q|Q) echo -e "${GREEN}感謝使用 Komari Agent 管理腳本！${NC}"; exit 0 ;;
            *) echo -e "${RED}無效的輸入，請重試。${NC}" ;;
        esac
        
        echo
        read -n 1 -s -r -p "按任意鍵返回主選單..."
    done
}

# --- 腳本入口 ---
check_root
parse_args "$@"
main_menu
