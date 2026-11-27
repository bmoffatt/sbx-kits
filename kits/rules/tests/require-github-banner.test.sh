#!/usr/bin/env bash
# Tests for files/home/.claude/hooks/require-github-banner.sh. Needs jq.
#   bash kits/rules/tests/require-github-banner.test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
HOOK="$here/../files/home/.claude/hooks/require-github-banner.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export CLAUDE_CONFIG_DIR="$tmp/cfg"

pass=0
fail=0
t() { # case expected-exit command
  local rc
  jq -n --arg c "$3" '{tool_name: "Bash", tool_input: {command: $c}}' |
    bash "$HOOK" >/dev/null 2>"$tmp/err"
  rc=$?
  if [ "$rc" = "$2" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL (want %s, got %s): %s\n' "$2" "$rc" "$1"
    sed 's/^/    /' "$tmp/err"
  fi
}

# ---- allowed ----
t "non-gh command" 0 'ls -la'
t "gh read" 0 'gh pr list --author @me'
t "gh-claude" 0 "$tmp/cfg/bin/gh-claude /tmp/x.md pr comment 12"
t "gh-claude by name" 0 'gh-claude x.md pr edit 12'
t "mentioned in a quoted string" 0 'echo "gh pr create --body x"'
t "mentioned in a commit message" 0 "git commit -m 'use gh pr comment --body-file'"
t "mentioned in a heredoc" 0 "cat > /tmp/x.md <<'EOF'
Run gh pr comment 12 --body-file x.md
EOF"
t "mentioned in a <<- heredoc" 0 "cat > /tmp/x.md <<-EOF
	gh issue create --title t
	EOF
gh pr view 12"
t "label edit" 0 'gh pr edit 1 --add-label x'
t "body-less approval" 0 'gh pr review 1 --approve'
t "api GET" 0 'gh api repos/o/r/issues/1/comments'
t "api state change" 0 'gh api -X PATCH repos/o/r/pulls/1 -f state=closed'

# ---- blocked ----
t "pr create" 2 'gh pr create --title t --fill'
t "pr comment with a file" 2 'gh pr comment 1 --body-file x.md'
t "issue comment" 2 'gh issue comment 3 -b hi'
t "after cd &&" 2 'cd x && gh issue comment 3 --body "hi"'
t "full path to gh" 2 '/usr/bin/gh pr comment 1 -F x.md'
t "after a heredoc ends" 2 "cat > /tmp/x.md <<EOF
text
EOF
gh pr comment 1 --body-file /tmp/x.md"
t "a here-string is not a heredoc" 2 'jq . <<<x; gh pr comment 1 -F x.md'
t "description edit" 2 'gh pr edit 1 --body-file x.md'
t "issue edit" 2 'gh issue edit 1 -b hi'
t "review with a body" 2 'gh pr review 1 --comment --body "hi"'
t "api body field" 2 'gh api -X POST repos/o/r/issues/1/comments -f body=hi'
t "api body file" 2 'gh api repos/o/r/issues/comments/9 -X PATCH -F body=@x.md'
t "api --input" 2 'gh api repos/o/r/issues/1/comments --input x.json'
t "graphql with a body" 2 "gh api graphql -f query='mutation { addComment(input: {subjectId: \"x\", body: \"hi\"}) { clientMutationId } }'"

grep -qF "$tmp/cfg/bin/gh-claude FILE pr comment 12" "$tmp/err" ||
  { fail=$((fail + 1)); echo "FAIL: the message names gh-claude's path"; }

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
