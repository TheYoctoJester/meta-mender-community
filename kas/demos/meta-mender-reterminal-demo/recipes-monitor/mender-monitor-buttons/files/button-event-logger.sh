#!/bin/bash
# Stream reTerminal button press events to a log file.
# Runs as a systemd service; mender-monitor log checks tail this file.

LOGFILE="/var/log/button-events.log"
INPUT_DEV=$(/opt/mender-monitor-buttons/find-gpio-keys.sh)

if [ $? -ne 0 ] || [ -z "$INPUT_DEV" ]; then
    echo "Failed to find gpio_keys device, retrying in 5s..." >&2
    sleep 5
    INPUT_DEV=$(/opt/mender-monitor-buttons/find-gpio-keys.sh)
    if [ $? -ne 0 ] || [ -z "$INPUT_DEV" ]; then
        echo "gpio_keys device still not found, exiting." >&2
        exit 1
    fi
fi

echo "Monitoring $INPUT_DEV for button events..." >&2

# Filter to EV_KEY lines only to avoid log bloat from SYN events
exec evtest "$INPUT_DEV" 2>&1 | grep --line-buffered "EV_KEY" >> "$LOGFILE"
