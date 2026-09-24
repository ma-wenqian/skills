# skills

我的 [Agent Skills](https://agentskills.io) 合集。每个 skill 是 `skills/` 下的一个文件夹，核心是一个 `SKILL.md`，Claude Code、Codex、Gemini CLI、Cursor、GitHub Copilot 等支持 Agent Skills 的工具都能用。

My collection of [Agent Skills](https://agentskills.io). Each skill is a folder under `skills/` built around a `SKILL.md`, usable in any agent that supports the format: Claude Code, Codex, Gemini CLI, Cursor, GitHub Copilot and others.

| Skill | 用途 / What it does |
| --- | --- |
| [claude-ssh-proxy](skills/claude-ssh-proxy/SKILL.md) | 让 Claude 桌面版通过 SSH 在远程服务器上运行的 Claude 走 HTTP(S) 代理 · Route the Claude that Claude Desktop runs on an SSH server through an HTTP(S) proxy. [Blog post](https://www.mawenqian.com/zh/claude-desktop-ssh-proxy/) |

## 安装 / Install

**Claude Code**

```
/plugin marketplace add ma-wenqian/skills
/plugin install claude-ssh-proxy@vinkey-skills
```

更新 / Update: `/plugin marketplace update vinkey-skills`

**其他工具 / Other agents**

把 `skills/<name>` 整个文件夹复制到该工具的 skills 目录，具体位置见各自文档。

Copy the whole `skills/<name>` folder into your agent's skills directory; see its docs for the location.

## 新增 skill / Adding a skill

1. 新建 `skills/<name>/SKILL.md`，frontmatter 里的 `name` 要和文件夹同名。
2. 在 `.claude-plugin/marketplace.json` 的 `plugins` 里加一项，照抄现有写法。
3. `claude plugin validate .` 检查格式。
