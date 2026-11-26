## sbx-rules

Part of [`bmoffatt/sbx-kits`](https://github.com/bmoffatt/sbx-kits). Claude rules, installed into `~/.claude/rules/`. It ships two ways, both using the same files:

- [Claude Code plugin](#claude-code-plugin-host) for Claude Code running directly on your machine
- [sbx kit](#sbx-claude-sandbox-kit) for Docker sandboxes

| Rule | What it does |
| --- | --- |
| `collaborative-editing` | Re-read files before editing and prefer small targeted edits, since the user or other agents may be editing the same files concurrently. |
| `github-banner` | Put Claude's text on GitHub (PR descriptions, comments, review and issue bodies, and edits) in sections headed by a banner with the model, effort and sandbox, and leave the user's own text alone. |

### The banner hook

`github-banner` is backed by a `PreToolUse` hook (`files/home/.claude/hooks/require-github-banner.sh`). Claude's text goes in sections that start with a banner line:

```
🤖 [Claude Code](https://claude.com/claude-code) · Opus 5.5 · high effort · sandbox my-project
```

The model comes from the session transcript, the effort from the hook input, and the sandbox name from the hostname when `IS_SANDBOX=1`. A section runs from its banner to the end, or to a `---` rule not followed by another banner, so you can write your own words above a `---` and Claude's edits keep them.

The hook checks `gh pr|issue create|comment`, `gh pr|issue edit` and `gh pr review` with a body, `--edit-last`, and `gh api` POST/PATCH/PUT on comments, reviews, pulls or issues:

- the text must come from a file (`--body-file`, `-F body=@file`, `--input`) written in an earlier step, so the hook sees what gh will post
- a new post must open with the banner
- for an edit it fetches the current text and rejects any change outside Claude's sections, and any new or changed section without the current banner
- if it can't fetch the current text, the edit is blocked (fail closed)

It ignores the stock `🤖 Generated with [Claude Code](...)` line. It does not cover MCP GitHub tools (the rule does) or commit messages. In the plugin it is registered through `hooks/hooks.json`; in the sbx kit an install hook merges it into `~/.claude/settings.json`. Tests: `bash kits/rules/tests/require-github-banner.test.sh` (needs `jq`; `gh` is faked).

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
