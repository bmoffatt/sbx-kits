#!/usr/bin/env bash
# SessionStart hook: keep the rules in ~/.claude/rules/ and the tools in ~/.claude/bin/
# current. A plugin can't ship rules, so copy them. Runs every session and is
# idempotent. Mirrors what the sbx kit overlay (sbx-rules.dockerfile) puts in the
# sandbox.
set -eu

src="${CLAUDE_PLUGIN_ROOT}/files/home/.claude"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

sync() { # source-dir dest-dir glob mode
  mkdir -p "$2"
  for f in "$1"/$3; do
    [ -e "$f" ] || continue
    dst="$2/$(basename "$f")"
    cmp -s "$f" "$dst" 2>/dev/null || { cp "$f" "$dst.tmp" && chmod "$4" "$dst.tmp" && mv "$dst.tmp" "$dst"; }
  done
}
sync "$src/rules" "$cfg/rules" '*.md' 0644
sync "$src/bin" "$cfg/bin" '*' 0755
