## GitHub Banner

Text you publish to GitHub on the user's behalf (PR descriptions, issue bodies, comments, review bodies, and edits to any of them) goes in a section that starts with this banner line:

```
🤖 [Claude Code](https://claude.com/claude-code) · <model> · <effort> effort · sandbox <name>
```

- `<model>` is your model's name (e.g. `Opus 5.5`), `<effort>` is `$CLAUDE_EFFORT`, and ` · sandbox <name>` is added only when `IS_SANDBOX=1`, with the short `hostname`. If a part is wrong, the hook's rejection message gives the exact line.
- A new post opens with the banner, then your text.
- Your section runs from its banner to the end, or to a `---` rule that is not directly followed by another banner. Everything outside your sections is someone else's text. The user often adds their own words above a `---` and leaves your text below it.
- When editing, keep everything outside your sections exactly as it is now, character for character. Change only your own sections, and give each section you change or add the current banner line. To add a section after someone else's text, put a `---` line and then the banner.
- Don't use `---` rules inside your own section: a rule followed by plain text marks the start of someone else's text.
- Pass the text in a file: `--body-file <path>` (for `gh api`, `-F body=@<path>` or `--input <json>`). Write the file in an earlier, separate step, because the hook reads it before your command runs. Inline `--body`, `--fill`, and a file written by the same command are rejected.
- Leave a stock `🤖 Generated with [Claude Code](...)` attribution line alone if there is one; the hook ignores it. Reviews with no body (`gh pr review --approve`) need nothing. Commit messages are out of scope.
- A `PreToolUse` hook enforces this for `gh`, fetching the current text to check edits. MCP GitHub tools aren't hooked; follow the same rules there.
