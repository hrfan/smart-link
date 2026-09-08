# Smart-Link — DCES 内部 AI 网关客户端配置

集中化接入公司 AI 网关，共用 GLM-5.3（1M 上下文，含思考）、GPT-5.x（含 5.6 Sol/Terra/Luna）、Kimi（K3 1M 上下文 / K2.7 / HighSpeed，按人授权）等模型，以及 MCP 工具集（联网搜索、网页抓取等）。**所有底层 API Key 由网关统一托管，你只需要一个 Virtual Key。**

支持两种 AI 编程 CLI：

- 🅐 **OpenCode**（推荐）—— 对接最完整，模型、MCP 工具一次全上
- 🅑 **Claude Code**（可选）—— 官方 Claude CLI 也能接，复用同一个 VK

---

## 第 0 步：先拿 Virtual Key

找 **@fengyi** 要一个 VK，格式 `sk-bf-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`。

---

<table><tr><td bgcolor="#fff3cd">

### ⚠️ 请定期重跑脚本同步最新配置

- 🗓️ **每周重跑一次** —— 网关支持的模型与 MCP 工具仍在快速迭代，避免本地配置过期
- 🚨 **遇到模型调用报错也立即重跑** —— 多半是底层 provider / model 清单已变更，客户端没跟上

*脚本自动复用本地缓存的 VK，无需重新输入。*

</td></tr></table>

---

---

# 🅐 OpenCode 接入（推荐）

先装好 [OpenCode](https://opencode.ai/docs/install/)，按平台跑下面一键命令。**首次运行会提示输入 VK**（找 @fengyi 要），脚本会缓存到本地；之后重跑同样命令直接拉最新配置，无需再输入。装完重启CLI或APP。

**Linux / macOS**

```bash
bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.sh)"
```

**Windows PowerShell**

```powershell
& ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-opencode.ps1 })))
```

> 💡 优先直连 GitHub raw，5 秒内失败自动降级走 ghfast.top 加速镜像，无需手动切换。

---

# 🅑 Claude Code 接入（可选）

先装 Claude Code CLI（[安装文档](https://docs.claude.com/en/docs/claude-code/setup)），按平台跑下面一键命令。**首次会提示输入 VK**，之后重跑直接复用。装完重开终端 → `claude` → 进对话。

装完 5 个 alias 槽位全部绑定 GLM-5.3（`zai/glm-5.3`），详见下方表格。

**Linux / macOS**

```bash
bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.sh)"
```

**Windows PowerShell**

```powershell
& ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-claude.ps1 })))
```

> 💡 优先直连 GitHub raw，5 秒内失败自动降级走 ghfast.top 加速镜像，无需手动切换。

### 自定义 `/model` 槽位绑定的模型

5 个 alias 槽位通过环境变量绑定，改完**重开终端**生效（PowerShell 还要重启 Claude Code）：

| 环境变量 | 对应槽位 | 默认值 |
|---|---|---|
| `ANTHROPIC_MODEL` | Default（主对话） | `zai/glm-5.3` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `/model` → Custom Opus | `zai/glm-5.3` |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `/model` → Custom Sonnet | `zai/glm-5.3` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `/model` → Custom Haiku | `zai/glm-5.3` |
| `CLAUDE_CODE_SUBAGENT_MODEL` | subagent / 后台任务 | `zai/glm-5.3` |

可选 model id：默认 `zai/glm-5.3`（1M 上下文，含思考，网关 anthropic 入口由 bifrost 桥接到 GLM）。**有 Kimi 权限的人**也可以把槽位改成 `kimi/k3`（1M 上下文）、`kimi/kimi-for-coding-highspeed`（高速）、`kimi/k2p7`。GPT 走 OpenCode 那条 OpenAI 入口，不在 Claude Code 这里。

> ⚠️ 2026-09-03 起默认槽位从 Kimi 改为 GLM-5.3，Kimi 改为**按人授权**。没有 Kimi 权限的老配置会报 "Provider 'kimi' is not allowed"——**重跑上面的 setup-claude 一键命令切到 GLM 即可**，需要继续用 Kimi 的找管理员开通。

**Linux / macOS** — 改 `~/.zshrc` / `~/.bashrc` 里对应 `export` 行（脚本会写一份默认进去），然后 `source ~/.zshrc`。

**Windows PowerShell**

```powershell
# 比如把 Default 槽显式指到 GLM-5.3
[Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", "zai/glm-5.3", "User")
# 关掉所有终端 / Claude Code 重开生效
```

或直接打开"系统属性 → 环境变量 → 用户变量"图形界面改。

### 切回官方 Claude（撤销网关接入）

一键清掉网关配置（环境变量 + 自签 CA），Claude Code 恢复用 Anthropic 官方 API。之后跑 `claude /login` 登录你自己的 Anthropic 账号 / API Key 即可；想再接回网关重跑 setup-claude 就行。

**Linux / macOS**

```bash
bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.sh)"
```

**Windows PowerShell**

```powershell
& ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/unset-claude.ps1 })))
```

> 💡 优先直连 GitHub raw，5 秒内失败自动降级走 ghfast.top 加速镜像，无需手动切换。

---

# 🅒 全局代理（可选）

把整机流量交给公司网关上的 sing-box 代理，**浏览器 + 命令行工具（git / npm / curl / AI CLI）一起生效**。

分流由 sing-box 自己完成：**国内网站和公司内网直连，境外才走海外出口**，不用手动切来切去。默认使用共享口 `192.168.13.229:10808`。

> ⚠️ 这是**整机代理**，跟上面 OpenCode / Claude Code 的接入是两件独立的事。只想用 AI 网关的话不需要开它。

### 开启代理

**macOS**

```bash
bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh)"
```

> ⚠️ **必须用 `bash -c "$(curl ...)"` 这种写法，不要写成 `curl ... | bash`** —— 修改系统代理需要管理员权限，管道会占用输入通道，导致密码提示卡住读不到输入。
>
> 脚本会要你输入 **Mac 登录密码**（`networksetup` 改系统代理所需），属正常现象。

**Windows PowerShell**

```powershell
& ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 })))
```

脚本会先测端口连通性，再配好系统代理和环境变量，最后自动验证一次能否访问境外站点。

### 关闭代理

**macOS**

```bash
bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh)" -- --off
```

**Windows PowerShell**

```powershell
& ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 }))) -Off
```

系统代理和环境变量都会被清掉，重复执行无副作用。

### 使用专属出口（可选）

除了共享口 `:10808`，网关还提供**每人独立的专属出口**（端口 `:20001`–`:20012`，各自绑一个固定的海外住宅 IP，抗风控效果更好），以及一个新加坡出口 `:19999`（联通用户实测延迟最低）。

在开启命令末尾加参数指定端口即可：

**macOS** — 末尾追加 `-- --proxy 192.168.13.229:20001`

```bash
bash -c "$(curl -fsSL --connect-timeout 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh 2>/dev/null || curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.sh)" -- --proxy 192.168.13.229:20001
```

**Windows PowerShell** — 末尾追加 `-Proxy "192.168.13.229:20001"`

```powershell
& ([scriptblock]::Create($(try { irm -TimeoutSec 5 https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 } catch { irm https://ghfast.top/https://raw.githubusercontent.com/hrfan/smart-link/main/scripts/setup-proxy.ps1 }))) -Proxy "192.168.13.229:20001"
```

> 你的专属端口是哪个，找管理员确认（或查 ShowDoc「Claude 多出口 VPS 端口映射表」）。**请勿使用别人的端口** —— 一人一口才能保证出口 IP 干净、互不牵连。

### 生效范围

| | 何时生效 |
|---|---|
| 浏览器 / 图形界面程序 | **立即生效** |
| 命令行工具（git / npm / curl / AI CLI） | `source ~/.zshrc`（macOS）或**新开终端**后生效 |

> 💡 macOS 上如果你已装了 ClashX / Surge 等代理软件，本脚本会覆盖系统代理设置，可能与之冲突 —— 二者请择一使用。
