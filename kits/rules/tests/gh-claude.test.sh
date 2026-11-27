#!/usr/bin/env bash
# Tests for files/home/.claude/bin/gh-claude. Needs jq; gh is faked.
#   bash kits/rules/tests/gh-claude.test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
GHC="$here/../files/home/.claude/bin/gh-claude"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fake gh: GitHub is one text, $FAKE/body. Reads print it as {"body": ...}; a call
# with --body-file F or body=@F replaces it with F. Every call goes to $FAKE/calls.
export FAKE="$tmp/gh"
mkdir -p "$FAKE/bin"
cat >"$FAKE/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE/calls"
[ -n "${FAKE_FAIL:-}" ] && exit 1
prev=""
for a in "$@"; do
  case $prev in --body-file) cp "$a" "$FAKE/body"; exit 0 ;; esac
  case $a in body=@*) cp "${a#body=@}" "$FAKE/body"; exit 0 ;; esac
  prev=$a
done
jq -n --rawfile b "$FAKE/body" '{body: $b}'
EOF
chmod +x "$FAKE/bin/gh"
export PATH="$FAKE/bin:$PATH"

export CLAUDE_CONFIG_DIR="$tmp/cfg" CLAUDE_CODE_SESSION_ID=sess CLAUDE_EFFORT=high
export IS_SANDBOX=1 HOSTNAME=my-project.local
mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
model() {
  printf '%s\n' '{"type":"user"}' "{\"type\":\"assistant\",\"message\":{\"model\":\"$1\"}}" \
    '{"type":"assistant","message":{"model":"<synthetic>"}}' >"$CLAUDE_CONFIG_DIR/projects/p/sess.jsonl"
}
model claude-opus-5-5

BANNER='🤖 [Claude Code](https://claude.com/claude-code) · Opus 5.5 · high · sbx my-project'
B='<!-- claude:begin id=my-project -->'
E='<!-- claude:end id=my-project -->'
OB='<!-- claude:begin id=other -->'
OE='<!-- claude:end id=other -->'

F="$tmp/text.md"
say() { printf '%s\n' "$@" >"$F"; }
cur() { printf '%s\n' "$@" >"$FAKE/body"; }
want() { printf '%s\n' "$@" >"$tmp/want"; }

pass=0
fail=0
# run case expected-exit gh-claude-args...; on success $FAKE/body must match $tmp/want
run() {
  local name=$1 exp=$2 rc
  shift 2
  cp "$FAKE/body" "$tmp/before"
  : >"$FAKE/calls"
  bash "$GHC" "$@" >/dev/null 2>"$tmp/err"
  rc=$?
  if [ "$rc" != "$exp" ]; then
    fail=$((fail + 1))
    printf 'FAIL (want exit %s, got %s): %s\n' "$exp" "$rc" "$name"
    sed 's/^/    /' "$tmp/err"
  elif [ "$exp" = 0 ] && [ "$(cat "$FAKE/body")" != "$(cat "$tmp/want")" ]; then
    fail=$((fail + 1))
    printf 'FAIL (body): %s\n' "$name"
    diff "$tmp/want" "$FAKE/body" | sed 's/^/    /'
  elif [ "$exp" != 0 ] && ! cmp -s "$tmp/before" "$FAKE/body"; then
    fail=$((fail + 1))
    printf 'FAIL (failed but wrote): %s\n' "$name"
  else
    pass=$((pass + 1))
  fi
}
called() { # case fixed-string expected in the gh calls
  if grep -qF -- "$2" "$FAKE/calls"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf 'FAIL: %s: no call with %s\n' "$1" "$2"
    sed 's/^/    /' "$FAKE/calls"
  fi
}

# ---- new posts ----
cur ""
say "Looks good."
want "$B" "$BANNER" "" "Looks good." "" "$E"
run "comment" 0 "$F" pr comment 12
called "comment" "pr comment 12 --body-file"
say "$BANNER" "" "Looks good."
run "a banner in the text is replaced" 0 "$F" issue comment 3
say "" "" "Looks good." "" ""
run "surrounding blank lines trimmed" 0 "$F" pr review 12 --comment
run "create passes its args" 0 "$F" pr create --title "a title" --draft
called "create" "pr create --title a title --draft --body-file"
say "$B" "x" "$E"
run "markers in the text" 2 "$F" pr comment 12
say "" ""
run "empty text" 2 "$F" pr comment 12
say "x"
run "--body" 2 "$F" pr comment 12 --body hi
run "--fill" 2 "$F" pr create --fill
run "--edit-last" 2 "$F" pr comment 12 --edit-last
run "unknown command" 2 "$F" pr merge 12
run "missing file" 2 "$tmp/nope.md" pr comment 12

# ---- description edits ----
cur ""
say "Description."
want "$B" "$BANNER" "" "Description." "" "$E"
run "empty description" 0 "$F" pr edit 12
called "edit reads the target" "pr view 12 --json body"

cur "My own words." "" "More of mine."
want "My own words." "" "More of mine." "" "---" "" "$B" "$BANNER" "" "Description." "" "$E"
run "user text, no block: appended after ---" 0 "$F" pr edit 12

cur "My own words." "" "---" ""
want "My own words." "" "---" "" "$B" "$BANNER" "" "Description." "" "$E"
run "user already ended with ---: no second rule" 0 "$F" pr edit 12

# The user wrote around the block in the browser (CRLF), with trailing spaces.
printf 'Mine, edited on GitHub.  \r\n\r\n---\r\n\r\n%s\r\n%s\r\n\r\nOld.\r\n\r\n%s\r\nA footnote of mine.\r\n' \
  "$B" "$BANNER" "$E" >"$FAKE/body"
say "New."
printf 'Mine, edited on GitHub.  \r\n\r\n---\r\n\r\n%s\n%s\n\nNew.\n\n%s\nA footnote of mine.\r\n' \
  "$B" "$BANNER" "$E" >"$tmp/want"
run "own block replaced in place, the rest byte for byte" 0 "$F" pr edit 12

OTHER_BLOCK=("$OB" "🤖 [Claude Code](https://claude.com/claude-code) · Sonnet 5.5 · low · sbx other" "" "Theirs." "" "$OE")
cur "Mine." "" "---" "" "${OTHER_BLOCK[@]}"
say "Ours."
want "Mine." "" "---" "" "${OTHER_BLOCK[@]}" "" "---" "" "$B" "$BANNER" "" "Ours." "" "$E"
run "another sandbox's block is kept, ours appended" 0 "$F" issue edit 5 -R o/r
called "edit passes -R to view" "issue view 5 -R o/r --json body"

model claude-sonnet-5-5
cur "Mine." "" "---" "" "$B" "$BANNER" "" "Old." "" "$E"
say "Newer."
want "Mine." "" "---" "" "$B" "${BANNER/Opus 5.5 · high/Sonnet 5.5 · low}" "" "Newer." "" "$E"
CLAUDE_EFFORT=low run "model and effort change: same block, new banner" 0 "$F" pr edit 12
model claude-opus-5-5

cur "Mine." "" "$B" "$BANNER" "" "Half a block."
run "begin without end" 2 "$F" pr edit 12
cur "$B" "a" "$E" "" "$B" "b" "$E"
run "two blocks for this sandbox" 2 "$F" pr edit 12
FAKE_FAIL=1 run "can't read the description" 2 "$F" pr edit 12

# ---- comments and reviews by URL, and gh api ----
cur "Note from me." "" "---" "" "$B" "$BANNER" "" "Earlier." "" "$E"
say "Updated."
want "Note from me." "" "---" "" "$B" "$BANNER" "" "Updated." "" "$E"
run "comment-edit an issue comment" 0 "$F" comment-edit 'https://github.com/o/r/pull/12#issuecomment-99'
called "issue comment endpoint" "api repos/o/r/issues/comments/99 -X PATCH -F body=@"
run "comment-edit a review comment" 0 "$F" comment-edit 'https://github.com/o/r/pull/12#discussion_r77'
called "review comment endpoint" "api repos/o/r/pulls/comments/77 -X PATCH"
run "comment-edit a review" 0 "$F" comment-edit 'https://github.com/o/r/pull/12#pullrequestreview-55'
called "review endpoint" "api repos/o/r/pulls/12/reviews/55 -X PUT"
run "comment-edit a bad URL" 2 "$F" comment-edit 'https://github.com/o/r/pull/12'

cur ""
want "$B" "$BANNER" "" "Updated." "" "$E"
run "api POST, a reply" 0 "$F" api 'repos/{owner}/{repo}/pulls/12/comments/77/replies'
called "api POST" "api repos/{owner}/{repo}/pulls/12/comments/77/replies -X POST -F body=@"
run "api with a body field" 2 "$F" api repos/o/r/issues/1/comments -f body=hi
run "api --input" 2 "$F" api repos/o/r/issues/1/comments --input x.json
run "api GET" 2 "$F" api repos/o/r/issues/1/comments -X GET

# ---- outside a sandbox ----
cur ""
say "Hi."
want "<!-- claude:begin id=laptop -->" "🤖 [Claude Code](https://claude.com/claude-code) · Opus 5.5 · high" "" "Hi." "" "<!-- claude:end id=laptop -->"
IS_SANDBOX= HOSTNAME=laptop.lan run "host: id is the hostname, no sandbox part" 0 "$F" pr comment 1

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
