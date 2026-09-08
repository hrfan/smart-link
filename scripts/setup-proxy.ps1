# 一键配置使用 DCES 网关 sing-box 代理 (Windows)
# 启用:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1)))
# 关闭:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1))) -Off
# 启用(域名优先,自动降级内网IP):
#   & ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 })))
# 换地址: ... )) -Proxy "192.168.13.229:10808"
#
# 同时配「系统代理(浏览器/GUI)」+「环境变量(git/npm/curl/AI CLI)」。
# sing-box 自己分流: 国内/公司内网直连, 境外走出口。Windows 端只管把流量丢给 :10808。

param(
    [string]$Proxy = "192.168.13.229:10808",
    [switch]$Off
)

$reg     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$bypass  = 'localhost;127.*;192.168.*;10.*;*.dcjet.com.cn;<local>'
$noProxy = 'localhost,127.0.0.1,192.168.13.229,192.168.*,10.*,*.dcjet.com.cn'
$envVars = @{
    'HTTP_PROXY'  = "http://$Proxy"
    'HTTPS_PROXY' = "http://$Proxy"
    'ALL_PROXY'   = "socks5://$Proxy"
    'NO_PROXY'    = $noProxy
}

# 让系统代理改动立即生效 (免重开浏览器)
function Refresh-SystemProxy {
    $sig = @'
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
    $w = Add-Type -MemberDefinition $sig -Name WinINet -Namespace pinvoke -PassThru -ErrorAction SilentlyContinue
    if ($w) { $w::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null; $w::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null }
}

# ============ 关闭模式 ============
if ($Off) {
    Set-ItemProperty -Path $reg -Name ProxyEnable -Value 0
    Refresh-SystemProxy
    foreach ($k in $envVars.Keys) {
        [Environment]::SetEnvironmentVariable($k, $null, "User")
        Remove-Item "Env:$k" -ErrorAction SilentlyContinue
    }
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "已关闭 DCES 代理 (系统代理 + 环境变量都已清)" -ForegroundColor Cyan
    Write-Host "  浏览器立即生效; 命令行工具新开终端生效" -ForegroundColor DarkGray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# ============ 启用模式 ============
$h = $Proxy.Split(':')[0]; $p = $Proxy.Split(':')[1]

Write-Host "测试连通性 $Proxy ..." -ForegroundColor Yellow
$ok = (Test-NetConnection -ComputerName $h -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue)
if (-not $ok) {
    Write-Host "❌ 连不上 $Proxy" -ForegroundColor Red
    Write-Host "   排查: 1) 是否在公司内网/同网段  2) 服务器 sing-box 是否在跑  3) 防火墙是否放行 :$p" -ForegroundColor DarkGray
    return
}
Write-Host "✓ 端口可达" -ForegroundColor Green

# 1) 系统代理 (浏览器 / GUI)
Set-ItemProperty -Path $reg -Name ProxyServer   -Value $Proxy
Set-ItemProperty -Path $reg -Name ProxyOverride -Value $bypass
Set-ItemProperty -Path $reg -Name ProxyEnable   -Value 1
Refresh-SystemProxy
Write-Host "✓ 系统代理已设 (浏览器/GUI), bypass: 内网+国内直连" -ForegroundColor Green

# 2) 环境变量 (命令行 / 开发工具)
foreach ($k in $envVars.Keys) {
    [Environment]::SetEnvironmentVariable($k, $envVars[$k], "User")
    Set-Item -Path "env:$k" -Value $envVars[$k]
}
Write-Host "✓ 环境变量已设 (HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/NO_PROXY)" -ForegroundColor Green

# 3) 验证翻墙
Write-Host ""
Write-Host "验证翻墙 (经代理访问境外) ..." -ForegroundColor Yellow
$code = (curl.exe -s -o NUL -w "%{http_code}" -x "http://$Proxy" --max-time 15 https://www.google.com/generate_204 2>$null)
if ($code -match '^(204|200|301|302)$') {
    Write-Host "✓ 翻墙正常 (google 返回 $code)" -ForegroundColor Green
} else {
    Write-Host "⚠️ 翻墙验证未通过 (返回 '$code') — 端口通但出海可能有问题, 找管理员看 sing-box 出口" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "DCES 代理已启用: $Proxy" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  浏览器: 立即生效" -ForegroundColor Yellow
Write-Host "  命令行工具 (git/npm/curl/AI CLI): 新开终端生效" -ForegroundColor Yellow
Write-Host ""
Write-Host "关闭代理: 同样命令加 -Off" -ForegroundColor DarkGray
Write-Host "============================================" -ForegroundColor Cyan
