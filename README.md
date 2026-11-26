# sbx-kits

My [sbx](https://docs.docker.com/ai/sandboxes/) (Docker Sandboxes) kits, one directory each under `kits/`. Every kit ships two ways from the same files: an sbx kit published to Docker Hub, and a Claude Code plugin from this repo's marketplace for Claude Code on the host.

| Kit | What it does | sbx kit | Claude Code plugin |
| --- | --- | --- | --- |
| [`statusline`](kits/statusline) | Statusline: directory, git branch, model, context window, cost, 5h/7d rate-limit gauges | `docker.io/bmoffatt/sbx-statusline` | `sbx-statusline` |
| [`rules`](kits/rules) | Claude rules in `~/.claude/rules/` | `docker.io/bmoffatt/sbx-rules` | `sbx-rules` |

## Use

In a sandbox (v3 kits compose with each other; sbx rejects a mix of v1/v2 and v3):

``` sh
sbx run claude --kit docker.io/bmoffatt/sbx-statusline:latest --kit docker.io/bmoffatt/sbx-rules:latest --name my-project
```

On the host:

``` text
/plugin marketplace add bmoffatt/sbx-kits
/plugin install sbx-statusline@sbx-kits
/plugin install sbx-rules@sbx-kits
```

Each kit's README has the details.

### If you installed the plugin from `bmoffatt/sbx-statusline`

The repo was renamed to `sbx-kits` and the marketplace with it. Move over once:

``` text
/plugin uninstall sbx-statusline@sbx-statusline
/plugin marketplace remove sbx-statusline
/plugin marketplace add bmoffatt/sbx-kits
/plugin install sbx-statusline@sbx-kits
```

The Docker Hub image names are unchanged.

## Publishing

`.github/workflows/publish.yml` builds every kit on pull requests, and on a push to `main` publishes the kits whose directory changed: `:latest` plus the `version:` from the kit's descriptor. It needs the `DOCKERHUB_USERNAME` variable and `DOCKERHUB_TOKEN` secret on this repo. See [CLAUDE.md](CLAUDE.md) for the layout and how to add a kit.
