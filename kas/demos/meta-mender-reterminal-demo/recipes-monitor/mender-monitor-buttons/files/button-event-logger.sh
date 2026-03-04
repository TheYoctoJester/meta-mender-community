#!/bin/sh
# Toggle reTerminal button alerts directly to Mender server.
# Press once → CRITICAL alert; press again → OK (clear).
# Sends alerts directly to the Mender server to avoid local API rate limits.

STATE_DIR="/run/button-toggle"
mkdir -p "$STATE_DIR"

get_mender_auth() {
    # Fetch JWT token from mender-client via D-Bus
    eval $(busctl --system call \
        io.mender.AuthenticationManager \
        /io/mender/AuthenticationManager \
        io.mender.Authentication1 \
        GetJwtToken 2>/dev/null \
        | awk '{gsub(/"/, "", $2); gsub(/"/, "", $3); print "AUTH_TOKEN=" $2 "\nSERVER_URL=" $3}')
    SERVER_URL="${SERVER_URL:-https://hosted.mender.io}"
}

send_alert() {
    local level="$1" name="$2" description="$3" subject_name="$4" status="$5"
    local timestamp attempt http_code
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    get_mender_auth
    if [ -z "$AUTH_TOKEN" ]; then
        echo "No auth token available, cannot send alert" >&2
        return 1
    fi

    local payload
    payload=$(cat <<-ENDJSON
[{"subject":{"type":"button","details":{"description":"${description}"},"status":"${status}","name":"${subject_name}"},"level":"${level}","timestamp":"${timestamp}","name":"${name}"}]
ENDJSON
)

    attempt=0
    while [ $attempt -lt 3 ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 10 --connect-timeout 5 \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${AUTH_TOKEN}" \
            -d "${payload}" \
            "${SERVER_URL}/api/devices/v1/devicemonitor/alert")

        if [ "$http_code" = "204" ]; then
            echo "Alert sent: ${name} (${level})" >&2
            return 0
        elif [ "$http_code" = "429" ]; then
            attempt=$((attempt + 1))
            echo "Rate limited, retry ${attempt}/3 in 5s..." >&2
            sleep 5
        else
            echo "Alert send failed: HTTP ${http_code}" >&2
            return 1
        fi
    done
    echo "Alert send failed after 3 retries" >&2
    return 1
}

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

evtest "$INPUT_DEV" 2>&1 | awk '/EV_KEY/ && /value 1/ {
    if ($0 ~ /KEY_A/) print "f1 F1 WARNING"
    else if ($0 ~ /KEY_S/) print "f2 F2 WARNING"
    else if ($0 ~ /KEY_D/) print "f3 F3 WARNING"
    else if ($0 ~ /KEY_F/) print "o O CRITICAL"
    fflush()
}' | while read btn label level; do
    state_file="${STATE_DIR}/${btn}"
    if [ -f "$state_file" ]; then
        rm "$state_file"
        send_alert "OK" \
            "Button ${label} pressed - clear" \
            "Button ${label} alert cleared" \
            "button_${btn}" \
            "clear"
    else
        touch "$state_file"
        send_alert "${level}" \
            "Button ${label} pressed - set" \
            "Button ${label} alert triggered" \
            "button_${btn}" \
            "set"
    fi
done
