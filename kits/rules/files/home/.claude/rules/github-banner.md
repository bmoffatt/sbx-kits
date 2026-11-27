## GitHub Banner

Text you publish to GitHub on the user's behalf (PR and issue descriptions, comments, reviews, replies, and edits to any of them) goes through `~/.claude/bin/gh-claude`, not `gh` directly. Write only your own text to a file (no banner, no markers), then run gh-claude with that file and a gh command:

```
~/.claude/bin/gh-claude FILE pr create --title "..." --draft
~/.claude/bin/gh-claude FILE pr|issue comment 12
~/.claude/bin/gh-claude FILE pr review 12 --comment|--approve|--request-changes
~/.claude/bin/gh-claude FILE pr|issue edit 12                     # the description
~/.claude/bin/gh-claude FILE comment-edit <comment or review URL>
~/.claude/bin/gh-claude FILE api repos/{owner}/{repo}/pulls/12/comments/34/replies
```

- gh-claude puts your text in a block that belongs to this sandbox, headed by a banner with your model, effort and sandbox name, and hidden `<!-- claude:begin/end -->` markers around it. Don't write the banner or the markers yourself.
- An edit replaces only this sandbox's block, or adds one after a `---` rule. Everything else is kept exactly: the user's own words (they often write above a `---`), other sandboxes' blocks, and older text without markers.
- You can't change anyone else's text, even when the user asks. Give them the new text to copy and paste instead.
- If gh-claude reports a damaged or duplicated block, don't work around it: tell the user and give them the full text to paste.
- A `PreToolUse` hook blocks `gh` commands that post or edit text directly. Commit messages and body-less actions (`gh pr review --approve`, labels, merges) are out of scope. MCP GitHub tools aren't hooked; don't use them to publish text.
