## sbx-rules

Part of [`bmoffatt/sbx-kits`](https://github.com/bmoffatt/sbx-kits). Claude rules, installed into `~/.claude/rules/`. It ships two ways, both using the same files:

- [Claude Code plugin](#claude-code-plugin-host) for Claude Code running directly on your machine
- [sbx kit](#sbx-claude-sandbox-kit) for Docker sandboxes

| Rule | What it does |
| --- | --- |
| `collaborative-editing` | Re-read files before editing and prefer small targeted edits, since the user or other agents may be editing the same files concurrently. |
| `github-banner` | Publish Claude's text on GitHub (PR descriptions, comments, reviews, and edits) through `gh-claude`, in a block headed by a banner with the model, effort and sandbox, and never touch the user's own text. |

### gh-claude and the banner hook

Claude publishes to GitHub through `gh-claude` (`files/home/.claude/bin/gh-claude`, installed as `~/.claude/bin/gh-claude`). Claude writes only its own text to a file; gh-claude wraps it in a block owned by the sandbox and publishes it:

```
<!-- claude:begin id=my-project -->
🤖 [Claude Code](https://claude.com/claude-code) · Opus 5.5 · high effort · sandbox my-project

Claude's text.

<!-- claude:end id=my-project -->
```

The markers are HTML comments, so GitHub shows only the banner and the text. The model comes from the session transcript, the effort from `CLAUDE_EFFORT`, and the name from the hostname (labelled `sandbox` when `IS_SANDBOX=1`).

- **New posts** (`pr create`, `pr|issue comment`, `pr review`, `api` POST) are just the block.
- **Edits** (`pr|issue edit`, `comment-edit <URL>`, `api` PATCH/PUT) fetch the current text, replace this sandbox's block where it is, or append one after a `---` (reusing yours if the text already ends with one). Every other line passes through byte for byte. So you can write your own words above or below Claude's block, and other sandboxes' blocks are left alone.
- **Ownership is the block id**, the sandbox name, not the banner text. A new model or effort just updates the banner. A recreated sandbox with the same name keeps its block, and one with a new name adds its own.
- **Damaged blocks** (a missing or duplicated marker) are refused, and Claude gives you the text to paste instead. Claude never edits text outside its block; when you ask it to, it hands you copy-paste.

A `PreToolUse` hook (`files/home/.claude/hooks/require-github-banner.sh`) blocks `gh` commands that would post or edit text directly (`gh pr|issue create|comment`, `edit` and `pr review` with a body, `gh api` with a body) and tells Claude to use gh-claude. Text in quotes and heredocs is ignored, so writing a file that mentions those commands is fine. It keeps Claude consistent; it isn't a security boundary: `curl`, scripts and MCP GitHub tools can still post. In the plugin the hook is registered through `hooks/hooks.json` and `scripts/sync.sh` copies gh-claude to `~/.claude/bin/`; in the sbx kit the overlay ships both and an install hook merges the hook into `~/.claude/settings.json`.

Tests: `bash kits/rules/tests/gh-claude.test.sh` and `bash kits/rules/tests/require-github-banner.test.sh` (need `jq`; `gh` is faked).

### Claude Code plugin (host)

``` text
/plugin marketplace add bmoffatt/sbx-kits
/plugin install sbx-rules@sbx-kits
```

A plugin can't ship rules, so the plugin ships a `SessionStart` hook (`scripts/sync.sh`) that copies `files/home/.claude/rules/*.md` into `~/.claude/rules/` every session. It overwrites same-named files, so local edits to those are reverted. To remove it, uninstall the plugin and delete the copied files from `~/.claude/rules/`.

### sbx Claude sandbox kit

It is a [v3 kit](https://github.com/docker/sandbox-kit-spec) (`sbx-rules.yaml` plus `sbx-rules.dockerfile`), so it composes with the v3 `claude` kit and with `sbx-statusline`, but **not** with v1/v2 kits: sbx rejects a sandbox that mixes the two formats. It requires the `claude` kit and `jq`.

``` sh
sbx run claude --kit docker.io/bmoffatt/sbx-rules:latest --name my-project
```

`docker.io/` is on sbx's default kit allowlist, so no setup is needed. A push to `main` that changes this directory republishes `:latest` to [Docker Hub](https://hub.docker.com/r/bmoffatt/sbx-rules), along with a tag for the `version:` in `sbx-rules.yaml`. Bump `version:` when the kit changes. `--kit` applies only when the sandbox is created, so an existing sandbox must be removed (`sbx rm`) and recreated to pick it up.

#### From a local checkout or git

``` sh
sbx run claude --kit ./kits/rules --name my-project
```

sbx only installs git kits from allowlisted sources. Allow this account first (this replaces the list, so keep `docker.io/`):

``` sh
sbx settings set kit.allowedSources '["docker.io/","github.com/bmoffatt/"]'
sbx run claude --kit 'git+https://github.com/bmoffatt/sbx-kits.git#dir=kits/rules' --name my-project
```
