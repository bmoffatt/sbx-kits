#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) for the github-banner rule (rules/github-banner.md).
#
# Text Claude publishes to GitHub with `gh` must come from a file, and every part
# of it Claude wrote must sit in a section headed by this session's banner:
#
#   🤖 [Claude Code](https://claude.com/claude-code) · Opus 5.5 · high effort · sandbox my-project
#
# A section runs from a banner line to the next horizontal rule (---) that is not
# itself followed by a banner, or to the end. Everything else is someone else's
# text: typically the user writes above a --- and leaves Claude's text below it.
#
# For an edit the current body is fetched from GitHub, and the edit passes when
#   - text outside banner sections is unchanged (blank lines aside), and
#   - every new or changed section starts with this session's banner.
# A new post is the same check against an empty body, so it opens with the banner.
# The stock "🤖 Generated with [Claude Code](...)" attribution line is ignored.
#
# Exit 2 blocks the call and sends stderr back to Claude; exit 0 allows it.
# Written for bash 3.2 as well (macOS hosts run the plugin form).
set -u

BASE='🤖 [Claude Code](https://claude.com/claude-code)'

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$cmd" ] || exit 0
# Cheap pre-filter before any parsing: no `gh` word, nothing to check.
[[ $cmd =~ (^|[^[:alnum:]_.-])gh[[:space:]] ]] || exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
effort=$(jq -r '.effort.level // empty' <<<"$input")
effort=${effort:-${CLAUDE_EFFORT:-}}

deny() {
  printf 'Blocked by the github-banner hook: %s\n' "$1" >&2
  exit 2
}

# ---- this session's banner ---------------------------------------------------
# Hooks get no model field; the transcript's latest assistant entry has its ID.
model_id=""
if [ -f "$transcript" ]; then
  model_id=$(tail -n 500 "$transcript" 2>/dev/null |
    jq -r 'select(.type == "assistant") | .message.model // empty' 2>/dev/null | tail -n 1)
fi
# claude-opus-5-5 -> Opus 5.5, claude-haiku-4-5-20251001 -> Haiku 4.5
model=""
if [[ $model_id =~ ^claude-([a-z]+)-([0-9]+)(-([0-9]{1,2}))?(-[0-9]{8})?$ ]]; then
  fam=${BASH_REMATCH[1]}
  model="$(printf '%s' "${fam:0:1}" | tr '[:lower:]' '[:upper:]')${fam:1} ${BASH_REMATCH[2]}"
  [ -n "${BASH_REMATCH[4]}" ] && model+=".${BASH_REMATCH[4]}"
elif [ -n "$model_id" ]; then
  model=$model_id
fi
sandbox=""
if [ "${IS_SANDBOX:-}" = 1 ]; then
  sandbox=${HOSTNAME:-$(hostname 2>/dev/null)}
  sandbox=${sandbox%%.*}
fi

banner=$BASE
parts=()
[ -n "$model" ] && { banner+=" · $model"; parts+=(" · $model"); }
[ -n "$effort" ] && { banner+=" · $effort effort"; parts+=(" · $effort effort"); }
[ -n "$sandbox" ] && { banner+=" · sandbox $sandbox"; parts+=(" · sandbox $sandbox"); }
# A banner passes when it starts with BASE and carries every part known here, so
# a part the hook could not determine is not required.
required=$(printf '%s\n' ${parts[@]+"${parts[@]}"} | jq -R . | jq -s 'map(select(. != ""))')

# ---- split the command into words -------------------------------------------
# '...', "..." and \ quoting, no expansion. Unquoted ; & | ( ) and newlines become
# a lone $'\x1e' word, so each simple command can be checked on its own. LC_ALL=C
# keeps ${s:i:1} byte-indexed, which matters for long commands.
tokenize() {
  local LC_ALL=C s=$1 n=${#1} i=0 c w="" inw=0 q=""
  TOKENS=()
  while [ $i -lt $n ]; do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then
        q=""
      elif [ "$q" = '"' ] && [ "$c" = '\' ] && [ $((i + 1)) -lt $n ]; then
        i=$((i + 1))
        w+=${s:i:1}
      else
        w+=$c
      fi
    else
      case $c in
        "'" | '"') q=$c; inw=1 ;;
        '\') i=$((i + 1)); w+=${s:i:1}; inw=1 ;;
        ' ' | $'\t')
          if [ $inw = 1 ]; then TOKENS+=("$w"); w=""; inw=0; fi ;;
        ';' | '&' | '|' | '(' | ')' | $'\n')
          if [ $inw = 1 ]; then TOKENS+=("$w"); w=""; inw=0; fi
          TOKENS+=($'\x1e') ;;
        *) w+=$c; inw=1 ;;
      esac
    fi
    i=$((i + 1))
  done
  if [ $inw = 1 ]; then TOKENS+=("$w"); fi
}

# ---- the body and what it replaces --------------------------------------------
# Sets BODY from a --body-file path, refusing cases where the hook would read
# something other than what gh will post.
read_body_file() {
  local raw=$1 f
  [ "$raw" = - ] && deny "read the text from a file, not stdin (--body-file -), so it can be checked."
  case $raw in
    /*) f=$raw ;;
    '~/'*) f=$HOME/${raw#'~/'} ;;
    *) f=${cwd:-.}/$raw ;;
  esac
  [ -f "$f" ] || deny "body file $raw not found. Write it in an earlier, separate step, then run the gh command."
  # Written by this same command? The hook runs first, so it would see stale text.
  local rest=$cmd seen=0
  while [[ $rest == *"$raw"* ]]; do
    seen=$((seen + 1))
    rest=${rest#*"$raw"}
  done
  if [ $seen -gt 1 ]; then
    deny "write $raw in an earlier, separate step: this hook reads it before the command runs, so a file written by the same command is checked stale."
  fi
  BODY=$(cat "$f"; printf x)
  BODY=${BODY%x}
}

# Runs gh from the session's directory, so {owner}/{repo} and the current branch
# resolve as they will for the command itself.
gh_in_cwd() {
  (cd "${cwd:-.}" 2>/dev/null; gh "$@" 2>/dev/null)
}

# ---- the check ------------------------------------------------------------------
# $1 = old body ("" for a new post), $2 = new body, $3 = new|edit
check_body() {
  local result reason line
  result=$(jq -n -c --arg old "$1" --arg new "$2" --arg base "$BASE" --argjson req "$required" '
    def is_blank: test("^\\s*$");
    def is_stock: test("^\\s*🤖 Generated with \\[Claude Code\\]\\(https://claude\\.com/claude-code\\)\\s*$");
    def is_banner: startswith($base);
    def is_hr: test("^ {0,3}([-*_])( *\\1){2,} *$");
    def parse:
      (split("\n") | map(sub("\r$"; ""))) as $l
      | reduce range(0; $l | length) as $i ({human: [], sections: [], in: false};
          $l[$i] as $x
          | if ($x | is_blank) or ($x | is_stock) then .
            elif ($x | is_banner) then .in = true | .sections += [[$x]]
            elif ($x | is_hr) then
              ([$l[($i + 1):][] | select((is_blank or is_stock) | not)] | first // "") as $next
              | if ($next | is_banner) then . else .in = false | .human += [$x] end
            elif .in then .sections[-1] += [$x]
            else .human += [$x] end);
    ($old | parse) as $o | ($new | parse) as $n
    | if $o.human != $n.human then
        ([range(0; [($o.human | length), ($n.human | length)] | max)]
          | map(select($o.human[.] != $n.human[.])) | first) as $i
        | {ok: false, reason: "human",
           line: (if $i < ($o.human | length) then $o.human[$i] else "(added) " + $n.human[$i] end)}
      else
        [$n.sections[] | select(. as $s | any($o.sections[]; . == $s) | not)]
        | map(.[0]) | map(select(. as $b | all($req[]; . as $p | $b | contains($p)) | not))
        | if length > 0 then {ok: false, reason: "banner", line: .[0]} else {ok: true} end
      end')
  [ "$(jq -r .ok <<<"$result")" = true ] && return 0
  reason=$(jq -r .reason <<<"$result")
  line=$(jq -r .line <<<"$result")
  if [ "$reason" = banner ]; then
    deny "each section you add or change must start with this session's banner line, exactly:
$banner
Found: $line"
  elif [ "$3" = new ]; then
    deny "a new post must open with the banner line, then your text. Use exactly:
$banner
First line outside a banner section: $line
(Don't use --- rules inside your section: a rule followed by plain text marks someone else's text.)"
  else
    deny "this edit changes text outside your banner sections. Text before a banner, or after a --- rule that isn't followed by one, belongs to someone else (often the user, who writes above a ---): keep it exactly as it is now. Put your text in a section that starts with:
$banner
First difference: $line"
  fi
}

# ---- gh pr|issue ... ------------------------------------------------------------
check_pr_issue() {
  local group=$1 sub=$2 body_file="" inline="" repo="" target="" edit_last=0 a mode old
  shift 2
  case "$group $sub" in
    "pr create" | "issue create" | "pr comment" | "issue comment" | "pr review" | "pr edit" | "issue edit") ;;
    *) return 0 ;;
  esac
  while [ $# -gt 0 ]; do
    a=$1
    shift
    case $a in
      --body-file | -F) body_file=${1:-}; [ $# -gt 0 ] && shift ;;
      --body-file=*) body_file=${a#*=} ;;
      -b | --body) inline=1; [ $# -gt 0 ] && shift ;;
      --body=* | -b?*) inline=1 ;;
      --fill | --fill-first | --fill-verbose | -f) inline=1 ;;
      -R | --repo) repo=${1:-}; [ $# -gt 0 ] && shift ;;
      --repo=*) repo=${a#*=} ;;
      --edit-last) edit_last=1 ;;
      *)
        if [ -z "$target" ] && [[ $a =~ ^([0-9]+|https://github\.com/[^/]+/[^/]+/(pull|issues)/[0-9]+)$ ]]; then
          target=$a
        fi ;;
    esac
  done
  case "$group $sub" in
    *edit | "pr review")
      # label edits and body-less approvals publish no text
      [ -z "$body_file" ] && [ -z "$inline" ] && return 0 ;;
  esac
  mode=new
  case "$group $sub" in *edit) mode=edit ;; esac
  [ "$edit_last" = 1 ] && mode=edit
  [ -n "$inline" ] && deny "pass the text with --body-file <path>, written in an earlier step, not --body or --fill, so it can be checked."
  [ -n "$body_file" ] || deny "gh $group $sub needs --body-file <path> (written in an earlier step) so the text can be checked."
  read_body_file "$body_file"
  old=""
  if [ "$mode" = edit ]; then
    local rflag
    rflag=()
    [ -n "$repo" ] && rflag=(-R "$repo")
    if [ "$edit_last" = 1 ]; then
      local me
      me=$(gh_in_cwd api user --jq .login) || deny "couldn't read your GitHub login to check the edit. Retry, or check gh auth."
      old=$(gh_in_cwd "$group" view $target ${rflag[@]+"${rflag[@]}"} --json comments \
        --jq "[.comments[] | select(.author.login == \"$me\")] | last | .body // \"\"") ||
        deny "couldn't read the comment you're editing, so the edit can't be checked. Retry."
    else
      old=$(gh_in_cwd "$group" view $target ${rflag[@]+"${rflag[@]}"} --json body --jq '.body // ""') ||
        deny "couldn't read the current body of the $group you're editing, so the edit can't be checked. Retry."
    fi
  fi
  check_body "$old" "$BODY" "$mode"
}

# ---- gh api ... ------------------------------------------------------------------
check_api() {
  local method="" endpoint="" body_file="" inline="" fields=0 input_file="" a v old
  while [ $# -gt 0 ]; do
    a=$1
    shift
    case $a in
      -X | --method) method=${1:-}; [ $# -gt 0 ] && shift ;;
      --method=*) method=${a#*=} ;;
      -X?*) method=${a#-X} ;;
      -F | --field | -f | --raw-field)
        v=${1:-}
        [ $# -gt 0 ] && shift
        fields=1
        case "$a $v" in
          "-F body=@"* | "--field body=@"*) body_file=${v#body=@} ;;
          *" body="*) inline=1 ;;
        esac ;;
      --field=body=@*) fields=1; body_file=${a#--field=body=@} ;;
      --field=body=* | --raw-field=body=*) fields=1; inline=1 ;;
      --field=* | --raw-field=*) fields=1 ;;
      --input) input_file=${1:-}; [ $# -gt 0 ] && shift ;;
      -H | --header | -q | --jq | -t | --template | --hostname | --cache | -p | --preview) [ $# -gt 0 ] && shift ;;
      -*) ;;
      *) [ -z "$endpoint" ] && endpoint=$a ;;
    esac
  done
  if [ -z "$method" ]; then
    if [ "$fields" = 1 ] || [ -n "$input_file" ]; then method=POST; else method=GET; fi
  fi
  method=$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')
  case $method in POST | PATCH | PUT) ;; *) return 0 ;; esac
  [[ $endpoint =~ (comments|reviews|pulls|issues) ]] || return 0
  [ -n "$inline" ] && deny "pass the text as -F body=@<path>, written in an earlier step, not inline, so it can be checked."
  if [ -n "$input_file" ]; then
    [ "$input_file" = - ] && deny "read the JSON from a file, not stdin (--input -), so it can be checked."
    read_body_file "$input_file"
    jq -e 'has("body")' <<<"$BODY" >/dev/null 2>&1 || return 0
    BODY=$(jq -r '.body // ""' <<<"$BODY")
  elif [ -n "$body_file" ]; then
    read_body_file "$body_file"
  else
    return 0 # no text in this call (a state change, a label, ...)
  fi
  old=""
  if [ "$method" != POST ]; then
    old=$(gh_in_cwd api "$endpoint" --jq '.body // ""') ||
      deny "couldn't read the current text at $endpoint, so the edit can't be checked. Retry."
  fi
  if [ "$method" = POST ]; then check_body "" "$BODY" new; else check_body "$old" "$BODY" edit; fi
}

# ---- each simple command in the line -----------------------------------------------
tokenize "$cmd"
TOKENS+=($'\x1e')
seg=()
for t in "${TOKENS[@]}"; do
  if [ "$t" != $'\x1e' ]; then
    seg+=("$t")
    continue
  fi
  if [ ${#seg[@]} -gt 0 ]; then
    j=0
    # skip VAR=value prefixes
    while [ $j -lt ${#seg[@]} ] && [[ ${seg[$j]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do j=$((j + 1)); done
    if [ $j -lt ${#seg[@]} ] && [[ ${seg[$j]} == gh || ${seg[$j]} == */gh ]]; then
      args=("${seg[@]:$((j + 1))}")
      case ${args[0]:-} in
        pr | issue) [ ${#args[@]} -ge 2 ] && check_pr_issue "${args[@]}" ;;
        api) check_api "${args[@]:1}" ;;
      esac
    fi
  fi
  seg=()
done
exit 0
