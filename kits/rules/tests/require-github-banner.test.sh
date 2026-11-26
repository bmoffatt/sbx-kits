#!/usr/bin/env bash
# Tests for files/home/.claude/hooks/require-github-banner.sh. Needs jq; gh is faked.
#   bash kits/rules/tests/require-github-banner.test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
HOOK="$here/../files/home/.claude/hooks/require-github-banner.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fake gh: `view --json body` and `api <endpoint>` print $FAKE_BODY, `view --json
# comments` prints $FAKE_COMMENT, FAKE_FAIL=1 makes reads fail.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_FAIL:-}" ] && exit 1
case "$*" in
  "api user --jq .login") echo bmoffatt ;;
  *"--json comments"*) printf '%s\n' "${FAKE_COMMENT:-}" ;;
  *) printf '%s\n' "${FAKE_BODY:-}" ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

printf '%s\n' '{"type":"user"}' '{"type":"assistant","message":{"model":"claude-opus-5-5"}}' >"$tmp/transcript.jsonl"
export IS_SANDBOX=1 HOSTNAME=my-project.local
unset CLAUDE_EFFORT

BANNER='🤖 [Claude Code](https://claude.com/claude-code) · Opus 5.5 · high effort · sandbox my-project'
OTHER='🤖 [Claude Code](https://claude.com/claude-code) · Sonnet 5.5 · low effort · sandbox other'
STOCK='🤖 Generated with [Claude Code](https://claude.com/claude-code)'

pass=0
fail=0
body() { printf '%s\n' "$@" >"$tmp/body.md"; }
run() { # expected-exit command
  local exp=$1 c=$2 rc
  jq -n --arg c "$c" --arg t "$tmp/transcript.jsonl" --arg d "$tmp" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d, transcript_path: $t, effort: {level: "high"}}' |
    bash "$HOOK" >/dev/null 2>"$tmp/err"
  rc=$?
  if [ "$rc" = "$exp" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL (want %s, got %s): %s\n' "$exp" "$rc" "$CASE"
    sed 's/^/    /' "$tmp/err"
  fi
}
t() { CASE=$1; shift; run "$@"; }

F="$tmp/body.md"

# ---- not publishing ----
t "non-gh command" 0 'ls -la'
t "gh read" 0 'gh pr list --author @me'
t "gh in a quoted string" 0 'echo "gh pr create --body x"'
t "label edit" 0 'gh pr edit 1 --add-label x'
t "body-less approval" 0 'gh pr review 1 --approve'
t "api GET" 0 'gh api repos/o/r/issues/1/comments'
t "api PATCH without text" 0 'gh api -X PATCH repos/o/r/pulls/1 -f state=closed'

# ---- how the text is passed ----
t "inline --body" 2 'gh pr create --title t --body "x"'
t "--fill" 2 'gh pr create --fill'
t "no body at all" 2 'gh issue comment 3'
t "inline after cd &&" 2 'cd x && gh issue comment 3 --body "hi"'
t "api inline field" 2 'gh api -X POST repos/o/r/issues/1/comments -f body=hi'
t "missing body file" 2 "gh pr comment 1 --body-file $tmp/nope.md"
body "$BANNER" "hi"
t "body file written by the same command" 2 "printf x > $F && gh pr comment 1 --body-file $F"
t "stdin body" 2 'gh pr comment 1 --body-file -'

# ---- new posts ----
body "$BANNER" "" "Looks good."
t "new: banner first" 0 "gh pr comment 1 --body-file $F"
t "new: relative path" 0 "gh pr comment 1 --body-file body.md"
t "new: -F short flag" 0 "gh issue create -t x -F $F"
body "" "$BANNER" "Looks good." "" "$STOCK"
t "new: leading blank, stock line at end" 0 "gh pr create -t x --body-file $F"
body "Looks good." "" "$BANNER"
t "new: banner at the end" 2 "gh pr comment 1 --body-file $F"
body "$STOCK"
t "new: stock attribution line only (ignored)" 0 "gh pr comment 1 --body-file $F"
body "$OTHER" "hi"
t "new: wrong model/effort/sandbox" 2 "gh pr comment 1 --body-file $F"
body "${BANNER% · sandbox my-project}" "hi"
t "new: banner missing the sandbox" 2 "gh pr comment 1 --body-file $F"
body "$BANNER" "first" "" "---" "" "my notes"
t "new: --- inside own section, then text" 2 "gh pr comment 1 --body-file $F"
body "$BANNER" "first" "" "---" "" "$BANNER" "second"
t "new: two sections, --- then banner" 0 "gh pr comment 1 --body-file $F"
body "$BANNER" "review"
t "new: review with body" 0 "gh pr review 1 --comment --body-file $F"
t "new: api POST -F body=@" 0 "gh api -X POST repos/o/r/issues/1/comments -F body=@$F"
jq -n --arg b "$(cat "$F")" '{body: $b}' >"$tmp/in.json"
t "new: api --input json" 0 "gh api repos/o/r/issues/1/comments --input $tmp/in.json"

# ---- edits: the user's text above a --- stays ----
export FAKE_BODY="My own words.
More of mine.

---

$OTHER
Old Claude text."
body "My own words." "More of mine." "" "---" "" "$BANNER" "New Claude text."
t "edit: replace own section, keep user text" 0 "gh pr edit 1 --body-file $F"
body "---" "" "$BANNER" "New Claude text."
t "edit: drops the user's text" 2 "gh pr edit 1 --body-file $F"
body "My own words, reworded." "More of mine." "" "---" "" "$BANNER" "New Claude text."
t "edit: rewrites the user's text" 2 "gh pr edit 1 --body-file $F"
body "My own words." "More of mine." "Claude adds a line here." "" "---" "" "$BANNER" "x"
t "edit: adds text outside a section" 2 "gh pr edit 1 --body-file $F"
body "My own words." "More of mine." "" "---" "" "$OTHER" "Old Claude text." "" "---" "" "$BANNER" "Appended."
t "edit: keep old section, append a new one" 0 "gh pr edit 1 --body-file $F"
body "My own words." "More of mine." "" "---" "" "$OTHER" "Old Claude text, changed."
t "edit: changes old section under its old banner" 2 "gh pr edit 1 --body-file $F"
body "My own words." "More of mine." "" "" "---" "" "" "$BANNER" "New Claude text."
t "edit: blank lines differ" 0 "gh pr edit 1 --body-file $F"
t "edit: issue edit with -R" 0 "gh issue edit 5 -R o/r --body-file $F"
t "edit: api PATCH" 0 "gh api -X PATCH repos/o/r/issues/comments/9 -F body=@$F"
body "---" "" "$BANNER" "x"
t "edit: api PATCH drops user text" 2 "gh api --method PATCH repos/o/r/issues/comments/9 -F body=@$F"

# The user wrote above Claude's earlier comment and Claude edits its last comment.
export FAKE_COMMENT="Note from me.

---

$BANNER
Earlier."
body "Note from me." "" "---" "" "$BANNER" "Updated."
t "edit-last: keeps the user's note" 0 "gh pr comment 1 --edit-last --body-file $F"
body "$BANNER" "Updated."
t "edit-last: drops the user's note" 2 "gh pr comment 1 --edit-last --body-file $F"

# An empty PR body edited for the first time behaves like a new post.
export FAKE_BODY=""
body "$BANNER" "Description."
t "edit: empty body gets a section" 0 "gh pr edit 1 --body-file $F"

FAKE_FAIL=1 t "edit: can't read the current body" 2 "gh pr edit 1 --body-file $F"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
