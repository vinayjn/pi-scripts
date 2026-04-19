#!/bin/bash
# Set qBittorrent WebUI username/password from .env via the qBittorrent API.
# Must be run after `docker compose up -d`.

set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "Error: .env not found. Copy .env.example to .env and fill it in first."
    exit 1
fi

# shellcheck disable=SC1091
set -a; . ./.env; set +a

: "${QBT_USER:?QBT_USER not set in .env}"
: "${QBT_PASS:?QBT_PASS not set in .env}"

WEBUI="http://localhost:8080"

echo "Waiting for qBittorrent WebUI..."
for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "$WEBUI"; then
        break
    fi
    sleep 2
done

TEMP_PASS=$(docker compose logs qbittorrent 2>&1 \
    | grep -oE 'temporary password[^:]*: ?[^[:space:]]+' \
    | awk '{print $NF}' \
    | tail -1)

if [ -z "$TEMP_PASS" ]; then
    echo "Could not find temporary password in logs — WebUI may already be configured."
    echo "If you forgot the password, delete ./qbittorrent/qBittorrent/qBittorrent.conf and restart the stack."
    exit 1
fi

echo "Logging in with temporary password..."
COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

LOGIN=$(curl -s -c "$COOKIE_JAR" \
    --data-urlencode "username=admin" \
    --data-urlencode "password=$TEMP_PASS" \
    "$WEBUI/api/v2/auth/login")

if [ "$LOGIN" != "Ok." ]; then
    echo "Login failed: $LOGIN"
    exit 1
fi

echo "Setting new WebUI username and password..."
JSON=$(printf '{"web_ui_username":"%s","web_ui_password":"%s"}' "$QBT_USER" "$QBT_PASS")
curl -s -b "$COOKIE_JAR" \
    --data-urlencode "json=$JSON" \
    "$WEBUI/api/v2/app/setPreferences"

echo
echo "Done. Log in at $WEBUI with $QBT_USER / <your QBT_PASS>."
