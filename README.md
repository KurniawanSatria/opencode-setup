# opencode-setup

One-command installer for OpenCode V2 on a fresh Linux box: optional systemd service, nginx + TLS, 9Router provider, global `AGENTS.md`, all Anthropic skills, and two plugins.

```sh
curl -fsSL https://raw.githubusercontent.com/KurniawanSatria/opencode-setup/main/install.sh | bash
```

Press Enter to accept the default on every question.

| Question | Default | What it does |
|---|---|---|
| Install all 19 Anthropic skills? | **yes** | downloads `anthropics/skills` and copies every skill to `~/.config/opencode/skills` |
| Install global AGENTS.md? | **yes** | coding guidelines at `~/.config/opencode/AGENTS.md` |
| Do you have 9Router? | no | writes a `9router` provider with base URL, key, model ID |
| Run as systemd service? | no | `opencode.service` on `127.0.0.1:4096` with a generated `OPENCODE_SERVER_PASSWORD` |
| Domain for HTTPS? | blank | nginx reverse proxy + `certbot --nginx` (only if service = yes) |

OpenCode itself is installed first if `opencode` is not found, and its bin directory is appended to `~/.bashrc` / `~/.zshrc` so later shells find it.

## Bundled

- **Plugins** (auto-enabled in `opencode.json`): [`@dietrichgebert/ponytail`](https://www.npmjs.com/package/@dietrichgebert/ponytail) and [`opencode-mem`](https://www.npmjs.com/package/opencode-mem). npm installs them on first start.
- **Skills**: fetched live from [`anthropics/skills`](https://github.com/anthropics/skills) at install time, with their `LICENSE.txt` files intact. Nothing is vendored here.
- **AGENTS.md**: profile-independent coding guidelines in [`AGENTS.md`](./AGENTS.md).

## Notes

- Service binds to `127.0.0.1`; expose it through nginx, never directly. Without `OPENCODE_SERVER_PASSWORD` the V2 API is unauthenticated, including file reads and shell execution.
- The server password is printed once and stored in the unit file. Pair clients with `opencode api post /api/pair`.
- A blank 9Router key is written as `{env:9ROUTER_API_KEY}`, so no secret lands in the config file.
- `certbot` is not installed by this script; it prints the apt command if missing.
- Re-running is safe: it overwrites the config, `AGENTS.md`, the systemd unit and the nginx site, then reloads systemd/nginx.
