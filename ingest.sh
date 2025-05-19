#!/usr/bin/env bash
# Script to ingest STIX 2.1 data with pagination, persistent state, and dual logging (console + log file)

# Configuration
STATE_FILE="./stix_ingest.state"
OUTPUT_DIR="./downloaded"
CONTENT_TYPE="application/taxii+json;version=2.1"
PAGE_LIMIT=1000
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/ingest_stix21.log"

source .config

# Logging function
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(timestamp) - $*"; }

# Setup logging: create dirs, redirect stdout and stderr to tee
mkdir -p "$OUTPUT_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log "----- Starting ingestion -----"

# Initialize state if missing
if [[ ! -f "$STATE_FILE" ]]; then
  log "State file not found, creating new state file."
  ADDED_AFTER=$(date -u -d '-24 hours' +"%Y-%m-%dT%H:%M:%SZ")
  PAGE_TOKEN=""
  printf "%s\n%s" "$ADDED_AFTER" "$PAGE_TOKEN" > "$STATE_FILE"
fi

MORE=true
while [[ "$MORE" == "true" ]]; do
  # Load state
  read -r ADDED_AFTER PAGE_TOKEN < <(tr '\n' ' ' < "$STATE_FILE")
  log "Current state: added_after=$ADDED_AFTER next_token=$PAGE_TOKEN"

  # Build URL
  URL="${API_URL}?added_after=${ADDED_AFTER}&limit=${PAGE_LIMIT}"
  if [[ -n "$PAGE_TOKEN" ]]; then
    enc_next=$(jq -nr --arg v "$PAGE_TOKEN" '$v|@uri')
    URL+="&next=${enc_next}"
  fi
  log "Fetching: $URL"

  # Request
  HTTP_BODY=$(mktemp)
  HTTP_CODE=$(curl -su "$API_USER:$API_PASS" \
    -H "Accept: $CONTENT_TYPE" -w "%{http_code}" -o "$HTTP_BODY" "$URL")
  log "HTTP response code: $HTTP_CODE"

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    log "Request failed, will retry after 60s."
    printf "%s\n%s" "$ADDED_AFTER" "$PAGE_TOKEN" > "$STATE_FILE"
    sleep 60
    continue
  fi

  TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
  PAGE_FILE="$OUTPUT_DIR/objects_page_${TIMESTAMP}.json"
  mv "$HTTP_BODY" "$PAGE_FILE"
  log "Saved page to $PAGE_FILE"

  # Parse
  MORE=$(jq -r '.more' "$PAGE_FILE")
  PAGE_TOKEN=$(jq -r '.next // ""' "$PAGE_FILE")

  # If done
  if [[ "$MORE" != "true" ]]; then
    LAST_CREATED=$(jq -r '.objects | last | .created' "$PAGE_FILE")
    if [[ -n "$LAST_CREATED" && "$LAST_CREATED" != "null" ]]; then
      ADDED_AFTER=$(date -u -d "${LAST_CREATED} -1 second" +"%Y-%m-%dT%H:%M:%SZ")
      log "Updated added_after to ${ADDED_AFTER}"
    fi
    PAGE_TOKEN=""
  fi

  # Persist
  printf "%s\n%s" "$ADDED_AFTER" "$PAGE_TOKEN" > "$STATE_FILE"
  log "State persisted"

  log "Sleeping 30s before next iteration"
  sleep 30
done

log "Ingestion complete"