# OpenCode 一键配置脚本 (Windows PowerShell)
# 本地:  .\setup-opencode.ps1 -ApiKey "sk-bf-xxx"
# 远程:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.ps1))) -ApiKey "sk-bf-xxx"
# 远程(域名优先,自动降级内网IP):
#   & ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.ps1 }))) -ApiKey "sk-bf-xxx"

param(
    [string]$ApiKey = "",
    [string]$TemplatePath = "",
    [string]$TemplateUrl  = ""
)

$ErrorActionPreference = 'Stop'

# 模板默认 URL（和 bash 版保持同步。部署前改成你自己的 raw URL）
# 域名解析失败时自动降级到内网 IP（同一台 GitLab）；$env:OPENCODE_TEMPLATE_URL 显式指定时不降级
$domainTemplateUrl   = "https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/opencode.template.json"
$fallbackTemplateUrl = "https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/opencode.template.json"
$defaultTemplateUrl = if ($env:OPENCODE_TEMPLATE_URL) { $env:OPENCODE_TEMPLATE_URL } else { $domainTemplateUrl }

# 1) 获取 API Key（优先级：-ApiKey 参数 > 当前会话 env > 用户级 env > 交互输入）
$updateMode = $false
if ([string]::IsNullOrWhiteSpace($ApiKey) -and -not [string]::IsNullOrWhiteSpace($env:DCES_API_KEY)) {
    $ApiKey = $env:DCES_API_KEY
    $updateMode = $true
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $userKey = [Environment]::GetEnvironmentVariable("DCES_API_KEY", "User")
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
    Write-Host "🔁 更新模式：复用已有 DCES_API_KEY ($keyShort...)" -ForegroundColor Cyan
}

# 2) 决定模板来源
$resolvedTemplate = ""
$tmpFile = $null

if ($TemplatePath -and (Test-Path $TemplatePath)) {
    $resolvedTemplate = $TemplatePath
} else {
    $localSibling = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'opencode.template.json' } else { "" }
    if ($localSibling -and (Test-Path $localSibling)) {
        $resolvedTemplate = $localSibling
    } else {
        $url = if ($TemplateUrl) { $TemplateUrl } else { $defaultTemplateUrl }
        $tmpFile = [IO.Path]::GetTempFileName()
        Write-Host "本地无模板，从远程下载: $url" -ForegroundColor Yellow
        # ⚠️ 不用 Invoke-WebRequest -OutFile：PS 5.x 在中文系统按 GBK 编码读写会破坏 UTF-8 中文。
        # 用 Invoke-WebRequest 拿 RawContentStream 按字节流写。
        function Get-TemplateBytes([string]$reqUrl, [int]$timeoutSec) {
            $resp = Invoke-WebRequest -Uri $reqUrl -TimeoutSec $timeoutSec -UseBasicParsing
            if ($resp.RawContentStream) {
                return $resp.RawContentStream.ToArray()
            } else {
                $b = $resp.Content
                if ($b -is [string]) { $b = [Text.Encoding]::UTF8.GetBytes($b) }
                return $b
            }
        }
        try {
            $bytes = Get-TemplateBytes $url 5
        } catch {
            if (-not $env:OPENCODE_TEMPLATE_URL) {
                Write-Host "域名解析/连接失败，降级使用内网 IP: $fallbackTemplateUrl" -ForegroundColor Yellow
                try {
                    $bytes = Get-TemplateBytes $fallbackTemplateUrl 15
                } catch {
                    Write-Host "错误: 下载模板失败（域名和内网 IP 均不可用）: $($_.Exception.Message)" -ForegroundColor Red
                    exit 1
                }
            } else {
                Write-Host "错误: 下载模板失败: $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }
        }
        [IO.File]::WriteAllBytes($tmpFile, $bytes)
        $resolvedTemplate = $tmpFile
    }
}

# 3) 配置路径
$configDir  = Join-Path $env:USERPROFILE '.config\opencode'
$configFile = Join-Path $configDir 'opencode.json'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Write-Host "创建目录: $configDir" -ForegroundColor Green
}

# 4) 备份
if (Test-Path $configFile) {
    $backup = "$configFile.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
    Copy-Item $configFile $backup -Force
    Write-Host "已备份旧配置: $backup" -ForegroundColor Yellow
}

# 5) 写入（用 byte 流复制，避免 PS 5.x 按系统代码页二次编码）
[IO.File]::WriteAllBytes($configFile, [IO.File]::ReadAllBytes($resolvedTemplate))
Write-Host "写入配置文件: $configFile" -ForegroundColor Green

# 5.1) 验证 JSON 合法（捕捉 UTF-8 破坏 / 编码错位的早期信号）
try {
    $cfgText = [IO.File]::ReadAllText($configFile, [Text.Encoding]::UTF8)
    [void]($cfgText | ConvertFrom-Json)
} catch {
    Write-Host "错误: 配置文件 JSON 解析失败 — 模板可能在传输/写入时被破坏" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  保留 broken 文件: $configFile" -ForegroundColor Yellow
    exit 1
}

# 6) 环境变量
$Gateway = "https://192.168.13.229:8443"
[Environment]::SetEnvironmentVariable("DCES_API_KEY", $ApiKey, "User")
[Environment]::SetEnvironmentVariable("DCES_GATEWAY_URL", $Gateway, "User")
$env:DCES_API_KEY = $ApiKey
$env:DCES_GATEWAY_URL = $Gateway
Write-Host "环境变量 DCES_API_KEY / DCES_GATEWAY_URL 已写入用户级" -ForegroundColor Green

# 6.0) 写入 Bifrost 自签 CA 证书 + NODE_EXTRA_CA_CERTS
# 网关 :8443 用自签证书,客户端必须信任这把 CA 才能走 HTTPS(绕开公司 DPI body 扫描)
$caFile = Join-Path $configDir 'bifrost-ca.crt'
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
Write-Host "环境变量 NODE_EXTRA_CA_CERTS 已写入 (OpenCode Node/Bun runtime 会信任自签 CA)" -ForegroundColor Green

# 6.1) NO_PROXY: 确保 OpenCode 直连 bifrost (Bun runtime 不识别 CIDR, 必须明确写 IP/wildcard)
# 不直接覆盖用户已有 NO_PROXY，做合并去重
$requiredBypass = @(
    '127.0.0.1', 'localhost', '::1',
    '192.168.13.229',          # bifrost 网关本机，必须直连绕开 sing-box
    '*.dcjet.com.cn',          # 公司内网 (gitea / showdoc / ...)
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
Write-Host "环境变量 NO_PROXY 已合并 ($($merged.Count) 项, 含 192.168.13.229)" -ForegroundColor Green

# 7) 清理临时文件
if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -Force }

$keyShort = if ($ApiKey.Length -gt 8) { $ApiKey.Substring(0, 8) } else { $ApiKey }
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "OpenCode 配置完成" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "配置文件:   $configFile"
Write-Host "API Key:    $keyShort..."
Write-Host ""
Write-Host "生效方式: 关闭并重新打开终端 / OpenCode" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
