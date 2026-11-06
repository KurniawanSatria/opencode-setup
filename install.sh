#!/usr/bin/env bash
# OpenCode one-command installer. Interactive; safe to pipe.
#   curl -fsSL https://raw.githubusercontent.com/KurniawanSatria/opencode-setup/main/install.sh | bash
set -euo pipefail

DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
PORT=4096

say() { printf '\033[1m%s\033[0m\n' "$*"; }

ask() { # ask <prompt> <default> -> prints answer (prompt goes to the terminal)
  local prompt="$1" default="${2:-}" answer=""
  if [ -r /dev/tty ] && [ -t 0 ]; then
    printf '%s' "$prompt" > /dev/tty 2>/dev/null
    IFS= read -r answer < /dev/tty 2>/dev/null || answer=""
  else
    printf '%s' "$prompt" >&2
    IFS= read -r answer || answer=""
  fi
  printf '%s' "${answer:-$default}"
}

yes_no() { # yes_no <prompt> <default y|n> -> 0 if yes
  local a
  a=$(ask "$1 " "$2")
  case "$a" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# 1. Install OpenCode if missing, then make sure the shell can find it later
find_opencode() {
  command -v opencode 2>/dev/null && return 0
  for c in "$HOME/.opencode/bin/opencode" "/usr/local/bin/opencode" "$HOME/.local/bin/opencode"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

if ! BIN=$(find_opencode); then
  say "OpenCode not found. Installing..."
  curl -fsSL https://opencode.ai/install | bash || {
    say "Install failed. Install manually: https://opencode.ai/v2/docs/cli"
    exit 1
  }
  BIN=$(find_opencode) || { say "Installed, but binary still not found. Open a new shell and re-run."; exit 1; }
  say "Installed: $BIN"
fi
say "OpenCode: $($BIN --version 2>/dev/null || echo installed)"

# PATH persistence: only touch shell rc files if the bin dir is not already on PATH
bin_dir=$(dirname "$BIN")
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      [ -e "$rc" ] || continue
      grep -qxF "export PATH=\"$bin_dir:\$PATH\"" "$rc" 2>/dev/null && continue
      printf '\n# opencode\nexport PATH="%s:$PATH"\n' "$bin_dir" >> "$rc"
      say "Added $bin_dir to PATH in $rc"
    done
    export PATH="$bin_dir:$PATH"
    ;;
esac

# 2. Questions
say ""
say "A few questions (Enter = default)."
SERVICE=no; yes_no "Run OpenCode as a systemd service (headless web/API)?" n && SERVICE=yes

DOMAIN=""
if [ "$SERVICE" = yes ]; then
  DOMAIN=$(ask "Domain for HTTPS (blank = localhost only): " "")
fi

ROUTER=no; yes_no "Do you have a 9Router instance?" n && ROUTER=yes
ROUTER_URL=""; ROUTER_KEY=""; MODEL=""
if [ "$ROUTER" = yes ]; then
  ROUTER_URL=$(ask "  9Router base URL: " "http://127.0.0.1:20128/v1")
  ROUTER_KEY=$(ask "  9Router API key (blank = read env 9ROUTER_API_KEY): " "")
  MODEL=$(ask "  Model ID: " "Coding")
fi

# 3. Config
mkdir -p "$DEST"
cfg="$DEST/opencode.json"
if [ "$ROUTER" = yes ]; then
  if [ -n "$ROUTER_KEY" ]; then keyjson="$ROUTER_KEY"; else keyjson='{env:9ROUTER_API_KEY}'; fi
  cat > "$cfg" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "9router/$MODEL",
  "providers": {
    "9router": {
      "name": "9Router",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "$ROUTER_URL",
        "apiKey": "$keyjson"
      },
      "models": {
        "$MODEL": { "name": "$MODEL", "modelID": "$MODEL" }
      }
    }
  }
}
EOF
else
  cat > "$cfg" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
fi
say "Config written: $cfg"

# 4. systemd
if [ "$SERVICE" = yes ]; then
  unit=/etc/systemd/system/opencode.service
  sudo=""; [ "$(id -u)" -ne 0 ] && sudo="sudo"
  PW=$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 20)
  $sudo tee "$unit" >/dev/null <<EOF
[Unit]
Description=OpenCode server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(id -un)
WorkingDirectory=$HOME
Environment=HOME=$HOME
Environment=PATH=$PATH
Environment=OPENCODE_SERVER_PASSWORD=$PW
ExecStart=$BIN serve --hostname 127.0.0.1 --port $PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  $sudo systemctl daemon-reload
  $sudo systemctl enable --now opencode
  say "Service: systemctl status opencode  (127.0.0.1:$PORT)"
  say "Server password: $PW   (saved in $unit)"
fi

# 5. nginx + TLS
if [ -n "$DOMAIN" ]; then
  if ! command -v nginx >/dev/null; then
    say "nginx not found. Install nginx and proxy $DOMAIN -> 127.0.0.1:$PORT yourself."
  else
    sudo=""; [ "$(id -u)" -ne 0 ] && sudo="sudo"
    $sudo tee "/etc/nginx/sites-available/opencode" >/dev/null <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  location / {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_read_timeout 3600s;
  }
}
EOF
    $sudo ln -sf /etc/nginx/sites-available/opencode /etc/nginx/sites-enabled/opencode
    $sudo nginx -t && $sudo systemctl reload nginx
    say "nginx: http://$DOMAIN"
    if command -v certbot >/dev/null; then
      say "Requesting TLS certificate..."
      $sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --redirect || \
        say "certbot failed; run: sudo certbot --nginx -d $DOMAIN"
    else
      say "certbot not installed: sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d $DOMAIN"
    fi
  fi
fi

say ""
say "Done. Pair a client with: opencode api post /api/pair"
[ -n "$DOMAIN" ] && say "Then open https://$DOMAIN"
