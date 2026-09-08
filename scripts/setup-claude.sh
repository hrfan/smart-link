#!/bin/bash
# Claude Code 接入 AI 网关 (Linux/macOS)
# 本地:  ./setup-claude.sh <api-key> [model]
# 远程:  curl -fsSL <raw-url>/setup-claude.sh | bash -s -- <api-key>
# 远程(域名优先,自动降级内网IP):
#   bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.sh)"

set -e

GATEWAY_URL="https://192.168.13.229:8443/anthropic"
API_KEY=""
EFFORT="max"

# 5 个 alias 槽位全部绑定 GLM-5.3 (2026-09-03 起默认走 GLM-5.3: bifrost v2.0.0 能把 anthropic 入口桥接到 zai 的 openai chat 路径; kimi 改为按人授权, 有权限者可自行把槽位改成 kimi/k3 等)
MODEL="zai/glm-5.3"                        # Default (主对话, 1M context, 含思考)
OPUS_MODEL="zai/glm-5.3"                   # /model 选 "Custom Opus"
SONNET_MODEL="zai/glm-5.3"                 # /model 选 "Custom Sonnet"
HAIKU_MODEL="zai/glm-5.3"                  # /model 选 "Custom Haiku" + 后台任务(标题/compact)
SUBAGENT_MODEL="zai/glm-5.3"               # subagent 后台

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            echo "用法: $0 <api-key>"
            echo ""
            echo "装完 Claude Code 5 个槽位全部 = GLM-5.3 (1M context)"
            exit 0 ;;
        *) API_KEY="$1"; shift ;;
    esac
done

# 按登录 shell 选 rc 文件（先定好，后面要从里面读缓存）
case "$(basename "${SHELL:-/bin/sh}")" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
    *)    SHELL_RC="$HOME/.profile" ;;
esac
touch "$SHELL_RC"

# 获取 API Key：参数 > 环境变量 > shell rc 缓存 > 交互输入
UPDATE_MODE=0
if [ -z "$API_KEY" ] && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    API_KEY="$ANTHROPIC_AUTH_TOKEN"
    UPDATE_MODE=1
fi
if [ -z "$API_KEY" ]; then
    CACHED=$(grep -E 'ANTHROPIC_AUTH_TOKEN' "$SHELL_RC" 2>/dev/null | tail -1 | sed -E 's/^.*ANTHROPIC_AUTH_TOKEN[ =]+"?([^"]*)"?.*$/\1/')
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
[ "$UPDATE_MODE" = "1" ] && echo "🔁 更新模式：复用已有 ANTHROPIC_AUTH_TOKEN (${API_KEY:0:8}...)"

# 清旧 ANTHROPIC_* / CLAUDE_CODE_* 行（只清本脚本管的 8 个，别误伤）
sed -i.bak \
    -e '/ANTHROPIC_BASE_URL/d' \
    -e '/ANTHROPIC_AUTH_TOKEN/d' \
    -e '/ANTHROPIC_MODEL/d' \
    -e '/ANTHROPIC_DEFAULT_OPUS_MODEL/d' \
    -e '/ANTHROPIC_DEFAULT_SONNET_MODEL/d' \
    -e '/ANTHROPIC_DEFAULT_HAIKU_MODEL/d' \
    -e '/CLAUDE_CODE_SUBAGENT_MODEL/d' \
    -e '/CLAUDE_CODE_EFFORT_LEVEL/d' \
    "$SHELL_RC"
rm -f "$SHELL_RC.bak"

# 5 个 alias 槽位 hardcode 不同 model,Claude Code /model 命令可在它们之间切换
if [ "$(basename "$SHELL_RC")" = "config.fish" ]; then
    {
        echo "set -gx ANTHROPIC_BASE_URL              \"$GATEWAY_URL\""
        echo "set -gx ANTHROPIC_AUTH_TOKEN            \"$API_KEY\""
        echo "set -gx ANTHROPIC_MODEL                 \"$MODEL\""
        echo "set -gx ANTHROPIC_DEFAULT_OPUS_MODEL    \"$OPUS_MODEL\""
        echo "set -gx ANTHROPIC_DEFAULT_SONNET_MODEL  \"$SONNET_MODEL\""
        echo "set -gx ANTHROPIC_DEFAULT_HAIKU_MODEL   \"$HAIKU_MODEL\""
        echo "set -gx CLAUDE_CODE_SUBAGENT_MODEL      \"$SUBAGENT_MODEL\""
        echo "set -gx CLAUDE_CODE_EFFORT_LEVEL        \"$EFFORT\""
    } >> "$SHELL_RC"
else
    {
        echo "export ANTHROPIC_BASE_URL=\"$GATEWAY_URL\""
        echo "export ANTHROPIC_AUTH_TOKEN=\"$API_KEY\""
        echo "export ANTHROPIC_MODEL=\"$MODEL\""
        echo "export ANTHROPIC_DEFAULT_OPUS_MODEL=\"$OPUS_MODEL\""
        echo "export ANTHROPIC_DEFAULT_SONNET_MODEL=\"$SONNET_MODEL\""
        echo "export ANTHROPIC_DEFAULT_HAIKU_MODEL=\"$HAIKU_MODEL\""
        echo "export CLAUDE_CODE_SUBAGENT_MODEL=\"$SUBAGENT_MODEL\""
        echo "export CLAUDE_CODE_EFFORT_LEVEL=\"$EFFORT\""
    } >> "$SHELL_RC"
fi
chmod 600 "$SHELL_RC" 2>/dev/null || true

export ANTHROPIC_BASE_URL="$GATEWAY_URL"
export ANTHROPIC_AUTH_TOKEN="$API_KEY"
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$OPUS_MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$SONNET_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$HAIKU_MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$SUBAGENT_MODEL"
export CLAUDE_CODE_EFFORT_LEVEL="$EFFORT"

echo "ANTHROPIC_BASE_URL              = $GATEWAY_URL"
echo "ANTHROPIC_AUTH_TOKEN            = ${API_KEY:0:8}..."
echo "ANTHROPIC_MODEL                 = $MODEL   (Default / 主对话)"
echo "ANTHROPIC_DEFAULT_OPUS_MODEL    = $OPUS_MODEL   (/model Custom Opus)"
echo "ANTHROPIC_DEFAULT_SONNET_MODEL  = $SONNET_MODEL   (/model Custom Sonnet)"
echo "ANTHROPIC_DEFAULT_HAIKU_MODEL   = $HAIKU_MODEL   (/model Custom Haiku / 标题 / compact)"
echo "CLAUDE_CODE_SUBAGENT_MODEL      = $SUBAGENT_MODEL   (subagent 后台)"
echo "CLAUDE_CODE_EFFORT_LEVEL        = $EFFORT"
echo "环境变量已写入: $SHELL_RC"

# 写入 Bifrost 自签 CA + NODE_EXTRA_CA_CERTS
# 网关 :8443 用自签证书,客户端必须信任这把 CA 才能走 HTTPS (绕开公司 DPI body 扫描)
CA_DIR="$HOME/.claude"
CA_FILE="$CA_DIR/bifrost-ca.crt"
mkdir -p "$CA_DIR"
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

sed -i.bak '/NODE_EXTRA_CA_CERTS/d' "$SHELL_RC"
if [ "$(basename "$SHELL_RC")" = "config.fish" ]; then
    echo "set -gx NODE_EXTRA_CA_CERTS \"$CA_FILE\"" >> "$SHELL_RC"
else
    echo "export NODE_EXTRA_CA_CERTS=\"$CA_FILE\"" >> "$SHELL_RC"
fi
rm -f "$SHELL_RC.bak"
chmod 600 "$SHELL_RC" 2>/dev/null || true
export NODE_EXTRA_CA_CERTS="$CA_FILE"
echo "NODE_EXTRA_CA_CERTS = $CA_FILE (让 Claude Code Node/Bun runtime 信任自签 CA)"

command -v claude >/dev/null || echo "⚠️ 未检测到 claude CLI。安装见: https://docs.claude.com/en/docs/claude-code/setup"

echo ""
echo "============================================"
echo "Claude Code 环境变量已配置"
echo "============================================"
echo ""
echo "使用方式:"
echo "  1. source $SHELL_RC  (或关掉终端重开)"
echo "  2. 运行: claude"
echo ""
echo "槽位: 5 个全部 = GLM-5.3 (zai/glm-5.3, 1M context)，/model 选哪个都走 GLM"
echo ""
echo "恢复 Claude 官方 API: 跑 unset-claude.sh (自动清环境变量+CA)，或手动从 $SHELL_RC 删所有 ANTHROPIC_* / CLAUDE_CODE_* 行 + 关掉终端重开"
echo "  curl -fsSL https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.sh | bash"
echo "============================================"
