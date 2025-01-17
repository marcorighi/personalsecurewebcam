#!/bin/bash

# Configuration
OUTPUT_DIR="/media/data/resources/scambio/tmp/images"
LOG_FILE="$HOME/log/secure_get_image.log"
FRAME_DELAY=0.9
FILE_RETENTION_DAYS=8
IMAGE_FORMAT=jpg
RESOLUTION="1280x720"
FUZZY_VALUE="10%"
LOW_THRESHOLD=400
LOW_THRESHOLD_ACTIVATION=200
VARIATION_AVERAGE_THRESHOLD=80 # percentage threshold on variation to start recording
LOW_VARIATION_AVERAGE_THRESHOLD=10
VARIATION_HISTORY_SIZE=30
SECONDS_BETWEEN_IMAGES_CLEANUP_CHECK=3600
COMPARE_IMAGE_ERROR=false

# Create directories and log file
mkdir -p "$OUTPUT_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
    local message="$*"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

capture_frame() {
    local output_file="$1"
    fswebcam -r "$RESOLUTION" --fps 30 --jpeg 95 -d /dev/video0 "$output_file" >/dev/null 2>&1
}

# Temporary files
IMAGE_prev=$(mktemp --suffix=.$IMAGE_FORMAT)
IMAGE_now=$(mktemp --suffix=.$IMAGE_FORMAT)
IMAGE_prev_processed=$(mktemp --suffix=.$IMAGE_FORMAT)
IMAGE_now_processed=$(mktemp --suffix=.$IMAGE_FORMAT)

# Variable to track the last cleanup execution
last_cleanup_time=$(date +%s)

delete_old_files() {
    local current_time=$(date +%s)
    if (( current_time - last_cleanup_time >= $SECONDS_BETWEEN_IMAGES_CLEANUP_CHECK )); then
        deleted_files=$(find "$OUTPUT_DIR" -type f -name "*.$IMAGE_FORMAT" -mtime +"$FILE_RETENTION_DAYS" -print -exec rm -f {} \;)
        if [ -n "$deleted_files" ]; then
            log "Deleted files: $deleted_files"
        else
            log "No files deleted during cleanup."
        fi
        last_cleanup_time=$current_time
    fi
}

# Check dependencies
for cmd in fswebcam compare magick bc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Error: command $cmd not found"
        exit 1
    fi
done

trap 'log "Script termination..."; rm -f "$IMAGE_prev" "$IMAGE_now" "$IMAGE_prev_processed" "$IMAGE_now_processed"; exit 0' SIGINT SIGTERM EXIT

log "*** START ***"

# Initial capture
if capture_frame "$IMAGE_prev"; then
    log "Initial capture completed."
else
    log "Error in initial capture with fswebcam."
    exit 1
fi

log "LOW THRESHOLD: $LOW_THRESHOLD"
log "LOW_THRESHOLD_ACTIVATION $LOW_THRESHOLD_ACTIVATION"
log "LOW_VARIATION_AVERAGE_THRESHOLD ${LOW_VARIATION_AVERAGE_THRESHOLD}%"
log "VARIATION AVERAGE THRESHOLD: ${VARIATION_AVERAGE_THRESHOLD}%"
log "VARIATION_HISTORY_SIZE $VARIATION_HISTORY_SIZE"
log "FRAME_DELAY: $FRAME_DELAY"
log "FILE_RETENTION_DAYS: $FILE_RETENTION_DAYS"
log "RESOLUTION: $RESOLUTION"
log "FUZZY_VALUE: $FUZZY_VALUE"

log "Starting motion monitoring..."

# Buffer to store the latest variations
variation_history=()
total_variation=0
index=0
capturing=false

while true; do
    sleep "$FRAME_DELAY"

    if ! capture_frame "$IMAGE_now"; then
        log "Error in frame capture."
        continue
    fi

    magick "$IMAGE_now" -strip -quality 100 -crop +0-20 "$IMAGE_now_processed"
    magick "$IMAGE_prev" -strip -quality 100 -crop +0-20 "$IMAGE_prev_processed"

    sleep 0.1
    diff=0
    diff=$(compare -fuzz "$FUZZY_VALUE" -metric AE "$IMAGE_prev_processed" "$IMAGE_now_processed" null: 2>&1)
    
    # Update the variation buffer
    if [ ${#variation_history[@]} -ge $VARIATION_HISTORY_SIZE ]; then
        total_variation=$((total_variation - variation_history[index]))
        variation_history[index]=$diff
    else
        variation_history+=($diff)
    fi
    total_variation=$((total_variation + diff))
    index=$(( (index + 1) % VARIATION_HISTORY_SIZE ))

    # Calculate the average of the latest variations
    if [ ${#variation_history[@]} -eq 0 ]; then
        mean=0
    else
        mean=$((total_variation / ${#variation_history[@]}))
    fi

    # Calculate the percentage variation
    if [ $mean -eq 0 ]; then
            average_variation=0
    else
        average_variation=$(echo "scale=3; (($diff - $mean) / $mean * 100)" | bc | awk '{print ($1<0)? -1*$1 : $1}')
    fi


    log "*** capturing $capturing --- mean $mean -- average_variation $average_variation -- diff $diff***"
    log "+++ ${variation_history[@]} +++"

    #if [ "$capturing" = false ] && [ "$(echo "$average_variation > $VARIATION_AVERAGE_THRESHOLD" | bc)" -eq 1 ] && [ $diff -gt $LOW_THRESHOLD  ] ; then
    if [ "$capturing" = false ] && [ "$(echo "$average_variation > $VARIATION_AVERAGE_THRESHOLD" | bc)" -eq 1 ] && [ "$(echo "$diff > $LOW_THRESHOLD_ACTIVATION" | bc)" -eq 1 ]  ; then
        capturing=true
        log "Starting capture. Difference: $diff (average_variation: $average_variation)"
    fi

    if [ "$capturing" = true ]; then
        TIMESTAMP=$(date +"%Y_%m_%d_%H_%M_%S_%N")
        IMAGE_PATH="${OUTPUT_DIR}/${TIMESTAMP}.${IMAGE_FORMAT}"
        cp "$IMAGE_now" "$IMAGE_PATH"
    fi

    if [ "$capturing" = true ] && ( [ "$diff" -lt "$LOW_THRESHOLD" ] || [ "$(echo "$average_variation < $LOW_VARIATION_AVERAGE_THRESHOLD" | bc)" -eq 1 ] ); then
        capturing=false
        log "Stopping capture. Difference: $diff"
    fi

    # Swap frames
    tmp_PREV=$IMAGE_prev
    IMAGE_prev=$IMAGE_now
    IMAGE_now=$tmp_PREV
#     cp $IMAGE_now $IMAGE_prev

    # Cleanup old files (once every hour)
    delete_old_files
done

