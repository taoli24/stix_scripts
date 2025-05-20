#!/usr/bin/env bash
# Script to push STIX objects to a local TAXII2 server (with logging), without persisting bundle files

# Configuration (loaded from .config)
source .config
FILES_DIR="./downloaded"
PROCESSED_DIR="./processed"
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/push_to_local_taxii.log"
CONTENT_TYPE="application/taxii+json;version=2.1"

# Logging function
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(timestamp) - $*"; }

# Setup logging and directories
mkdir -p "$FILES_DIR" "$PROCESSED_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log "----- Starting push at $(timestamp) -----"

# Process each JSON file in the feed directory
for file in "$FILES_DIR"/*.json; do
  [[ -e "$file" ]] || continue
  log "Processing file: $file"

  # Generate UUID for bundle
  BUNDLE_ID="bundle--$(uuidgen)"
  # Stream STIX bundle directly to curl, avoiding intermediate file
  HTTP_CODE=$(jq -c --arg id "$BUNDLE_ID" '{type: "bundle", id: $id, objects: .objects}' "$file" \
    | curl -s \
      -H "Authorization: $LOCAL_TAXII_API_KEY" \
      -X POST "$LOCAL_TAXII_URL" \
      -H "Content-Type: $CONTENT_TYPE" \
      --data-binary @- -w "%{http_code}" -o /dev/null)
  log "Push HTTP code: $HTTP_CODE"

  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    mv "$file" "$PROCESSED_DIR/"
    log "Successfully pushed and moved $(basename "$file") to processed"
  else
    log "Failed to push $(basename "$file") (status $HTTP_CODE); file retained for retry"
  fi
done

log "----- Push complete at $(timestamp) -----"
