#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) for the github-banner rule (rules/github-banner.md).
#
# Claude's text goes to GitHub through gh-claude (~/.claude/bin/gh-claude), which adds
# the banner and merges edits without touching anyone else's text. This hook
#   - blocks gh commands that would post or edit text directly, pointing at gh-claude;
#   - tells gh-claude who is calling: a command that runs gh-claude gets
#     GH_CLAUDE_TRANSCRIPT and GH_CLAUDE_EFFORT exported in front of it, from the hook
#     input. Only the hook can tell a sub-agent (agent_id) from its parent: they
#     share the session ID, and the sub-agent's model is in its own transcript.
# It keeps a cooperative model consistent; it is not a security boundary (curl,
# scripts and MCP tools can still post).
#
# Exit 2 blocks the call and sends stderr back to Claude; exit 0 allows it, with
# stdout optionally carrying the rewritten command (hookSpecificOutput.updatedInput).
# Written for bash 3.2 as well (macOS hosts run the plugin form).
set -u

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
gh='(^|[^[:alnum:]_.-])gh[[:space:]]+'

if [[ $cmd =~ $gh ]]; then
  # Heredoc bodies and quoted strings are data, not commands: drop them, so writing
  # a file or a commit message that mentions `gh pr comment` isn't taken for one.
  bare=$(printf '%s\n' "$cmd" | awk '
    doc != "" { l = $0; if (strip) sub(/^\t+/, "", l); if (l == doc) doc = ""; next }
    { print
      if (match($0, /(^|[^<])<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
        d = substr($0, RSTART, RLENGTH); sub(/^[^<]/, "", d); strip = (d ~ /^<<-/)
        sub(/^<<-?[ \t]*["\047]?/, "", d); doc = d } }' |
    sed -E "s/'[^']*'//g; s/\"([^\"\\\\]|\\\\.)*\"//g")

  posts='(pr|issue)[[:space:]]+(create|comment)([[:space:]]|$)'
  edits='(pr[[:space:]]+(edit|review)|issue[[:space:]]+edit)([[:space:]]|$)'
  body_flag='(^|[[:space:]])(-b|--body|-F|--body-file|--fill|--fill-first|--fill-verbose)([[:space:]=]|$)'
  api='api([[:space:]]|$)'
  # gh api sends text only through a body field, --input, or a GraphQL mutation;
  # `--json body` and `--jq '{body: ...}'` are reads.
  api_body="(-f|-F|--field|--raw-field)[[:space:]=]+['\"]?body=|(^|[[:space:]])--input([[:space:]=]|$)|mutation.*body"

  blocked=0
  if [[ $bare =~ $gh$posts ]]; then blocked=1
  elif [[ $bare =~ $gh$edits ]] && [[ $bare =~ $body_flag ]]; then blocked=1
  elif [[ $bare =~ $gh$api ]] && [[ $cmd =~ $api_body ]]; then blocked=1
  fi
  if [ $blocked = 1 ]; then
    ghc=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/gh-claude
    cat >&2 <<EOF
Blocked by the github-banner hook: publish text on GitHub with gh-claude, not gh. Write only your own text (no banner, no markers) to a file, then for example:
  $ghc FILE pr create --title "..." --draft
  $ghc FILE pr comment 12
  $ghc FILE pr review 12 --request-changes
  $ghc FILE pr edit 12                            (the description)
  $ghc FILE comment-edit <comment URL>
  $ghc FILE api repos/{owner}/{repo}/pulls/12/comments/34/replies
It adds this session's banner and never changes anyone else's text. To change the user's text, give them the new text to paste instead. See ~/.claude/rules/github-banner.md.
EOF
    exit 2
  fi
fi

[[ $cmd == *gh-claude* ]] || exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
agent=$(jq -r '.agent_id // empty' <<<"$input")
effort=$(jq -r '.effort.level // empty' <<<"$input")
# A sub-agent's transcript: <session>.jsonl -> <session>/subagents/agent-<id>.jsonl
if [ -n "$agent" ] && [ -f "${transcript%.jsonl}/subagents/agent-$agent.jsonl" ]; then
  transcript=${transcript%.jsonl}/subagents/agent-$agent.jsonl
fi
prefix=$(printf 'export GH_CLAUDE_TRANSCRIPT=%q GH_CLAUDE_EFFORT=%q; ' "$transcript" "$effort")
jq -c --arg p "$prefix" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input + {command: ($p + .tool_input.command)})}}' \
  <<<"$input"
