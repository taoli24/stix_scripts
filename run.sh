# ============================
# Wrapper to run ingest and schedule push
# ============================

# run_ingest_and_schedule_push.sh
#!/usr/bin/env bash
# Start the ingest script in the background and schedule the push script via cron

INGEST_SCRIPT="./ingest.sh"
PUSH_SCRIPT="./push_stix.sh"
CRON_SCHEDULE="*/5 * * * *"

# Ensure ingest is running in background
if pgrep -f "${INGEST_SCRIPT}" > /dev/null; then
  echo "ingest.sh is already running."
else
  nohup bash "${INGEST_SCRIPT}" > /dev/null 2>&1 &
  echo "Started ingest.sh in background."
fi

# Install cron job for push script if not already present
CRON_ENTRY="${CRON_SCHEDULE} bash ${PUSH_SCRIPT}"
( crontab -l 2>/dev/null | grep -F "${PUSH_SCRIPT}" ) && {
  echo "Cron job for push already exists."
} || {
  ( crontab -l 2>/dev/null; echo "${CRON_ENTRY}" ) | crontab -
  echo "Installed cron job: ${CRON_ENTRY}"
} $(timestamp) -----"