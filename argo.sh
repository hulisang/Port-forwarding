#!/usr/bin/env bash

# ============================================================
# Argo Tunnel 独立管理脚本 v1.3
# 默认使用 HTTP/2 协议（添加 --protocol http2）
# ============================================================

set -e

# 颜色
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# 路径变量
WORK_DIR="/etc/argo"
SERVICE_FILE=""
CF_BIN="$WORK_DIR/cloudflared"
CONFIG_FILE="$WORK_DIR/config"
TUNNEL_JSON="$WORK_DIR/tunnel.json"
TUNNEL_YML="$WORK_DIR/tunnel.yml"
LOG_FILE="$WORK_DIR/cloudflared.log"
SHORTCUT="/usr/bin/argo"

# 检测系统
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "alpine" ]]; then
            SYSTEM="alpine"
            SERVICE_FILE="/etc/init.d/argo"
        elif command -v systemctl >/dev/null 2>&1; then
            SYSTEM="systemd"
            SERVICE_FILE="/etc/systemd/system/argo.service"
        else
            SYSTEM="unknown"
        fi
    else
        if command -v systemctl >/dev/null 2>&1; then
            SYSTEM="systemd"
            SERVICE_FILE="/etc/systemd/system/argo.service"
        else
            SYSTEM="unknown"
        fi
    fi
}

# root 检查
check_root() {
    [ "$EUID" -ne 0 ] && echo -e "${RED}请使用 root 权限运行${NC}" && exit 1
}

# 架构
get_arch() {
    case $(uname -m) in
        aarch64|arm64) ARCH="arm64" ;;
        x86_64|amd64) ARCH="amd64" ;;
        armv7l) ARCH="arm" ;;
        *) echo -e "${RED}不支持的架构: $(uname -m)${NC}"; exit 1 ;;
    esac
}

# 安装 cloudflared
install_cloudflared() {
    mkdir -p "$WORK_DIR"
    echo -e "${YELLOW}正在下载 cloudflared (linux-$ARCH)...${NC}"
    wget -qO "$CF_BIN" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH"
    chmod +x "$CF_BIN"
    echo -e "${GREEN}cloudflared 安装成功${NC}"
}

# 快捷方式
create_shortcut() {
    local SCRIPT_PATH=$(realpath "$0")
    ln -sf "$SCRIPT_PATH" "$SHORTCUT"
    echo -e "${GREEN}已创建全局快捷方式: $SHORTCUT -> $SCRIPT_PATH${NC}"
}

# 配置读写
read_config() {
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
}

write_config() {
    cat > "$CONFIG_FILE" <<EOF
# Argo Tunnel 配置
TUNNEL_TYPE="$TUNNEL_TYPE"
ARGO_TOKEN="$ARGO_TOKEN"
ARGO_JSON="$ARGO_JSON"
ARGO_DOMAIN="$ARGO_DOMAIN"
LOCAL_SERVICE="$LOCAL_SERVICE"
EOF
}

# 生成服务文件（默认添加 --protocol http2）
generate_service() {
    local CMD=""
    if [ "$TUNNEL_TYPE" = "try" ]; then
        CMD="$CF_BIN tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url $LOCAL_SERVICE"
    elif [ "$TUNNEL_TYPE" = "token" ]; then
        CMD="$CF_BIN tunnel --edge-ip-version auto --protocol http2 run --token $ARGO_TOKEN"
    elif [ "$TUNNEL_TYPE" = "json" ] || [ "$TUNNEL_TYPE" = "api" ]; then
        CMD="$CF_BIN tunnel --edge-ip-version auto --protocol http2 --config $TUNNEL_YML run"
    else
        echo -e "${RED}未知隧道类型${NC}"
        return 1
    fi

    if [ "$SYSTEM" = "systemd" ]; then
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Argo Tunnel (HTTP/2)
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=$CMD
Restart=on-failure
RestartSec=5s
User=root

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    elif [ "$SYSTEM" = "alpine" ]; then
        cat > "$SERVICE_FILE" <<EOF
#!/sbin/openrc-run

name="argo"
description="Cloudflare Tunnel (HTTP/2)"

command="${CF_BIN}"
command_args="${CMD#*$CF_BIN }"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background="yes"
output_log="$LOG_FILE"
error_log="$LOG_FILE"

depend() {
    need net
    after firewall
}
EOF
        chmod +x "$SERVICE_FILE"
    else
        echo -e "${RED}无法生成服务文件：未知初始化系统${NC}"
        return 1
    fi
}

# 服务控制
start_tunnel() {
    if [ "$SYSTEM" = "systemd" ]; then
        systemctl start argo
        systemctl enable argo >/dev/null 2>&1
    elif [ "$SYSTEM" = "alpine" ]; then
        rc-service argo start
        rc-update add argo default >/dev/null 2>&1
    fi
    echo -e "${GREEN}隧道已启动${NC}"
}

stop_tunnel() {
    if [ "$SYSTEM" = "systemd" ]; then
        systemctl stop argo
        systemctl disable argo >/dev/null 2>&1
    elif [ "$SYSTEM" = "alpine" ]; then
        rc-service argo stop
        rc-update del argo default >/dev/null 2>&1
    fi
    echo -e "${GREEN}隧道已停止${NC}"
}

restart_tunnel() {
    if [ "$SYSTEM" = "systemd" ]; then
        systemctl restart argo
    elif [ "$SYSTEM" = "alpine" ]; then
        rc-service argo restart
    fi
    echo -e "${GREEN}隧道已重启${NC}"
}

status_tunnel() {
    if [ "$SYSTEM" = "systemd" ]; then
        systemctl status argo --no-pager
    elif [ "$SYSTEM" = "alpine" ]; then
        rc-service argo status
    else
        ps aux | grep -v grep | grep "$CF_BIN" && echo -e "${GREEN}运行中${NC}" || echo -e "${RED}未运行${NC}"
    fi
}

# 获取域名
get_domain() {
    local PID=$(pgrep -f "$CF_BIN")
    if [ -z "$PID" ]; then
        echo -e "${RED}隧道未运行${NC}"
        return 1
    fi
    local METRICS=$(ss -nltp | awk -v pid="$PID" '$0 ~ "pid="pid"," {split($4,a,":"); print a[length(a)]; exit}')
    if [ -z "$METRICS" ]; then
        echo -e "${RED}无法获取 metrics 端口${NC}"
        return 1
    fi
    local DOMAIN=""
    if [ "$TUNNEL_TYPE" = "try" ]; then
        DOMAIN=$(wget -qO- "http://127.0.0.1:$METRICS/quicktunnel" | grep -o '[a-zA-Z0-9.-]*\.trycloudflare\.com' 2>/dev/null)
    else
        DOMAIN=$(wget -qO- "http://127.0.0.1:$METRICS/config" 2>/dev/null | grep -o '"hostname":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    if [ -n "$DOMAIN" ]; then
        echo -e "${GREEN}隧道域名: $DOMAIN${NC}"
    else
        echo -e "${RED}未能获取域名${NC}"
    fi
}

# 交互安装
interactive_install() {
    echo -e "${YELLOW}===== 安装 Argo 隧道 (HTTP/2) =====${NC}"
    read -p "本地服务地址 (默认 http://localhost:8080): " LOCAL_SERVICE
    LOCAL_SERVICE=${LOCAL_SERVICE:-"http://localhost:8080"}

    echo "请选择隧道类型:"
    echo "1) 临时隧道 (Try)"
    echo "2) Token"
    echo "3) Json 文件"
    echo "4) Cloudflare API"
    read -p "选择 [1-4]: " TYPE_CHOICE

    case $TYPE_CHOICE in
        1) TUNNEL_TYPE="try" ;;
        2)
            TUNNEL_TYPE="token"
            read -p "请输入 Token: " ARGO_TOKEN
            ;;
        3)
            TUNNEL_TYPE="json"
            read -p "请输入 Json 内容 (或文件路径): " JSON_INPUT
            if [ -f "$JSON_INPUT" ]; then
                ARGO_JSON=$(cat "$JSON_INPUT" | tr -d '\n')
            else
                ARGO_JSON="$JSON_INPUT"
            fi
            echo "$ARGO_JSON" > "$TUNNEL_JSON"
            TUNNEL_ID=$(echo "$ARGO_JSON" | grep -o '"TunnelID":"[^"]*"' | cut -d'"' -f4)
            cat > "$TUNNEL_YML" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_JSON

ingress:
  - hostname: $ARGO_DOMAIN
    service: $LOCAL_SERVICE
  - service: http_status:404
EOF
            ;;
        4)
            TUNNEL_TYPE="api"
            read -p "请输入 Cloudflare API Token: " API_TOKEN
            read -p "请输入根域名: " ROOT_DOMAIN
            read -p "请输入子域名: " SUB_DOMAIN
            ARGO_DOMAIN="${SUB_DOMAIN}.${ROOT_DOMAIN}"
            create_tunnel_api "$API_TOKEN" "$ROOT_DOMAIN" "$SUB_DOMAIN" "$LOCAL_SERVICE"
            if [ $? -ne 0 ]; then
                echo -e "${RED}API 创建失败${NC}"
                return 1
            fi
            ;;
        *) echo -e "${RED}无效选择${NC}"; return 1 ;;
    esac

    if [ "$TUNNEL_TYPE" = "json" ] && [ -z "$ARGO_DOMAIN" ]; then
        read -p "请输入隧道域名: " ARGO_DOMAIN
        sed -i "s/^  - hostname:.*/  - hostname: $ARGO_DOMAIN/" "$TUNNEL_YML"
    fi

    write_config
    generate_service
    start_tunnel
    create_shortcut
    echo -e "${GREEN}安装完成${NC}"
    get_domain
}

# API 创建隧道
create_tunnel_api() {
    local API_TOKEN="$1" ROOT_DOMAIN="$2" SUB_DOMAIN="$3" SERVICE_URL="$4"
    local ZONE_RESPONSE=$(wget -qO- --header="Authorization: Bearer $API_TOKEN" \
        --header="Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones?name=$ROOT_DOMAIN")
    if ! echo "$ZONE_RESPONSE" | grep -q '"success":true'; then
        echo -e "${RED}获取 Zone 失败${NC}"
        return 1
    fi
    ZONE_ID=$(echo "$ZONE_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    ACCOUNT_ID=$(echo "$ZONE_RESPONSE" | grep -o '"account":{"id":"[^"]*"' | cut -d'"' -f4)

    local TUNNEL_NAME="$SUB_DOMAIN"
    local TUNNEL_SECRET=$(openssl rand -base64 32)
    local CREATE_RESPONSE=$(wget -qO- --method=POST \
        --header="Authorization: Bearer $API_TOKEN" \
        --header="Content-Type: application/json" \
        --body-data="{\"name\":\"$TUNNEL_NAME\",\"config_src\":\"cloudflare\",\"tunnel_secret\":\"$TUNNEL_SECRET\"}" \
        "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel")
    if ! echo "$CREATE_RESPONSE" | grep -q '"success":true'; then
        echo -e "${RED}创建隧道失败${NC}"
        return 1
    fi
    TUNNEL_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    local CONFIG_PAYLOAD="{\"config\":{\"ingress\":[{\"service\":\"$SERVICE_URL\",\"hostname\":\"$ARGO_DOMAIN\"},{\"service\":\"http_status:404\"}],\"warp-routing\":{\"enabled\":false}}}"
    wget -qO- --method=PUT \
        --header="Authorization: Bearer $API_TOKEN" \
        --header="Content-Type: application/json" \
        --body-data="$CONFIG_PAYLOAD" \
        "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" >/dev/null

    local DNS_PAYLOAD="{\"name\":\"$ARGO_DOMAIN\",\"type\":\"CNAME\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"proxied\":true}"
    wget -qO- --method=POST \
        --header="Authorization: Bearer $API_TOKEN" \
        --header="Content-Type: application/json" \
        --body-data="$DNS_PAYLOAD" \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" >/dev/null

    ARGO_JSON="{\"AccountTag\":\"$ACCOUNT_ID\",\"TunnelSecret\":\"$TUNNEL_SECRET\",\"TunnelID\":\"$TUNNEL_ID\",\"Endpoint\":\"\"}"
    echo "$ARGO_JSON" > "$TUNNEL_JSON"
    cat > "$TUNNEL_YML" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_JSON

ingress:
  - hostname: $ARGO_DOMAIN
    service: $SERVICE_URL
  - service: http_status:404
EOF
    echo -e "${GREEN}API 隧道创建成功${NC}"
    return 0
}

# 卸载
uninstall() {
    stop_tunnel
    rm -f "$SHORTCUT"
    rm -rf "$WORK_DIR"
    if [ "$SYSTEM" = "systemd" ]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    elif [ "$SYSTEM" = "alpine" ]; then
        rm -f "$SERVICE_FILE"
    fi
    echo -e "${GREEN}已卸载 Argo 隧道${NC}"
}

# 更换配置
change_config() {
    echo -e "${YELLOW}当前配置:${NC}"
    read_config
    [ -n "$TUNNEL_TYPE" ] && echo "类型: $TUNNEL_TYPE"
    [ -n "$ARGO_DOMAIN" ] && echo "域名: $ARGO_DOMAIN"
    [ -n "$LOCAL_SERVICE" ] && echo "本地服务: $LOCAL_SERVICE"
    echo ""
    read -p "是否重新配置? (y/n): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        stop_tunnel
        interactive_install
    fi
}

# 帮助
usage() {
    cat <<EOF
用法: argo [选项]    (或直接运行本脚本)

选项:
  -i         安装/重新配置（默认 HTTP/2 协议）
  -s         启动隧道
  -t         停止隧道
  -r         重启隧道
  -c         查看状态
  -d         显示隧道域名
  -u         卸载（删除所有文件和服务）
  -h         显示帮助

安装后即可使用全局命令: argo -s
无参数时进入交互菜单。
EOF
}

# 主菜单
menu() {
    clear
    echo -e "${YELLOW}===== Argo Tunnel 管理 (HTTP/2) =====${NC}"
    echo "1. 安装/配置"
    echo "2. 启动"
    echo "3. 停止"
    echo "4. 重启"
    echo "5. 状态"
    echo "6. 域名"
    echo "7. 更换配置"
    echo "8. 卸载"
    echo "0. 退出"
    read -p "请选择 [0-8]: " choice
    case $choice in
        1) interactive_install ;;
        2) start_tunnel ;;
        3) stop_tunnel ;;
        4) restart_tunnel ;;
        5) status_tunnel ;;
        6) get_domain ;;
        7) change_config ;;
        8) uninstall ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac
    echo ""
    read -p "按回车继续..." dummy
}

# 主入口
main() {
    check_root
    detect_system
    get_arch
    [ ! -f "$CF_BIN" ] && install_cloudflared
    if [ $# -eq 0 ]; then
        menu
    else
        case "$1" in
            -i) interactive_install ;;
            -s) start_tunnel ;;
            -t) stop_tunnel ;;
            -r) restart_tunnel ;;
            -c) status_tunnel ;;
            -d) get_domain ;;
            -u) uninstall ;;
            -h|--help) usage ;;
            *) echo -e "${RED}未知选项: $1${NC}"; usage ;;
        esac
    fi
}

main "$@"
