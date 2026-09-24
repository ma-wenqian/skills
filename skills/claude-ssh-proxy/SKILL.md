---
name: claude-ssh-proxy
description: Route the Claude Code that Claude Desktop runs on a remote SSH server through an HTTP(S) proxy, by writing the env block of the server's ~/.claude/settings.json. Use when a Desktop SSH session never replies or hangs at "Starting session…", when the server's region can't reach Anthropic (api.anthropic.com returns 403), or when the user wants the remote Claude to use a specific egress.
---

# Claude over SSH: give the remote Claude its own proxy

Claude Desktop's Code tab can run Claude Code on a server over SSH. The app uploads its own CLI to `~/.claude/remote/` and supplies authentication itself, so nothing needs installing or signing in on the server. When the server's egress can't reach Anthropic, the fix is an `env` block in the server's `~/.claude/settings.json`. It affects only Claude and the commands it runs, not the rest of the machine.

Talk to the user in their language. Run everything from the user's local machine with `ssh <host>`; the scripts in `scripts/` are piped over stdin, so nothing is copied to the server.

## 1. Gather

- **SSH host**: an alias from `~/.ssh/config` or `user@host -p port`. It must be the same user the Desktop app connects as, because the settings file lives in that user's home.
- **Proxy URL**: see below.
- **NO_PROXY** (optional): defaults to `localhost,127.0.0.1`. Suggest adding the server's LAN range, and `100.64.0.0/10,.ts.net` if they use Tailscale.

### Finding the proxy URL

Never invent one. In this order:

1. **Already known.** If memory, CLAUDE.md, notes or the conversation name a proxy for this host, propose it and ask the user to confirm before using it.
2. **Look on the server.** Check for a proxy already in `~/.claude/settings.json`, proxy variables in the login shell, and a proxy listening locally (Clash, mihomo, sing-box, xray, squid and the like). Offer what you find as candidates and confirm with the user.
3. **Ask the user.** If they don't have one, lay out the options:
   - **A proxy the server can already reach**: one running on the server, or a gateway on its LAN. Use its HTTP (or mixed) port.
   - **Borrow the proxy on the user's own computer** through an SSH reverse tunnel. See the next section.
   - **Set up a new proxy** on the server or another machine. That is outside this skill: offer to help with it separately, then come back to step 2.

Rules for the URL:

- `http://` or `https://`, optionally with `user:pass@`. Reject `socks5://` and `socks5h://`: Claude Code does not support SOCKS. A Clash/mihomo mixed port also speaks HTTP, so suggest `http://` on the same port.
- `127.0.0.1` means a proxy on the server itself, not on the user's computer.
- Never echo a proxy password back in chat; refer to it as `user:***@host`.

### Borrowing the local proxy over a reverse tunnel

When the user's computer has a working HTTP proxy (check locally with `curl -x http://127.0.0.1:<port> -sI https://api.anthropic.com`), forward it to the server's loopback:

```bash
ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -R 127.0.0.1:17890:127.0.0.1:<local-port> <host>
```

Then use `http://127.0.0.1:17890` as the proxy URL. Tell the user the trade-offs before choosing this:

- It works only while that `ssh` process runs on their computer. It dies with sleep, network changes or a reboot, and the remote Claude then loses its network until it's started again (`autossh` or a startup task can keep it up).
- Run it as its own process. Don't put `RemoteForward` in `~/.ssh/config` and expect the Desktop app's connection to open it; the app isn't guaranteed to honor it.
- The remote Claude then exits wherever the user's local proxy exits.

## 2. Check

```bash
ssh <host> 'bash -s' -- check '<proxy-url>' < scripts/configure.sh
```

It prints the HTTP status of `api.anthropic.com` direct and through the proxy.

- Direct `403`: the region is blocked; the proxy is needed.
- Through the proxy, any of `401` `404` `405` means it reaches Anthropic. `000` means the server can't reach the proxy; `403` means the proxy's exit is blocked too. Stop and report either one; don't write a proxy that doesn't work.

## 3. Apply

```bash
ssh <host> 'bash -s' -- apply '<proxy-url>' '<no-proxy>' < scripts/configure.sh
```

The script merges `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY` into `env`, keeping every other key in the file, backs up an existing file to `settings.json.bak-<timestamp>`, and sets mode 600 because the URL may carry a password. It needs `jq` or `python3` on the server and stops if the existing file isn't valid JSON; relay that to the user rather than overwriting it.

## 4. Restart the remote server

The Desktop app's remote server (`~/.claude/remote/srv/*/server --serve`) is long-lived and reused across connections, so it keeps the settings it started with. The `apply` output says whether one is running and how many sessions it hosts.

- None running: nothing to do.
- Running with no sessions: stop it with the command below.
- Running with sessions: stopping it ends them. Ask the user first.

```bash
ssh <host> 'bash -s' -- restart < scripts/configure.sh
```

Don't hand-write `ssh <host> "pkill -f claude/remote/..."`: the remote shell's own command line contains the pattern and gets killed with it. The script avoids this.

## 5. Verify

Ask the user to open a new session to that host in Claude Desktop and send a message, then:

```bash
ssh <host> 'bash -s' -- verify < scripts/configure.sh
```

It lists the remote Claude process's TCP peers. They should all be the proxy's address and port. Also valid: the user asks the remote session to run `env | grep -i proxy`.

Don't check `/proc/<pid>/environ`: Claude applies the settings `env` after launch, so the variables never show there even when they work.

## Notes for the user

- Signing in on the server is not needed; the Desktop app handles authentication.
- The remote CLI is about 230 MB on disk and about 270 MB of RAM per open session, peaking around 330 MB. On a 1 GB VPS one session is already tight.
- To undo: remove the three keys from `env` (or restore the backup), then run step 4 again.
