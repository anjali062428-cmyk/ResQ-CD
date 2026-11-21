#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${1:-}"
if [ -z "$IMAGE_TAG" ]; then
    echo "Usage: $0 <IMAGE_TAG>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared state directory: prefer environment variable, then mounted /deploy, then relative to script
if [ -n "${STATE_DIR:-}" ]; then
    STATE_DIR="$STATE_DIR"
elif [ -d "/deploy/state" ]; then
    STATE_DIR="/deploy/state"
elif [ -d "/c/Users/Dell/Documents/ResQ-CD/deploy/state" ]; then
    STATE_DIR="/c/Users/Dell/Documents/ResQ-CD/deploy/state"
else
    STATE_DIR="$SCRIPT_DIR/state"
fi
mkdir -p "$STATE_DIR"

ACTIVE_COLOR_FILE="$STATE_DIR/active_color"
HISTORY_FILE="$STATE_DIR/history.json"

if [ -n "${UPSTREAM_CONF:-}" ]; then
    UPSTREAM_CONF="$UPSTREAM_CONF"
elif [ -d "/deploy/nginx/active" ]; then
    UPSTREAM_CONF="/deploy/nginx/active/upstream.conf"
elif [ -d "/c/Users/Dell/Documents/ResQ-CD/deploy/nginx/active" ]; then
    UPSTREAM_CONF="/c/Users/Dell/Documents/ResQ-CD/deploy/nginx/active/upstream.conf"
else
    UPSTREAM_CONF="$SCRIPT_DIR/nginx/active/upstream.conf"
fi

START_TIME=$(date +%s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

record_history() {
    local version="$1"
    local color="$2"
    local status="$3"
    local reason="$4"
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local win_history_file="$(cygpath -w "$HISTORY_FILE" 2>/dev/null || echo "$HISTORY_FILE")"

    if command -v python >/dev/null 2>&1; then
        python -c "
import json, os, sys

history_path = sys.argv[1]
entry = {
    'timestamp': sys.argv[2],
    'version': sys.argv[3],
    'color': sys.argv[4],
    'status': sys.argv[5],
    'reason': sys.argv[6],
    'duration_sec': int(sys.argv[7])
}

history = []
if os.path.exists(history_path):
    try:
        with open(history_path, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            if content:
                data = json.loads(content)
                if isinstance(data, list):
                    history = data
    except Exception:
        history = []

history.append(entry)

with open(history_path, 'w', encoding='utf-8') as f:
    json.dump(history, f, indent=2)
" "$win_history_file" "$TIMESTAMP" "$version" "$color" "$status" "$reason" "$duration"
    else
        local entry="  {\"timestamp\": \"$TIMESTAMP\", \"version\": \"$version\", \"color\": \"$color\", \"status\": \"$status\", \"reason\": \"$reason\", \"duration_sec\": $duration}"
        if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ] || [ "$(tr -d '[:space:]' < "$HISTORY_FILE")" = "[]" ]; then
            printf "[\n%s\n]\n" "$entry" > "$HISTORY_FILE"
        else
            sed -i '$ d' "$HISTORY_FILE"
            echo "  ," >> "$HISTORY_FILE"
            printf "%s\n]\n" "$entry" >> "$HISTORY_FILE"
        fi
    fi

    if [ "$SCRIPT_DIR/state" != "$STATE_DIR" ] && [ -d "$SCRIPT_DIR/state" ]; then
        cp "$HISTORY_FILE" "$SCRIPT_DIR/state/history.json" 2>/dev/null || true
    fi
}

# 1. Read deploy/state/active_color (default blue). NEW = the other color.
ACTIVE_COLOR="blue"
if [ -f "$ACTIVE_COLOR_FILE" ]; then
    READ_COLOR=$(tr -d '\r\n ' < "$ACTIVE_COLOR_FILE")
    if [ -n "$READ_COLOR" ]; then
        ACTIVE_COLOR="$READ_COLOR"
    fi
fi

OLD="$ACTIVE_COLOR"
if [ "$OLD" = "blue" ]; then
    NEW="green"
else
    NEW="blue"
fi

echo "Deploying version '$IMAGE_TAG' to color '$NEW' (current active: '$OLD')..."

# 2. Start container NEW (name = NEW) from image resqcd:IMAGE_TAG on network resqcd-net. Pass env BREAK_HEALTH if set.
docker rm -f "$NEW" >/dev/null 2>&1 || true

ENV_ARGS=()
if [ -n "${BREAK_HEALTH:-}" ]; then
    ENV_ARGS+=("-e" "BREAK_HEALTH=${BREAK_HEALTH}")
fi

echo "Starting container $NEW from image resqcd:${IMAGE_TAG}..."
docker run -d --name "$NEW" --network resqcd-net "${ENV_ARGS[@]}" "resqcd:${IMAGE_TAG}"

# 3. Health check NEW at http://NEW:8080/actuator/health from a curl container on resqcd-net. Retry 10x, 3s gap.
HEALTHY=false
for i in $(seq 1 10); do
    echo "Health check attempt $i/10 for $NEW..."
    if docker run --rm --network resqcd-net curlimages/curl:latest -s -f "http://${NEW}:8080/actuator/health" >/dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    sleep 3
done

# 4. If fail: remove NEW, log FAILED_HEALTHCHECK, exit 1. Active untouched.
if [ "$HEALTHY" != "true" ]; then
    echo "Health check failed for $NEW."
    docker rm -f "$NEW" >/dev/null 2>&1 || true
    record_history "$IMAGE_TAG" "$NEW" "FAILED_HEALTHCHECK" "FAILED_HEALTHCHECK"
    exit 1
fi

echo "Health check passed for $NEW."

# 5. If pass: write upstream.conf pointing to NEW, run `docker exec nginx nginx -s reload`, update active_color.
mkdir -p "$(dirname "$UPSTREAM_CONF")"
echo "upstream app { server ${NEW}:8080; }" > "$UPSTREAM_CONF"
docker exec nginx sh -c "echo 'upstream app { server ${NEW}:8080; }' > /etc/nginx/active/upstream.conf" >/dev/null 2>&1 || true

if ! docker ps --format '{{.Names}}' | grep -q "^nginx$"; then
    echo "Starting nginx container..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
else
    docker exec nginx nginx -s reload
fi

echo "$NEW" > "$ACTIVE_COLOR_FILE"

# 6. Post-switch verify: curl http://localhost:8080/actuator/health 5 times over 15s.
POST_PASS=true
for i in $(seq 1 5); do
    echo "Post-switch verify attempt $i/5..."
    if ! curl -s -f "http://localhost:8080/actuator/health" >/dev/null 2>&1 && \
       ! curl -s -f "http://nginx/actuator/health" >/dev/null 2>&1; then
        POST_PASS=false
        break
    fi
    sleep 3
done

# 7. If fail: switch upstream back to OLD, reload, log ROLLED_BACK, exit 1.
if [ "$POST_PASS" != "true" ]; then
    echo "Post-switch verification failed! Rolling back to $OLD..."
    echo "upstream app { server ${OLD}:8080; }" > "$UPSTREAM_CONF"
    docker exec nginx sh -c "echo 'upstream app { server ${OLD}:8080; }' > /etc/nginx/active/upstream.conf" >/dev/null 2>&1 || true
    docker exec nginx nginx -s reload >/dev/null 2>&1 || true
    echo "$OLD" > "$ACTIVE_COLOR_FILE"
    docker rm -f "$NEW" >/dev/null 2>&1 || true
    record_history "$IMAGE_TAG" "$NEW" "ROLLED_BACK" "ROLLED_BACK"
    exit 1
fi

# 8. If pass: log SUCCESS, remove OLD container.
echo "Post-switch verification passed."
record_history "$IMAGE_TAG" "$NEW" "SUCCESS" "SUCCESS"
echo "Removing old container $OLD..."
docker rm -f "$OLD" >/dev/null 2>&1 || true

echo "Deployment of version $IMAGE_TAG ($NEW) completed successfully."
