#!/usr/bin/env bash
# Runs ON the remote server, piped over ssh:
#   ssh <host> "bash -s -- <check|apply|restart|verify> '<arg>'..." < configure.sh
# The server's shell re-parses that string: quote each argument as shown and
# percent-encode the proxy user/password so the URL holds no single quote.
#
#   check   <proxy-url>               API status direct and through the proxy
#   apply   <proxy-url> [no-proxy]    merge proxy vars into ~/.claude/settings.json
#   restart                           stop the Desktop app's long-lived remote server
#   verify                            show where the remote Claude CLI connects
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
# write through a symlinked settings file (dotfile repos) instead of replacing the link
SETTINGS=$(readlink -f "$SETTINGS" 2>/dev/null || echo "$SETTINGS")
API=https://api.anthropic.com
# "[c]laude" matches "claude" but not this literal text, so pgrep/pkill never
# match a shell whose own command line carries the pattern
SERVER_PAT='[c]laude/remote/srv/.*/server'
CLI_PAT='[c]laude/remote/ccd-cli/'

mask() { sed -E 's#(://[^:/@]+):[^@]*@#\1:***@#'; }

check_url() {
  case "$1" in
    http://*|https://*) ;;
    socks*) echo "ERROR: Claude Code does not support SOCKS proxies; use an http:// or https:// URL" >&2; exit 2 ;;
    *) echo "ERROR: proxy URL must start with http:// or https://" >&2; exit 2 ;;
  esac
}

status() {
  local servers sessions
  servers=$(pgrep -u "$(id -u)" -fc -- "$SERVER_PAT --serve" || true)
  sessions=$(pgrep -u "$(id -u)" -fc -- "$CLI_PAT" || true)
  echo "remote server running: ${servers:-0}, open sessions: ${sessions:-0}"
}

cmd=${1:-}; shift || true
case "$cmd" in
  check)
    proxy=${1:?proxy URL required}; check_url "$proxy"
    direct=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$API" || true)
    via=$(curl -s -o /dev/null -m 15 -w '%{http_code}' -x "$proxy" "$API" || true)
    echo "direct:        $direct"
    echo "through proxy: $via  ($(printf %s "$proxy" | mask))"
    ;;

  apply)
    proxy=${1:?proxy URL required}; check_url "$proxy"
    noproxy=${2:-localhost,127.0.0.1}
    mkdir -p "$(dirname "$SETTINGS")"
    umask 077
    tmp=$(mktemp "$SETTINGS.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    if [ -s "$SETTINGS" ]; then src=$SETTINGS; else src=/dev/null; fi

    if command -v jq >/dev/null; then
      { [ "$src" = /dev/null ] && echo '{}' || cat "$src"; } |
        jq --arg p "$proxy" --arg n "$noproxy" \
          '.env = ((.env // {}) + {HTTPS_PROXY: $p, HTTP_PROXY: $p, NO_PROXY: $n})' > "$tmp" ||
        { echo "ERROR: $SETTINGS is not valid JSON; left untouched" >&2; exit 1; }
    elif command -v python3 >/dev/null; then
      python3 - "$src" "$proxy" "$noproxy" > "$tmp" <<'PY' ||
import json, sys
src, p, n = sys.argv[1:]
data = {}
if src != "/dev/null":
    with open(src) as f:
        data = json.load(f)
data.setdefault("env", {}).update({"HTTPS_PROXY": p, "HTTP_PROXY": p, "NO_PROXY": n})
print(json.dumps(data, indent=2, ensure_ascii=False))
PY
        { echo "ERROR: $SETTINGS is not valid JSON; left untouched" >&2; exit 1; }
    else
      echo "ERROR: need jq or python3 on the server to merge JSON safely" >&2; exit 1
    fi

    if [ "$src" != /dev/null ]; then
      backup="$SETTINGS.bak-$(date +%Y%m%d%H%M%S)"
      cp -p "$SETTINGS" "$backup"
      echo "backup: $backup"
    fi
    mv "$tmp" "$SETTINGS"; trap - EXIT
    chmod 600 "$SETTINGS"
    echo "wrote: $SETTINGS"
    grep -E '"(HTTPS?_PROXY|NO_PROXY)"' "$SETTINGS" | mask
    status
    ;;

  restart)
    if pkill -u "$(id -u)" -f -- "$SERVER_PAT"; then
      echo "stopped; Claude Desktop starts a fresh one on its next connection"
    else
      echo "no remote server was running"
    fi
    ;;

  verify)
    status
    pids=$(pgrep -u "$(id -u)" -f -- "$CLI_PAT" || true)
    [ -n "$pids" ] || { echo "no Claude session running; open one from Claude Desktop first"; exit 1; }
    for pid in $pids; do
      echo "pid $pid connects to:"
      ss -tnpH state established 2>/dev/null | grep "pid=$pid," | awk '{print "  " $4}' | sort | uniq -c
    done
    ;;

  *)
    echo "usage: configure.sh check|apply|restart|verify ..." >&2; exit 2 ;;
esac
