# OpenCode 本机诊断脚本（Windows PowerShell）
# 用法：复制全部内容贴到 PowerShell 回车，把输出截图发回
# 不会改任何配置，只读取信息

$ErrorActionPreference = 'Continue'
Write-Host "===== OpenCode 本机诊断 =====" -ForegroundColor Cyan
Write-Host "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "用户: $env:USERNAME"
Write-Host "机器: $env:COMPUTERNAME"
Write-Host ""

# === 1) 环境变量 ===
Write-Host "--- 1) 环境变量 DCES_API_KEY ---" -ForegroundColor Yellow
$sessionKey = $env:DCES_API_KEY
$userKey = [Environment]::GetEnvironmentVariable("DCES_API_KEY", "User")
function ShortKey($k) { if ($k) { "$($k.Substring(0,8))...$($k.Substring($k.Length-6))" } else { "<空>" } }
Write-Host "  当前会话 (env):    $(ShortKey $sessionKey)"
Write-Host "  用户级 (持久化):   $(ShortKey $userKey)"
if ($sessionKey -ne $userKey) {
    Write-Host "  ⚠️  当前 session 和用户级不一致 — 可能没重启 PowerShell" -ForegroundColor Red
}

# === 2) 系统代理 ===
Write-Host ""
Write-Host "--- 2) 系统代理（可能干扰内网调用） ---" -ForegroundColor Yellow
$envProxy = @{
    HTTP_PROXY     = $env:HTTP_PROXY
    HTTPS_PROXY    = $env:HTTPS_PROXY
    NO_PROXY       = $env:NO_PROXY
}
$envProxy.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key) = $(if ($_.Value) { $_.Value } else { '<空>' })"
}

# === 3) 配置文件 ===
Write-Host ""
Write-Host "--- 3) opencode.json 配置 ---" -ForegroundColor Yellow
$cfgFile = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
if (Test-Path $cfgFile) {
    $info = Get-Item $cfgFile
    Write-Host "  路径: $cfgFile"
    Write-Host "  大小: $($info.Length) 字节"
    Write-Host "  修改时间: $($info.LastWriteTime)"
    try {
        # opencode.json 是 UTF-8（含中文 name），PowerShell 5.x 默认按系统代码页读
        # 必须显式 -Encoding UTF8 才不会乱码导致 JSON 解析失败
        $raw = [IO.File]::ReadAllText($cfgFile, [Text.Encoding]::UTF8)
        $cfg = $raw | ConvertFrom-Json
        $providers = $cfg.provider.PSObject.Properties.Name -join ', '
        Write-Host "  providers: $providers"
        if ($cfg.provider.'dces-coding') {
            $models = $cfg.provider.'dces-coding'.models.PSObject.Properties.Name -join ', '
            Write-Host "  dces-coding 模型: $models"
            Write-Host "  baseURL: $($cfg.provider.'dces-coding'.options.baseURL)"
        }
    } catch {
        Write-Host "  ❌ JSON 解析失败: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  ❌ 配置文件不存在！" -ForegroundColor Red
}

# === 4) 网关连通性 ===
Write-Host ""
Write-Host "--- 4) 网关 192.168.13.229:8080 连通性 ---" -ForegroundColor Yellow
try {
    $tcp = Test-NetConnection -ComputerName 192.168.13.229 -Port 8080 -WarningAction SilentlyContinue -InformationLevel Quiet
    Write-Host "  TCP 8080: $(if ($tcp) { '✅ 通' } else { '❌ 不通' })"
} catch { Write-Host "  TCP 测试异常: $_" }

$curlExe = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if ($curlExe) {
    # health
    $tmp = [IO.Path]::GetTempFileName()
    $hc = & $curlExe --silent --noproxy '*' --max-time 5 -o $tmp -w '%{http_code}' http://192.168.13.229:8080/health 2>$null
    Write-Host "  /health HTTP: $hc"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    # 真实 messages 调用（HighSpeed 最快；必须带 kimi/ 前缀，裸模型名会触发全 provider 轮询产生假错日志）
    if ($userKey) {
        $tmp = [IO.Path]::GetTempFileName()
        $body = '{"model":"kimi/kimi-for-coding-highspeed","max_tokens":10,"messages":[{"role":"user","content":"OK"}]}'
        $mc = & $curlExe --silent --noproxy '*' --max-time 30 `
            -H "x-api-key: $userKey" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" `
            -X POST -d $body `
            -o $tmp -w '%{http_code}' `
            http://192.168.13.229:8080/anthropic/v1/messages 2>$null
        Write-Host "  /messages HTTP: $mc"
        $resp = Get-Content $tmp -Raw -ErrorAction SilentlyContinue
        if ($resp) {
            $head = if ($resp.Length -gt 200) { $resp.Substring(0, 200) + '...' } else { $resp }
            Write-Host "  响应: $head"
        }
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "  ⚠️ 没找到 curl.exe，跳过 HTTP 测试"
}

# === 5) OpenCode 版本 + 进程 ===
Write-Host ""
Write-Host "--- 5) OpenCode 状态 ---" -ForegroundColor Yellow
$ocExe = (Get-Command opencode -ErrorAction SilentlyContinue).Source
if ($ocExe) {
    Write-Host "  opencode 路径: $ocExe"
    try {
        $ver = & opencode --version 2>$null
        Write-Host "  版本: $ver"
    } catch { Write-Host "  版本获取失败: $_" }
} else {
    Write-Host "  ❌ opencode 命令不存在" -ForegroundColor Red
}

$ocProc = Get-Process opencode -ErrorAction SilentlyContinue
if ($ocProc) {
    Write-Host "  OpenCode 当前进程: PID $($ocProc.Id) (启动: $($ocProc.StartTime))"
}

Write-Host ""
Write-Host "===== 诊断完成 =====" -ForegroundColor Cyan
Write-Host "把上面所有输出复制粘贴回去，我据此判断"
