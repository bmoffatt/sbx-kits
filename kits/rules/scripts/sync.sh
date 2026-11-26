#!/usr/bin/env bash
# SessionStart hook: keep the rules in ~/.claude/rules/ current. A plugin can't ship
# rules, so copy them. Runs every session and is idempotent. Mirrors what the sbx kit
# overlay (sbx-rules.dockerfile) puts in the sandbox.
set -eu

src="${CLAUDE_PLUGIN_ROOT}/files/home/.claude/rules"
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules"

mkdir -p "$dir"
for f in "$src"/*.md; do
  [ -e "$f" ] || continue
  dst="$dir/$(basename "$f")"
  cmp -s "$f" "$dst" 2>/dev/null || { cp "$f" "$dst.tmp" && mv "$dst.tmp" "$dst"; }
done
