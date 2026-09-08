#!/bin/bash
# 撤销 Claude Code 到 AI 网关的接入，恢复 Anthropic 官方 API (Linux/macOS)
# 本地:  ./unset-claude.sh
# 远程:  curl -fsSL https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.sh | bash
# 远程(域名优先,自动降级内网IP):
#   bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.sh)"
#
# 清掉 setup-claude.sh 写入的全部环境变量 + 网关自签 CA。
# NO_PROXY 不动（那些内网 bypass 条目留着无害）。

set -e

case "$(basename "${SHELL:-/bin/sh}")" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
    *)    SHELL_RC="$HOME/.profile" ;;
esac

if [ ! -f "$SHELL_RC" ]; then
    echo "未找到 $SHELL_RC，没什么可清理的"
    exit 0
fi

echo "从 $SHELL_RC 清除网关相关环境变量..."
# 删 setup-claude.sh 写的 9 个变量（sed 删行，fish 的 set -gx / bash 的 export 都覆盖）
sed -i.bak \
    -e '/ANTHROPIC_BASE_URL/d' \
    -e '/ANTHROPIC_AUTH_TOKEN/d' \
    -e '/ANTHROPIC_MODEL/d' \
    -e '/ANTHROPIC_DEFAULT_OPUS_MODEL/d' \
    -e '/ANTHROPIC_DEFAULT_SONNET_MODEL/d' \
    -e '/ANTHROPIC_DEFAULT_HAIKU_MODEL/d' \
    -e '/CLAUDE_CODE_SUBAGENT_MODEL/d' \
    -e '/CLAUDE_CODE_EFFORT_LEVEL/d' \
    -e '/NODE_EXTRA_CA_CERTS/d' \
    "$SHELL_RC"
rm -f "$SHELL_RC.bak"

# 清当前会话
unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL \
      ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL \
      CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_EFFORT_LEVEL NODE_EXTRA_CA_CERTS 2>/dev/null || true

# 删网关自签 CA（官方 API 用真证书，不需要它）
CA_FILE="$HOME/.claude/bifrost-ca.crt"
if [ -f "$CA_FILE" ]; then
    rm -f "$CA_FILE"
    echo "已删网关自签 CA: $CA_FILE"
fi

echo ""
echo "============================================"
echo "Claude Code 已恢复 Anthropic 官方配置"
echo "============================================"
echo "执行 'source $SHELL_RC' 或重开终端，claude 就用回官方 API"
echo "(前提你有 Anthropic API Key 或 Claude 订阅；登录跑 claude /login)"
echo ""
echo "想重新接回公司网关：重跑 setup-claude.sh 即可"
echo "============================================"
