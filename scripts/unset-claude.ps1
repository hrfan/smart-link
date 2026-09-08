# 撤销 Claude Code 到 AI 网关的接入，恢复 Anthropic 官方 API (Windows PowerShell)
# 本地:  .\unset-claude.ps1
# 远程:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.ps1)))
# 远程(域名优先,自动降级内网IP):
#   & ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.ps1 })))
#
# 清掉 setup-claude.ps1 写入的全部用户级环境变量 + 网关自签 CA。
# NO_PROXY 不动（那些内网 bypass 条目留着无害）。

$vars = @(
    'ANTHROPIC_BASE_URL',
    'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'CLAUDE_CODE_SUBAGENT_MODEL',
    'CLAUDE_CODE_EFFORT_LEVEL',
    'NODE_EXTRA_CA_CERTS'
)

foreach ($v in $vars) {
    [Environment]::SetEnvironmentVariable($v, $null, "User")
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    Write-Host "清除: $v" -ForegroundColor Green
}

# 删网关自签 CA（官方 API 用真证书，不需要它）
$caFile = Join-Path $env:USERPROFILE '.claude\bifrost-ca.crt'
if (Test-Path $caFile) {
    Remove-Item $caFile -Force -ErrorAction SilentlyContinue
    Write-Host "已删网关自签 CA: $caFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Claude Code 已恢复 Anthropic 官方配置" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "关闭所有终端 / claude 进程 → 新开窗口后 claude 就用回官方 API" -ForegroundColor Yellow
Write-Host "(前提你有 Anthropic API Key 或 Claude 订阅；登录跑 claude /login)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "想重新接回公司网关：重跑 setup-claude.ps1 即可" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
