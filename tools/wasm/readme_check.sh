#!/bin/bash
# The README's web commands, run the way an app author runs them: a scratch app made of the README's own pieces -
# its Installation stanza (with only the source swapped from GitHub to this checkout), its Quick Start program -
# then `shards install` and every command of the "In a browser" section, in order. Run from crymble-ui's root.
set -euo pipefail

CUI=$PWD
APP=$(mktemp -d)
trap 'kill ${SERVER:-} 2> /dev/null || true; rm -rf "$APP"' EXIT
fail() { echo "readme_check: FAIL - $*" >&2; exit 1; }

# The README's blocks: the first ```yaml (Installation), the first ```crystal (Quick Start), and the ```bash block of
# the web section.
block() { # LANG [AFTER-HEADING]
  awk -v lang="$1" -v after="${2:-}" '
    after != "" && index($0, after) == 1 { armed = 1 }
    after == "" { armed = 1 }
    armed && $0 == "```" lang { inside = 1; next }
    inside && $0 == "```" { exit }
    inside { print }' README.md
}
stanza=$(block yaml)
program=$(block crystal "## Quick Start")
commands=$(block bash "## In a browser")
[ -n "$stanza" ] && [ -n "$program" ] && [ -n "$commands" ] || fail "README.md lacks a block this check reads"
echo "$stanza" | grep -q 'github: wolfgang371/crymbleui' || fail "the Installation stanza changed shape: $stanza"

{
  echo "name: hello"
  echo "version: 0.1.0"
  echo "license: MIT"
  echo "$stanza" | sed "s|github: wolfgang371/crymbleui|path: $CUI|"
} > "$APP/shard.yml"
mkdir -p "$APP/src"
echo "$program" > "$APP/src/hello.cr"

cd "$APP"
shards install > shards.log 2>&1 || { cat shards.log; fail "shards install"; }
[ -x bin/crymble-web ] || fail "shards install did not put bin/crymble-web into the app's bin/"

while IFS= read -r line; do
  cmd=${line%%#*}
  cmd=$(echo "$cmd" | sed 's/ *$//')
  [ -n "$cmd" ] || continue
  echo "readme_check: \$ $cmd"
  case "$cmd" in
    "bin/crymble-web serve "*)
      # on a free port, not the default the command uses: a server already running there would answer instead
      port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
      $cmd "$port" > serve.log 2>&1 &
      SERVER=$!
      for _ in $(seq 50); do curl -sf "http://127.0.0.1:$port/" -o index.html && break; sleep 0.2; done
      grep -q 'crymble-web.js' index.html 2> /dev/null || fail "$cmd $port: no page at http://127.0.0.1:$port/"
      grep -q '<b>hello</b>' index.html || fail "$cmd: the page is not the hello app's"
      ;;
    *)
      $cmd || fail "$cmd"
      ;;
  esac
done <<< "$commands"
[ -s bin/web/hello/hello.wasm ] || fail "no bin/web/hello/hello.wasm"
echo "readme_check: PASS ($(echo "$commands" | grep -c '^bin/') commands in a scratch app)"
