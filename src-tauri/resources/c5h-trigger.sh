#!/bin/bash
# c5h-trigger.sh — invoked by launchd plists to run a scheduled CLI command,
# capture its result, and leave a small JSON file the C5h app can pick up.
#
# Args:
#   $1  schedule_id (integer)
#   $2  output_dir  (absolute path; created if missing)
#   $3+ the CLI command and its arguments (passed verbatim to exec)
#
# On exit, writes:
#   <output_dir>/<schedule_id>.meta.json     - { schedule_id, exit_code, started_at, finished_at }
#   <output_dir>/<schedule_id>.stderr.log    - last 4KB of stderr (omitted if no stderr)

set -uo pipefail

SCHEDULE_ID="${1:?missing schedule_id}"
OUTPUT_DIR="${2:?missing output_dir}"
shift 2

mkdir -p "$OUTPUT_DIR"
META_TMP="$OUTPUT_DIR/.${SCHEDULE_ID}.meta.tmp"
META_FINAL="$OUTPUT_DIR/${SCHEDULE_ID}.meta.json"
STDERR_FINAL="$OUTPUT_DIR/${SCHEDULE_ID}.stderr.log"

started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
if [ "$#" -eq 0 ]; then
    printf '%s\n' "c5h-trigger: no command provided after schedule_id and output_dir" > "$STDERR_FINAL"
    code=64
else
    "$@" 2>"$STDERR_FINAL" >/dev/null
    code=$?
fi
finished_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Trim stderr to the last 4KB so result files stay small.
if [ -s "$STDERR_FINAL" ]; then
    tail -c 4096 "$STDERR_FINAL" > "${STDERR_FINAL}.tmp" \
        && mv "${STDERR_FINAL}.tmp" "$STDERR_FINAL"
else
    rm -f "$STDERR_FINAL"
fi

# All values below are integers or fixed-format ISO timestamps —
# no shell escaping needed for valid JSON.
printf '{"schedule_id":%s,"exit_code":%s,"started_at":"%s","finished_at":"%s"}\n' \
    "$SCHEDULE_ID" "$code" "$started_at" "$finished_at" \
    > "$META_TMP"

# Atomic move so the polling task never sees a partial file.
mv "$META_TMP" "$META_FINAL"
