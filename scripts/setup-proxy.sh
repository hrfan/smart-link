#!/bin/bash
# 一键配置使用 DCES 网关 sing-box 代理 (macOS)
# 启用:  bash -c "$(curl -fsSL https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh)"
# 关闭:  bash -c "$(curl -fsSL https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh)" -- --off
# 启用(域名优先,自动降级内网IP):
#   bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh)"
# 换地址: 上述命令末尾加  -- --proxy 192.168.13.229:20001
#
# 同时配「系统代理(浏览器/GUI)」+「环境变量(git/npm/curl/AI CLI)」。
# sing-box 自己分流: 国内/公司内网直连, 境外走出口。mac 端只管把流量丢给 :10808。
#
# ⚠️ 必须用 bash -c "$(curl ...)" 形式, 不要用 curl ... | bash
#    管道会占用 stdin, 导致改系统代理时 sudo 密码提示读不到输入。

set -e

PROXY="192.168.13.229:10808"
OFF=0

while [ $# -gt 0 ]; do
    case "$1" in
        --off|-off|off|--Off|-Off) OFF=1; shift ;;
        --proxy|-proxy) PROXY="$2"; shift 2 ;;
        *) echo "未知参数: $1"; echo "用法: $0 [--off] [--proxy host:port]"; exit 1 ;;
    esac
done

# ============ 平台检查 ============
if [ "$(uname -s)" != "Darwin" ]; then
    echo "❌ 本脚本仅支持 macOS (当前: $(uname -s))"
    echo "   Windows 请用 setup-proxy.ps1"
    exit 1
fi

PROXY_HOST="${PROXY%%:*}"
PROXY_PORT="${PROXY##*:}"

# 环境变量 bypass（逗号分隔，给 curl/git/npm 等用）
NO_PROXY_VAL='localhost,127.0.0.1,192.168.13.229,192.168.*,10.*,*.dcjet.com.cn'
# 系统代理 bypass（空格分隔，给 networksetup 用）
BYPASS_DOMAINS=(localhost 127.0.0.1 "192.168.*" "10.*" "*.dcjet.com.cn" "*.local")

# 写进 shell 配置的标记块（幂等：重跑先删旧块再写）
MARK_BEGIN='# >>> DCES proxy >>>'
MARK_END='# <<< DCES proxy <<<'

case "$(basename "${SHELL:-/bin/zsh}")" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bash_profile" ;;
    fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
    *)    SHELL_RC="$HOME/.profile" ;;
esac
IS_FISH=0
[ "$(basename "${SHELL:-}")" = "fish" ] && IS_FISH=1

# 删掉旧的标记块（幂等，重跑不会堆重复行）
# 标记里只有 # > < 空格和字母，均非 sed BRE 元字符，可直接用
clean_rc() {
    [ -f "$SHELL_RC" ] || return 0
    sed -i.bak "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$SHELL_RC"
    rm -f "$SHELL_RC.bak"
}

# 列出所有「已启用」的网络服务（第 1 行是说明文字，带 * 前缀的是已禁用项）
list_services() {
    networksetup -listallnetworkservices 2>/dev/null \
        | tail -n +2 \
        | grep -v '^\*' || true
}

# networksetup 改代理需要管理员权限
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

# ============ 关闭模式 ============
if [ "$OFF" -eq 1 ]; then
    echo "关闭 DCES 代理..."
    if [ -n "$SUDO" ]; then
        echo "  改系统代理需要管理员密码:"
        sudo -v || { echo "❌ 未获得管理员权限，系统代理没关掉（环境变量仍会清）"; SUDO="SKIP"; }
    fi

    if [ "$SUDO" != "SKIP" ]; then
        while IFS= read -r svc; do
            [ -z "$svc" ] && continue
            $SUDO networksetup -setwebproxystate          "$svc" off 2>/dev/null || true
            $SUDO networksetup -setsecurewebproxystate    "$svc" off 2>/dev/null || true
            $SUDO networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null || true
            echo "  ✓ 已关闭系统代理: $svc"
        done < <(list_services)
    fi

    clean_rc
    unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY 2>/dev/null || true

    echo ""
    echo "============================================"
    echo "已关闭 DCES 代理 (系统代理 + 环境变量都已清)"
    echo "  浏览器立即生效; 命令行工具新开终端生效"
    echo "============================================"
    exit 0
fi

# ============ 启用模式 ============
echo "测试连通性 $PROXY ..."
if ! nc -z -G 5 "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null; then
    echo "❌ 连不上 $PROXY"
    echo "   排查: 1) 是否在公司内网/同网段  2) 服务器 sing-box 是否在跑  3) 防火墙是否放行 :$PROXY_PORT"
    exit 1
fi
echo "✓ 端口可达"

# 1) 系统代理 (浏览器 / GUI)
if [ -n "$SUDO" ]; then
    echo "  改系统代理需要管理员密码:"
    sudo -v
fi
SVC_COUNT=0
while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    $SUDO networksetup -setwebproxy           "$svc" "$PROXY_HOST" "$PROXY_PORT"
    $SUDO networksetup -setsecurewebproxy     "$svc" "$PROXY_HOST" "$PROXY_PORT"
    $SUDO networksetup -setsocksfirewallproxy "$svc" "$PROXY_HOST" "$PROXY_PORT"
    $SUDO networksetup -setproxybypassdomains "$svc" "${BYPASS_DOMAINS[@]}"
    echo "  ✓ $svc"
    SVC_COUNT=$((SVC_COUNT+1))
done < <(list_services)
echo "✓ 系统代理已设 ($SVC_COUNT 个网络服务), bypass: 内网+国内直连"

# 2) 环境变量 (命令行 / 开发工具)
clean_rc
if [ "$IS_FISH" -eq 1 ]; then
    mkdir -p "$(dirname "$SHELL_RC")"
    {
        echo "$MARK_BEGIN"
        echo "set -gx HTTP_PROXY  \"http://$PROXY\""
        echo "set -gx HTTPS_PROXY \"http://$PROXY\""
        echo "set -gx ALL_PROXY   \"socks5://$PROXY\""
        echo "set -gx NO_PROXY    \"$NO_PROXY_VAL\""
        echo "set -gx http_proxy  \"http://$PROXY\""
        echo "set -gx https_proxy \"http://$PROXY\""
        echo "set -gx all_proxy   \"socks5://$PROXY\""
        echo "set -gx no_proxy    \"$NO_PROXY_VAL\""
        echo "$MARK_END"
    } >> "$SHELL_RC"
else
    {
        echo "$MARK_BEGIN"
        echo "export HTTP_PROXY=\"http://$PROXY\""
        echo "export HTTPS_PROXY=\"http://$PROXY\""
        echo "export ALL_PROXY=\"socks5://$PROXY\""
        echo "export NO_PROXY=\"$NO_PROXY_VAL\""
        echo "export http_proxy=\"http://$PROXY\""
        echo "export https_proxy=\"http://$PROXY\""
        echo "export all_proxy=\"socks5://$PROXY\""
        echo "export no_proxy=\"$NO_PROXY_VAL\""
        echo "$MARK_END"
    } >> "$SHELL_RC"
fi
echo "✓ 环境变量已写入 $SHELL_RC (HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/NO_PROXY)"

# 3) 验证翻墙
echo ""
echo "验证翻墙 (经代理访问境外) ..."
CODE=$(curl -s -o /dev/null -w "%{http_code}" -x "http://$PROXY" --max-time 15 https://www.google.com/generate_204 2>/dev/null || echo "000")
case "$CODE" in
    204|200|301|302) echo "✓ 翻墙正常 (google 返回 $CODE)" ;;
    *) echo "⚠️ 翻墙验证未通过 (返回 '$CODE') — 端口通但出海可能有问题, 找管理员看 sing-box 出口" ;;
esac

echo ""
echo "============================================"
echo "DCES 代理已启用: $PROXY"
echo "============================================"
echo "  浏览器: 立即生效"
echo "  命令行工具 (git/npm/curl/AI CLI): 执行 'source $SHELL_RC' 或新开终端生效"
echo ""
echo "关闭代理: 同样命令末尾加  -- --off"
echo "============================================"
