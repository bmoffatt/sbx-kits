## sbx-rules

Part of [`bmoffatt/sbx-kits`](https://github.com/bmoffatt/sbx-kits). Claude rules, installed into `~/.claude/rules/`. It ships two ways, both using the same files:

- [Claude Code plugin](#claude-code-plugin-host) for Claude Code running directly on your machine
- [sbx kit](#sbx-claude-sandbox-kit) for Docker sandboxes

| Rule | What it does |
| --- | --- |
| `collaborative-editing` | Re-read files before editing and prefer small targeted edits, since the user or other agents may be editing the same files concurrently. |

### Claude Code plugin (host)

``` text
/plugin marketplace add bmoffatt/sbx-kits
/plugin install sbx-rules@sbx-kits
```

A plugin can't ship rules, so the plugin ships a `SessionStart` hook (`scripts/sync.sh`) that copies `files/home/.claude/rules/*.md` into `~/.claude/rules/` every session. It overwrites same-named files, so local edits to those are reverted. To remove it, uninstall the plugin and delete the copied files from `~/.claude/rules/`.

### sbx Claude sandbox kit

It is a [v3 kit](https://github.com/docker/sandbox-kit-spec) (`sbx-rules.yaml` plus `sbx-rules.dockerfile`), so it composes with the v3 `claude` kit and with `sbx-statusline`, but **not** with v1/v2 kits: sbx rejects a sandbox that mixes the two formats. It requires the `claude` kit.

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
