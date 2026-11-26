# sbx-kits

Monorepo of sbx (Docker Sandboxes) kits. Each kit is a directory under `kits/` and is also a Claude Code plugin; the top-level `.claude-plugin/marketplace.json` lists them, one plugin per kit, by name.

## Layout of a kit (`kits/<name>/`)

- `sbx-<name>.yaml` + `sbx-<name>.dockerfile`: the v3 sbx kit. The build context is this directory. `version:` is the published tag, so bump it when the kit's content or declarations change.
- `files/home/`: the tree overlaid onto `/home/agent/` in the sandbox, and read by the plugin's sync script.
- `.claude-plugin/plugin.json`, `hooks/hooks.json`, `scripts/sync.sh`: the host plugin (`${CLAUDE_PLUGIN_ROOT}` is the kit directory).
- `.dockerignore`: keeps the plugin files and README out of the kit image.
- `README.md`.

## Adding a kit

1. Create `kits/<name>/` as above, named `sbx-<name>` (the Docker Hub repo is `sbx-<name>`).
2. Add it to the `matrix.kit` list in `.github/workflows/publish.yml`.
3. Add a plugin entry to `.claude-plugin/marketplace.json` (`"source": "./kits/<name>"`) and a row to the README table.

## Checking changes

- Plugins and marketplace: `claude plugin validate .` and `claude plugin validate kits/<name>`.
- Kit tests: `kits/<name>/tests/*.test.sh` (CI runs them before building the kit).
- Kit build (no push): `docker buildx build kits/<name> -f kits/<name>/sbx-<name>.yaml --platform linux/amd64,linux/arm64 --provenance=mode=min --output type=cacheonly`, using a `docker-container` builder. `sbx kit validate --offline` can't check v3 source kits.
- A kit and its plugin must ship the same files; keep `sync.sh` in step with the kit's install hook.
