# Claude Code 接入 AI 网关 (Windows PowerShell)
# 本地:  .\setup-claude.ps1 -ApiKey "sk-bf-xxx"
# 远程:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.ps1))) -ApiKey "sk-bf-xxx"
# 远程(域名优先,自动降级内网IP):
#   & ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.ps1 }))) -ApiKey "sk-bf-xxx"

param(
    [string]$ApiKey = ""
)

$ErrorActionPreference = 'Stop'
$GatewayUrl = "https://192.168.13.229:8443/anthropic"
$Effort     = "max"

# 5 个 alias 槽位全部绑定 GLM-5.3 (2026-09-03 起默认走 GLM-5.3: bifrost v2.0.0 能把 anthropic 入口桥接到 zai 的 openai chat 路径; kimi 改为按人授权, 有权限者可自行把槽位改成 kimi/k3 等)
$Model         = "zai/glm-5.3"                         # Default (主对话, 1M context, 含思考)
$OpusModel     = "zai/glm-5.3"                         # /model 选 "Custom Opus"
$SonnetModel   = "zai/glm-5.3"                         # /model 选 "Custom Sonnet"
$HaikuModel    = "zai/glm-5.3"                         # /model 选 "Custom Haiku" + 后台任务
$SubagentModel = "zai/glm-5.3"                         # subagent 后台

# 1) 获取 API Key（优先级：-ApiKey 参数 > 当前会话 env > 用户级 env > 交互输入）
$updateMode = $false
if ([string]::IsNullOrWhiteSpace($ApiKey) -and -not [string]::IsNullOrWhiteSpace($env:ANTHROPIC_AUTH_TOKEN)) {
    $ApiKey = $env:ANTHROPIC_AUTH_TOKEN
    $updateMode = $true
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $userKey = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User")
    if (-not [string]::IsNullOrWhiteSpace($userKey)) {
        $ApiKey = $userKey
        $updateMode = $true
    }
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = Read-Host "请输入 DCES_API_KEY"
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "错误: API Key 不能为空" -ForegroundColor Red
    exit 1
}
if ($updateMode) {
    $keyShort = if ($ApiKey.Length -gt 8) { $ApiKey.Substring(0,8) } else { $ApiKey }
    Write-Host "🔁 更新模式：复用已有 ANTHROPIC_AUTH_TOKEN ($keyShort...)" -ForegroundColor Cyan
}

# 2) 设置用户级环境变量 - 5 个 alias 各放不同 model
$vars = @{
    "ANTHROPIC_BASE_URL"             = $GatewayUrl
    "ANTHROPIC_AUTH_TOKEN"           = $ApiKey
    "ANTHROPIC_MODEL"                = $Model
    "ANTHROPIC_DEFAULT_OPUS_MODEL"   = $OpusModel
    "ANTHROPIC_DEFAULT_SONNET_MODEL" = $SonnetModel
    "ANTHROPIC_DEFAULT_HAIKU_MODEL"  = $HaikuModel
    "CLAUDE_CODE_SUBAGENT_MODEL"     = $SubagentModel
    "CLAUDE_CODE_EFFORT_LEVEL"       = $Effort
}
foreach ($k in $vars.Keys) {
    [Environment]::SetEnvironmentVariable($k, $vars[$k], "User")
    Set-Item -Path "env:$k" -Value $vars[$k]
}

foreach ($k in "ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_MODEL","ANTHROPIC_DEFAULT_OPUS_MODEL","ANTHROPIC_DEFAULT_SONNET_MODEL","ANTHROPIC_DEFAULT_HAIKU_MODEL","CLAUDE_CODE_SUBAGENT_MODEL","CLAUDE_CODE_EFFORT_LEVEL") {
    $v = $vars[$k]
    if ($k -eq "ANTHROPIC_AUTH_TOKEN") { $v = "$($ApiKey.Substring(0,8))..." }
    Write-Host ("{0,-32} = {1}" -f $k, $v) -ForegroundColor Green
}

# 3) 写入 Bifrost 自签 CA + NODE_EXTRA_CA_CERTS
# 网关 :8443 用自签证书,客户端必须信任这把 CA 才能走 HTTPS (绕开公司 DPI body 扫描)
$caDir = Join-Path $env:USERPROFILE '.claude'
$caFile = Join-Path $caDir 'bifrost-ca.crt'
if (-not (Test-Path $caDir)) { New-Item -ItemType Directory -Path $caDir -Force | Out-Null }
$caPem = @'
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
'@
[IO.File]::WriteAllText($caFile, $caPem, [Text.UTF8Encoding]::new($false))
Write-Host "已写入 CA 证书: $caFile" -ForegroundColor Green

[Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $caFile, "User")
$env:NODE_EXTRA_CA_CERTS = $caFile
Write-Host "NODE_EXTRA_CA_CERTS = $caFile" -ForegroundColor Green

# 4) NO_PROXY 合并去重 (Bun runtime 不识别 CIDR, 必须明确写 IP/wildcard)
$requiredBypass = @(
    '127.0.0.1', 'localhost', '::1',
    '192.168.13.229',          # bifrost 网关本机,必须直连绕开 sing-box
    '*.dcjet.com.cn',          # 公司内网域名
    '192.168.*', '10.*'        # 公司 LAN + ZeroTier 网段
)
$existingNoProxy = [Environment]::GetEnvironmentVariable("NO_PROXY", "User")
$existingList = @()
if ($existingNoProxy) {
    $existingList = $existingNoProxy -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
$merged = $existingList
foreach ($item in $requiredBypass) {
    if ($merged -notcontains $item) { $merged += $item }
}
$mergedStr = $merged -join ','
[Environment]::SetEnvironmentVariable("NO_PROXY", $mergedStr, "User")
[Environment]::SetEnvironmentVariable("no_proxy", $mergedStr, "User")
$env:NO_PROXY = $mergedStr
$env:no_proxy = $mergedStr
Write-Host "NO_PROXY 已合并 ($($merged.Count) 项, 含 192.168.13.229)" -ForegroundColor Green

# 5) 检查 claude 可执行
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host ""
    Write-Host "⚠️ 未检测到 claude CLI。" -ForegroundColor Yellow
    Write-Host "   安装方法见: https://docs.claude.com/en/docs/claude-code/setup" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Claude Code 环境变量已配置" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "使用方式:" -ForegroundColor Yellow
Write-Host "  1. 关掉当前所有终端 / claude 进程" -ForegroundColor Yellow
Write-Host "  2. 打开新的 PowerShell 窗口" -ForegroundColor Yellow
Write-Host "  3. 运行: claude" -ForegroundColor Yellow
Write-Host ""
Write-Host "槽位: 5 个全部 = GLM-5.3 (zai/glm-5.3, 1M context)" -ForegroundColor Yellow
Write-Host ""
Write-Host "恢复 Claude 官方 API:" -ForegroundColor Yellow
Write-Host "  跑 unset-claude.ps1 (自动清环境变量+CA), 或手动清用户级 ANTHROPIC_* / CLAUDE_CODE_* 后重开终端" -ForegroundColor DarkGray
Write-Host '  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.ps1)))' -ForegroundColor DarkGray
Write-Host "============================================" -ForegroundColor Cyan
