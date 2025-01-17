#!/bin/bash

# Configurazione
OUTPUT_DIR="/media/data/resources/scambio/tmp/images"
LOG_FILE="$HOME/log/secure_get_image.log"
FRAME_DELAY=0.9
FILE_RETENTION_DAYS=8
IMAGE_FORMAT=jpg
RESOLUTION="1280x720"
FUZZY_VALUE="10%"
LOW_THRESHOLD=400
LOW_THRESHOLD_ACTIVATION=200
VARIATION_AVERAGE_THRESHOLD=80 # soglia percentuale sulla variazione per far partire la registrazione
LOW_VARIATION_AVERAGE_THRESHOLD=10
VARIATION_HISTORY_SIZE=30
SECONDS_BETWEEN_IMAGES_CLEANUP_CHECK=3600
COMPARE_IMAGE_ERROR=false

# Creazione directory e file di log
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

# File temporanei
IMAGE_prev=$(mktemp --suffix=.$IMAGE_FORMAT)
IMAGE_now=$(mktemp --suffix=.$IMAGE_FORMAT)
IMAGE_prev_processed=$(mktemp --suffix=.$IMAGE_FORMAT)
IMAGE_now_processed=$(mktemp --suffix=.$IMAGE_FORMAT)

# Variabile per tracciare l'ultima esecuzione di pulizia
last_cleanup_time=$(date +%s)

delete_old_files() {
    local current_time=$(date +%s)
    if (( current_time - last_cleanup_time >= $SECONDS_BETWEEN_IMAGES_CLEANUP_CHECK )); then
        deleted_files=$(find "$OUTPUT_DIR" -type f -name "*.$IMAGE_FORMAT" -mtime +"$FILE_RETENTION_DAYS" -print -exec rm -f {} \;)
        if [ -n "$deleted_files" ]; then
            log "File eliminati: $deleted_files"
        else
            log "Nessun file eliminato durante la pulizia."
        fi
        last_cleanup_time=$current_time
    fi
}

# Verifica dipendenze
for cmd in fswebcam compare magick bc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Errore: comando $cmd non trovato"
        exit 1
    fi
done

trap 'log "Terminazione script..."; rm -f "$IMAGE_prev" "$IMAGE_now" "$IMAGE_prev_processed" "$IMAGE_now_processed"; exit 0' SIGINT SIGTERM EXIT

log "*** START ***"

# Acquisizione iniziale
if capture_frame "$IMAGE_prev"; then
    log "Acquisizione iniziale completata."
else
    log "Errore nell'acquisizione iniziale con fswebcam."
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

log "Avvio monitoraggio movimento..."

# Buffer per memorizzare le ultime variazioni
variation_history=()
total_variation=0
index=0
capturing=false

while true; do
    sleep "$FRAME_DELAY"

    if ! capture_frame "$IMAGE_now"; then
        log "Errore nell'acquisizione del frame."
        continue
    fi

    magick "$IMAGE_now" -strip -quality 100 -crop +0-20 "$IMAGE_now_processed"
    magick "$IMAGE_prev" -strip -quality 100 -crop +0-20 "$IMAGE_prev_processed"

    sleep 0.1
    diff=0
    diff=$(compare -fuzz "$FUZZY_VALUE" -metric AE "$IMAGE_prev_processed" "$IMAGE_now_processed" null: 2>&1)
    
    # Aggiorna il buffer delle variazioni
    if [ ${#variation_history[@]} -ge $VARIATION_HISTORY_SIZE ]; then
        total_variation=$((total_variation - variation_history[index]))
        variation_history[index]=$diff
    else
        variation_history+=($diff)
    fi
    total_variation=$((total_variation + diff))
    index=$(( (index + 1) % VARIATION_HISTORY_SIZE ))

    # Calcola la media delle ultime variazioni
    if [ ${#variation_history[@]} -eq 0 ]; then
        mean=0
    else
        mean=$((total_variation / ${#variation_history[@]}))
    fi

    # Calcola la variazione percentuale
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
        log "Inizio acquisizione. Differenza: $diff (average_variation: $average_variation)"
    fi

    if [ "$capturing" = true ]; then
        TIMESTAMP=$(date +"%Y_%m_%d_%H_%M_%S_%N")
        IMAGE_PATH="${OUTPUT_DIR}/${TIMESTAMP}.${IMAGE_FORMAT}"
        cp "$IMAGE_now" "$IMAGE_PATH"
    fi

    if [ "$capturing" = true ] && ( [ "$diff" -lt "$LOW_THRESHOLD" ] || [ "$(echo "$average_variation < $LOW_VARIATION_AVERAGE_THRESHOLD" | bc)" -eq 1 ] ); then
        capturing=false
        log "Interruzione acquisizione. Differenza: $diff"
    fi

    # Scambia i frame
    tmp_PREV=$IMAGE_prev
    IMAGE_prev=$IMAGE_now
    IMAGE_now=$tmp_PREV
#     cp $IMAGE_now $IMAGE_prev

    # Pulizia dei file vecchi (una volta ogni ora)
    delete_old_files
done

