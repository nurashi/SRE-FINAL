#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/nurashi/SRE-FINAL"
REPO_DIR="/home/nurashi/autoscale/repo"
TERRAFORM_DIR="$REPO_DIR/terraform"
STATE_DIR="/home/nurashi/terraform-state"
COOLDOWN_FILE="/home/nurashi/autoscale/cooldown"
LOG_FILE="/home/nurashi/autoscale/autoscale.log"

PROMETHEUS_URL="http://localhost:9090"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-nurashi}"

MAX_REPLICAS=5
MIN_REPLICAS=1
SCALE_UP_THRESHOLD=50
SCALE_DOWN_THRESHOLD=10
COOLDOWN_SECONDS=60

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

if [ ! -d "$REPO_DIR" ]; then
    log "Cloning repository..."
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR" 2>&1 | tee -a "$LOG_FILE"
fi

cd "$REPO_DIR"
git fetch origin main 2>&1 | tee -a "$LOG_FILE"
git reset --hard origin/main 2>&1 | tee -a "$LOG_FILE"

mkdir -p "$STATE_DIR"
cd "$TERRAFORM_DIR"

if [ ! -d ".terraform" ]; then
    log "Running terraform init..."
    terraform init -input=false 2>&1 | tee -a "$LOG_FILE"
fi

if [ -f "$COOLDOWN_FILE" ]; then
    LAST_SCALE=$(cat "$COOLDOWN_FILE")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_SCALE))
    if [ "$ELAPSED" -lt "$COOLDOWN_SECONDS" ]; then
        log "Cooldown active: ${ELAPSED}s / ${COOLDOWN_SECONDS}s"
        exit 0
    fi
fi

RATE_RESPONSE=$(curl -s --max-time 5 "${PROMETHEUS_URL}/api/v1/query?query=sum(rate(http_requests_total[1m]))" || true)
RATE=$(echo "$RATE_RESPONSE" | jq -r '.data.result[0].value[1] // "0"')
RATE_INT=$(printf "%.0f" "${RATE:-0}")

CURRENT_RESPONSE=$(curl -s --max-time 5 "${PROMETHEUS_URL}/api/v1/query?query=count(up{job=\"sre-final-app\"})" || true)
CURRENT=$(echo "$CURRENT_RESPONSE" | jq -r '.data.result[0].value[1] // "1"')
CURRENT_INT=$(printf "%.0f" "${CURRENT:-1}")

NEW=$CURRENT_INT

if [ "$RATE_INT" -gt "$SCALE_UP_THRESHOLD" ] && [ "$CURRENT_INT" -lt "$MAX_REPLICAS" ]; then
    NEW=$((CURRENT_INT + 1))
    REASON="rate $RATE_INT > threshold $SCALE_UP_THRESHOLD"
elif [ "$RATE_INT" -lt "$SCALE_DOWN_THRESHOLD" ] && [ "$CURRENT_INT" -gt "$MIN_REPLICAS" ]; then
    NEW=$((CURRENT_INT - 1))
    REASON="rate $RATE_INT < threshold $SCALE_DOWN_THRESHOLD"
fi

if [ "$NEW" != "$CURRENT_INT" ]; then
    log "SCALING: $CURRENT_INT -> $NEW replicas ($REASON)"

    terraform apply -auto-approve -input=false \
        -var="dockerhub_username=${DOCKERHUB_USERNAME}" \
        -var="app_image_tag=latest" \
        -var="app_replicas=${NEW}" 2>&1 | tee -a "$LOG_FILE"

    date +%s > "$COOLDOWN_FILE"
    log "Scale complete, cooldown set for ${COOLDOWN_SECONDS}s"
else
    log "No scaling: ${CURRENT_INT} replicas, rate=${RATE_INT} req/s"
fi
