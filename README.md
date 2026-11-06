# opencode-setup

One-command installer for OpenCode V2 on a fresh Linux box, with optional systemd service, nginx + TLS, and 9Router.

```sh
curl -fsSL https://raw.githubusercontent.com/KurniawanSatria/opencode-setup/main/install.sh | bash
```

The script asks, with sane defaults (press Enter to skip):

| Question | Default | What it does |
|---|---|---|
| Run as a systemd service? | no | creates `opencode.service`, `127.0.0.1:4096`, generates `OPENCODE_SERVER_PASSWORD` |
| Domain for HTTPS? | blank | nginx reverse proxy + `certbot --nginx` (only if service = yes) |
| Do you have 9Router? | no | writes a `9router` provider block with your base URL, key and model ID |

Without 9Router it writes a minimal config and you pick a provider later with `opencode auth login`.

## Notes

- Service binds to `127.0.0.1`; expose it through nginx, never directly.
- The server password is printed once and stored in the unit file. API clients authenticate with it; `opencode api post /api/pair` creates a pairing code.
- 9Router key left blank is written as `{env:9ROUTER_API_KEY}`, so no secret lands in the config file.
- `certbot` is not installed by this script; it tells you the apt command if missing.
- Idempotent: re-running overwrites the config and the unit, and reloads systemd/nginx.
