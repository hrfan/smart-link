#!/bin/bash
# OpenCode 一键配置脚本 (Linux/macOS)
# 本地:  ./setup-opencode.sh <api-key>
# 远程:  curl -fsSL <raw-url>/setup-opencode.sh | bash -s -- <api-key>
# 远程(域名优先,自动降级内网IP):
#   bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.sh)"

set -e

# 模板位置（按优先级）：
#   1) --template /path/to/opencode.template.json
#   2) 脚本同级目录下的 opencode.template.json
#   3) $OPENCODE_TEMPLATE_URL 指向的远程 URL（显式指定时不做内网IP降级，尊重用户选择）
#   4) 下面这个默认域名 URL；解析失败自动降级到内网 IP（同一台 GitLab）
DOMAIN_TEMPLATE_URL="https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/opencode.template.json"
FALLBACK_TEMPLATE_URL="https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/opencode.template.json"
DEFAULT_TEMPLATE_URL="${OPENCODE_TEMPLATE_URL:-$DOMAIN_TEMPLATE_URL}"

API_KEY=""
TEMPLATE_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --template) TEMPLATE_ARG="$2"; shift 2 ;;
        -h|--help)
            echo "用法: $0 [--template PATH] <api-key>"
            echo "     $0 <api-key>"
            exit 0 ;;
        *) API_KEY="$1"; shift ;;
    esac
done

# 1) 获取 API Key（按优先级：命令行参数 > 环境变量 > shell rc 缓存 > 交互输入）
UPDATE_MODE=0
# 先定位 shell rc 以便读取缓存
case "$(basename "${SHELL:-/bin/sh}")" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
    *)    SHELL_RC="$HOME/.profile" ;;
esac
if [ -z "$API_KEY" ] && [ -n "${DCES_API_KEY:-}" ]; then
    API_KEY="$DCES_API_KEY"
    UPDATE_MODE=1
fi
if [ -z "$API_KEY" ] && [ -f "$SHELL_RC" ]; then
    CACHED=$(grep -E 'DCES_API_KEY' "$SHELL_RC" 2>/dev/null | tail -1 | sed -E 's/^.*DCES_API_KEY[ =]+"?([^"]*)"?.*$/\1/')
    if [ -n "$CACHED" ]; then
        API_KEY="$CACHED"
        UPDATE_MODE=1
    fi
fi
if [ -z "$API_KEY" ]; then
    # curl | bash 下 stdin 是 pipe,但真终端的 /dev/tty 仍可读。先 try open
    if { exec 3</dev/tty; } 2>/dev/null; then
        read -rp "首次安装,请输入 DCES_API_KEY (sk-bf-...): " API_KEY <&3
        exec 3<&-
    fi
fi
if [ -z "$API_KEY" ]; then
    echo "错误: VK 不能为空。无 tty 时请把 VK 作为参数传:" >&2
    echo "  curl ... | bash -s -- sk-bf-你的VK" >&2
    exit 1
fi
[ "$UPDATE_MODE" = "1" ] && echo "🔁 更新模式：复用已有 DCES_API_KEY (${API_KEY:0:8}...)"

# 2) 决定模板来源
RESOLVED_TEMPLATE=""
TMP_TEMPLATE=""
cleanup() { [ -n "$TMP_TEMPLATE" ] && rm -f "$TMP_TEMPLATE"; }
trap cleanup EXIT

if [ -n "$TEMPLATE_ARG" ] && [ -f "$TEMPLATE_ARG" ]; then
    RESOLVED_TEMPLATE="$TEMPLATE_ARG"
elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/opencode.template.json" ]; then
    RESOLVED_TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/opencode.template.json"
else
    TMP_TEMPLATE="$(mktemp)"
    echo "本地无模板，从远程下载: $DEFAULT_TEMPLATE_URL"
    if ! curl -fsSL --connect-timeout 5 --max-time 15 "$DEFAULT_TEMPLATE_URL" -o "$TMP_TEMPLATE" 2>/dev/null; then
        if [ -z "${OPENCODE_TEMPLATE_URL:-}" ]; then
            echo "域名解析/连接失败，降级使用内网 IP: $FALLBACK_TEMPLATE_URL" >&2
            if ! curl -fsSL --max-time 15 "$FALLBACK_TEMPLATE_URL" -o "$TMP_TEMPLATE"; then
                echo "错误: 下载模板失败（域名和内网 IP 均不可用）" >&2
                exit 1
            fi
        else
            echo "错误: 下载模板失败" >&2
            exit 1
        fi
    fi
    RESOLVED_TEMPLATE="$TMP_TEMPLATE"
fi

# 3) 配置路径
CONFIG_DIR="$HOME/.config/opencode"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
mkdir -p "$CONFIG_DIR"

# 4) 备份已有配置
if [ -f "$CONFIG_FILE" ]; then
    BACKUP="$CONFIG_FILE.bak.$(date +%s)"
    cp "$CONFIG_FILE" "$BACKUP"
    echo "已备份旧配置: $BACKUP"
fi

# 5) 写入配置
cp "$RESOLVED_TEMPLATE" "$CONFIG_FILE"
echo "写入配置文件: $CONFIG_FILE"

# 6) 确保 shell rc 存在（$SHELL_RC 已在步骤 1 决定）
touch "$SHELL_RC"

# 7) 清旧 DCES_*、写新行
DCES_GATEWAY_URL="https://192.168.13.229:8443"
sed -i.bak -e '/DCES_API_KEY/d' -e '/DCES_GATEWAY_URL/d' "$SHELL_RC"
if [ "$(basename "$SHELL_RC")" = "config.fish" ]; then
    {
        echo "set -gx DCES_API_KEY \"$API_KEY\""
        echo "set -gx DCES_GATEWAY_URL \"$DCES_GATEWAY_URL\""
    } >> "$SHELL_RC"
else
    {
        echo "export DCES_API_KEY=\"$API_KEY\""
        echo "export DCES_GATEWAY_URL=\"$DCES_GATEWAY_URL\""
    } >> "$SHELL_RC"
fi
rm -f "$SHELL_RC.bak"
chmod 600 "$SHELL_RC" 2>/dev/null || true
echo "环境变量已写入: $SHELL_RC (权限 600)"

export DCES_API_KEY="$API_KEY"
export DCES_GATEWAY_URL="$DCES_GATEWAY_URL"

# 7.1) 写入 Bifrost 自签 CA + NODE_EXTRA_CA_CERTS
# 网关 :8443 用自签证书,客户端必须信任这把 CA 才能走 HTTPS (绕开公司 DPI body 扫描)
CA_FILE="$CONFIG_DIR/bifrost-ca.crt"
cat > "$CA_FILE" <<'EOF'
-----BEGIN CERTIFICATE-----
MIIDHTCCAgWgAwIBAgIURJrgORHCNjDlvcBIYtOuVA4UkeswDQYJKoZIhvcNAQEL
BQAwHjEcMBoGA1UEAwwTQmlmcm9zdC1JbnRlcm5hbC1DQTAeFw0yNjA1MTQwMjI3
MjJaFw0zNjA1MTEwMjI3MjJaMB4xHDAaBgNVBAMME0JpZnJvc3QtSW50ZXJuYWwt
Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC+achJPlCgJ/31lEqy
Gkyoeg7FRXWI0LJxHvi73XoXUlcVHMty6RIx67Wr81boIr8JVsWF2rI7DCAP+q94
/QTUnqJ7OuyqmphQhXhSez5bxmqwZlZ8mjBX3UDCGocZZvu/EqcfRBEcAGr1Jn/I
rF3V6soKFH30/3p9LQ78QcmUn4KYC74AK/TbNiWMuO/7zpswd6Ocuf1H9qLFGnT0
ejZs2pVdpOC4jri5gu/9KZAKLHBc5DDpyhBnZC+WZaEleubUiUxhoYvQvUPs8UNh
FL45dPmxUtM9gtiBq9cdXbpTi2yT3Y4A6oxXCECyzfUHyeltXAAyrCuGXq3FYkgi
Jq37AgMBAAGjUzBRMB0GA1UdDgQWBBSeql7NZA30fEBdNoerxn3lXraTuDAfBgNV
HSMEGDAWgBSeql7NZA30fEBdNoerxn3lXraTuDAPBgNVHRMBAf8EBTADAQH/MA0G
CSqGSIb3DQEBCwUAA4IBAQA5HPYENwJveEvg69aqHfKF8oXA/7WO7SUr1E9+j1vy
u9w+UbFd4sONzT36flC410hl8wjptYBRaRZIAEzVjSv/3bdrFgMzA8AEiI5bcPih
xG8y359zvzASupZvFls9Dt9O+kUDgJHTlW2iLK3SFtf4J48CFkWtCSiHHXIHzrm6
Qg34kZbPCLRZHYRX8ajEXHJlGmpz+GzsrUWkotg53I80FCuJNSr3kweDLCL/rcNw
FfuQ03tgM1yEKtRv7FaIbWNYK3KqR5G2CyTKVz7OAvI/0sV54Pcf+oIkz964mWCe
JRubwPkm/ozmtLfZ5L8QSM5o6uf/BB//kpckQi0Bd04Q
-----END CERTIFICATE-----
EOF
echo "已写入 CA 证书: $CA_FILE"

# 写到 shell rc 让 OpenCode (Node/Bun runtime) 信任自签 CA
sed -i.bak '/NODE_EXTRA_CA_CERTS/d' "$SHELL_RC"
if [ "$(basename "$SHELL_RC")" = "config.fish" ]; then
    echo "set -gx NODE_EXTRA_CA_CERTS \"$CA_FILE\"" >> "$SHELL_RC"
else
    echo "export NODE_EXTRA_CA_CERTS=\"$CA_FILE\"" >> "$SHELL_RC"
fi
rm -f "$SHELL_RC.bak"
chmod 600 "$SHELL_RC" 2>/dev/null || true
export NODE_EXTRA_CA_CERTS="$CA_FILE"
echo "环境变量 NODE_EXTRA_CA_CERTS 已写入 (OpenCode Node/Bun runtime 会信任自签 CA)"

echo ""
echo "============================================"
echo "OpenCode 配置完成"
echo "============================================"
echo "配置文件:   $CONFIG_FILE"
echo "Shell rc:   $SHELL_RC"
echo "API Key:    ${API_KEY:0:8}..."
echo ""
echo "生效方式:  source $SHELL_RC   (或重开终端)"
echo "============================================"
